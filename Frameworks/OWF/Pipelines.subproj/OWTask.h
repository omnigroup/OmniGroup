// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSCountedSet, NSDate, NSLock, NSMutableArray, NSRecursiveLock;
@class OWAddress, OWContentInfo;

#import <Foundation/NSDate.h> // For NSTimeInterval
#import <OmniFoundation/OFMessageQueuePriorityProtocol.h>
#import <os/lock.h>

typedef enum {
    OWPipelineInit,            // pipeline is freshly created
    OWPipelineBuilding,        // pipeline is creating processors & waiting for them to produce results
    OWPipelineRunning,         // pipeline has delivered content & is waiting for processors to finish
    /* PipelinePaused,       || no longer used */
    OWPipelineAborting,        // -abortTask has been called
    OWPipelineInvalidating,    // -invalidate has been called
    OWPipelineDead             // pipeline has completed & is idle
} OWPipelineState;

@interface OWTask : OFObject
{
    OWContentInfo *_contentInfo;
    NSLock *_contentInfoLock;
    OWContentInfo *parentContentInfo;
    NSRecursiveLock *parentContentInfoLock;
    
    NSTimeInterval lastActivationTimeInterval;

    struct {
        unsigned int wasActiveOnLastCheck:1;
        unsigned int wasOpenedByProcessPanel:2;
    } taskFlags;
    OWPipelineState state;

    os_unfair_lock displayablesLock;
    NSString *compositeTypeString;
}

+ (NSString *)HMSStringFromTimeInterval:(NSTimeInterval)interval;

// Init and dealloc
- init;
    // Designated initializer
- initWithName:(NSString *)name contentInfo:(OWContentInfo *)aContentInfo parentContentInfo:(OWContentInfo *)aParentContentInfo;
    // NB: the 'name' string should be localized to the user's language
    
// Task management
- (void)abortTask;

// Active tree
- (BOOL)treeHasActiveChildren;
- (void)treeActiveStatusMayHaveChanged;
- (void)activateInTree;
- (void)deactivateInTree;
- (void)abortTreeActivity;

// State
- (OWPipelineState)state;
- (OWAddress *)lastAddress;

- (NSTimeInterval)timeSinceTreeActivationInterval;
- (NSTimeInterval)estimatedRemainingTimeInterval;
- (NSTimeInterval)estimatedRemainingTreeTimeInterval;

- (BOOL)hadError;
- (BOOL)isRunning;
- (BOOL)hasThread;
- (NSString *)errorNameString;
- (NSString *)errorReasonString;

- (NSString *)compositeTypeString;  // localized string to present to user
- (void)calculateDeadPipelines:(NSUInteger *)deadPipelines totalPipelines:(NSUInteger *)totalPipelines;
- (size_t)workDone;
- (size_t)workToBeDone;
- (size_t)workDoneIfNotFinished;
- (size_t)workToBeDoneIfNotFinished;
- (size_t)workDoneIncludingChildren;
- (size_t)workToBeDoneIncludingChildren;
- (NSString *)statusString;

// Network activity panel / inspector helper methods
- (BOOL)wasOpenedByProcessPanelIndex:(unsigned int)panelIndex;
- (void)setWasOpenedByProcessPanelIndex:(unsigned int)panelIndex;

// Parent contentInfo
- (void)setParentContentInfo:(OWContentInfo *)aParentContentInfo;
- (OWContentInfo *)parentContentInfo;

// ContentInfo
- (void)setContentInfo:(OWContentInfo *)newContentInfo;
- (OWContentInfo *)contentInfo;
- (void)nullifyContentInfo;

// OFMessageQueue protocol helpers
- (OFMessageQueueSchedulingInfo)messageQueueSchedulingInfo;
- (NSComparisonResult)comparePriority:(OWTask *)aTask;

@end
