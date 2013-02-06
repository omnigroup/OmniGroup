// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import "OUIExportOptionsBackgroundView.h"

RCS_ID("$Id$")

@implementation OUIExportOptionsBackgroundView


- (id)initWithFrame:(CGRect)frame {
    
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code.
    }
    return self;
}

- (void)drawRect:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    CGContextSaveGState(ctx);
    {
        CGPoint start = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMinY(self.bounds)+75);
        CGFloat startRadius = 0;
        CGPoint end = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMinY(self.bounds));
        CGFloat endRadius = 200;
        
        NSArray *gradientColors = [NSArray arrayWithObjects:(id)[[UIColor colorWithRed:0.867f green:0.882f blue:0.894f alpha:1] CGColor], (id)[[UIColor colorWithRed:0.749f green:0.773f blue:0.796f alpha:1] CGColor], nil];
        CGGradientRef gradient = CGGradientCreateWithColors(NULL, (OB_BRIDGE CFArrayRef)gradientColors, NULL);
        CGContextDrawRadialGradient(ctx, gradient, start, startRadius, end, endRadius, kCGGradientDrawsBeforeStartLocation|kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(gradient);
    }
    CGContextRestoreGState(ctx);
}



@end
