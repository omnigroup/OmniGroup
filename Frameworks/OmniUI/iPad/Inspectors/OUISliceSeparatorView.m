// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUISliceSeparatorView.h"
#import <OmniUI/OUIInspectorSlice.h>

RCS_ID("$Id$")

@interface OUISliceSeparatorView ()
@property (readwrite,copy) UIColor *strokeColor;
@end

@implementation OUISliceSeparatorView

static id _commonInit(OUISliceSeparatorView *self)
{
    self.backgroundColor = [UIColor clearColor];
    self.strokeColor = [OUIInspectorSlice sliceSeparatorColor];
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

- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    CGFloat contentScaleFactor = self.contentScaleFactor;
    if ((CGRectGetHeight(bounds) <= 0.0f) || (CGRectGetWidth(bounds) <= 0.0f))
        return; // Nothing to do here
    
    [self.backgroundColor set];
    UIRectFill(bounds);
    
    [self.strokeColor set];
    UIBezierPath *path = [UIBezierPath bezierPath];
    path.lineWidth = 1.0f / contentScaleFactor;
    [path moveToPoint:(CGPoint){ .x = CGRectGetMinX(bounds), .y = CGRectGetMaxY(rect) - (path.lineWidth/2.0)}];
    [path addLineToPoint:(CGPoint){ .x = CGRectGetMinX(rect) + CGRectGetWidth(rect), .y = CGRectGetMaxY(rect) - (path.lineWidth/2.0)}];
    [path stroke];
}

@end
