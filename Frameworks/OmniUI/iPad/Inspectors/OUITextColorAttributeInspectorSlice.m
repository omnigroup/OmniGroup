// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITextColorAttributeInspectorSlice.h>

#import <OmniAppKit/OAColor.h>
#import <OmniUI/OUITextSelectionSpan.h>
#import <OmniUI/OUITextView.h>

RCS_ID("$Id$")

@implementation OUITextColorAttributeInspectorSlice

- initWithLabel:(NSString *)label attributeName:(NSString *)attributeName;
{
    OBPRECONDITION(![NSString isEmptyString:attributeName]);
    
    if (!(self = [super initWithLabel:label]))
        return nil;
    
    _attributeName = [attributeName copy];
    
    return self;
}

#pragma mark - OUIAbstractColorInspectorSlice subclass

- (OAColor *)colorForObject:(id)object;
{
    OBPRECONDITION([object isKindOfClass:[OUITextSelectionSpan class]]);
    OUITextSelectionSpan *span = object;

    UIColor *backgroundColor = (UIColor *)[span.textView attribute:_attributeName inRange:span.range];
    if (!backgroundColor)
        return nil;
    
    return [OAColor colorWithPlatformColor:backgroundColor];
}

- (void)setColor:(OAColor *)color forObject:(id)object;
{
    OBPRECONDITION([object isKindOfClass:[OUITextSelectionSpan class]]);
    OUITextSelectionSpan *span = object;

    [span.textView setValue:[color toColor] forAttribute:_attributeName inRange:span.range];
}

#pragma mark - OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object isKindOfClass:[OUITextSelectionSpan class]];
}

@end
