// Copyright 1997-2005, 2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSAttributedString-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/OAColorPalette.h>

RCS_ID("$Id$")

@interface OAInlineImageTextAttachmentCell : NSImageCell /* <NSTextAttachmentCell> */
{
    NSTextAttachment *nonretained_attachment;
}
@property (readwrite, assign) NSTextAttachment *attachment;
@end

@implementation NSAttributedString (OAExtensions)

static NSDictionary *keywordDictionary = nil;
static NSFontTraitMask mask = NO;
static BOOL underlineFlag = NO;
static CGFloat size = 12.0;
static NSString *linkString;
static NSString *blackColorString;

+ (void)didLoad;
{
    if (keywordDictionary)
        return;

    keywordDictionary = [[NSDictionary dictionaryWithObjectsAndKeys:
            @"&quot", @"\"",
	    @"&amp", @"&",
	    @"&lt", @"<",
	    @"&gt", @">",
        nil] retain];
    blackColorString = [[OAColorPalette stringForColor:[NSColor blackColor]] retain];
}

+ (NSString *)attachmentString;
{
    static NSString *AttachmentString = nil;
    if (!AttachmentString) {
        unichar c = NSAttachmentCharacter;
        AttachmentString = [[NSString alloc] initWithCharacters:&c length:1];
    }
    return AttachmentString;
}

+ (NSAttributedString *)attributedStringWithImage:(NSImage *)anImage;
{
    OAInlineImageTextAttachmentCell *imageCell = [[OAInlineImageTextAttachmentCell alloc] initImageCell:anImage];
    NSTextAttachment *attach = [[NSTextAttachment alloc] initWithFileWrapper:nil];
    [attach setAttachmentCell:(id <NSTextAttachmentCell>)imageCell];
    [imageCell release];
    
    NSAttributedString *result = [self attributedStringWithAttachment:attach];
    [attach release];
    return result;
}

- (void)resetAttributes;
{
    mask = 0;
    underlineFlag = NO;
    size = 12;
}

- (void)setBold:(BOOL)newBold;
{
    if (newBold)
	mask |= NSBoldFontMask;
    else
	mask &= ~NSBoldFontMask;
}

- (void)setItalic:(BOOL)newItalic;
{
    if (newItalic)
	mask |= NSItalicFontMask;
    else
	mask &= ~NSItalicFontMask;
}

- (void)setUnderline:(BOOL)newUnderline;
{
    underlineFlag = newUnderline;
}

- (void)setCurrentAttributes:(NSMutableAttributedString *)attrString;
{
    NSRange range;
    NSFont *font;
    NSFontManager *fontManager;
    NSMutableDictionary *attrDict;

    range.location = 0;
    range.length = [attrString length];

    fontManager = [NSFontManager sharedFontManager];
    font = [fontManager fontWithFamily:@"Helvetica" traits:mask weight:5 size:size];

    attrDict = [NSMutableDictionary dictionaryWithCapacity:0];
    [attrDict setObject:font forKey:NSFontAttributeName];
    [attrDict setObject:[NSNumber numberWithBool:underlineFlag] forKey:NSUnderlineStyleAttributeName];
    if (linkString)
	[attrDict setObject:linkString forKey:NSLinkAttributeName];

    [attrString addAttributes:attrDict range:range];
}

- (NSAttributedString *)initWithHTML:(NSString *)htmlString;
{
    NSMutableAttributedString *attributedString;
    NSRange range;
    NSScanner *htmlScanner;
    NSMutableString *strippedString;

    [self resetAttributes];

    strippedString = [NSMutableString stringWithCapacity:[htmlString length]];
    htmlScanner = [NSScanner scannerWithString:htmlString];
    while (![htmlScanner isAtEnd]) {
        NSString *token;

        [htmlScanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&token];
        [htmlScanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:NULL];
        [strippedString appendFormat:@"%@ ", token];
    }

    attributedString = [[[NSMutableAttributedString alloc] init] autorelease];

    htmlScanner = [NSScanner scannerWithString:strippedString];
    while (![htmlScanner isAtEnd]) {
        NSString *firstPass, *tagString, *newString;
        NSScanner *keywordScanner;
        NSCharacterSet *openTagSet;
        NSCharacterSet *closeTagSet;
        NSMutableAttributedString *newAttributedString;

        openTagSet = [NSCharacterSet characterSetWithCharactersInString:@"<"];
        closeTagSet = [NSCharacterSet characterSetWithCharactersInString:@">"];
        newAttributedString = [[[NSMutableAttributedString alloc] init] autorelease];

        if ([htmlScanner scanUpToCharactersFromSet:openTagSet intoString:&firstPass]) {
            keywordScanner = [NSScanner scannerWithString:firstPass];
            while (![keywordScanner isAtEnd]) {
                NSString *keyword = nil;
                BOOL knownTag = NO;
                NSCharacterSet *keywordTag;
                NSEnumerator *keyEnum;

                keywordTag = [NSCharacterSet characterSetWithCharactersInString:@"&"];
                keyEnum = [[keywordDictionary allKeys] objectEnumerator];
                [keywordScanner scanUpToCharactersFromSet:keywordTag intoString:&newString];
                [newAttributedString appendAttributedString:[[[NSAttributedString alloc] initWithString:newString]autorelease]];

                while (![keywordScanner isAtEnd] && (keyword = [keyEnum nextObject]))
                    if ([keywordScanner scanString:keyword intoString:NULL]) {
                        [newAttributedString appendAttributedString:[[[NSAttributedString alloc] initWithString:[keywordDictionary objectForKey:keyword]]autorelease]];
                        knownTag = YES;
                    }
                if (!knownTag && [keywordScanner scanCharactersFromSet:keywordTag intoString:&newString])
                    [newAttributedString appendAttributedString:[[[NSAttributedString alloc] initWithString:newString]autorelease]];
            }

            [self setCurrentAttributes:newAttributedString];
            [attributedString appendAttributedString:newAttributedString];
        }
        
        // Either we hit a '<' or we're at the end of the text.
        if (![htmlScanner isAtEnd]) {
            [htmlScanner scanCharactersFromSet:openTagSet intoString:NULL];
            [htmlScanner scanUpToCharactersFromSet:closeTagSet intoString:&tagString];
            [htmlScanner scanCharactersFromSet:closeTagSet intoString:NULL];
	    
	    if ([tagString hasPrefix:@"a "]) {
		NSRange range = [tagString rangeOfString:@"\""];
		
		if (range.length) {
		    tagString = [tagString substringFromIndex:NSMaxRange(range)];
		    range = [tagString rangeOfString:@"\""];
		    linkString = [tagString substringToIndex:range.location];
		} else if ((range = [tagString rangeOfString:@"="]).length) {
		    linkString = [tagString substringFromIndex:NSMaxRange(range)];
		} else
		    linkString = nil;
		[linkString retain];
	    } else if ([tagString isEqual:@"/a"]) {
		[linkString release];
		linkString = nil;
            } else if ([tagString isEqual:@"b"])
                [self setBold:YES];
            else if ([tagString isEqual:@"/b"])
                [self setBold:NO];
            else if ([tagString isEqual:@"i"])
                [self setItalic:YES];
            else if ([tagString isEqual:@"/i"])
                [self setItalic:NO];
            else if ([tagString isEqual:@"u"])
                [self setUnderline:YES];
            else if ([tagString isEqual:@"/u"])
                [self setUnderline:NO];
            else if ([tagString isEqual:@"p"])
                [attributedString appendAttributedString:[[[NSAttributedString alloc] initWithString:@"\n\n"]autorelease]];
            else if ([tagString isEqual:@"br"])
                [attributedString appendAttributedString:[[[NSAttributedString alloc] initWithString:@"\n"]autorelease]];
            else if ([tagString isEqual:@"/font"])
                size = 12.0;
            else if ([tagString hasPrefix:@"font size="] || [tagString hasPrefix:@"font size ="]) {
                float foo;
                if (sscanf([tagString UTF8String], "font size = +%f", &foo) == 1)
                    size += foo + 9;
                else if (sscanf([tagString UTF8String], "font size = %f", &foo) == 1)
                    size = foo + 9;
            }
        }
    }

    range.location = 0;
    range.length = [attributedString length];

    return [self initWithAttributedString:attributedString];
}


// Generating HTML
static NSMutableDictionary *cachedAttributes = nil;
static NSMutableArray *fontDirectiveStack = nil;

void resetAttributeTags()
{
    if (cachedAttributes)
        [cachedAttributes release];
    if (!fontDirectiveStack)
        fontDirectiveStack = [[NSMutableArray alloc] initWithCapacity:0];
    else
        [fontDirectiveStack removeAllObjects];
    cachedAttributes = nil;
}

- (void)pushFontDirective:(NSString *)aDirective;
{
    [fontDirectiveStack addObject:aDirective];
}

- (void)popFontDirective;
{
    if ([fontDirectiveStack count])
        [fontDirectiveStack removeLastObject];
}

NSString *attributeTagString(NSDictionary *effectiveAttributes)
{
    NSFont *newFont, *oldFont;
    NSColor *newColor, *oldColor;
    NSString *newLink, *oldLink;
    NSMutableString *tagString;
    BOOL wasUnderlined = NO, underlined;

    if ([cachedAttributes isEqualToDictionary:effectiveAttributes])
        return nil;

    tagString = [NSMutableString stringWithCapacity:0];
    
    newLink = [effectiveAttributes objectForKey:NSLinkAttributeName];
    oldLink = [cachedAttributes objectForKey:NSLinkAttributeName];
    if (newLink != oldLink) {
	if (oldLink != nil)
	    [tagString appendString:@"</a>"];
	else if (newLink != nil)
	    [tagString appendFormat:@"<a href=\"%@\">", newLink];
    }

    newFont = [effectiveAttributes objectForKey:NSFontAttributeName];
    oldFont = [cachedAttributes objectForKey:NSFontAttributeName];
    if (newFont != oldFont) {
        NSFontTraitMask newTraits;
        float oldSize, size;
        BOOL wasBold, wasItalic, bold, italic;
        NSFontManager *fontManager = [NSFontManager sharedFontManager];
        size = [newFont pointSize];
        newTraits = [fontManager traitsOfFont:newFont];
        bold = newTraits & NSBoldFontMask;
        italic = newTraits & NSItalicFontMask;

        if (oldFont) {
            NSFontTraitMask oldTraits;
            oldTraits = [fontManager traitsOfFont:oldFont];
            wasBold = oldTraits & NSBoldFontMask;
            wasItalic = oldTraits & NSItalicFontMask;
            oldSize = [oldFont pointSize];
        } else {
            wasBold = wasItalic = NO;
            oldSize = 12.0;
        }

        if (bold && !wasBold)
            [tagString appendString:@"<b>"];
        else if (!bold && wasBold)
            [tagString appendString:@"</b>"];

        if (italic && !wasItalic)
            [tagString appendString:@"<i>"];
        else if (!italic && wasItalic)
            [tagString appendString:@"</i>"];

        if (size != oldSize) {
            if (oldFont)
                [tagString appendString:@"</font>"];
            [tagString appendFormat:@"<font size=%d>", (int)size - 9];
        }
    }

    underlined = [[effectiveAttributes objectForKey:NSUnderlineStyleAttributeName] boolValue];
    wasUnderlined = [[cachedAttributes objectForKey:NSUnderlineStyleAttributeName] boolValue];
    if (underlined && !wasUnderlined)
        [tagString appendString:@"<u>"];
    else if (!underlined && wasUnderlined)
        [tagString appendString:@"</u>"];

    oldColor = [cachedAttributes objectForKey:NSForegroundColorAttributeName];
    newColor = [effectiveAttributes objectForKey:NSForegroundColorAttributeName];
    if (oldColor != newColor) {
        if (oldColor)
            [tagString appendString:@"</font>"];
        if (newColor) {
            NSString *newColorString;
        
            newColorString = [OAColorPalette stringForColor:newColor];
            if (![blackColorString isEqualToString:newColorString])
                [tagString appendFormat:@"<font color=\"%@\">", newColorString];
        }
    }
    
    

    if (cachedAttributes)
        [cachedAttributes release];
    cachedAttributes = [effectiveAttributes retain];

    return tagString;
}

- (NSString *)closeTags;
{
    NSMutableString *closeTagsString;
    NSFontTraitMask traits;
    NSFontManager *fontManager;
    NSFont *font;
    NSColor *color;

    closeTagsString = [NSMutableString stringWithCapacity:0];
    if ([cachedAttributes objectForKey:NSLinkAttributeName])
        [closeTagsString appendString:@"</a>"];	

    fontManager = [NSFontManager sharedFontManager];
    font = [cachedAttributes objectForKey:NSFontAttributeName];
    color = [cachedAttributes objectForKey:NSForegroundColorAttributeName];
    if (([font pointSize] != 12.0) || (color && ![blackColorString isEqual:[OAColorPalette stringForColor:color]]))
        [closeTagsString appendString:@"</font>"];

    traits = [fontManager traitsOfFont:font];
    if ([[cachedAttributes objectForKey:NSUnderlineStyleAttributeName] boolValue])
        [closeTagsString appendString:@"</u>"];
    if (traits & NSItalicFontMask)
        [closeTagsString appendString:@"</i>"];
    if (traits & NSBoldFontMask)
        [closeTagsString appendString:@"</b>"];	
    return closeTagsString;
}

- (NSString *)htmlString;
{
    NSDictionary *effectiveAttributes;
    NSRange range;
    unsigned int pos = 0;
    NSMutableString *storeString = [NSMutableString stringWithCapacity:[self length]];

    resetAttributeTags();
    while ((pos < [self length]) &&
           (effectiveAttributes = [self attributesAtIndex:pos effectiveRange:&range])) {
        NSString *markupString = attributeTagString(effectiveAttributes);
        if (markupString)
            [storeString appendString:markupString];
        [storeString appendString:[[[self attributedSubstringFromRange:range] string] htmlString]];

        pos = range.location + range.length;
    }
    [storeString appendString:[self closeTags]];
    return storeString;
}

- (NSData *)rtf;
{
    return [self RTFFromRange:NSMakeRange(0, [self length]) documentAttributes:nil];
}

- (NSAttributedString *)substringWithEllipsisToWidth:(CGFloat)width;
{
    static NSTextStorage *substringWithEllipsisTextStorage = nil;
    static NSLayoutManager *substringWithEllipsisLayoutManager = nil;
    static NSTextContainer *substringWithEllipsisTextContainer = nil;

    NSRange drawGlyphRange;
    NSRange lineCharacterRange;
    NSRect lineFragmentRect;
    NSSize lineSize;
    NSString *ellipsisString;
    NSSize ellipsisSize;
    NSDictionary *ellipsisAttributes;
    BOOL requiresEllipsis = YES;
    BOOL isRightToLeft = NO;
    
    if ([self length] == 0)
        return self;

    if (substringWithEllipsisTextContainer == nil) {
        substringWithEllipsisTextStorage = [[NSTextStorage alloc] init];

        substringWithEllipsisLayoutManager = [[NSLayoutManager alloc] init];
        [substringWithEllipsisTextStorage addLayoutManager:substringWithEllipsisLayoutManager];

        substringWithEllipsisTextContainer = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(1.0e7, 1.0e7)];
        [substringWithEllipsisTextContainer setLineFragmentPadding:0.0];
        [substringWithEllipsisLayoutManager addTextContainer:substringWithEllipsisTextContainer];
    }
    
    [substringWithEllipsisTextStorage setAttributedString:self];
    
    lineFragmentRect = [substringWithEllipsisLayoutManager lineFragmentUsedRectForGlyphAtIndex:0 effectiveRange:&drawGlyphRange];
    lineSize = lineFragmentRect.size;
    if (lineSize.width <= width)
	return self;
	
    lineCharacterRange = [substringWithEllipsisLayoutManager characterRangeForGlyphRange:drawGlyphRange actualGlyphRange:NULL];
    
    NSUInteger ellipsisAttributeCharacterIndex;

    isRightToLeft = ([substringWithEllipsisLayoutManager intAttribute:NSGlyphAttributeBidiLevel forGlyphAtIndex:[substringWithEllipsisLayoutManager numberOfGlyphs] - 1] != 0);        

    if (lineCharacterRange.length != 0)
	ellipsisAttributeCharacterIndex = NSMaxRange(lineCharacterRange) - 1;
    else
	ellipsisAttributeCharacterIndex = 0;
    ellipsisAttributes = [self attributesAtIndex:ellipsisAttributeCharacterIndex longestEffectiveRange:NULL inRange:NSMakeRange(0, 1)];
    ellipsisString = [NSString horizontalEllipsisString];
    ellipsisSize = [ellipsisString sizeWithAttributes:ellipsisAttributes];

    NSPoint glyphLocation;
    glyphLocation.x = (isRightToLeft) ? ellipsisSize.width : width - ellipsisSize.width;
    glyphLocation.y = 0.5 * lineSize.height;
    drawGlyphRange.length = [substringWithEllipsisLayoutManager glyphIndexForPoint:glyphLocation inTextContainer:substringWithEllipsisTextContainer];

    if (drawGlyphRange.length == 0) {
	// We couldn't fit any characters with the ellipsis, so try drawing some without it (rather than drawing nothing)
	requiresEllipsis = NO;
	glyphLocation.x = (isRightToLeft) ? 0.0 : width;
	drawGlyphRange.length = [substringWithEllipsisLayoutManager glyphIndexForPoint:glyphLocation inTextContainer:substringWithEllipsisTextContainer];
    }
    
    NSMutableAttributedString *copy = [self mutableCopy];
    
    lineCharacterRange = [substringWithEllipsisLayoutManager characterRangeForGlyphRange:drawGlyphRange actualGlyphRange:NULL];
    if (isRightToLeft)
	[copy replaceCharactersInRange:NSMakeRange(0, lineCharacterRange.location) withString:(requiresEllipsis ? ellipsisString : @"")];
    else
	[copy replaceCharactersInRange:NSMakeRange(NSMaxRange(lineCharacterRange), [copy length]-NSMaxRange(lineCharacterRange)) withString:(requiresEllipsis ? ellipsisString : @"")];
    return [copy autorelease];
}

- (void)drawInRectangle:(NSRect)rectangle alignment:(int)alignment verticallyCentered:(BOOL)verticallyCenter;
    // ASSUMPTION: This is for one line
{
    static NSTextStorage *showStringTextStorage = nil;
    static NSLayoutManager *showStringLayoutManager = nil;
    static NSTextContainer *showStringTextContainer = nil;

    NSRange drawGlyphRange;
    NSRange lineCharacterRange;
    NSRect lineFragmentRect;
    NSSize lineSize;
    NSString *ellipsisString;
    NSSize ellipsisSize;
    NSDictionary *ellipsisAttributes;
    BOOL requiresEllipsis;
    BOOL lineTooLong;
    BOOL isRightToLeft = NO;
    
    if ([self length] == 0)
        return;

    if (showStringTextStorage == nil) {
        showStringTextStorage = [[NSTextStorage alloc] init];

        showStringLayoutManager = [[NSLayoutManager alloc] init];
        [showStringTextStorage addLayoutManager:showStringLayoutManager];

        showStringTextContainer = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(1.0e7, 1.0e7)];
        [showStringTextContainer setLineFragmentPadding:0.0];
        [showStringLayoutManager addTextContainer:showStringTextContainer];
    }
    
    [showStringTextStorage setAttributedString:self];
    
    lineFragmentRect = [showStringLayoutManager lineFragmentUsedRectForGlyphAtIndex:0 effectiveRange:&drawGlyphRange];
    lineSize = lineFragmentRect.size;
    lineTooLong = lineSize.width > NSWidth(rectangle);
    lineCharacterRange = [showStringLayoutManager characterRangeForGlyphRange:drawGlyphRange actualGlyphRange:NULL];
    requiresEllipsis = lineTooLong || NSMaxRange(lineCharacterRange) < [self length];
    
    if (requiresEllipsis) {
        unsigned int ellipsisAttributeCharacterIndex;

        isRightToLeft = ([showStringLayoutManager intAttribute:NSGlyphAttributeBidiLevel forGlyphAtIndex:[showStringLayoutManager numberOfGlyphs] - 1] != 0);        

        if (lineCharacterRange.length != 0)
            ellipsisAttributeCharacterIndex = NSMaxRange(lineCharacterRange) - 1;
        else
            ellipsisAttributeCharacterIndex = 0;
        ellipsisAttributes = [self attributesAtIndex:ellipsisAttributeCharacterIndex longestEffectiveRange:NULL inRange:NSMakeRange(0, 1)];
        ellipsisString = [NSString horizontalEllipsisString];
        ellipsisSize = [ellipsisString sizeWithAttributes:ellipsisAttributes];

        if (lineTooLong || lineSize.width + ellipsisSize.width > NSWidth(rectangle)) {
            NSPoint glyphLocation;
            glyphLocation.x = (isRightToLeft) ? ellipsisSize.width : NSWidth(rectangle) - ellipsisSize.width;
            glyphLocation.y = 0.5 * lineSize.height;
            drawGlyphRange.length = [showStringLayoutManager glyphIndexForPoint:glyphLocation inTextContainer:showStringTextContainer];

            if (drawGlyphRange.length == 0) {
                // We couldn't fit any characters with the ellipsis, so try drawing some without it (rather than drawing nothing)
                requiresEllipsis = NO;
                glyphLocation.x = (isRightToLeft) ? 0.0 : NSWidth(rectangle);
                drawGlyphRange.length = [showStringLayoutManager glyphIndexForPoint:glyphLocation inTextContainer:showStringTextContainer];
            }
            lineSize.width = [showStringLayoutManager locationForGlyphAtIndex:NSMaxRange(drawGlyphRange)].x;
            if (isRightToLeft)
                lineSize.width = NSWidth(rectangle) - lineSize.width;
        }
        if (requiresEllipsis) // NOTE: Could have been turned off if the ellipsis didn't fit
            lineSize.width += ellipsisSize.width;
    } else {
        // Make the compiler happy, since it doesn't know we're not going to take the requiresEllipsis branch later
        ellipsisString = nil;
        ellipsisSize = NSMakeSize(0, 0);
        ellipsisAttributes = nil;
    }

    if (drawGlyphRange.length) {
        NSPoint drawPoint;

        // determine drawPoint based on alignment
        drawPoint.y = NSMinY(rectangle);
        switch (alignment) {
            default:
            case NSLeftTextAlignment:
                drawPoint.x = NSMinX(rectangle);
                break;
            case NSCenterTextAlignment:
                drawPoint.x = NSMidX(rectangle) - lineSize.width / 2.0;
                break;
            case NSRightTextAlignment:
                drawPoint.x = NSMaxX(rectangle) - lineSize.width;
                break;
        }
        
        if (verticallyCenter)
            drawPoint.y = NSMidY(rectangle) - lineSize.height / 2.0;

        [showStringLayoutManager drawGlyphsForGlyphRange:drawGlyphRange atPoint:drawPoint];
        if (requiresEllipsis) {
            if (!isRightToLeft)
                drawPoint.x += lineSize.width - ellipsisSize.width;
            [ellipsisString drawAtPoint:drawPoint withAttributes:ellipsisAttributes];
        }
    }
}

- (void)drawCenteredShrinkingToFitInRect:(NSRect)rect;
{
    NSSize size = [self size];
    float scale = MIN(NSWidth(rect) / size.width, NSHeight(rect) / size.height);
    if (scale >= 1.0) {
	rect.origin.y += (NSHeight(rect) - size.height) / 2.0;
	[self drawInRect:rect];
	return;
    }
    
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:rect.origin.x yBy:rect.origin.y];
    [transform scaleBy:scale];
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [transform concat];
    rect.origin = NSZeroPoint;
    rect.size.width /= scale;
    rect.size.height /= scale;
    [self drawInRect:rect];
    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

@end


@implementation OAInlineImageTextAttachmentCell

// Many of the NSTextAttachmentCell protocol's methods are supplied by NSCell.
// - (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
// - (void)highlight:(BOOL)flag withFrame:(NSRect)cellFrame inView:(NSView *)controlView;
// - (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)flag;

- (BOOL)wantsToTrackMouse;
{
    return NO;
}

- (NSPoint)cellBaselineOffset;
{
    NSImage *img = [self image];
    if (img) {
        return [img alignmentRect].origin;
    } else {
        return (NSPoint){0, 0};
    }
}

@synthesize attachment = nonretained_attachment;

- (NSSize)cellSize
{
    return [[self image] size];
}

@end


