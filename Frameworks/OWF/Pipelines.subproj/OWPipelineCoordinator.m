// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWPipelineCoordinator.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWPipeline.h>
#import <OWF/OWProcessor.h> // For +processorQueue

RCS_ID("$Id$")

@interface OWPipelineCoordinator (Private)
- initWithAddress:(OWAddress *)anAddress;
@end

@implementation OWPipelineCoordinator

static NSLock *pipelineCoordinatorLock;
static NSMutableDictionary *pipelineCoordinatorValueDictionary;
static BOOL OWPipelineCoordinatorDebug = NO;

+ (void)initialize;
{
    static BOOL initialized = NO;

    [super initialize];
    if (initialized)
        return;
    initialized = YES;

    pipelineCoordinatorLock = [[NSLock alloc] init];
    pipelineCoordinatorValueDictionary = [[NSMutableDictionary alloc] init];
}

+ (OWPipelineCoordinator *)pipelineCoordinatorForAddress:(OWAddress *)anAddress;
{
    OWPipelineCoordinator *pipelineCoordinator = nil;
    NSString *cacheKey;

    cacheKey = [anAddress cacheKey];
    [pipelineCoordinatorLock lock];
    NS_DURING {
	if (!cacheKey)
	    pipelineCoordinator = [[[self alloc] initWithAddress:nil] autorelease];
        else {
            NSValue *value;

            value = [pipelineCoordinatorValueDictionary objectForKey:cacheKey];
            pipelineCoordinator = [[[value nonretainedObjectValue] retain] autorelease];
        }
        
	if (!pipelineCoordinator) {
            NSValue *value;

	    pipelineCoordinator =  [[[self alloc] initWithAddress:anAddress] autorelease];

            value = [NSValue valueWithNonretainedObject: pipelineCoordinator];
            [pipelineCoordinatorValueDictionary setObject:value forKey:cacheKey];
	}
    } NS_HANDLER {
	[pipelineCoordinatorLock unlock];
	[localException raise];
    } NS_ENDHANDLER;
    [pipelineCoordinatorLock unlock];

    return pipelineCoordinator;
}

- initWithAddress:(OWAddress *)anAddress;
{
    if (!(self = [super init]))
	return nil;
    
    address = [(id)anAddress retain];
    buildingPipeline = NO;
    coordinatorLock = [[NSRecursiveLock alloc] init];
    queuedPipelines = [[NSMutableArray alloc] init];
    
    return self;
}

- (void)dealloc;
{
    NSString *cacheKey;

    [pipelineCoordinatorLock lock];

    if ([self retainCount] != 1) {
        // Woops!  Someone else retained us in another thread while we were grabbing the lock.  Guess we don't want to go away after all.

        // Our last -release called -dealloc rather than decrementing the retain count, so we need to call -release again.
        [self release]; 
        [pipelineCoordinatorLock unlock];
        return;
    }

    cacheKey = [address cacheKey];
    if (cacheKey)
        [pipelineCoordinatorValueDictionary removeObjectForKey:cacheKey];

    [pipelineCoordinatorLock unlock];

    [(id)address release];
    [coordinatorLock release];
    [queuedPipelines release];
    [super dealloc];
}

- (void)buildPipeInPipeline:(OWPipeline *)aPipeline;
{
    if (aPipeline == buildingPipeline) {
	[aPipeline _buildPipe];
	return;
    }

    [coordinatorLock lock];
    if (!buildingPipeline) {
	buildingPipeline = [aPipeline retain];
	[coordinatorLock unlock];
	if (OWPipelineCoordinatorDebug)
	    NSLog(@"%@ pipeline building: %@", [(id)address shortDescription], [buildingPipeline shortDescription]);
	[buildingPipeline _buildPipe];
    } else {
	[queuedPipelines addObject:aPipeline];
	[coordinatorLock unlock];
	if (OWPipelineCoordinatorDebug)
	    NSLog(@"%@ pipeline waiting: %@", [(id)address shortDescription], [aPipeline shortDescription]);
    }
}

- (void)pipebuildingComplete:(OWPipeline *)aPipeline;
{
    BOOL buildPipe = NO;

    if (aPipeline != buildingPipeline)
	return;
    [coordinatorLock lock];
    if (OWPipelineCoordinatorDebug)
	NSLog(@"%@ pipeline complete: %@", [(id)address shortDescription], [buildingPipeline shortDescription]);
    [buildingPipeline release];
    buildingPipeline = nil;
    if ([queuedPipelines count] > 0) {
	buildPipe = YES;
	buildingPipeline = [[queuedPipelines objectAtIndex:0] retain];
	[queuedPipelines removeObjectAtIndex:0];
    }
    [coordinatorLock unlock];
    if (!buildPipe)
	return;
    if (OWPipelineCoordinatorDebug)
	NSLog(@"%@ pipeline building: %@", [(id)address shortDescription], [buildingPipeline shortDescription]);
    [[OWProcessor processorQueue] queueSelector:@selector(_buildPipe) forObject:buildingPipeline];
}

- (void)pipelineAbort:(OWPipeline *)aPipeline;
{
    if (aPipeline == buildingPipeline) {
        [self pipebuildingComplete:aPipeline];
        return;
    }
    [coordinatorLock lock];
    [queuedPipelines removeObjectIdenticalTo:aPipeline];
    [coordinatorLock unlock];
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:address forKey:@"address"];
    if (buildingPipeline)
	[debugDictionary setObject:buildingPipeline forKey:@"buildingPipeline"];
    [debugDictionary setObject:queuedPipelines forKey:@"queuedPipelines"];
    return debugDictionary;
}

@end
