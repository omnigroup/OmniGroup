// Copyright 1997-2005, 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OIF/OIImage.h>

@class NSTimer;
@class OFScheduledEvent;
@class OIAnimation, OIAnimationFrame;

#import <OWF/OWFWeakRetainConcreteImplementation.h>

@interface OIAnimationInstance : OIImage <OIImageObserver, OWFWeakRetain>
{
    OIAnimation *animation;
    OIAnimationFrame *frame;
    int loopSeconds;                    // Total duration the animation should last before stopping
    unsigned int loopCount;             // Maximum number of loops to display
    unsigned int remainingLoops;        // Remaining number of loops to display, initialized from loopCount
    NSUInteger nextFrame;             // Index of animation frame to display
    OFScheduledEvent *nextFrameEvent;
    NSLock *nextFrameEventLock;
    NSTimer *expirationTimer;
    NSLock *expirationTimerLock;

    OWFWeakRetainConcreteImplementation_IVARS;
}

- (id)initWithAnimation:(OIAnimation *)animation;
- (OIAnimation *)animation;

- (void)setLoopCount:(unsigned int)aLoopCount;
- (void)setLoopSeconds:(int)aLoopSeconds;

// Called by the animation, possibly from another thread.
- (void)animationEnded;
- (void)animationReceivedFrame:(OIAnimationFrame *)aFrame;

OWFWeakRetainConcreteImplementation_INTERFACE

@end
