// Copyright 1997-2005, 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OWF/OWTask.h>

@class /* Foundation */ NSArray, NSCountedSet, NSConditionLock, NSLock, NSMutableArray, NSMutableDictionary, NSMutableSet, NSNotificationCenter;
@class /* OmniFoundation */ OFInvocation, OFPreference;
@class /* OWF */ OWAddress, OWCacheSearch, OWContentCacheGroup, OWContentInfo, OWHeaderDictionary, OWProcessor, OWPipelineCoordinator, OWURL;

#import <OWF/OWFWeakRetainConcreteImplementation.h>
#import <OWF/OWTargetProtocol.h>
#import <OWF/FrameworkDefines.h>

#define ASSERT_OWPipeline_Locked() OBASSERT([OWPipeline isLockHeldByCallingThread])

typedef enum {
    OWPipelineFollowAction,    // Following a link, submitting a form, etc.
    OWPipelineHistoryAction,   // Retrieving something previously viewed
    OWPipelineReloadAction     // Reloading something previously (or currently) viewed
} OWPipelineAction;

@protocol OWCacheArc, OWPipelineDeallocationObserver;

@interface OWPipeline : OWTask <OWFWeakRetain>
// For notification of pipeline fetches. Notifications' objects are a pipeline, their info dictionary keys are listed below. 
+ (void)addObserver:(id)anObserver selector:(SEL)aSelector address:(OWAddress *)anAddress;
- (void)addObserver:(id)anObserver selector:(SEL)aSelector;
+ (void)removeObserver:(id)anObserver address:(OWAddress *)anAddress;
+ (void)removeObserver:(id)anObserver;

// Pipeline target management
+ (void)invalidatePipelinesForTarget:(id <OWTarget>)aTarget;
    // Targets call this when they are freed so no pipeline tries to give them content.
+ (void)abortTreeActivityForTarget:(id <OWTarget>)aTarget;
    // Usually called because of user input
+ (void)abortPipelinesForTarget:(id <OWTarget>)aTarget;
    // Only affects the current pipelines for the target, not the their children
    // You probably want to use +abortTreeActivityForTarget: instead.
+ (OWPipeline *)currentPipelineForTarget:(id <OWTarget>)aTarget;
    // Last pipeline that the target accepted content from, in -pipelineBuilt.
+ (NSArray *)pipelinesForTarget:(id <OWTarget>)aTarget;
+ (OWPipeline *)firstActivePipelineForTarget:(id <OWTarget>)aTarget;
+ (OWPipeline *)lastActivePipelineForTarget:(id <OWTarget>)aTarget;

// For notifying groups of pipelines semi-synchronously (locks and invokes in background)
+ (void)postSelector:(SEL)aSelector toPipelines:(NSArray *)pipelines withObject:(NSObject *)arg;

// Status Monitoring
+ (void)activeTreeHasChanged;
+ (void)startActiveStatusUpdateTimer;
+ (void)stopActiveStatusUpdateTimer;

// For sending notification of permanent redirects
// + (void)notePermanentRedirection:(OWAddress *)redirectFrom to:(OWAddress *)redirectTo;

// We currently have a single global lock for cache management.
+ (void)lock;
+ (void)unlock;
+ (BOOL)isLockHeldByCallingThread;

// Utility methods
+ (NSString *)stringForTargetContentOffer:(OWTargetContentOffer)offer;

// Init and dealloc
+ (void)startPipelineWithAddress:(OWAddress *)anAddress target:(id <OWTarget, OWFWeakRetain, NSObject>)aTarget;

- (id)initWithContent:(OWContent *)aContent target:(id <OWTarget, OWFWeakRetain, NSObject>)aTarget;
- (id)initWithAddress:(OWAddress *)anAddress target:(id <OWTarget, OWFWeakRetain, NSObject>)aTarget;

- (id)initWithCacheGroup:(OWContentCacheGroup *)someCaches content:(NSArray *)someContent arcs:(NSArray *)someArcs target:(id <OWTarget, OWFWeakRetain, NSObject>)aTarget;  // Designated initializer

// Pipeline management
- (void)startProcessingContent;
- (void)abortTask;

- (void)fetch;

// Target
- (id <OWTarget, OWFWeakRetain, NSObject>)target;
- (void)invalidate;
    // Called in +invalidatePipelinesForTarget:, if the pipeline was pointing at the target that wants to be invalidated.
    // Also called in -pipelineBuilt if our target rejects the content we offer and didn't suggest a new target, and in +_target:acceptedContentFromPipeline: on all pipelines created before the parameter that point at the same target (eg, some other pipeline beat you to the punch, sorry, guys).
- (void)parentContentInfoLostContent;
    // When our parent content info's content calls [OWContentInfo nullifyContent], this method will be called on all of the contentInfo's childTasks.  We call the same method on our target if it implements it.  This is currently unused.
- (void)updateStatusOnTarget;
- (void)setErrorName:(NSString *)newName reason:(NSString *)newReason;

// Content

- (id)contextObjectForKey:(NSString *)key;
- (id)contextObjectForKey:(NSString *)key arc:(id <OWCacheArc>)arc;
- (OFPreference *)preferenceForKey:(NSString *)key arc:(id <OWCacheArc>)arc;
- (void)setContextObject:(id)anObject forKey:(NSString *)key;
    // returns the object that's in the context dictionary, whichever one it turns out to be
- (id)setContextObjectNoReplace:(id)anObject forKey:(NSString *)key;
- (NSDictionary *)contextDictionary;
- (void)setReferringAddress:(OWAddress *)anAddress;
- (void)setReferringContentInfo:(OWContentInfo *)anInfo;
- (NSDate *)fetchDate;

- (OWHeaderDictionary *)headerDictionary;  // inefficient
- (NSArray *)validator;  // Useful for making a value for OWCacheArcConditionalKey. (calls -headerDictionary)

- (OWPipeline *)cloneWithTarget:(id <OWTarget, OWFWeakRetain, NSObject>)aTarget;

- (NSNumber *)estimateCostFromType:(OWContentType *)aType;

// Messages sent to us by our arcs

- (void)arcHasStatus:(NSDictionary *)info;
- (void)arcHasResult:(NSDictionary *)info;

// Some objects are interested in knowing when we're about to deallocate
- (void)addDeallocationObserver:(id <OWPipelineDeallocationObserver, OWFWeakRetain>)anObserver;
- (void)removeDeallocationObserver:(id <OWPipelineDeallocationObserver, OWFWeakRetain>)anObserver;

@end

@interface OWPipeline (SubclassesOnly)

- (void)deactivate;

@end

OWF_EXTERN NSString *OWWebPipelineReferringContentInfoKey;

// For notification of pipeline errors.
// A pipeline posts a HasError notification when it encounters an error. The note's object is the pipeline; other info is available in the user dictionary.
// Currently used by OHDownloader (asks about a specific pipeline) and OWConsoleController (subscribes to all notifications).
OWF_EXTERN NSString *OWPipelineHasErrorNotificationName;
OWF_EXTERN NSString *OWPipelineHasErrorNotificationPipelineKey;
OWF_EXTERN NSString *OWPipelineHasErrorNotificationProcessorKey;
OWF_EXTERN NSString *OWPipelineHasErrorNotificationErrorNameKey;
OWF_EXTERN NSString *OWPipelineHasErrorNotificationErrorReasonKey;

// When a pipeline creates a clone of itself, this notification is posted. The object is the old (parent) pipeline; the new pipeline is available in the user dictionary.
// This notification is not posted if you call -cloneWithTarget:.
// NOTE: This notification is sent with the pipeline lock held. Don't do anything in an observer of this notification that might lead to deadlock.
OWF_EXTERN NSString *OWPipelineHasBuddedNotificationName;
OWF_EXTERN NSString *OWPipelineChildPipelineKey;

// The notifications delivered by +addObserver:selector:address: and friends have the following user info keys
OWF_EXTERN NSString *OWPipelineFetchLastAddressKey;
OWF_EXTERN NSString *OWPipelineFetchNewContentKey;
OWF_EXTERN NSString *OWPipelineFetchNewArcKey;

// Other pipeline notification names.

OWF_EXTERN NSString *OWPipelineTreeActivationNotificationName;
OWF_EXTERN NSString *OWPipelineTreeDeactivationNotificationName;
OWF_EXTERN NSString *OWPipelineTreePeriodicUpdateNotificationName;

@protocol OWPipelineDeallocationObserver
- (void)pipelineWillDeallocate:(OWPipeline *)aPipeline;
@end
