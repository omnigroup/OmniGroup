// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWContentInfo.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWAddress.h>
#import <OWF/OWContent.h>
#import <OWF/OWPipeline.h>
#import <OWF/OWTask.h>

RCS_ID("$Id$")

@interface OWTopLevelActiveContentInfo : OWContentInfo
@end


@interface OWContentInfo (Private)
- (void)_treeActiveStatusMayHaveChanged;
- (OWTask *)_taskWithLowestPriority;
- (NSUInteger)_indexOfTaskWithLowestPriority;
@end

@implementation OWContentInfo

static OWContentInfo *topLevelActiveContentInfo = nil;
static NSLock *headerContentInfoLock = nil;
static NSMutableDictionary *headerContentInfoDictionary = nil;
static NSMutableArray *allActiveTasks = nil;
static NSLock *allActiveTasksLock = nil;
static NSMutableArray *headerTasks = nil;

+ (void)initialize;
{
    OBINITIALIZE;

    topLevelActiveContentInfo = [[OWTopLevelActiveContentInfo alloc] initWithContent:nil];
    headerContentInfoLock = [[NSLock alloc] init];
    headerContentInfoDictionary = [[NSMutableDictionary alloc] init];

    allActiveTasks = [[NSMutableArray alloc] initWithCapacity:16];
    allActiveTasksLock = [[NSLock alloc] init];
    headerTasks = [[NSMutableArray alloc] init];
}

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(NSDictionary *)description;
{
    OWContentInfo *headerContentInfo = [self headerContentInfoWithName:itemName];

    OBASSERT(headerContentInfo != nil);
    headerContentInfo->schedulingInfo.priority = [description intForKey:@"priority"];
    headerContentInfo->schedulingInfo.maximumSimultaneousThreadsInGroup = [description intForKey:@"maximumSimultaneousThreadsInGroup"];
}

+ (OWContentInfo *)topLevelActiveContentInfo;
{
    return topLevelActiveContentInfo;
}

// NB: "name" will be presented to user, and therefore must be a localized string
+ (OWContentInfo *)headerContentInfoWithName:(NSString *)name;
{
    OWContentInfo *newContentInfo;

    OBPRECONDITION(name != nil);
    [headerContentInfoLock lock];
    
    newContentInfo = [headerContentInfoDictionary objectForKey:name];
    if (!newContentInfo) {
        NS_DURING {
            
            newContentInfo = [[self alloc] initWithContent:nil];
    
            // OWTask object is permanent header
            OWTask *headerTask = [[OWTask alloc] initWithName:name contentInfo:newContentInfo parentContentInfo:topLevelActiveContentInfo];
            [headerTasks addObject:headerTask];
    
            newContentInfo->flags.isHeader = YES;
    
            // newContentInfo is permanent, also
            [headerContentInfoDictionary setObject:newContentInfo forKey:name];

        } NS_HANDLER {
            [headerContentInfoLock unlock];
            NSLog(@"%@ %@ : %@", NSStringFromSelector(_cmd), name, localException);
            [localException raise];
        } NS_ENDHANDLER;
    }
    
    [headerContentInfoLock unlock];

    OBPOSTCONDITION(newContentInfo != nil);
    return newContentInfo;
}


+ (OWContentInfo *)orphanParentContentInfo;
{
    static OWContentInfo *orphanParentContentInfo = nil;
    
    if (orphanParentContentInfo == nil)
        orphanParentContentInfo = [self headerContentInfoWithName:NSLocalizedStringFromTableInBundle(@"Closing", @"OWF", [OWTask bundle], "contentinfo name of processes which have no parents")];

    return orphanParentContentInfo;
}


+ (NSArray *)allActiveTasks;
{
    NSArray *copiedArray;

    [allActiveTasksLock lock];
    copiedArray = [NSArray arrayWithArray:allActiveTasks];
    [allActiveTasksLock unlock];
    
    return copiedArray;
}

// Init and dealloc

- initWithContent:(OWContent *)aContent;
{
    return [self initWithContent:aContent typeString:nil];
}

- initWithContent:(OWContent *)aContent typeString:(NSString *)aType;
{
    if (!(self = [super init]))
        return nil;

    nonretainedContent = aContent;
    
    typeString = [aType copy];

    tasksLock = [[NSLock alloc] init];
    childTasksLock = [[NSLock alloc] init];
    childFossilsLock = [[NSLock alloc] init];
    activeChildTasksLock = [[NSLock alloc] init];
    addressLock = [[NSLock alloc] init];
    flagsLock = [[NSLock alloc] init];

    tasks = [[NSMutableArray alloc] init];
    childTasks = [[NSMutableArray alloc] init];
    activeChildTasks = [[NSMutableArray alloc] init];

    workToBeDoneIncludingChildren = 0;
    schedulingInfo.group = (__bridge const void *)(self);
    schedulingInfo.priority = OFMediumPriority;
    schedulingInfo.maximumSimultaneousThreadsInGroup = 4;

    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(nonretainedContent == nil);
    OBPRECONDITION([tasks count] == 0);
    OBPRECONDITION([childTasks count] == 0);
    OBPRECONDITION([activeChildTasks count] == 0);
}

// Actions

// Content

- (OWContent *)content;
{
    return nonretainedContent;
}

- (void)nullifyContent;
{
    nonretainedContent = nil;
    [[self childTasks] makeObjectsPerformSelector:@selector(parentContentInfoLostContent)];
    [self _treeActiveStatusMayHaveChanged];
}

// Info

- (NSString *)typeString;
{
    return typeString;
}

- (BOOL)isHeader;
{
    return ( flags.isHeader ? YES : NO );
}

- (void)setAddress:(OWAddress *)newAddress;
{
    [addressLock lock];
    if (address != newAddress) {
        address = newAddress;
    }
    [addressLock unlock];
}

- (OWAddress *)address;
{
    OWAddress *snapshotAddress;

    [addressLock lock];
    snapshotAddress = address;
    [addressLock unlock];
    return snapshotAddress;
}



// Pipelines

- (NSArray *)tasks;
{
    NSArray *copiedArray;

    [tasksLock lock];
    copiedArray = [NSArray arrayWithArray:tasks];
    [tasksLock unlock];
    return copiedArray;
}

- (void)addTask:(OWTask *)aTask;
{
    [tasksLock lock];
    OBPRECONDITION([tasks indexOfObjectIdenticalTo:aTask] == NSNotFound);
    [tasks addObject:aTask];
    [tasksLock unlock];
}

- (void)removeTask:(OWTask *)aTask;
{
    NSUInteger index;

    [tasksLock lock];
    index = [tasks indexOfObjectIdenticalTo:aTask];
    OBPRECONDITION(index != NSNotFound);
    if (index != NSNotFound) // Belt *and* suspenders.
        [tasks removeObjectAtIndex:index];
    [tasksLock unlock];
}


// Children tasks

- (void)addChildTask:(OWTask *)aTask;
{
    [childTasksLock lock];
    OBPRECONDITION([childTasks indexOfObjectIdenticalTo:aTask] == NSNotFound);
    [childTasks addObject:aTask];
    [childTasksLock unlock];
}

- (void)removeChildTask:(OWTask *)aTask;
{
    NSUInteger index;

    [childTasksLock lock];
    index = [childTasks indexOfObjectIdenticalTo:aTask];
    OBPRECONDITION(index != NSNotFound);
    if (index != NSNotFound) // Belt *and* suspenders.
        [childTasks removeObjectAtIndex:index];
    [childTasksLock unlock];
}

- (NSArray *)childTasks;
{
    NSArray *copiedArray;

    [childTasksLock lock];
    copiedArray = [NSArray arrayWithArray:childTasks];
    [childTasksLock unlock];
    return copiedArray;
}

- (OWTask *)childTaskAtIndex:(NSUInteger)childIndex;
{
    OWTask *childTask = nil;

    [childTasksLock lock];
    if (childIndex < [childTasks count])
        childTask = [childTasks objectAtIndex:childIndex];
    [childTasksLock unlock];
    return childTask;
}

- (NSUInteger)childTasksCount;
{
    NSUInteger childTasksCount;

    [childTasksLock lock];
    childTasksCount = [childTasks count];
    [childTasksLock unlock];
    return childTasksCount;
}

- (size_t)workDoneByChildTasks;
{
    size_t work;
    
    if (flags.wasActiveOnLastCheck) {
        [childTasksLock lock];
        NSArray *childTasksCopy = [[NSArray alloc] initWithArray:childTasks];
        [childTasksLock unlock];

        work = 0;
        for (OWTask *childTask in childTasksCopy)
            work += [childTask workDoneIncludingChildren];
    } else
        work = 0;

    return work;
}

- (size_t)workToBeDoneByChildTasks;
{
    size_t work;
    
    if (flags.wasActiveOnLastCheck) {
        [childTasksLock lock];
        NSArray *childTasksCopy = [[NSArray alloc] initWithArray:childTasks];
        [childTasksLock unlock];

        work = 0;
        for (OWTask *childTask in childTasksCopy)
            work += [childTask workToBeDoneIncludingChildren];
        workToBeDoneIncludingChildren = work;
    } else
        work = 0;

    return work;
}

- (void)calculateDeadPipelines:(NSUInteger *)deadPipelines totalPipelines:(NSUInteger *)totalPipelines;
{
    [childTasksLock lock];
    NSArray *childTasksCopy = [[NSArray alloc] initWithArray:childTasks];
    [childTasksLock unlock];

    for (OWTask *childTask in childTasksCopy)
        [childTask calculateDeadPipelines:deadPipelines totalPipelines:totalPipelines];
}

- (void)addChildFossil:(id <NSObject>)childFossil;
{
    [childFossilsLock lock];
    if (childFossils == nil)
        childFossils = [[NSMutableArray alloc] init];
    [childFossils addObject:childFossil];
    [childFossilsLock unlock];
}

// Active tree

- (BOOL)treeHasActiveChildren;
{
    return [self activeChildTasksCount] > 0;
}

- (void)addActiveChildTask:(OWTask *)aTask;
{
    BOOL treeActiveStatusMayHaveChanged;

    [activeChildTasksLock lock];
    OBPRECONDITION([activeChildTasks indexOfObjectIdenticalTo:aTask] == NSNotFound);

    [allActiveTasksLock lock];
    // Note: aTask may already be present in allActiveTasks, but we'll remove all instances later as necessary
    [allActiveTasks addObject:aTask];
    [allActiveTasksLock unlock];
        
    // Member, not subclass
    if ([aTask isMemberOfClass:[OWTask class]])
        // If we're at the top level, sort the OWTask headers by priority so they don't jump around as they appear and disappear.  (eg, "Saving files, Web pages, Downloads,...")
        [activeChildTasks insertObject:aTask inArraySortedUsingSelector:@selector(comparePriority:)];
    else
        [activeChildTasks addObject:aTask];
    treeActiveStatusMayHaveChanged = [activeChildTasks count] == 1;
    [activeChildTasksLock unlock];
    if (treeActiveStatusMayHaveChanged)
        [self _treeActiveStatusMayHaveChanged];
    [OWPipeline activeTreeHasChanged];
}

- (void)removeActiveChildTask:(OWTask *)aTask;
{
    BOOL treeActiveStatusMayHaveChanged;
    NSUInteger index;

    [activeChildTasksLock lock];
    
    [allActiveTasksLock lock];
    index = [allActiveTasks indexOfObjectIdenticalTo:aTask];
    OBPRECONDITION(index != NSNotFound);
    if (index != NSNotFound) {
        // We used to assert that index != NSNotFound, but we were getting exceptions.
        [allActiveTasks removeObjectAtIndex:index];
    }
    [allActiveTasksLock unlock];

    index = [activeChildTasks indexOfObjectIdenticalTo:aTask];
    OBPRECONDITION(index != NSNotFound);
    if (index != NSNotFound) {
        // We used to assert that index != NSNotFound, but we were getting exceptions.
        [activeChildTasks removeObjectAtIndex:index];
    }
    treeActiveStatusMayHaveChanged = [activeChildTasks count] == 0;
    [activeChildTasksLock unlock];
    if (treeActiveStatusMayHaveChanged)
        [self _treeActiveStatusMayHaveChanged];
    [OWPipeline activeTreeHasChanged];
}

- (NSArray *)activeChildTasks;
{
    NSArray *childrenCopy;

    [activeChildTasksLock lock];
    childrenCopy = [[NSArray alloc] initWithArray:activeChildTasks];
    [activeChildTasksLock unlock];
    return childrenCopy;
}

- (OWTask *)activeChildTaskAtIndex:(NSUInteger)childIndex;
{
    OWTask *activeChildTask = nil;

    [activeChildTasksLock lock];
    if (childIndex < [activeChildTasks count])
        activeChildTask = [activeChildTasks objectAtIndex:childIndex];
    [activeChildTasksLock unlock];
    return activeChildTask;
}

- (NSUInteger)activeChildTasksCount;
{
    NSUInteger activeChildTasksCount;

    [activeChildTasksLock lock];
    activeChildTasksCount = [activeChildTasks count];
    [activeChildTasksLock unlock];
    return activeChildTasksCount;
}

- (void)abortActiveChildTasks;
{
    NSArray *activeChildrenCopy;

    [activeChildTasksLock lock];
    activeChildrenCopy = [[NSArray alloc] initWithArray:activeChildTasks];
    [activeChildTasksLock unlock];

    [activeChildrenCopy makeObjectsPerformSelector:@selector(abortTreeActivity)];
}

- (NSTimeInterval)timeSinceTreeActivationIntervalForActiveChildTasks;
{
    NSTimeInterval maxTimeInterval = 0.0;

    if (flags.wasActiveOnLastCheck) {
        [childTasksLock lock];
        NSArray *childTasksCopy = [[NSArray alloc] initWithArray:childTasks];
        [childTasksLock unlock];
        
        for (OWTask *childTask in childTasksCopy)
            maxTimeInterval = MAX(maxTimeInterval, [childTask timeSinceTreeActivationInterval]);
    }
    return maxTimeInterval;
}

- (NSTimeInterval)estimatedRemainingTreeTimeIntervalForActiveChildTasks;
{
    NSTimeInterval maxTimeInterval = 0.0;

    if (flags.wasActiveOnLastCheck) {
        [childTasksLock lock];
        NSArray *childTasksCopy = [[NSArray alloc] initWithArray:childTasks];
        [childTasksLock unlock];
        
        for (OWTask *childTask in childTasksCopy)
            maxTimeInterval = MAX(maxTimeInterval, [childTask estimatedRemainingTreeTimeInterval]);
    }
    return maxTimeInterval;
}


// OFMessageQueue protocol helpers

- (OFMessageQueueSchedulingInfo)messageQueueSchedulingInfo;
{
    if (!flags.isHeader) {
        OWTask *taskWithLowestPriority = [self _taskWithLowestPriority];
        if (taskWithLowestPriority)
            return [taskWithLowestPriority messageQueueSchedulingInfo];
    }
    return schedulingInfo;
}

// OBObject subclass

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];

    // NOTE: Not thread-safe
    if (nonretainedContent)
        [debugDictionary setObject:[(OBObject *)nonretainedContent shortDescription] forKey:@"nonretainedContent"];
    if (tasks)
        [debugDictionary setObject:[NSString stringWithFormat:@"%p", tasks] forKey:@"tasks"];
    if (childTasks)
        [debugDictionary setObject:childTasks forKey:@"childTasks"];
    if (activeChildTasks)
        [debugDictionary setObject:activeChildTasks forKey:@"activeChildTasks"];
    if (typeString)
        [debugDictionary setObject:typeString forKey:@"typeString"];
    if (address)
        [debugDictionary setObject:[address addressString] forKey:@"address"];
    [debugDictionary setBoolValue:flags.isHeader forKey:@"isHeader"];
    [debugDictionary setBoolValue:flags.wasActiveOnLastCheck forKey:@"wasActiveOnLastCheck"];

    return debugDictionary;
}

@end

@implementation OWContentInfo (Private)

- (void)_treeActiveStatusMayHaveChanged;
{
    BOOL treeHasActiveChildren;
    BOOL flagChanged = NO;

    treeHasActiveChildren = [self treeHasActiveChildren];
    [flagsLock lock];
    if (treeHasActiveChildren != flags.wasActiveOnLastCheck) {
        flagChanged = YES;
        flags.wasActiveOnLastCheck = treeHasActiveChildren;
    }
    [flagsLock unlock];
    if (flagChanged) {
        [[self tasks] makeObjectsPerformSelector:@selector(treeActiveStatusMayHaveChanged)];
    }

    // Are we dead, but just don't know it yet?
    if (treeHasActiveChildren && !flags.isHeader && !nonretainedContent && [[self childTasks] count] == 0) {
        OWContentInfo *strongSelf = self;
        [tasksLock lock];
        NSArray *oldTasks = tasks;
        tasks = nil;
        [tasksLock unlock];
        [oldTasks makeObjectsPerformSelector:@selector(nullifyContentInfo)];
        strongSelf = nil;
    }
}

- (OWTask *)_taskWithLowestPriority;
{
    OWTask *taskWithLowestPriority;

    [tasksLock lock];
    NSUInteger taskCount = [tasks count];
    switch (taskCount) {
        case 0:
            taskWithLowestPriority = nil;
            break;
        case 1: // Common optimization
            taskWithLowestPriority = [tasks objectAtIndex:0];
            break;
        default:
            taskWithLowestPriority = [tasks objectAtIndex:[self _indexOfTaskWithLowestPriority]];
            break;
    }
    [tasksLock unlock];
    return taskWithLowestPriority;
}

- (NSUInteger)_indexOfTaskWithLowestPriority;
    // Tasks MUST be locked before entering this routine.
{
    OBPRECONDITION(!flags.isHeader);

    NSUInteger taskIndex = [tasks count];
    if (taskIndex == 1)
        return 0;
    
    NSUInteger lowestPriority = INT_MAX;
    NSUInteger lowestPriorityTaskIndex = NSNotFound;

    while (taskIndex--) {
        OWTask *task = [tasks objectAtIndex:taskIndex];
        unsigned int taskPriority = [task messageQueueSchedulingInfo].priority;
        if (taskPriority < lowestPriority) {
            lowestPriorityTaskIndex = taskIndex;
            lowestPriority = taskPriority;
        }
    }

    return lowestPriorityTaskIndex;
}

@end


@implementation OWTopLevelActiveContentInfo

- (void)_treeActiveStatusMayHaveChanged;
{
    BOOL treeHasActiveChildren;
    BOOL flagChanged = NO;

    [flagsLock lock];
    treeHasActiveChildren = [self treeHasActiveChildren];
    if (treeHasActiveChildren != flags.wasActiveOnLastCheck) {
        flagChanged = YES;
        flags.wasActiveOnLastCheck = treeHasActiveChildren;
    }
    [flagsLock unlock];
    if (flagChanged) {
        if (treeHasActiveChildren) {
            [OWPipeline queueSelector:@selector(startActiveStatusUpdateTimer)];
        } else {
            [OWPipeline queueSelector:@selector(stopActiveStatusUpdateTimer)];
        }
    }
}

@end
