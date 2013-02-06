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

+ (OUIHoldOnesHorsesIndicator *)holdOnesHorsesIndicatorForView:(UIView *)view shouldDisableAllInteraction:(BOOL)disable; //creates _and activates_ a waiting indicator

- (id)initForView:(UIView *)view shouldDisableAllInteraction:(BOOL)disable;

- (void)activate; // adds the waiting indicator to the given view, appearing after a short delay; ends user interaction if requested
- (void)deactivateImmediately:(BOOL)immediately withCompletionHandler:(void(^)())handler; // removes the waiting indicator and resumes user interaction, then calls the completion handler. If immediately == NO, then ensures that spinner has been displayed for some minimum time, or not at all, before clearing it.
@end
