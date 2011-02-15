// Copyright 2010-2011 The Omni Group. All rights reserved.
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
+ (OUIGradientView *)horizontalShadow:(BOOL)bottomToTop;
+ (OUIGradientView *)verticalShadow:(BOOL)leftToRight;

- (void)fadeHorizontallyFromColor:(UIColor *)leftColor toColor:(UIColor *)rightColor;
- (void)fadeVerticallyFromColor:(UIColor *)bottomColor toColor:(UIColor *)topColor; // where 'bottom' == min y

@end
