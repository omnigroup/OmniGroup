// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITextSelectionSpan.h>

#import <OmniUI/OUITextView.h>
#import <OmniUI/NSTextStorage-OUIExtensions.h>

#import <OmniAppKit/OAColor.h>
#import <OmniAppKit/OAFontDescriptor.h>

RCS_ID("$Id$");

@implementation OUITextSelectionSpan

- initWithRange:(UITextRange *)range inTextView:(OUITextView *)textView;
{
    OBPRECONDITION(range);
    OBPRECONDITION(textView);
    
    if (!(self = [super init]))
        return nil;
    
    _range = range;
    _textView = textView;
    _textStorage = textView.textStorage.underlyingTextStorage;
    
    return self;
}

#pragma mark - OUIColorInspection

- (OAColor *)colorForInspectorSlice:(OUIInspectorSlice *)inspector;
{
    UIColor *color = (UIColor *)[_textView attribute:NSForegroundColorAttributeName inRange:_range];
    if (color == nil)
        return nil;

    return [OAColor colorWithPlatformColor:color];
}

- (void)setColor:(OAColor *)color fromInspectorSlice:(OUIInspectorSlice *)inspector;
{
    [_textView setValue:[color toColor] forAttribute:NSForegroundColorAttributeName inRange:_range];
}

- (NSString *)preferenceKeyForInspectorSlice:(OUIInspectorSlice *)inspector;
{
    return nil;
}

#pragma mark - OUIFontInspection

- (OAFontDescriptor *)fontDescriptorForInspectorSlice:(OUIInspectorSlice *)inspector;
{
    // If the text storage has a font descriptor registered, use that.
    // This is mostly of interest to OmniStyle where we record the font descriptor as the desired font in our text storage and the other attributes are the derived values.
    // As a concreted example, we don't want to change a "family=Helvetica" descriptor to "font=Helvetica" descriptor by going through -initWithFont:
    
    OAFontDescriptor *fontDescriptor = (OAFontDescriptor *)[_textView attribute:OAFontDescriptorAttributeName inRange:_range];
    if (fontDescriptor)
        return fontDescriptor;
    
    UIFont *font = (UIFont *)[_textView attribute:NSFontAttributeName inRange:_range];
    if (!font)
        return nil;
    
    return [[OAFontDescriptor alloc] initWithFont:font];
}

- (void)setFontDescriptor:(OAFontDescriptor *)fontDescriptor fromInspectorSlice:(OUIInspectorSlice *)inspector;
{
    UIFont *newFont;
    
    if (fontDescriptor)
        newFont = [fontDescriptor font];
    else
        newFont = NULL;
    
    [_textView setValue:newFont forAttribute:NSFontAttributeName inRange:_range];
}

- (CGFloat)fontSizeForInspectorSlice:(OUIInspectorSlice *)inspector;
{
    UIFont *font = (UIFont *)[_textView attribute:NSFontAttributeName inRange:_range];
    if (!font)
        return 0;
    
    return [font pointSize];
}

- (void)setFontSize:(CGFloat)fontSize fromInspectorSlice:(OUIInspectorSlice *)inspector;
{
    UIFont *oldFont = (UIFont *)[_textView attribute:NSFontAttributeName inRange:_range];
    if (!oldFont)
        return; // This shouldn't happen; OUITextView will ensure that all spans have fonts.
    
    UIFont *newFont = [oldFont fontWithSize:fontSize];
    [_textView setValue:newFont forAttribute:NSFontAttributeName inRange:_range];
}

- (NSUnderlineStyle)underlineStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
{
    return [(NSNumber *)[_textView attribute:NSUnderlineStyleAttributeName inRange:_range] integerValue];
}

- (void)setUnderlineStyle:(NSUnderlineStyle)underlineStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;
{
    [_textView setValue:@(underlineStyle) forAttribute:NSUnderlineStyleAttributeName inRange:_range];
}

- (NSUnderlineStyle)strikethroughStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
{
    return [(NSNumber *)[_textView attribute:NSStrikethroughStyleAttributeName inRange:_range] integerValue];
}

- (void)setStrikethroughStyle:(NSUnderlineStyle)strikethroughStyle fromInspectorSlice:(OUIInspectorSlice *)inspector;
{
    [_textView setValue:@(strikethroughStyle) forAttribute:NSStrikethroughStyleAttributeName inRange:_range];
}

#pragma mark - OUIParagraphInspection

- (NSParagraphStyle *)paragraphStyleForInspectorSlice:(OUIInspectorSlice *)inspector;
{
    NSParagraphStyle *pgStyle = (NSParagraphStyle *)[_textView attribute:NSParagraphStyleAttributeName inRange:_range];
    if (!pgStyle)
        return [NSParagraphStyle defaultParagraphStyle];
    return pgStyle;
}

- (void)setParagraphStyle:(NSParagraphStyle *)paragraphDescriptor fromInspectorSlice:(OUIInspectorSlice *)inspector;
{
    UITextRange *paragraphStart = [_textView.tokenizer rangeEnclosingPosition:_range.start withGranularity:UITextGranularityParagraph inDirection:UITextStorageDirectionBackward];
    UITextRange *paragraphEnd = [_textView.tokenizer rangeEnclosingPosition:_range.end withGranularity:UITextGranularityParagraph inDirection:UITextStorageDirectionForward];
    
    UITextRange *fullRange = [_textView textRangeFromPosition:paragraphStart.start toPosition:paragraphEnd.end];
    
    [_textView setValue:paragraphDescriptor forAttribute:NSParagraphStyleAttributeName inRange:fullRange];
}

@end
