// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ScalingView.h"

RCS_ID("$Id$")

@implementation ScalingView

/*
- (void)drawRect:(CGRect)rect;
 */

// Subclass this to draw w/in a scaled (and possibly flipped) coordinate system.
- (void)drawScaledContent:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    [[UIColor redColor] set];
    CGContextFillRect(ctx, self.bounds);
}

@end
