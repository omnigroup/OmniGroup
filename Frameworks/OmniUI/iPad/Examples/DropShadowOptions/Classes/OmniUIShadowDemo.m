//
//  OmniUIShadowDemo.m
//  DropShadowOptions
//
//  Created by Timothy J. Wood on 5/21/10.
//  Copyright 2010 The Omni Group. All rights reserved.
//

#import "OmniUIShadowDemo.h"

#import <OmniUI/UIView-OUIExtensions.h>

@implementation OmniUIShadowDemo

- (void)dealloc;
{
    [_shadowEdges release];
    [super dealloc];
}

- (NSString *)name;
{
    return @"OmniUI Shadow Edge Views";
}

- (void)willMoveToWindow:(UIWindow *)newWindow;
{
    [super willMoveToWindow:newWindow];
    
    if (newWindow && !_shadowEdges) {
        self.opaque = YES;
        self.clearsContextBeforeDrawing = NO;
        self.backgroundColor = [UIColor grayColor];

        _shadowEdges = [OUIViewAddShadowEdges(self) retain];
    }
}

- (void)layoutSubviews;
{
    OUIViewLayoutShadowEdges(self, _shadowEdges, YES/*flipped*/);
}

@end
