// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIApplication.h>

@class ScalingScrollViewViewController;

@interface ScalingScrollViewAppDelegate : NSObject <UIApplicationDelegate> {
    UIWindow *window;
    ScalingScrollViewViewController *viewController;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet ScalingScrollViewViewController *viewController;

@end

