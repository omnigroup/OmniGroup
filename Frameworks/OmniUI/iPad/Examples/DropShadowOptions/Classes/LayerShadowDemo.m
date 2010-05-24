//
//  LayerShadowDemo.m
//  DropShadowOptions
//
//  Created by Timothy J. Wood on 4/2/10.
//  Copyright 2010 The Omni Group. All rights reserved.
//

#import "LayerShadowDemo.h"

#import <QuartzCore/QuartzCore.h>

@implementation LayerShadowDemo

- (NSString *)name;
{
    return @"CALayer Shadow";
}

- (void)willMoveToWindow:(UIWindow *)newWindow;
{
    if (newWindow) {
        self.opaque = YES;
        self.clearsContextBeforeDrawing = NO;
        self.backgroundColor = [UIColor grayColor];
        
        self.layer.shadowOpacity = 0.5;
        
        // Make the shadow more visible for debugging.
        self.layer.shadowColor = [[UIColor redColor] CGColor];
    }
    
    [super willMoveToWindow:newWindow];
}

@end
