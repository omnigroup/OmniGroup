// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIControl.h>

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

@property (nonatomic, copy) UIFont *tabTitleFont;
@property (nonatomic, copy) UIFont *selectedTabTitleFont;

@property (nonatomic, copy) UIFont *verticalTabTitleFont;
@property (nonatomic, copy) UIFont *selectedVerticalTabTitleFont;

@property (nonatomic) NSUInteger selectedTabIndex;
@property (nonatomic, readonly) NSUInteger tabCount;
@property (nonatomic, copy) NSArray *tabTitles;

- (void)setImage:(UIImage *)image forTabWithTitle:(NSString *)tabTitle;

/// This footer view will be installed below the tabs in the vertical orientation.
/// It should support flexible width/height.
@property (nonatomic, strong) UIView *footerView;

@end
