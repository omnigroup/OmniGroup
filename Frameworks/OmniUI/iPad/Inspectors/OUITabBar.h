// Copyright 2010-2013 The Omni Group. All rights reserved.
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

@property (nonatomic, copy) UIFont *tabTitleFont;
@property (nonatomic, copy) UIFont *selectedTabTitleFont;

@property (nonatomic) NSUInteger selectedTabIndex;
@property (nonatomic, readonly) NSUInteger tabCount;
@property (nonatomic, copy) NSArray *tabTitles;

@end
