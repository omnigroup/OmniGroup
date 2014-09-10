// Copyright 1998-2005, 2010-2011, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OIF/OIAnimation.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OWF/OWF.h>

#import <OIF/OIAnimationInstance.h>

RCS_ID("$Id$")

static OWContentType *contentType;
static NSString *animationContentName = nil;

@implementation OIAnimation

+ (void)initialize;
{
    OBINITIALIZE;

    contentType = [OWContentType contentTypeForString:@"omni/animation"];
    animationContentName = [NSLocalizedStringFromTableInBundle(@"Animation", @"OIF", [OIAnimation bundle], "content or task type name for animated image content") retain];
}

- initWithSourceContent:(OWContent *)someContent loopCount:(unsigned int)aLoopCount;
{
    if (!(self = [super initWithName:animationContentName]))
        return nil;

    sourceContent = [someContent retain];
    frames = [[NSMutableArray alloc] init];

    loopCount = aLoopCount;

    waitingInstances = [[NSMutableArray alloc] init];
    lock = [[NSLock alloc] init];
    haveAllFrames = NO;
    return self;
}

- (void)dealloc;
{
    [sourceContent release];
    [frames release];
    [waitingInstances release];
    [lock release];
    [super dealloc];
}

- (OWContent *)sourceContent;
{
    return sourceContent;
}

- (void)addFrame:(OIAnimationFrame *)frame;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
#if 0    
    unsigned int waitingInstanceIndex, waitingInstanceCount;
    NSMutableArray *snapshotOfWaitingInstances;

    [lock lock];

    if (loopCount == 0 && [frames count] != 0) {
        // We only want the first frame
        [lock unlock];
        return;
    }

    [frames addObject:frame];
    waitingInstanceCount = [waitingInstances count];
    if (waitingInstanceCount == 0) {
        // No waiting instances to notify
        [lock unlock];
        return;
    }

    // Notify waiting instances
    snapshotOfWaitingInstances = waitingInstances; // inherit retain
    waitingInstances = [[NSMutableArray alloc] init];
    [lock unlock];

    for (waitingInstanceIndex = 0; waitingInstanceIndex < waitingInstanceCount; waitingInstanceIndex++)
        [[snapshotOfWaitingInstances objectAtIndex:waitingInstanceIndex] animationReceivedFrame:frame];
    [snapshotOfWaitingInstances release];        
#endif
}

- (void)endFrames;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
#if 0    
    unsigned int waitingInstanceIndex, waitingInstanceCount;
    NSMutableArray *snapshotOfWaitingInstances = waitingInstances;

    [lock lock];
    haveAllFrames = YES;
    waitingInstances = nil;
    [lock unlock];

    waitingInstanceCount = [snapshotOfWaitingInstances count];
    for (waitingInstanceIndex = 0; waitingInstanceIndex < waitingInstanceCount; waitingInstanceIndex++)
        [[snapshotOfWaitingInstances objectAtIndex:waitingInstanceIndex] animationEnded];
    [snapshotOfWaitingInstances release];
#endif
}

- (OIImage *)animationInstance;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
    return nil;
#if 0    
    BOOL shouldNotAnimate;
    unsigned int frameCount;
    OIImage *result = nil;
    
    [lock lock];
    frameCount = [frames count];
    shouldNotAnimate = (haveAllFrames && frameCount == 1) || loopCount == 0;
    if (shouldNotAnimate && frameCount > 0)
        result = [frames objectAtIndex:0];
    [lock unlock];

    if (!result)
        result = [[[OIAnimationInstance alloc] initWithAnimation:self] autorelease];
    return result;
#endif
}

- (unsigned int)loopCount;
{
    return loopCount;
}

- (void)animationInstance:(OIAnimationInstance *)instance wantsFrame:(unsigned int)frameNumber;
{
    BOOL ended = NO;
    OIAnimationFrame *frame = nil;
    
    [lock lock];
    if (frameNumber < [frames count])
        frame = [frames objectAtIndex:frameNumber];
    else if (haveAllFrames)
        ended = YES;
    else
        [waitingInstances addObject:instance];
    [lock unlock];
        
    if (frame)
        [instance animationReceivedFrame:frame];
    else if (ended)
        [instance animationEnded];
}

// OWContent protocol

- (OWContentType *)contentType;
{
    return contentType;
}

- (OWCursor *)contentCursor;
{
    return nil;
}

- (unsigned long int)cacheSize;
{
    OBFinishPorting; // 64->32 warnings; if we even keep this class/framework
    return 0;
#if 0    
    unsigned long int total = 0;
    unsigned int index;

    index = [frames count];
    while (index--)
        total += [[frames objectAtIndex:index] cacheSize];

    return total;
#endif
}

- (BOOL)shareable;
{
    return YES;
}

- (BOOL)contentIsValid;
{
    return YES;
}

- (BOOL)endOfData;
{
    return YES;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:frames forKey:@"frames"];
    [debugDictionary setObject:[NSNumber numberWithInt:loopCount] forKey:@"loopCount"];
    [debugDictionary setObject:haveAllFrames ? @"YES" : @"NO" forKey:@"haveAllFrames"];

    return debugDictionary;
}

@end
