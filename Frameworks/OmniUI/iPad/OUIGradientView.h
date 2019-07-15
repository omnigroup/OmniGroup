// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIView.h>

NS_ASSUME_NONNULL_BEGIN

@interface OUIGradientView : UIView

+ (CGFloat)dropShadowThickness;
+ (instancetype)horizontalShadow:(BOOL)bottomToTop NS_RETURNS_RETAINED;
+ (instancetype)verticalShadow:(BOOL)leftToRight NS_RETURNS_RETAINED;

- (void)fadeHorizontallyFromColor:(UIColor *)leftColor toColor:(UIColor *)rightColor;
- (void)fadeVerticallyFromColor:(UIColor *)bottomColor toColor:(UIColor *)topColor; // where 'bottom' == min y

@end

NS_ASSUME_NONNULL_END
