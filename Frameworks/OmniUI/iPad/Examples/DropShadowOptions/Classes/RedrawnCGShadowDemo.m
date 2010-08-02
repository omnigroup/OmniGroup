// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "RedrawnCGShadowDemo.h"

#import <QuartzCore/CALayer.h>

RCS_ID("$Id$")

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
