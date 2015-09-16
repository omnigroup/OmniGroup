// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ScalingView.h"

#import <OmniFoundation/OmniFoundation.h>
#import "Box.h"

RCS_ID("$Id$")

@implementation ScalingView

- (void)setBoxes:(NSArray *)boxes;
{
    if (OFISEQUAL(_boxes, boxes)) {
        return;
    }
    
    _boxes = [boxes copy];
    
    [self setNeedsDisplay];
}

- (void)boxBoundsWillChange:(Box *)box;
{
    CGAffineTransform modelToViewTransform = self.transformToRenderingSpace;
    CGRect dirty = CGRectApplyAffineTransform(box.bounds, modelToViewTransform);
    
    [self setNeedsDisplayInRect:dirty];
}

- (void)boxBoundsDidChange:(Box *)box;
{
    CGAffineTransform modelToViewTransform = self.transformToRenderingSpace;
    CGRect dirty = CGRectApplyAffineTransform(box.bounds, modelToViewTransform);

    [self setNeedsDisplayInRect:dirty];
}

// Subclass this to draw w/in a scaled (and possibly flipped) coordinate system.
- (void)drawScaledContent:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    [[UIColor whiteColor] set];
    CGContextFillRect(ctx, self.bounds);
    
    [[UIColor redColor] set];
    for (Box *box in _boxes) {
        CGContextFillRect(ctx, box.bounds);
    }
}

@end
