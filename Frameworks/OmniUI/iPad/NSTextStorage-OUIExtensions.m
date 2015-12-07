// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/NSTextStorage-OUIExtensions.h>

#import <OmniUI/OUITextSelectionSpan.h>
#import <OmniUI/OUITextView.h>

RCS_ID("$Id$")

@implementation NSTextStorage (OUIExtensions)

- (NSArray *)textSpansInRange:(NSRange)entireRange inTextView:(OUITextView *)textView;
{
    OBPRECONDITION(NSMaxRange(entireRange) <= [self length]); // Allow '==' for insertion point at the end of a text view
    
    // Return one span per run so that the higher level code can make different edits to each span (for example, turning on italic should keep the font face that was on each span or keep the boldness).
    
    NSMutableArray *spans = [NSMutableArray array];

    // An insertion point should be inspectable so we can control the typingAttributes from the inspector.
    if (entireRange.length == 0) {
        UITextRange *textRange = [textView textRangeForCharacterRange:entireRange];
        OUITextSelectionSpan *span = [[OUITextSelectionSpan alloc] initWithRange:textRange inTextView:textView];
        [spans addObject:span];
        return spans;
    }
    
    [self enumerateAttributesInRange:entireRange options:0 usingBlock:^(NSDictionary *attrs, NSRange range, BOOL *stop) {
        NSRange effective;
        /* NSDictionary *d = */ [self attributesAtIndex:range.location longestEffectiveRange:&effective inRange:range];
        UITextRange *textRange = [textView textRangeForCharacterRange:effective];
        OUITextSelectionSpan *span = [[OUITextSelectionSpan alloc] initWithRange:textRange inTextView:textView];
        [spans addObject:span];
    }];
    
    return spans;
}

- (NSTextStorage *)underlyingTextStorage;
{
    return self;
}

@end
