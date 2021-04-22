// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorButton.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorSlice.h>

#import "OUIParameters.h"

@implementation OUIInspectorButton

+ (CGFloat)buttonHeight;
{
    return 29.0f;
}

static id _commonInit(OUIInspectorButton *self)
{
    self.opaque = NO;
    self.backgroundColor = nil;
    self.clearsContextBeforeDrawing = YES;
    
    self.adjustsImageWhenHighlighted = NO;
    self.adjustsImageWhenDisabled = YES;
    
    [self setTitleColor:self.tintColor forState:UIControlStateNormal];
    [self setTitleColor:[OUIInspector disabledLabelTextColor] forState:UIControlStateDisabled];

    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

#pragma mark - UIView subclass

- (CGSize)intrinsicContentSize
{
    return CGSizeMake(UIViewNoIntrinsicMetric, [[self class] buttonHeight]);
}

- (void)tintColorDidChange;
{
    [self setTitleColor:self.tintColor forState:UIControlStateNormal];
}

#ifdef OMNI_ASSERTIONS_ON
- (void)layoutSubviews;
{
    OBASSERT(CGRectEqualToRect(self.bounds, CGRectZero) || self.bounds.size.height == [[self class] buttonHeight]);
    [super layoutSubviews];
}
#endif

@end
