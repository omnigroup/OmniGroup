// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUEFTextSpan.h"

#import <CoreText/CoreText.h>
#import <OmniQuartz/OQColor.h>
#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniAppKit/OAParagraphStyle.h>
#import <OmniAppKit/OATextAttributes.h>
#import <OmniUI/OUIEditableFrame.h>
#import <OmniUI/OUIColorInspectorSlice.h>
#import <OmniUI/OUIFontInspectorSlice.h>
#import <OmniBase/rcsid.h>

#import "OUEFTextPosition.h"


RCS_ID("$Id$");


@implementation OUEFTextSpan

- initWithRange:(NSRange)characterRange generation:(NSUInteger)g editor:(OUIEditableFrame *)ed; // D.I.
{
    if ((self = [super initWithRange:characterRange generation:g]) != nil) {
        frame = [ed retain];
    }
    return self;
}

@synthesize frame;

- (void)dealloc
{
    [frame release];
    [super dealloc];
}

- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[self class]])
        return NO;
    
    OUEFTextSpan *o = (OUEFTextSpan *)other;
    
    return ( frame == o->frame ) && ( [super isEqual:o] );
}

- (NSUInteger)hash;
{
    return [super hash] ^ ( ( (uintptr_t)frame ) >> 4 );
}

#if 0 /* NSObject just does -conformsToProtocol:, which is good enough right now */
- (BOOL)shouldBeInspectedByInspectorSlice:(OUIInspectorSlice *)inspector protocol:(Protocol *)protocol;
{
    ...;
}
#endif

#pragma mark OUIFontInspection

- (OAFontDescriptor *)fontDescriptorForInspectorSlice:(OUIInspectorSlice *)inspector;
{
    // If the text storage has a font descriptor registered, use that.
    // This is mostly of interest to OmniStyle where we record the font descriptor as the desired font in our text storage and the other attributes are the derived values.
    // As a concreted example, we don't want to change a "family=Helvetica" descriptor to "font=Helvetica" descriptor by going through -initWithFont:
    
    OAFontDescriptor *fontDescriptor = (OAFontDescriptor *)[frame attribute:(id)OAFontDescriptorAttributeName inRange:self];
    if (fontDescriptor)
        return fontDescriptor;
    
    CTFontRef ctFont = (CTFontRef)[frame attribute:(id)kCTFontAttributeName inRange:self];
    if (!ctFont)
        return nil;
    
    return [[[OAFontDescriptor alloc] initWithFont:ctFont] autorelease];
}

- (void)setFontDescriptor:(OAFontDescriptor *)fontDescriptor fromInspectorSlice:(OUIInspectorSlice *)inspector;
{
    CTFontRef newFont;
    
    if (fontDescriptor)
        newFont = [fontDescriptor font];
    else
        newFont = NULL;
    
    [frame setValue:(id)newFont forAttribute:(id)kCTFontAttributeName inRange:self];
}

- (CGFloat)fontSizeForInspectorSlice:(OUIInspectorSlice *)inspector;
{
    CTFontRef ctFont = (CTFontRef)[frame attribute:(id)kCTFontAttributeName inRange:self];
    if (!ctFont)
        return 0;
    
    return CTFontGetSize(ctFont);
}

- (void)setFontSize:(CGFloat)fontSize fromInspectorSlice:(OUIInspectorSlice *)inspector;
{
    CTFontRef oldFont = (CTFontRef)[frame attribute:(id)kCTFontAttributeName inRange:self];
    if (!oldFont)
        return; // This shouldn't happen; OUIEditableFrame will ensure that all spans have fonts.
    
    CTFontRef newFont = CTFontCreateCopyWithAttributes(oldFont, fontSize, NULL, NULL);
    [frame setValue:(id)newFont forAttribute:(id)kCTFontAttributeName inRange:self];
    if (newFont)
        CFRelease(newFont);
}

- (CTUnderlineStyle)underlineStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
{
    return [(NSNumber *)[frame attribute:OAUnderlineStyleAttributeName inRange:self] intValue];
}

- (void)setUnderlineStyle:(CTUnderlineStyle)underlineStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;
{
    NSNumber *value = [[NSNumber alloc] initWithInt:underlineStyle];
    [frame setValue:value forAttribute:OAUnderlineStyleAttributeName inRange:self];
    [value release];
}

- (CTUnderlineStyle)strikethroughStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
{
    return [(NSNumber *)[frame attribute:OAStrikethroughStyleAttributeName inRange:self] intValue];
}

- (void)setStrikethroughStyle:(CTUnderlineStyle)strikethroughStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;
{
    NSNumber *value = [[NSNumber alloc] initWithInt:strikethroughStyle];
    [frame setValue:value forAttribute:OAStrikethroughStyleAttributeName inRange:self];
    [value release];
}

#pragma mark OUIParagraphInspection

- (OAParagraphStyle *)paragraphStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
{
    CTParagraphStyleRef pstyle = (CTParagraphStyleRef)[frame attribute:(id)kCTParagraphStyleAttributeName inRange:self];
    if (!pstyle)
        return [OAParagraphStyle defaultParagraphStyle];
    return [[[OAParagraphStyle alloc] initWithCTParagraphStyle:pstyle] autorelease];
}

- (void)setParagraphStyle:(OAParagraphStyle *)paragraphDescriptor fromInspectorSlice:(OUIInspectorSlice *)inspector;
{
    OUEFTextRange *beginningParagraph = (OUEFTextRange *)[[frame tokenizer] rangeEnclosingPosition:start withGranularity:UITextGranularityParagraph inDirection:UITextStorageDirectionForward];
    
    OUEFTextRange *fullParagraph;
    if (![beginningParagraph includesPosition:end]) {
        OUEFTextRange *endingParagraph = (OUEFTextRange *)[[frame tokenizer] rangeEnclosingPosition:end withGranularity:UITextGranularityParagraph inDirection:UITextStorageDirectionBackward];
        fullParagraph = [beginningParagraph rangeIncludingPosition:(OUEFTextPosition *)endingParagraph.end];
    } else
        fullParagraph = beginningParagraph;
    
    CTParagraphStyleRef newStyle = [paragraphDescriptor copyCTParagraphStyle];
    [frame setValue:(id)newStyle forAttribute:(id)kCTParagraphStyleAttributeName inRange:fullParagraph];
    CFRelease(newStyle);
}

@end
