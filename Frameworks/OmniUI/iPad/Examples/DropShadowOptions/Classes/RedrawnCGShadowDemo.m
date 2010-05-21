//
//  RedrawnCGShadowDemo.m
//  DropShadowOptions
//
//  Created by Timothy J. Wood on 5/21/10.
//  Copyright 2010 The Omni Group. All rights reserved.
//

#import "RedrawnCGShadowDemo.h"

#import <QuartzCore/CALayer.h>

@implementation RedrawnCGShadowDemo

- (NSString *)name;
{
    return @"CoreGraphics, redrawn";
}

- (void)willMoveToWindow:(UIWindow *)newWindow;
{
    [super willMoveToWindow:newWindow];
    
    if (newWindow) {
        // This (and setting self.layer.needsDisplayOnBoundsChange) will redraw once at each end of the animation and cross-fade between the two caches. Probably nice enough for most uses.
        self.contentMode = UIViewContentModeRedraw;
    }
}

@end
