// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OWF/OWAbstractContent.h>

@class NSLock;
@class NSMutableArray;
@class OIAnimationInstance;
@class OIAnimationFrame;
@class OIImage;

#define OIAnimationInfiniteLoopCount ((unsigned int)~0)

// Image animation limitation
enum {
    OIAnimationAnimateForever,
    OIAnimationAnimateOnce,
    OIAnimationAnimateThrice,
    OIAnimationAnimateSeconds,
    OIAnimationAnimateNever
};

@interface OIAnimation : OWAbstractContent <OWConcreteCacheEntry>
{
    OWContent *sourceContent;
    NSMutableArray *frames;
    unsigned int loopCount;
    NSMutableArray *waitingInstances;
    BOOL haveAllFrames;
    NSLock *lock;
}

- initWithSourceContent:(OWContent *)someContent loopCount:(unsigned int)aLoopCount;

- (OWContent *)sourceContent;

- (void)addFrame:(OIAnimationFrame *)frame;
- (void)endFrames;

- (OIImage *)animationInstance; // each call returns new instance 

- (unsigned int)loopCount;
- (void)animationInstance:(OIAnimationInstance *)instance wantsFrame:(unsigned int)frameNumber;

@end
