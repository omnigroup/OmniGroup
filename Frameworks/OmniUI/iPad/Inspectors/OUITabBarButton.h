// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIButton.h>

// UIButton subclass for use for OUITabBar segements
//
// We don't use a standard UIButton of type UIButtonTypeSystem because it draws a background on the label in the selected state and provides no way for us to remove it.

@interface OUITabBarButton : UIButton

+ (instancetype)tabBarButton;
+ (instancetype)verticalTabBarButton;

@end
