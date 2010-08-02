// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "LayerShadowDemo.h"

#import <QuartzCore/QuartzCore.h>

RCS_ID("$Id$")

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
