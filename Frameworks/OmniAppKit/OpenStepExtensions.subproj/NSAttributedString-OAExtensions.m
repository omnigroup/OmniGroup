// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSAttributedString-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OATextStorage.h> // OAAttachmentCharacter
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <AppKit/NSStringDrawing.h>
#endif

RCS_ID("$Id$")

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
@interface OAInlineImageTextAttachmentCell : NSImageCell /* <NSTextAttachmentCell> */
@property (nonatomic,weak) OATextAttachment *attachment;
@end
#endif

@implementation NSAttributedString (OAExtensions)

#if 0
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
#endif

+ (NSString *)attachmentString;
{
    static NSString *AttachmentString = nil;
    if (!AttachmentString) {
        unichar c = NSAttachmentCharacter;
        AttachmentString = [[NSString alloc] initWithCharacters:&c length:1];
    }
    return AttachmentString;
}

- (BOOL)containsAttribute:(NSString *)attributeName;
{
    return [self containsAttribute:attributeName inRange:NSMakeRange(0, [self length])];
}

- (BOOL)containsAttribute:(NSString *)attributeName inRange:(NSRange)range;
{
    NSUInteger position = range.location, end = NSMaxRange(range);
    
    while (position < end) {
        NSRange effectiveRange;
        if ([self attribute:attributeName atIndex:position effectiveRange:&effectiveRange])
            return YES;
        position = NSMaxRange(effectiveRange);
    }
    
    return NO;
}

- (BOOL)containsAttachments;
{
    return [self containsAttribute:NSAttachmentAttributeName];
}

- (id)attachmentAtCharacterIndex:(NSUInteger)characterIndex;
{
    return [self attribute:NSAttachmentAttributeName atIndex:characterIndex effectiveRange:NULL];
}

- (void)eachAttachment:(void (^)(OATextAttachment *, BOOL *stop))applier;
{
    NSString *string = [self string];
    NSString *attachmentString = [NSAttributedString attachmentString];
    
    NSUInteger location = 0, end = [self length];
    BOOL stop = NO;
    while (location < end && !stop) {
        NSRange attachmentRange = [string rangeOfString:attachmentString options:0 range:NSMakeRange(location,end-location)];
        if (attachmentRange.length == 0)
            break;
        
        OATextAttachment *attachment = [self attribute:NSAttachmentAttributeName atIndex:attachmentRange.location effectiveRange:NULL];
        OBASSERT(attachment);
        applier(attachment, &stop);
        
        location = NSMaxRange(attachmentRange);
    }
}

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
+ (NSAttributedString *)attributedStringWithImage:(NSImage *)anImage;
{
    OAInlineImageTextAttachmentCell *imageCell = [[OAInlineImageTextAttachmentCell alloc] initImageCell:anImage];
    OATextAttachment *attach = [[OATextAttachment alloc] initWithFileWrapper:nil];
    [attach setAttachmentCell:(id <NSTextAttachmentCell>)imageCell];

    NSAttributedString *result = [self attributedStringWithAttachment:attach];
    return result;
}
#endif

// Use -initWithHTML:options:documentAttributes:?
#if 0
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
#endif

// Use -dataFromRange:documentAttributes:error: with  NSDocumentTypeDocumentAttribute = NSHTMLTextDocumentType?
#if 0
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
#endif

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- (NSData *)rtf;
{
    return [self RTFFromRange:NSMakeRange(0, [self length]) documentAttributes:@{}];
}
#endif

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
// ASSUMPTION: These are for one line
- (void)drawInRectangle:(NSRect)rectangle verticallyCentered:(BOOL)verticallyCenter;
{
    if (verticallyCenter) {
        NSRect boundingRect = [self boundingRectWithSize:rectangle.size options:NSStringDrawingTruncatesLastVisibleLine | NSStringDrawingUsesLineFragmentOrigin context:nil];
        rectangle = OAInsetRectBySize(rectangle, NSMakeSize(0, (NSHeight(rectangle) - NSHeight(boundingRect)) / 2.0f));
    }
    
    [self drawWithRect:rectangle options:NSStringDrawingTruncatesLastVisibleLine | NSStringDrawingUsesLineFragmentOrigin context:nil];
}

- (void)drawInRectangle:(NSRect)rectangle alignment:(NSTextAlignment)alignment verticallyCentered:(BOOL)verticallyCenter;
{
    NSMutableParagraphStyle *pStyle = [[NSMutableParagraphStyle alloc] init];
    pStyle.alignment = alignment;
    [self drawInRectangle:rectangle paragraphStyle:pStyle verticallyCentered:verticallyCenter];
}

- (void)drawInRectangle:(NSRect)rectangle alignment:(NSTextAlignment)alignment lineBreakMode:(NSLineBreakMode)lineBreakMode verticallyCentered:(BOOL)verticallyCenter;
{
    NSMutableParagraphStyle *pStyle = [[NSMutableParagraphStyle alloc] init];
    pStyle.alignment = alignment;
    pStyle.lineBreakMode = lineBreakMode;
    [self drawInRectangle:rectangle paragraphStyle:pStyle verticallyCentered:verticallyCenter];
}

- (void)drawInRectangle:(NSRect)rectangle paragraphStyle:(NSParagraphStyle *)pStyle verticallyCentered:(BOOL)verticallyCenter;
{
#ifdef OMNI_ASSERTIONS_ON
    [self enumerateAttribute:NSParagraphStyleAttributeName inRange:NSMakeRange(0, self.length) options:0 usingBlock:^(id value, NSRange range, BOOL *stop) {
        if (value) {
            OBASSERT_NOT_REACHED("This is a convenience method for mashing a paragraph style into an attributed string and drawing it. If you are already providing paragraph styles provide all attributes as desired and call drawWithRect:options: instead");
            *stop = YES;
        }
    }];
#endif
    
    NSMutableAttributedString *mutableCopy = [self mutableCopy];
    [mutableCopy addAttribute:NSParagraphStyleAttributeName value:pStyle range:NSMakeRange(0, mutableCopy.length)];
    
    [mutableCopy drawInRectangle:rectangle verticallyCentered:verticallyCenter];
}

- (void)drawCenteredShrinkingToFitInRect:(NSRect)rect;
{
    NSSize size = [self size];
    CGFloat scale = MIN(NSWidth(rect) / size.width, NSHeight(rect) / size.height);
    if (scale >= 1.0) {
	rect.origin.y += (NSHeight(rect) - size.height) / 2.0f;
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
#endif

@end


#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
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

- (NSSize)cellSize
{
    return [[self image] size];
}

@end
#endif


