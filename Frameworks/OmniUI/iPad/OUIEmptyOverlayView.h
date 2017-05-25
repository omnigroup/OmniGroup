// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

@interface OUIEmptyOverlayView : UIView

// using the simpler version of this method will apply the light text for dark backround to the font color. if you want to negate that or set a different color, call the method below.
+ (instancetype)overlayViewWithMessage:(NSString *)message buttonTitle:(NSString *)buttonTitle action:(void (^)(void))action;

// passing nil for the customFontColor will prevent the color from being set at all and result in a black text and tint-color button text.
+ (instancetype)overlayViewWithMessage:(NSString *)message buttonTitle:(NSString *)buttonTitle customFontColor:(UIColor *)customFontColor action:(void (^)(void))action;

@end
