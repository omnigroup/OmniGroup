//
//  RasterizedLayerShadowDemo.m
//  DropShadowOptions
//
//  Created by Timothy J. Wood on 5/21/10.
//  Copyright 2010 The Omni Group. All rights reserved.
//

#import "RasterizedLayerShadowDemo.h"

#import <QuartzCore/CALayer.h>

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
