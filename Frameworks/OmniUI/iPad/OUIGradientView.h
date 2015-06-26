// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@interface OUIGradientView : UIView

+ (CGFloat)dropShadowThickness;
+ (OUIGradientView *)horizontalShadow:(BOOL)bottomToTop NS_RETURNS_RETAINED;
+ (OUIGradientView *)verticalShadow:(BOOL)leftToRight NS_RETURNS_RETAINED;

- (void)fadeHorizontallyFromColor:(UIColor *)leftColor toColor:(UIColor *)rightColor;
- (void)fadeVerticallyFromColor:(UIColor *)bottomColor toColor:(UIColor *)topColor; // where 'bottom' == min y

@end
