// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUISliceSeparatorView.h"

RCS_ID("$Id$")

@implementation OUISliceSeparatorView

- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    CGFloat contentScaleFactor = self.contentScaleFactor;
    if ((CGRectGetHeight(bounds) <= 0.0f) || (CGRectGetWidth(bounds) <= 0.0f))
        return; // Nothing to do here
    
    [[UIColor whiteColor] set];
    UIRectFill(bounds);
    
    [[UIColor colorWithWhite:0.9 alpha:1.0] set];
    UIBezierPath *path = [UIBezierPath bezierPath];
    path.lineWidth = 1.0f / contentScaleFactor;
    [path moveToPoint:(CGPoint){ .x = CGRectGetMinX(bounds), .y = CGRectGetMaxY(rect) - (path.lineWidth/2.0)}];
    [path addLineToPoint:(CGPoint){ .x = CGRectGetMinX(rect) + CGRectGetWidth(rect), .y = CGRectGetMaxY(rect) - (path.lineWidth/2.0)}];
    [path stroke];
}

@end
