// Copyright 2006-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSLayoutManager-OAExtensions.h>

#import <OmniAppKit/NSAttributedString-OAExtensions.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/NSTextContainer.h>
#else
#import <Cocoa/Cocoa.h>
#import <OmniAppKit/NSTextStorage-OAExtensions.h>
#endif

#import <OmniBase/OmniBase.h>


RCS_ID("$Id$");

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
@interface NSObject (Radar_19771353)
@end
@implementation NSObject (Radar_19771353)
// 2015-02-09 13:52:56.113 RulerTest[43156:423665] -[_NSLayoutManagerRulerHelper defaultLineHeightForFont:]: unrecognized selector sent to instance 0x6080000a2a00
- (CGFloat)defaultLineHeightForFont:(NSFont *)font;
{
    return ceil([font ascender] + fabs([font descender]) + [font leading]);
}

@end
#endif

@implementation NSLayoutManager (OAExtensions)

- (NSTextContainer *)textContainerForCharacterIndex:(NSUInteger)characterIndex;
{
    OBPRECONDITION(characterIndex < [[self textStorage] length]);
    
    NSRange charRange = NSMakeRange(characterIndex, 1);
    NSRange glyphRange = [self glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
    
    NSTextContainer *container = [self textContainerForGlyphAtIndex:glyphRange.location effectiveRange:NULL];
    OBASSERT(container);
    
    return container;
}

- (CGRect)attachmentFrameAtGlyphIndex:(NSUInteger)glyphIndex;
{
    // "Glyph locations are relative the their line fragment bounding rect's origin"
    CGRect lineFragmentRect = [self lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:NULL];
    //NSLog(@"      line point = %@", NSStringFromPoint(lineFragmentRect.origin));
    
    CGRect attachmentRect;
    attachmentRect.origin = [self locationForGlyphAtIndex:glyphIndex];
    attachmentRect.size   = [self attachmentSizeForGlyphAtIndex:glyphIndex];
    
    attachmentRect.origin.x += lineFragmentRect.origin.x;
    attachmentRect.origin.y += lineFragmentRect.origin.y - attachmentRect.size.height;
    
    return attachmentRect;
}

- (CGRect)attachmentFrameAtCharacterIndex:(NSUInteger)charIndex;
{
    NSRange glyphRange = [self glyphRangeForCharacterRange:(NSRange){charIndex, 1} actualCharacterRange:NULL];
    return [self attachmentFrameAtGlyphIndex:glyphRange.location];
}

- (CGRect)attachmentRectForAttachmentAtCharacterIndex:(NSUInteger)characterIndex inFrame:(CGRect)layoutFrame;
{
    CGRect attachmentRect = [self attachmentFrameAtCharacterIndex:characterIndex];
    attachmentRect.origin.x += layoutFrame.origin.x;
    attachmentRect.origin.y += layoutFrame.origin.y;
    return attachmentRect;
}

- (NSTextAttachment *)attachmentAtPoint:(CGPoint)point inTextContainer:(NSTextContainer *)container;
{
    // Point is in the text containers coordinate system.  Also, this returns the *nearest* glyph.
    NSUInteger glyphIndex = [self glyphIndexForPoint:point inTextContainer:container];
    
    if (glyphIndex >= [self numberOfGlyphs])
        // This most likely hits when -numberOfGlyphs == 0
        return nil;
    
    CGRect attachmentRect = [self attachmentFrameAtGlyphIndex:glyphIndex];
    if (!CGRectContainsPoint(attachmentRect, point))
        return nil;
    
    NSUInteger charIndex = [self characterIndexForGlyphAtIndex:glyphIndex];
    return [[self textStorage] attachmentAtCharacterIndex:charIndex];
}

// Returns the actual height used.  This is formed by computing the sum over the N-1 containers and the used rect of the Nth container.
- (CGFloat)totalHeightUsed;
{
    // Make sure all layout has happened.  It won't if we get called during the middle of editing due to the field editor using our layout manager:
    /*
     -titleRectForBounds: calls us...
#0  -[OOLiveTextFieldCell titleRectForBounds:] (self=0x633d8b0, _cmd=0x906db358, rect={origin = {x = 72, y = 18}, size = {width = 551, height = 42}}) at OOLiveTextFieldCell.m:145
#1  0x00032650 in -[OOOutlineCell titleRectForBounds:] (self=0x633d780, _cmd=0x906db358, cellFrame={origin = {x = 19, y = 18}, size = {width = 604, height = 42}}) at OOOutlineCell.m:385
#2  0x000327e8 in -[OOOutlineCell editorFrameForRect:] (self=0x633d780, _cmd=0x31a610, aRect={origin = {x = 19, y = 18}, size = {width = 604, height = 42}}) at OOOutlineCell.m:525
#3  0x0001fba4 in -[OOOutlineView(Layout) layoutCells] (self=0x6301050, _cmd=0x32ccb0) at OOOutlineView-Layout.m:103
#4  0x0002896c in -[OOOutlineView(Layout) layoutCellsIfNecessary] (self=0x6301050, _cmd=0x32c714) at OOOutlineView-Layout.m:133
#5  0x000d2b84 in -[OOOutlineView windowWillDisplayIfNeeded:] (self=0x6301050, _cmd=0x32d9e0, aNotification=0x5ce01c0) at OOOutlineView.m:2155
#6  0x97dfab40 in _nsNotificationCenterCallBack ()
     */
    NSUInteger glyphCount = [self numberOfGlyphs];
    if (glyphCount == 0)
        return 0.0f;
    [self lineFragmentRectForGlyphAtIndex:glyphCount-1 effectiveRange:NULL];
    
    NSTextContainer *textContainer;
    CGFloat totalHeight = 0;
    NSArray *textContainers = [self textContainers];
    NSUInteger tcIndex, tcCount = [textContainers count];
    for (tcIndex = 0; tcIndex < tcCount - 1; tcIndex++) {
        textContainer = [textContainers objectAtIndex:tcIndex];
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
        CGSize containerSize = textContainer.size;
#else
        CGSize containerSize = [textContainer containerSize];
#endif
        totalHeight += containerSize.height;
    }
    
    textContainer = [textContainers lastObject];
    // CGSize originalSize = textContainer.size;
    // textContainer.size = (CGSize){.width = originalSize.width, .height = 0.0};
    CGRect usedRect = [self usedRectForTextContainer:textContainer];
    totalHeight += usedRect.size.height;
    // textContainer.size = originalSize;

    return totalHeight;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
/*
 
 -[NSLayoutManager totalHeight] returns zero when it is empty, so we need to do sizing with the attributes.
 
 But, due do 14313143 (TextKit: String drawing and layout manager disagree about sizing), we can't use the NSStringDrawing.h methods.
 
 For most fonts (other than "Helvetica"), the NSStringDrawing.h methods and NSLayoutManger end up with slightly different results. This calculates the height with a text system so that NSLayoutManager-drawn text and a UITextView can agree on sizing.
 */
+ (CGFloat)heightForAttributes:(NSDictionary *)attributes;
{
    OBPRECONDITION([NSThread mainThread]); // We probably could do this on multiple threads as far as the frameworks should be concerned, but we've not tested if UIKit's text system is thread-safe.
    
    static dispatch_once_t onceToken;
    static NSCache *HeightForAttributesCache = nil;
    dispatch_once(&onceToken, ^{
        HeightForAttributesCache = [[NSCache alloc] init];
    });
    
    if (!attributes) {
        attributes = @{};
    }
    else {
        attributes = [self _dictionaryMinusAttributesNotRelevantForHeightCalculation:attributes];
    }

    NSNumber *heightNumber = [HeightForAttributesCache objectForKey:attributes];
    if (heightNumber)
        return [heightNumber cgFloatValue];
    
    // NOTE: This doesn't account for custom layout done by subclasses
    OBASSERT(self == [NSLayoutManager class]);
    
    NSTextStorage *textStorage = [[NSTextStorage alloc] initWithString:@" " attributes:attributes];
    NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
    [textStorage addLayoutManager:layoutManager];
    
    NSTextContainer *textContainer = [[NSTextContainer alloc] initWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    [layoutManager addTextContainer:textContainer];
    
    [layoutManager ensureLayoutForTextContainer:textContainer];
    
    CGFloat height = [layoutManager totalHeightUsed];
    
    [HeightForAttributesCache setObject:@(height) forKey:attributes];
    return height;
}

+ (NSDictionary *)_dictionaryMinusAttributesNotRelevantForHeightCalculation:(NSDictionary *)originalAttributes
{
    // <bug:///146279> (iOS-OmniOutliner Engineering: *** Expected deallocation of <OSStyleContext:0x61800086e880> 3.15s ago)
    // PBS 7 July 2017: Remove colors and OSStyle objects. This is conservative: it may not get rid of every single irrelevant attribute. The main thing is to get rid of OSStyle objects, so they don't end up cached and thus outliving their expected lifetime (which causes their OSStyleContext to outlive expectation).
    // This may have the side effect of fewer cache misses in heightForAttributes:, but it comes at the cost of more-expensive key creation.
    static dispatch_once_t onceToken;
    static NSArray *irrelevantKeys = nil;
    static Class styleClass = nil;
    dispatch_once(&onceToken, ^{
        irrelevantKeys = @[NSForegroundColorAttributeName, NSBackgroundColorAttributeName, NSStrokeColorAttributeName, NSUnderlineColorAttributeName, NSStrikethroughColorAttributeName];
        styleClass = NSClassFromString(@"OSStyle");
    });

    NSMutableDictionary *attributes = [originalAttributes mutableCopy];
    [attributes removeObjectsForKeys:irrelevantKeys];

    if (styleClass) {
        NSMutableArray *keysToRemove = [NSMutableArray array];
        [attributes enumerateKeysAndObjectsUsingBlock:^(id key, id object, BOOL *stop) {
            if ([object isKindOfClass:styleClass]) {
                [keysToRemove addObject:key];
            }
            else if ([object isKindOfClass:[NSArray class]]) {
                if ([self _array:(NSArray *)object containsAnyObjectOfClass:styleClass]) {
                    [keysToRemove addObject:key];
                }
            }
        }];
        [attributes removeObjectsForKeys:keysToRemove];
    }

    return [attributes copy];
}

+ (BOOL)_array:(NSArray *)potentialStylesArray containsAnyObjectOfClass:(Class)class
{
    for (id oneObject in potentialStylesArray) {
        if ([oneObject isKindOfClass:class]) {
            return YES;
        }
    }
    return NO;
}

#endif

- (CGFloat)widthOfLongestLine;
{
    NSTextStorage *textStorage = [self textStorage];
    NSUInteger characterCount = [textStorage length];
    if (!characterCount)
        return 0.0f;
    
    NSRange glyphRange = [self glyphRangeForCharacterRange:(NSRange){0, characterCount} actualCharacterRange:NULL];
    if (glyphRange.length == 0)
        return 0.0f;
    
    NSUInteger glyphLocation = glyphRange.location;
    NSUInteger glyphEnd = glyphRange.location + glyphRange.length;
    
    CGFloat maximumLineLength = 0.0f;
    while (glyphLocation < glyphEnd) {
        // The line fragment rect isn't what we want (if text is right aligned, it will span the width of the line from the left edge of the text container).  We want the glyph bounds...
        NSRange lineGlyphRange;
        [self lineFragmentRectForGlyphAtIndex:glyphLocation effectiveRange:&lineGlyphRange];
	
        // Look at the last character of the given line.  If it is a line breaking character, don't include it in the measurements.  Otherwise, the glyph bounds will extend to the end of the text container.
        NSRange lineCharRange = [self characterRangeForGlyphRange:lineGlyphRange actualGlyphRange:NULL];
        NSRange clippedGlyphRange = lineGlyphRange;
        if (lineCharRange.length) {
            unichar c = [[textStorage string] characterAtIndex:lineCharRange.location + lineCharRange.length - 1];
            if (c == '\n' || c == '\r') { // Other Unicode newline characters?
					  // Shorten the character range and get the new glyph range
                lineCharRange.length--;
                clippedGlyphRange = [self glyphRangeForCharacterRange:lineCharRange actualCharacterRange:NULL];
            }
        }
        if (!clippedGlyphRange.length) {
	    // Only a newline in this line; still need the update to glyphLocation below, though or we hang as in #20274
	} else {
	    NSTextContainer *container = [self textContainerForGlyphAtIndex:glyphLocation effectiveRange:NULL];
	    
	    CGRect glyphBounds = [self boundingRectForGlyphRange:clippedGlyphRange inTextContainer:container];
	    
	    //NSLog(@"glyphRange = %@, lineFrag = %@, glyphBounds = %@", NSStringFromRange(clippedGlyphRange), NSStringFromRect(lineFrag), NSStringFromRect(glyphBounds));
	    
	    maximumLineLength = MAX(glyphBounds.size.width, maximumLineLength);
	}
	
        // Step by the unclipped glyph range or we'll go into an infinite loop when we chop off a newline
        glyphLocation = lineGlyphRange.location + lineGlyphRange.length;
    }
    
    return maximumLineLength;
}

@end
