// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@interface OUIHoldOnesHorsesIndicator : NSObject

/**
 \brief creates _and activates_ a waiting indicator using the view's tint color
 \param view indicator will be centered on this view
 \param disable
 */
+ (OUIHoldOnesHorsesIndicator *)holdOnesHorsesIndicatorForView:(UIView *)view shouldDisableAllInteraction:(BOOL)disable NS_EXTENSION_UNAVAILABLE_IOS("Hold One's Horses Indicator is not available in extensions");

/**
 \brief creates _and activates_ a waiting indicator
 \param view indicator will be centered on this view
 \param color color for indicator, or nil for view's tint color
 \param drawShadingView whether to hide view behind a translucent shading view while spinning
 \param disable
*/
+ (OUIHoldOnesHorsesIndicator *)holdOnesHorsesIndicatorForView:(UIView *)view withColor:(UIColor *)color drawShadingView:(BOOL)drawShadingView shouldDisableAllInteraction:(BOOL)disable NS_EXTENSION_UNAVAILABLE_IOS("Hold One's Horses Indicator is not available in extensions");

- (id)initForView:(UIView *)view shouldDisableAllInteraction:(BOOL)disable NS_EXTENSION_UNAVAILABLE_IOS("Hold One's Horses Indicator is not available in extensions");

@property (nonatomic, strong) UIColor *color;
@property (nonatomic) BOOL shouldDrawShadingView;

- (void)activate NS_EXTENSION_UNAVAILABLE_IOS("Hold One's Horses Indicator is not available in extensions"); // adds the waiting indicator to the given view, appearing after a short delay; ends user interaction if requested
- (void)deactivateImmediately:(BOOL)immediately withCompletionHandler:(void(^)(void))handler NS_EXTENSION_UNAVAILABLE_IOS("Hold One's Horses Indicator is not available in extensions"); // removes the waiting indicator and resumes user interaction, then calls the completion handler. If immediately == NO, then ensures that spinner has been displayed for some minimum time, or not at all, before clearing it.
@end
