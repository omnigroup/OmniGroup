// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIControl.h>

@protocol OUITabBarAppearanceDelegate;

@interface OUITabBar : UIControl

+ (UIFont *)defaultTabTitleFont;
+ (void)setDefaultTabTitleFont:(UIFont *)font;

+ (UIFont *)defaultSelectedTabTitleFont;
+ (void)setDefaultSelectedTabTitleFont:(UIFont *)font;

+ (UIFont *)defaultVerticalTabTitleFont;
+ (void)setDefaultVerticalTabTitleFont:(UIFont *)font;

+ (UIFont *)defaultSelectedVerticalTabTitleFont;
+ (void)setDefaultSelectedVerticalTabTitleFont:(UIFont *)font;

@property (nonatomic) BOOL usesVerticalLayout;
@property (nonatomic) BOOL showsTabImage;
@property (nonatomic) BOOL showsTabTitle;
@property (nonatomic, copy) UIFont *tabTitleFont;
@property (nonatomic, copy) UIFont *selectedTabTitleFont;

@property (nonatomic, copy) UIFont *verticalTabTitleFont;
@property (nonatomic, copy) UIFont *selectedVerticalTabTitleFont;

@property (nonatomic) NSInteger selectedTabIndex;
@property (nonatomic, readonly) NSInteger tabCount;
@property (nonatomic, copy) NSArray *tabTitles;

- (void)setImage:(UIImage *)image forTabWithTitle:(NSString *)tabTitle;

/// This footer view will be installed below the tabs in the vertical orientation.
/// It should support flexible width/height.
@property (nonatomic, strong) UIView *footerView;

/// Tells the tab bar to invalidate cached appearance properties and request new values of its appearance delegate.
- (void)appearanceDidChange;
@property (nonatomic, weak) id <OUITabBarAppearanceDelegate> appearanceDelegate;

@end
