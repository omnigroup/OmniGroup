// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

// Consider using an OUIDragGestureRecognizer instead, with -requiresHoldToComplete set to YES and holdDuration set to 0.5.

#import <OmniUI/OUIGestureRecognizer.h>

@interface OUILongPressGestureRecognizer : OUIGestureRecognizer {
@private
    CGFloat _allowableMovement; // above which this is a drag
    CGPoint _firstTouchPoint;
    
    NSTimer *_movementTimer;    // to update likelihood when it is becoming more likely that this is not a movement; to avoid visual flicker as the likelihood can get set to 0.1 on touch and then immediately to 0 as this gesture is cancelled due to movement (like when a pan is happening)
}
@end
