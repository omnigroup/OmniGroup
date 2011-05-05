// Copyright 1997-2005, 2007, 2010-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWTask.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContentInfo.h>

RCS_ID("$Id$")

@implementation OWTask

static NSBundle *OWF_Bundle = nil;

#define OFMessageQueueSchedulingInfoCleaningUp OFMessageQueueSchedulingInfoDefault

+ (void)initialize;
{
    OBINITIALIZE;

    OWF_Bundle = [[NSBundle bundleForClass:[OWTask class]] retain];
}

+ (NSString *)HMSStringFromTimeInterval:(NSTimeInterval)interval;
{
    OBFinishPorting; // 64->32 warnings -- if we even keep this framework
    return nil;
#if 0
    unsigned int seconds;
    const unsigned int roundUpSeconds = 20;

    ASSERT_IN_MAIN_THREAD(@"NSLocalized... is not threadsafe");
    
    seconds = rint(interval / 5.0f) * 5;
    if (seconds < 1)
        return nil;

    if (seconds < 60)
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"about %d seconds", @"OWF", OWF_Bundle, @"task seconds time interval since start"), seconds];
        
    seconds = rint(interval / 30.0f) * 30;
    if (seconds < 2 * 60 - roundUpSeconds)
        return NSLocalizedStringFromTableInBundle(@"about a minute", @"OWF", OWF_Bundle, @"task one minute time interval since start");

    if (seconds < 3600)
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"about %d minutes", @"OWF", OWF_Bundle, @"task minutes time interval since start"), (seconds + roundUpSeconds)/60];

    if (seconds < 3600 + 360)
        return NSLocalizedStringFromTableInBundle(@"about an hour", @"OWF", OWF_Bundle, @"task one hour time interval since start");
        
    return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"about %.1f hours", @"OWF", OWF_Bundle, @"task hours time interval since start"), seconds/3600.0];
#endif
}



// Init and dealloc

- init;  // DESIGNATED INITIALIZER
{
    if (!(self = [super init]))
        return nil;

    OFSimpleLockInit(&displayablesSimpleLock);
    _contentInfoLock = [[NSLock alloc] init];
    parentContentInfoLock = [[NSRecursiveLock alloc] init];
    taskFlags.wasActiveOnLastCheck = NO;

    state = OWPipelineDead;
    
    return self;
}

- initWithName:(NSString *)name contentInfo:(OWContentInfo *)aContentInfo parentContentInfo:(OWContentInfo *)aParentContentInfo;
{
    if (!(self = [self init]))
        return nil;

    compositeTypeString = [name retain];
    [self setContentInfo:aContentInfo];
    [self setParentContentInfo:aParentContentInfo];

    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(parentContentInfo == nil);
    OBPRECONDITION(_contentInfo == nil);

    [compositeTypeString release];

    OFSimpleLockFree(&displayablesSimpleLock);
    [_contentInfoLock release];
    [parentContentInfoLock release];
    [super dealloc];
}


// Task management

- (void)abortTask;
{
}


// Active tree

- (BOOL)treeHasActiveChildren;
{
    OWContentInfo *contentInfo;

    contentInfo = [self contentInfo];
    return contentInfo != nil && [contentInfo treeHasActiveChildren];
}

- (void)treeActiveStatusMayHaveChanged;
{
    BOOL treeHasActiveChildren;

    treeHasActiveChildren = [self treeHasActiveChildren];
    if (treeHasActiveChildren == taskFlags.wasActiveOnLastCheck)
        return;
    taskFlags.wasOpenedByProcessPanel = 0; // Reset our "currently open in outline" state when we change our active state
    if (treeHasActiveChildren)
        [self activateInTree];
    else
        [self deactivateInTree];
}

- (void)activateInTree;
{
    NSTimeInterval activationTimeInterval;

    activationTimeInterval = [NSDate timeIntervalSinceReferenceDate];
    OFSimpleLock(&displayablesSimpleLock); {
        lastActivationTimeInterval = activationTimeInterval;
    } OFSimpleUnlock(&displayablesSimpleLock);
    [parentContentInfoLock lock]; {
        taskFlags.wasActiveOnLastCheck = YES;
        [parentContentInfo addActiveChildTask:self];
    } [parentContentInfoLock unlock];
}

- (void)deactivateInTree;
{
    [parentContentInfoLock lock]; {
        taskFlags.wasActiveOnLastCheck = NO;
        [parentContentInfo removeActiveChildTask:self];
    } [parentContentInfoLock unlock];
}

- (void)abortTreeActivity;
{
    [self abortTask];
    [[self contentInfo] abortActiveChildTasks];
}

// State

- (OWPipelineState)state;
{
    return state;
}

- (OWAddress *)lastAddress;
{
    return nil;
}

- (NSTimeInterval)timeSinceTreeActivationInterval;
{
    BOOL isActive;
    NSTimeInterval activationTimeInterval;

    OFSimpleLock(&displayablesSimpleLock); {
        isActive = taskFlags.wasActiveOnLastCheck;
        activationTimeInterval = lastActivationTimeInterval;
    } OFSimpleUnlock(&displayablesSimpleLock);
    if (isActive)
        return [NSDate timeIntervalSinceReferenceDate] - activationTimeInterval;
    else
        return 0.0;
}

- (NSTimeInterval)estimatedRemainingTimeInterval;
{
    return 0.0;
}

- (NSTimeInterval)estimatedRemainingTreeTimeInterval;
{
    OWContentInfo *contentInfo;

    contentInfo = [self contentInfo];
    return MAX([self estimatedRemainingTimeInterval], contentInfo ? [contentInfo estimatedRemainingTreeTimeIntervalForActiveChildTasks] : 0.0);
}

- (BOOL)hadError;
{
    return NO;
}

- (BOOL)isRunning;
{
    return NO;
}

- (BOOL)hasThread;
{
    return NO;
}

- (NSString *)errorNameString;
{
    return @"";
}

- (NSString *)errorReasonString;
{
    return @"";
}

- (NSString *)compositeTypeString;
{
    NSUInteger activeChildCount;

    activeChildCount = [[self contentInfo] activeChildTasksCount];
    if (activeChildCount == 0)
        return compositeTypeString;
    else
        return [NSString stringWithFormat:@"%@ (%d)", compositeTypeString, activeChildCount]; // Display active children count for headers on progress panel
}

- (void)calculateDeadPipelines:(NSUInteger *)deadPipelines totalPipelines:(NSUInteger *)totalPipelines;
{
    OWPipelineState threadSafeState = state;
    
    if (threadSafeState != OWPipelineInit)
        (*totalPipelines)++;
    if (threadSafeState == OWPipelineDead)
        (*deadPipelines)++;

    [[self contentInfo] calculateDeadPipelines:deadPipelines totalPipelines:totalPipelines];
}

- (size_t)workDone;
{
    return 0;
}

- (size_t)workToBeDone;
{
    return 0;
}

- (size_t)workDoneIfNotFinished;
{
    size_t workDone, workToBeDone;

    workDone = [self workDone];
    workToBeDone = [self workToBeDone] ;
    if (workDone == workToBeDone)
        return 0;
    return workDone;
}

- (size_t)workToBeDoneIfNotFinished;
{
    size_t workDone, workToBeDone;

    workDone = [self workDone];
    workToBeDone = [self workToBeDone] ;
    if (workDone == workToBeDone)
        return 0;
    return workToBeDone;
}

- (size_t)workDoneIncludingChildren;
{
    return [self workDoneIfNotFinished] + [[self contentInfo] workDoneByChildTasks];
}

- (size_t)workToBeDoneIncludingChildren;
{
    return [self workToBeDoneIfNotFinished] + [[self contentInfo] workToBeDoneByChildTasks];
}


- (NSString *)statusString;
{
    if (taskFlags.wasActiveOnLastCheck)
        return NSLocalizedStringFromTableInBundle(@"Loading elements", @"OWF", OWF_Bundle, @"task statusString");
    else
        return NSLocalizedStringFromTableInBundle(@"Activity finished", @"OWF", OWF_Bundle, @"task statusString");
}

// Network activity panel / inspector helper methods

- (BOOL)wasOpenedByProcessPanelIndex:(unsigned int)panelIndex;
{
    return taskFlags.wasOpenedByProcessPanel & (1 << panelIndex);
}

- (void)setWasOpenedByProcessPanelIndex:(unsigned int)panelIndex;
{
    taskFlags.wasOpenedByProcessPanel |= (1 << panelIndex);
}

// Parent contentInfo

- (void)setParentContentInfo:(OWContentInfo *)aParentContentInfo;
{
    OBASSERT(aParentContentInfo == nil || aParentContentInfo != _contentInfo);
    [parentContentInfoLock lock]; {
        if (parentContentInfo == aParentContentInfo) {
            [parentContentInfoLock unlock];
            return;
        }
        
        OWContentInfo *oldParentContentInfo = parentContentInfo;

        parentContentInfo = [aParentContentInfo retain];
        if (parentContentInfo) {
            [parentContentInfo addChildTask:self];
            if (taskFlags.wasActiveOnLastCheck)
                [parentContentInfo addActiveChildTask:self];
        }

        if (oldParentContentInfo) {
            [oldParentContentInfo removeChildTask:self];
            if (taskFlags.wasActiveOnLastCheck)
                [oldParentContentInfo removeActiveChildTask:self];
            [oldParentContentInfo release];
        }

    } [parentContentInfoLock unlock];
}

- (OWContentInfo *)parentContentInfo;
{
    OWContentInfo *info;

    [parentContentInfoLock lock]; {
        info = [[parentContentInfo retain] autorelease];
    } [parentContentInfoLock unlock];

    return info;
}


// ContentInfo

- (void)setContentInfo:(OWContentInfo *)newContentInfo;
{
    if (newContentInfo != nil && newContentInfo == parentContentInfo)
        newContentInfo = nil;
    [_contentInfoLock lock];
    if (_contentInfo != newContentInfo) {
        OWContentInfo *oldContentInfo;

        oldContentInfo = _contentInfo;
        _contentInfo = newContentInfo;
        if (newContentInfo != nil) {
            [newContentInfo retain];
            [newContentInfo setAddress:[self lastAddress]];
            [newContentInfo addTask:self]; // Note retain cycle, requires -nullifyContentInfo to break
        }
        if (oldContentInfo != nil) {
            if (newContentInfo == nil)
                [[self retain] autorelease]; // Make sure we're not deallocated out from underneath our caller when we remove ourselves from our oldContentInfo's tasks
            [oldContentInfo removeTask:self];
            [oldContentInfo release];
        }
    }
    [_contentInfoLock unlock];
}

- (OWContentInfo *)contentInfo;
{
    OWContentInfo *contentInfo;

    [_contentInfoLock lock];
    contentInfo = [_contentInfo retain];
    [_contentInfoLock unlock];
    return [contentInfo autorelease];
}

- (void)nullifyContentInfo;
{
    [self setContentInfo:nil];
}

// OFMessageQueue protocol helpers

- (OFMessageQueueSchedulingInfo)messageQueueSchedulingInfo;
{
    return OFMessageQueueSchedulingInfoDefault;
}

- (NSComparisonResult)comparePriority:(OWTask *)otherTask;
{
    return NSOrderedSame;
}

@end


@implementation OWTask (Private)

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];

    if (_contentInfo)
        [debugDictionary setObject:_contentInfo forKey:@"_contentInfo"];
    if (compositeTypeString)
        [debugDictionary setObject:compositeTypeString forKey:@"compositeTypeString"];

    return debugDictionary;
}

@end
