// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
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
+ (OUIHoldOnesHorsesIndicator *)holdOnesHorsesIndicatorForView:(UIView *)view shouldDisableAllInteraction:(BOOL)disable;

/**
 \brief creates _and activates_ a waiting indicator
 \param view indicator will be centered on this view
 \param color color for indicator, or nil for view's tint color
 \param drawShadingView whether to hide view behind a translucent shading view while spinning
 \param disable
*/
+ (OUIHoldOnesHorsesIndicator *)holdOnesHorsesIndicatorForView:(UIView *)view withColor:(UIColor *)color drawShadingView:(BOOL)drawShadingView shouldDisableAllInteraction:(BOOL)disable;

- (id)initForView:(UIView *)view shouldDisableAllInteraction:(BOOL)disable;

@property (nonatomic, strong) UIColor *color;
@property (nonatomic) BOOL shouldDrawShadingView;

- (void)activate; // adds the waiting indicator to the given view, appearing after a short delay; ends user interaction if requested
- (void)deactivateImmediately:(BOOL)immediately withCompletionHandler:(void(^)())handler; // removes the waiting indicator and resumes user interaction, then calls the completion handler. If immediately == NO, then ensures that spinner has been displayed for some minimum time, or not at all, before clearing it.
@end
