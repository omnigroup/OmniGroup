// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIGestureRecognizer.h>

/*
 This works like a UITapGestureRecognizer, except that it updates the likelihood property (of OUIGestureRecognizer) when the tap gesture begins. This is useful for fake buttons that should change their image at the start of a tap. Implement the gesture:likelihoodDidChange: delegate method to detect start and end of taps. Note that the likelihood resets to 0 when the tap ends, whether by success or failure.
 */
@interface OUITapGestureRecognizer : OUIGestureRecognizer {
@private
    CGFloat _allowableMovement; // above which this is a drag
    CGPoint _firstTouchPoint;

    // -[UIGestureRecognizer locationInView:] returns <0,0> for a cancelled or failed gesture. Our delegate might need the location of the aborted gesture when we tell it about our likelihood falling to zero. So, in reset we cache the _firstTouchPoint and we vend the cached value in our override of -locationInView. The cache is cleared in -touchesBegan:withEvent:.
    BOOL _cachingPreviousFirstTouchPoint; 
    CGPoint _previousFirstTouchPoint;
    
    NSTimer *_movementTimer;    // to update likelihood when it is becoming more likely that this is not a movement; to avoid visual flicker as the likelihood can get set to 0.1 on touch and then immediately to 0 as this gesture is cancelled due to movement (like when a pan is happening)
}
@end
