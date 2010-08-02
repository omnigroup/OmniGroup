// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OmniUIShadowDemo.h"

#import <OmniUI/UIView-OUIExtensions.h>

RCS_ID("$Id$")

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
