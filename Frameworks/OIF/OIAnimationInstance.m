// Copyright 1998-2005, 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OIF/OIAnimationInstance.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OIF/OIAnimation.h>
#import <OIF/OIAnimationFrame.h>

RCS_ID("$Id$")

@interface OIAnimationInstance (Private)
- (void)_displayNextFrame;
- (void)_scheduledDisplayNextFrame;
- (void)_cancelScheduledEvent;
- (void)_setScheduledEvent:(OFScheduledEvent *)newEvent;
- (void)_startExpirationTimer;
- (void)_invalidateExpirationTimer;
@end

@implementation OIAnimationInstance

static OFScheduler *animationScheduler;

+ (void)initialize;
{
    OBINITIALIZE;

    animationScheduler = [[OFScheduler mainScheduler] subscheduler];
    [animationScheduler retain];
}

- (id)initWithSourceContent:(OWContent *)sourceContent;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil; // NOT REACHED
}

- (id)initWithAnimation:(OIAnimation *)anAnimation;
{
    if (!(self = [super initWithSourceContent:nil]))
        return nil;

    OWFWeakRetainConcreteImplementation_INIT;
    animation = [anAnimation retain];
    remainingLoops = [anAnimation loopCount];
    nextFrameEventLock = [[NSLock alloc] init];
    expirationTimerLock = [[NSLock alloc] init];
    
    return self;
}

- (void)dealloc;
{
    OWFWeakRetainConcreteImplementation_DEALLOC;
    OBASSERT(frame == nil); // Our frame was already released by -invalidateWeakRetains
    [animation release];
    [nextFrameEventLock release];
    [nextFrameEvent release]; // Assert this is nil?
    [self _invalidateExpirationTimer];
    [expirationTimerLock release];
    
    [super dealloc];
}

- copyWithZone:(NSZone *)zone;
{
    OIAnimationInstance *result = [[OIAnimationInstance allocWithZone:zone] initWithAnimation:animation];
    
    [result setLoopCount:loopCount];
    [result setLoopSeconds:loopSeconds];

    return result;
}

- (OIAnimation *)animation;
{
    return [[animation retain] autorelease];
}

- (void)setLoopCount:(unsigned int)aLoopCount;
{
    loopCount = aLoopCount;
    remainingLoops = aLoopCount;
}

- (void)setLoopSeconds:(int)aLoopSeconds;
{
    loopSeconds = aLoopSeconds;
}

// Called by the animation, could possibly be in another thread.

- (void)animationEnded;
{
    if (remainingLoops == 0 || nextFrame <= 1)
        return;

    if (--remainingLoops > 0 && nextFrame != NSNotFound) {
        nextFrame = 0;
        [self _displayNextFrame];
    }
}

- (void)animationReceivedFrame:(OIAnimationFrame *)aFrame;
{
    if (nextFrame == NSNotFound)
        return;

    nextFrame++;
    if (frame != aFrame) {
        [frame removeObserver:self];
        [frame release];
        frame = [aFrame retain];
        if (!haveSize && [frame hasSize])
            [self setSize:[frame size]];
            
        CGImageRef retainedCGImage = [frame retainedCGImage];
        [self updateImage:retainedCGImage];
        
        if (retainedCGImage != NULL)
            CGImageRelease(retainedCGImage);
        
        [frame addObserver:self];
    }

    if ([self observerCount] != 0 && remainingLoops > 0) {
        OFScheduledEvent *event;

        event = [animationScheduler scheduleSelector:@selector(_scheduledDisplayNextFrame) onObject:self withObject:nil afterTime:[frame delayInterval]];
        [self _setScheduledEvent:event];
    }
}

OWFWeakRetainConcreteImplementation_IMPLEMENTATION

- (void)invalidateWeakRetains;
{
    [frame removeObserver:self];
    [frame release];
    frame = nil;
}

- (BOOL)endOfData
{
    return [animation endOfData];
}

// OIImage subclass

- (OWContent *)sourceContent;
{
    return [animation sourceContent];
}

- (void)startAnimation;
{
    [self _cancelScheduledEvent];
    remainingLoops = loopCount;
    nextFrame = 0;
    [self _displayNextFrame];

    // If we're limiting the number of seconds an animation can last, start a timer here
    if (loopSeconds > 0)
        [self _startExpirationTimer];
}

- (void)stopAnimation;
{
    [self _invalidateExpirationTimer];
    [self _cancelScheduledEvent];
    nextFrame = NSNotFound;
}


- (void)addObserver:(id <OIImageObserver, OWFWeakRetain>)anObserver;
{
    BOOL jumpstartAnimation;

    jumpstartAnimation = [self observerCount] == 0;
    [super addObserver:anObserver];
    if (jumpstartAnimation) {
        // We've added our first observer, time to animate
        [self startAnimation];
    }
}

- (void)removeObserver:(id <OIImageObserver, OWFWeakRetain>)anObserver;
{
    [super removeObserver:anObserver];
    if ([self observerCount] == 0) {
        // We've removed our last observer, no need to animate
        [self stopAnimation];
    }
}

// OIImageObserver protocol

- (void)imageDidSize:(OIImage *)anOmniImage;
{
    if (!haveSize)
        [self setSize:[anOmniImage size]];
}

- (void)imageDidUpdate:(OIImage *)anOmniImage;
{
    CGImageRef retainedCGImage = [anOmniImage retainedCGImage];
    [self updateImage:retainedCGImage];
    CGImageRelease(retainedCGImage);
}

- (void)imageDidAbort:(OIImage *)anOmniImage;
{
    [self _cancelScheduledEvent];
    // Pass the abort along to our observers
    [self abortImage];
}

// NSObject subclass (Debugging)

- (NSMutableDictionary *)debugDictionary;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
    return nil;
#if 0    
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:[NSNumber numberWithInt:remainingLoops] forKey:@"remainingLoops"];
    [debugDictionary setObject:[NSNumber numberWithInt:nextFrame] forKey:@"nextFrame"];

    return debugDictionary;
#endif
}

@end

@implementation OIAnimationInstance (Private)

- (void)_displayNextFrame;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
#if 0    
    if (nextFrame == NSNotFound)
        return;

    [animation animationInstance:self wantsFrame:nextFrame];
#endif
}

- (void)_scheduledDisplayNextFrame;
{
    [nextFrameEventLock lock];
    if (nextFrameEvent != nil) {
        // We're done with the event that just called us
        [nextFrameEvent release];
        nextFrameEvent = nil;
    }
    [nextFrameEventLock unlock];
    [self _displayNextFrame];
}

- (void)_cancelScheduledEvent;
{
    [self _setScheduledEvent:nil];
}

- (void)_setScheduledEvent:(OFScheduledEvent *)newEvent;
{
    OFScheduledEvent *oldEvent;

    [nextFrameEventLock lock];
    oldEvent = nextFrameEvent; // Inherit retain
    nextFrameEvent = [newEvent retain];
    [nextFrameEventLock unlock];
    if (oldEvent != nil) {
        [animationScheduler abortEvent:oldEvent];
        [oldEvent release];
    }
}

- (void)_startExpirationTimer;
{
    [self _invalidateExpirationTimer];

    // Sanity check -- do not loop for zero or a negative number of seconds.  That's that maxLoops is for.
    if (loopSeconds <= 0)
        return;
    
    [expirationTimerLock lock];
    expirationTimer = [[NSTimer scheduledTimerWithTimeInterval:loopSeconds target:self selector:@selector(stopAnimation) userInfo:nil repeats:NO] retain];
    [expirationTimerLock unlock];
}

- (void)_invalidateExpirationTimer;
{
    [expirationTimerLock lock];
    [expirationTimer invalidate];
    [expirationTimer release];
    expirationTimer = nil;
    [expirationTimerLock unlock];
}

@end
