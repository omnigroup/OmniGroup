// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Pipelines.subproj/OWContentInfo.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFMessageQueuePriorityProtocol.h>

#import <Foundation/NSDate.h> // For NSTimeInterval

@class NSArray, NSCountedSet, NSMutableArray, NSLock;
@class OWAddress, OWContent, OWTask;

@interface OWContentInfo : OFObject
{
    OWContent *nonretainedContent;

    NSMutableArray *tasks;
    NSLock *tasksLock;

    NSMutableArray *childTasks;
    NSLock *childTasksLock;

    NSMutableArray *childFossils;
    NSLock *childFossilsLock;

    NSMutableArray *activeChildTasks;
    NSLock *activeChildTasksLock;

    NSString *typeString;
    OWAddress *address;
    NSLock *addressLock;

    struct {
        unsigned int wasActiveOnLastCheck:1;
        unsigned int isHeader:1;
    } flags;
    NSLock *flagsLock;
    int workToBeDoneIncludingChildren;

    OFMessageQueueSchedulingInfo schedulingInfo;
}

+ (OWContentInfo *)topLevelActiveContentInfo;
+ (OWContentInfo *)headerContentInfoWithName:(NSString *)name;
+ (OWContentInfo *)orphanParentContentInfo;

+ (NSArray *)allActiveTasks;

- initWithContent:(OWContent *)aContent;
- initWithContent:(OWContent *)aContent typeString:(NSString *)aType;
    // NB: typeString, if non-nil, should be localized to the user's language preferences


// Content
- (OWContent *)content;
- (void)nullifyContent;

// Info
- (NSString *)typeString;

- (BOOL)isHeader;
- (void)setAddress:(OWAddress *)newAddress;
- (OWAddress *)address;

// Pipelines
    // Pipelines that have our content as their last content.  We may have multiple pipelines in the case where, say, a single image is in two browser windows.
- (NSArray *)tasks;
- (void)addTask:(OWTask *)aTask;
    // Only called by -[OWTask pipelineBuilt].
- (void)removeTask:(OWTask *)aTask;
    // Only called by -[OWTask pipelineBuilt].

// Children tasks
    // Pipelines whose OWTarget is a child element of our content somehow. For example, if we are an HTML file we may have some pipelines to inline images as children.  Frames have pipelines to HTML views as children.  Note that content can only contain targets, not content.  (However, most times these targets will have pointers to some content.)
- (void)addChildTask:(OWTask *)aTask;
    // Only can be called by -[OWTask setParentContentInfo:].
- (void)removeChildTask:(OWTask *)aTask;
    // Only can be called by -[OWTask setParentContentInfo:].
- (NSArray *)childTasks;
- (OWTask *)childTaskAtIndex:(unsigned int)childIndex;
- (unsigned int)childTasksCount;
- (int)workDoneByChildTasks;
- (int)workToBeDoneByChildTasks;
- (void)calculateDeadPipelines:(unsigned int *)deadPipelines totalPipelines:(unsigned int *)totalPipelines;

- (void)addChildFossil:(id <NSObject>)childFossil;
    // Hang onto this object until we're released:  this is a way of guaranteeing that a child task sticks around for the inspector

// Active tree
    // A pure subset of children tasks, we also track tasks that are active or any descendents that are active.
- (BOOL)treeHasActiveChildren;
- (void)addActiveChildTask:(OWTask *)aTask;
- (void)removeActiveChildTask:(OWTask *)aTask;
- (NSArray *)activeChildTasks;
- (OWTask *)activeChildTaskAtIndex:(unsigned int)childIndex;
- (unsigned int)activeChildTasksCount;
- (void)abortActiveChildTasks;
- (NSTimeInterval)timeSinceTreeActivationIntervalForActiveChildTasks;
- (NSTimeInterval)estimatedRemainingTreeTimeIntervalForActiveChildTasks;

// OFMessageQueue protocol helpers
- (OFMessageQueueSchedulingInfo)messageQueueSchedulingInfo;

@end
