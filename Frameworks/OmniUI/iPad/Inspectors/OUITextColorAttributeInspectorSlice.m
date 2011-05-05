// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITextColorAttributeInspectorSlice.h>

#import <OmniUI/OUIEditableFrame.h>
#import <OmniQuartz/OQColor.h>
#import "OUEFTextSpan.h"

RCS_ID("$Id$")

@implementation OUITextColorAttributeInspectorSlice

@synthesize attributeName = _attributeName;

- initWithLabel:(NSString *)label attributeName:(NSString *)attributeName;
{
    OBPRECONDITION(![NSString isEmptyString:attributeName]);
    
    if (!(self = [super initWithLabel:label]))
        return nil;
    
    _attributeName = [attributeName copy];
    
    return self;
}

- (void)dealloc;
{
    [_attributeName release];
    [super dealloc];
}

#pragma mark -
#pragma mark OUIAbstractColorInspectorSlice subclass

- (OQColor *)colorForObject:(id)object;
{
    OBPRECONDITION([object isKindOfClass:[OUEFTextSpan class]]);
    OUEFTextSpan *span = object;
    
    CGColorRef backgroundColor = (CGColorRef)[span.frame attribute:_attributeName inRange:span];
    
    if (!backgroundColor)
        return nil;
    
    return [OQColor colorWithCGColor:backgroundColor];
}

- (void)setColor:(OQColor *)color forObject:(id)object;
{
    OBPRECONDITION([object isKindOfClass:[OUEFTextSpan class]]);
    OUEFTextSpan *span = object;

    [span.frame setValue:(id)[[color toColor] CGColor] forAttribute:(id)_attributeName inRange:span];
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object isKindOfClass:[OUEFTextSpan class]];
}

@end
