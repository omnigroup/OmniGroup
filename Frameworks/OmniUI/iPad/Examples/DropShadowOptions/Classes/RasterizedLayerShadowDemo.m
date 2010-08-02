// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "RasterizedLayerShadowDemo.h"

#import <QuartzCore/CALayer.h>

RCS_ID("$Id$")

@implementation RasterizedLayerShadowDemo

- (NSString *)name;
{
    return @"CALayer Shadow, rasterized";
}

- (void)willMoveToWindow:(UIWindow *)newWindow;
{
    [super willMoveToWindow:newWindow];
    
    if (newWindow)
        self.layer.shouldRasterize =  YES;
}

@end
