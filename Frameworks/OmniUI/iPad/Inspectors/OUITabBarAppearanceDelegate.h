// Copyright 2015-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@protocol OUITabBarAppearanceDelegate <NSObject>

@optional
@property (nonatomic, readonly) UIColor *verticalTabSeparatorColor;
@property (nonatomic, readonly) UIColor *verticalTabRightEdgeColor;
@property (nonatomic, readonly) UIColor *verticalTabRightEdgeFadeToColor;

@property (nonatomic, readonly) UIColor *horizontalTabBottomStrokeColor;
@property (nonatomic, readonly) UIColor *horizontalTabSeparatorTopColor;

@property (nonatomic, readonly) UIColor *selectedTabTintColor;
@property (nonatomic, readonly) UIColor *disabledTabTintColor;

@end
