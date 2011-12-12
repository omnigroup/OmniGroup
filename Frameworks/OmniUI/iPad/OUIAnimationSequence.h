// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

extern const NSTimeInterval OUIAnimationSequenceDefaultDuration;
extern const NSTimeInterval OUIAnimationSequenceImmediateDuration; // Run synchronously w/o animating

@interface OUIAnimationSequence : OFObject
{
@private
    NSTimeInterval _duration;
    CFAbsoluteTime _startTime;
    NSArray *_steps;
    NSUInteger _stepIndex;
}

// Takes a time interval, an action and then a list of NSNumbers containing time intervals and action blocks. Numbers change the interval to be used for any remaining blocks. A zero duration means that animation will be disabled. All animations are run with user interaction off. If an action doesn't actually cause any animations, UIView will complete the action without waiting for the specified delay.
+ (void)runWithDuration:(NSTimeInterval)duration actions:(void (^)(void))action, ... NS_REQUIRES_NIL_TERMINATION;

@end
