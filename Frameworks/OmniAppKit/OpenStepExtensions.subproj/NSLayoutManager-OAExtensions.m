// Copyright 2006, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSLayoutManager-OAExtensions.h"

#import <Cocoa/Cocoa.h>
#import <OmniBase/OmniBase.h>

#import "NSTextStorage-OAExtensions.h"

RCS_ID("$Id$");

@implementation NSLayoutManager (OAExtensions)

- (NSTextContainer *)textContainerForCharacterIndex:(unsigned int)characterIndex;
{
    OBPRECONDITION(characterIndex < [[self textStorage] length]);
    
    NSRange charRange = NSMakeRange(characterIndex, 1);
    NSRange glyphRange = [self glyphRangeForCharacterRange:charRange actualCharacterRange:NULL];
    
    NSTextContainer *container = [self textContainerForGlyphAtIndex:glyphRange.location effectiveRange:NULL];
    OBASSERT(container);
    
    return container;
}

- (NSRect)attachmentFrameAtGlyphIndex:(unsigned int)glyphIndex;
{
    // "Glyph locations are relative the their line fragment bounding rect's origin"
    NSRect lineFragmentRect = [self lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:NULL];
    //NSLog(@"      line point = %@", NSStringFromPoint(lineFragmentRect.origin));
    
    NSRect attachmentRect;
    attachmentRect.origin = [self locationForGlyphAtIndex:glyphIndex];
    attachmentRect.size   = [self attachmentSizeForGlyphAtIndex:glyphIndex];
    
    attachmentRect.origin.x += lineFragmentRect.origin.x;
    attachmentRect.origin.y += lineFragmentRect.origin.y - attachmentRect.size.height;
    
    return attachmentRect;
}

- (NSRect)attachmentFrameAtCharacterIndex:(unsigned int)charIndex;
{
    NSRange glyphRange = [self glyphRangeForCharacterRange:(NSRange){charIndex, 1} actualCharacterRange:NULL];
    return [self attachmentFrameAtGlyphIndex:glyphRange.location];
}

- (NSRect)attachmentRectForAttachmentAtCharacterIndex:(unsigned int)characterIndex inFrame:(NSRect)layoutFrame;
{
    NSRect attachmentRect = [self attachmentFrameAtCharacterIndex:characterIndex];
    attachmentRect.origin.x += layoutFrame.origin.x;
    attachmentRect.origin.y += layoutFrame.origin.y;
    return attachmentRect;
}

- (NSTextAttachment *)attachmentAtPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container;
{
    // Point is in the text containers coordinate system.  Also, this returns the *nearest* glyph.
    unsigned int glyphIndex = [self glyphIndexForPoint:point inTextContainer:container];
    
    if (glyphIndex >= [self numberOfGlyphs])
        // This most likely hits when -numberOfGlyphs == 0
        return nil;
    
    NSRect attachmentRect = [self attachmentFrameAtGlyphIndex:glyphIndex];
    if (!NSPointInRect(point, attachmentRect))
        return nil;
    
    unsigned int charIndex = [self characterIndexForGlyphAtIndex:glyphIndex];
    return [[self textStorage] attachmentAtCharacterIndex:charIndex];
}

// Returns the actual height used.  This is formed by computing the sum over the N-1 containers and the used rect of the Nth container.
- (float)totalHeightUsed;
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
    unsigned int glyphCount = [self numberOfGlyphs];
    if (glyphCount == 0)
        return 0.0f;
    [self lineFragmentRectForGlyphAtIndex:glyphCount-1 effectiveRange:NULL];
    
    NSTextContainer *textContainer;
    float totalHeight = 0;
    NSArray *textContainers = [self textContainers];
    unsigned int tcIndex, tcCount = [textContainers count];
    for (tcIndex = 0; tcIndex < tcCount - 1; tcIndex++) {
        textContainer = [textContainers objectAtIndex:tcIndex];
        NSSize containerSize = [textContainer containerSize];
        totalHeight += containerSize.height;
    }
    
    textContainer = [textContainers lastObject];
    NSRect usedRect = [self usedRectForTextContainer:textContainer];
    totalHeight += usedRect.size.height;
    
    return totalHeight;
}

- (float)widthOfLongestLine;
{
    NSTextStorage *textStorage = [self textStorage];
    unsigned int characterCount = [textStorage length];
    if (!characterCount)
        return 0.0f;
    
    NSRange glyphRange = [self glyphRangeForCharacterRange:(NSRange){0, characterCount} actualCharacterRange:NULL];
    if (glyphRange.length == 0)
        return 0.0f;
    
    unsigned int glyphLocation = glyphRange.location;
    unsigned int glyphEnd = glyphRange.location + glyphRange.length;
    
    float maximumLineLength = 0.0f;
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
	    
	    NSRect glyphBounds = [self boundingRectForGlyphRange:clippedGlyphRange inTextContainer:container];
	    
	    //NSLog(@"glyphRange = %@, lineFrag = %@, glyphBounds = %@", NSStringFromRange(clippedGlyphRange), NSStringFromRect(lineFrag), NSStringFromRect(glyphBounds));
	    
	    maximumLineLength = MAX(glyphBounds.size.width, maximumLineLength);
	}
	
        // Step by the unclipped glyph range or we'll go into an infinite loop when we chop off a newline
        glyphLocation = lineGlyphRange.location + lineGlyphRange.length;
    }
    
    return maximumLineLength;
}

@end
