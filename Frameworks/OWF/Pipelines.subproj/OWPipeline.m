// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWPipeline.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/NSException-OWConcreteCacheEntry.h>
#import <OWF/OWAddress.h> // Only for heuristic for compositeTypeString
#import <OWF/OWContent.h>
#import <OWF/OWContentCacheGroup.h>
#import <OWF/OWContentCacheProtocols.h>
#import <OWF/OWCookieDomain.h>
#import "OWCacheSearch.h"
#import <OWF/OWContentInfo.h>
#import <OWF/OWContentType.h>
#import <OWF/OWContentTypeLink.h>
#import <OWF/OWConversionPathElement.h>
#import <OWF/OWHeaderDictionary.h>
#import <OWF/OWURL.h> // Only for heuristic for compositeTypeString
#import <OWF/OWProcessor.h>
#import "OWProcessorCacheArc.h"
#import <OWF/OWSitePreference.h>

// [wiml jan2004] ugly - should not be necessary to import these here at all
#import <OWF/OWStaticArc.h>

RCS_ID("$Id$")

#define OWF_Bundle [OWPipeline bundle]

@class OWProcessorCache;

#define OWPipelineErrorDisplayInterval (8.0)

static NSNumber *OWZeroNumber = nil;

@interface OWPipeline (Private)
// Status monitors
+ (void)_updateStatusMonitors:(NSTimer *)timer;

// Methods managing the targetPipelinesMapTable
+ (void)_addPipeline:(OWPipeline *)aPipeline forTarget:(id <OWTarget>)aTarget;
+ (void)_reorderPipeline:(OWPipeline *)aPipeline forTarget:(id <OWTarget>)aTarget nextToPipeline:(OWPipeline *)parentPipeline placeBefore:(BOOL)shouldPlaceBefore;
+ (void)_removePipeline:(OWPipeline *)aPipeline forTarget:(id <OWTarget>)aTarget;
+ (void)_target:(id <OWTarget>)aTarget acceptedContentFromPipeline:(OWPipeline *)acceptedPipeline;

- (void)_deactivateIfPipelineHasNoProcessors;
- (void)_cleanupPipelineIfDead;

- (BOOL)_incorporateOneEntry:(NSArray *)newlyFoundContent fromArc:(id <OWCacheArc>)producer;
- (void)_spawnCloneThroughArc:(NSUInteger)arcIndex addingContent:(OWContent *)newContent beforeSelf:(BOOL)precedes;
- (void)_arcFinished:(id <OWCacheArc, NSObject>)anArc;
- (void)_migrateArc:(id <OWCacheArc>)anArc;
- (void)_removeActiveArc:(id <OWCacheArc>)anArc;
- (void)_forgetArc:(id <OWCacheArc>)anArc;
- (void)_weAreAtAnImpasse;
- (void)_startProcessingContentInThread;
- (void)_startProcessingContentWithCloneParent:(OWPipeline *)cloneParent insertBefore:(BOOL)precedes;
- (OFInvocation *)_processContent;
- (NSNumber *)_deliveryCostOfContent:(OWContent *)someContent;
- (void)_offerContentToTarget;
- (void)_computeAcceptableContentTypes;
- (id <OWCacheArc>)_mostRecentArcProducingSource;

- (void)_sendPipelineFetchNotificationForArc:(id <OWCacheArc>)productiveArc;
- (void)_notifyDeallocationObservers;

// Target stuff
- (void)_notifyTargetOfTreeActivation;
- (void)_notifyTargetOfTreeDeactivation;
- (void)_notifyTargetOfTreeActivation:(id <OWTarget>)aTarget;
- (void)_notifyTargetOfTreeDeactivation:(id <OWTarget>)aTarget;
- (void)_updateStatusOnTarget:(id <OWTarget>)target;
- (void)_rebuildCompositeTypeString;

//
- (OWHeaderDictionary *)_headerDictionaryWaitForCompleteHeaders:(BOOL)shouldWaitForCompleteHeaders;

@end

@interface OWSitePreference (Private)
- (OFPreference *)_preferenceForReading;
@end

@implementation OWPipeline
{
    // Unless otherwise noted, instance variables are protected by the global pipeline lock.

    __weak id <OWTarget, NSObject> _weakTarget; // protected by displayablesSimpleLock

    struct {
        unsigned int pipelineDidBegin: 1;
        unsigned int pipelineDidEnd: 1;
        unsigned int pipelineTreeDidActivate: 1;
        unsigned int pipelineTreeDidDeactivate: 1;
        unsigned int updateStatusForPipeline: 1;
        unsigned int expectedContentDescriptionString: 1;
        unsigned int pipelineHasNewMetadata: 1;
        unsigned int preferenceForKey: 1;
    } targetRespondsTo;               // initialized in -init, and readonly thereafter

    NSMutableDictionary *costEstimates;  // Maps OWContentType to NSNumber. Lazily filled by _traverseArcFromEntry:.
    OWContentCacheGroup *caches;      // List of (id <OWCacheArcProvider>) instances, in search order
    NSMutableSet *rejectedArcs;       // Arcs we've thought about and rejected
    NSMutableArray *followedArcs;     // Arcs we've traversed, corresponding to entries in followedContent
    NSMutableArray *followedContent;  // Content we've found, in traversal order
    NSMutableArray *activeArcs;       // Arcs we've traversed which have not yet retired
    NSMutableSet *followedArcsWithThreads; // Arcs in followedArcs whose state was Running last we checked
    NSMutableArray *givenArcs;        // Arcs provided to us in -init, and considered to be 'free'
    OWCacheSearch *cacheSearch;       // The state of our search for suitable arcs, or nil
    NSUInteger firstErrorContent;     // Index of first content that's an error or error-result
    NSDictionary *targetAcceptableContentTypes;  // Read-only after -init; no lock required
    
    OWContent *mostRecentAddress;     // Latest content that represents an OWAddress; prot. by contextLock
    unsigned int addressCount;        // The number of addresses we've seen; protected by contextLock
    OWContent *mostRecentlyOffered;   // To avoid offering the same content repeatedly
    id <OWCacheArc> mostRecentArcProducingSource; // Basis for -workDone, -workToBeDone, protected by contextLock
    
    NSLock *contextLock;              // Protects a few ivars. NOTE: This is a 'leaf' lock. It is vital that no other locks be acquired while this lock is held.
    NSMutableDictionary *context;     // Miscellaneous context information. Protected by contextLock
    NSMutableArray <OFWeakReference *> *_deallocationObserverReferences; // Protected by contextLock

    struct {
        unsigned int contentError:1;
        unsigned int everHadContentError:1;

        unsigned int processingError:1;
        unsigned int delayedForError:1;
        
        // new
        unsigned int traversingLastArc:1;
        unsigned int delayedNotificationWaitingArc:1;

        unsigned int debug:1;
    } flags;
    OFInvocation *continuationEvent;

    NSString *targetTypeFormatString;
    size_t maximumWorkToBeDone;
    NSUInteger threadsUsedCount;

    NSString *errorNameString;
    NSString *errorReasonString;
    NSDate *errorDelayDate;
}

enum {
    PipelineProcessorConditionNoProcessors, PipelineProcessorConditionSomeProcessors,
};

static NSNotificationCenter *fetchedContentNotificationCenter;
  // Receives notifications whose names are address cache keys, whenever a pipeline completes or sees a permanent redirection

#if defined(DEBUG_wiml) || defined(DEBUG_kc0) || defined(DEBUG_neo0)
static BOOL OWPipelineDebug = YES;
#else
static BOOL OWPipelineDebug = NO;
#endif
static OFSimpleLockType targetPipelinesMapTableLock;
static NSMapTable *targetPipelinesMapTable;
static BOOL activeTreeHasUndisplayedChanges;
static NSTimer *activeStatusUpdateTimer;

// The global cache lock. This used to be a simple NSRecursiveLock, but then things got complicated.
static pthread_mutex_t globalCacheLock;
static pthread_cond_t globalCacheLockCondition;
static pthread_t globalCacheLockThread;
static NSUInteger globalCacheLockRecursionCount;
static NSMutableArray *pendingCacheNotifications;

#define DEFAULT_SIMULTANEOUS_TARGET_CAPACITY (128)

#ifdef DEBUG_kc0
#define DEBUG_OWPipelineSetState
#endif

static void OWPipelineSetState(OWPipeline *self, OWPipelineState newState)
{
    ASSERT_OWPipeline_Locked();
#ifdef DEBUG_OWPipelineSetState
    OWPipelineState oldState = self->state;
#endif
    self->state = newState;
#ifdef DEBUG_OWPipelineSetState
    NSLog(@"OWPipelineSetState(%@): %d -> %d", OBShortObjectDescription(self), oldState, newState);
#endif
}

+ (void)initialize;
{
    OBINITIALIZE;

    fetchedContentNotificationCenter = [[NSNotificationCenter alloc] init];
    OFSimpleLockInit(&targetPipelinesMapTableLock);
    targetPipelinesMapTable = NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks, NSObjectMapValueCallBacks, DEFAULT_SIMULTANEOUS_TARGET_CAPACITY);

    OWZeroNumber = [NSNumber numberWithInt:0];
    
    // Status monitor
    activeTreeHasUndisplayedChanges = NO;
    activeStatusUpdateTimer = nil;

    // Locking
    pthread_mutex_init(&globalCacheLock, NULL);
    pthread_cond_init(&globalCacheLockCondition, NULL);
    globalCacheLockThread = NULL;
    globalCacheLockRecursionCount = 0;
    pendingCacheNotifications = [[NSMutableArray alloc] init];
}

+ (void)setDebug:(BOOL)debug;
{
    OWPipelineDebug = debug;
}

// For notification of pipeline fetches

+ (void)addObserver:(id)anObserver selector:(SEL)aSelector address:(OWAddress *)anAddress;
{
    [fetchedContentNotificationCenter addObserver:anObserver selector:aSelector name:[anAddress cacheKey] object:nil];
}

- (void)addObserver:(id)anObserver selector:(SEL)aSelector
{
    [fetchedContentNotificationCenter addObserver:anObserver selector:aSelector name:nil object:self];
}

+ (void)removeObserver:(id)anObserver address:(OWAddress *)anAddress;
{
    [fetchedContentNotificationCenter removeObserver:anObserver name:[anAddress cacheKey] object:nil];
}

+ (void)removeObserver:(id)anObserver;
{
    [fetchedContentNotificationCenter removeObserver:anObserver];
}

// Target management

+ (void)invalidatePipelinesForTarget:(id <OWTarget>)aTarget;
{
    @autoreleasepool {
        NSArray *pipelines;
        while ((pipelines = [self pipelinesForTarget:aTarget]) != nil) {
            for (OWPipeline *pipeline in pipelines) {
                [pipeline invalidate];
            }
        }
    }
}

+ (void)abortTreeActivityForTarget:(id <OWTarget>)aTarget;
{
    NSArray *pipelines = [self pipelinesForTarget:aTarget];
    for (OWPipeline *pipeline in pipelines) {
        [pipeline abortTreeActivity];
    }
}

+ (void)abortPipelinesForTarget:(id <OWTarget>)aTarget;
{
    NSArray *pipelines = [self pipelinesForTarget:aTarget];
    for (OWPipeline *pipeline in pipelines) {
        [pipeline abortTask];
    }
}

+ (OWPipeline *)currentPipelineForTarget:(id <OWTarget>)aTarget;
{
    NSArray *pipelines = [self pipelinesForTarget:aTarget];
    return [pipelines firstObject];
}

+ (NSArray *)pipelinesForTarget:(id <OWTarget>)aTarget;
{
    NSArray *pipelinesSnapshot;

    OBPRECONDITION(aTarget != nil);

    OFSimpleLock(&targetPipelinesMapTableLock); {
        NSArray *pipelines = [targetPipelinesMapTable objectForKey:aTarget];
        pipelinesSnapshot = pipelines != nil ? [NSArray arrayWithArray:pipelines] : nil;
    } OFSimpleUnlock(&targetPipelinesMapTableLock);

    return pipelinesSnapshot;
}

+ (OWPipeline *)firstActivePipelineForTarget:(id <OWTarget>)aTarget;
{
    NSArray *pipelines = [self pipelinesForTarget:aTarget];
    for (OWPipeline *aPipeline in pipelines) {
        if ([aPipeline treeHasActiveChildren])
            return aPipeline;
    }

    return nil;
}

+ (OWPipeline *)lastActivePipelineForTarget:(id <OWTarget>)aTarget;
{
    NSArray *pipelines = [self pipelinesForTarget:aTarget];
    for (OWPipeline *aPipeline in [pipelines reverseObjectEnumerator]) {
        if ([aPipeline treeHasActiveChildren])
            return aPipeline;
    }
    return nil;
}


// Status Monitoring

+ (void)activeTreeHasChanged;
{
    if (activeTreeHasUndisplayedChanges)
        return;
    activeTreeHasUndisplayedChanges = YES;
    [self queueSelectorOnce:@selector(_updateStatusMonitors:) withObject:nil];
}

+ (void)startActiveStatusUpdateTimer;
{
    OBPRECONDITION(activeStatusUpdateTimer == nil);

    activeStatusUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(_updateStatusMonitors:) userInfo:nil repeats:YES];
}

+ (void)stopActiveStatusUpdateTimer;
{
    OBPRECONDITION(activeStatusUpdateTimer != nil);
    [activeStatusUpdateTimer invalidate];
    activeStatusUpdateTimer = nil;
}

// Managing the global cache lock

static void lockedPostUpdates(NSArray *notesToSend);
static void acquireLockMutexAlreadyHeld(BOOL localMutexHeld, BOOL deliverPending)
{
    NSArray *deliverThese;
    
    pthread_t thisThread = pthread_self();
    
    if (!localMutexHeld)
        pthread_mutex_lock(&globalCacheLock);

    while (1) {
        if (globalCacheLockRecursionCount == 0) {
            OBASSERT(globalCacheLockThread == NULL);
            globalCacheLockThread = thisThread;
            break;
        }
        if (pthread_equal(globalCacheLockThread, thisThread))
            break;
        OBASSERT(globalCacheLockThread != NULL);
        pthread_cond_wait(&globalCacheLockCondition, &globalCacheLock);
    }

    globalCacheLockRecursionCount ++;

    if (deliverPending && [pendingCacheNotifications count]) {
        deliverThese = pendingCacheNotifications;
        pendingCacheNotifications = [[NSMutableArray alloc] init];
    } else
        deliverThese = nil;

    pthread_mutex_unlock(&globalCacheLock);

    lockedPostUpdates(deliverThese);
}

+ (void)lock
{
    acquireLockMutexAlreadyHeld(NO, YES);
}

+ (void)unlock
{
#ifdef OMNI_ASSERTIONS_ON
    pthread_t thisThread = pthread_self();
#endif

    pthread_mutex_lock(&globalCacheLock);

    OBASSERT(pthread_equal(globalCacheLockThread, thisThread));
    OBASSERT(globalCacheLockRecursionCount > 0);

    globalCacheLockRecursionCount --;
    if (globalCacheLockRecursionCount == 0) {
        globalCacheLockThread = NULL;

        pthread_cond_signal(&globalCacheLockCondition);
    }

    pthread_mutex_unlock(&globalCacheLock);
}

+ (BOOL)isLockHeldByCallingThread
{
    pthread_mutex_lock(&globalCacheLock);
    int is = pthread_equal(globalCacheLockThread, pthread_self());
    pthread_mutex_unlock(&globalCacheLock);
    return is? YES : NO;
}

static void lockedPostUpdates(NSArray *updateBlocks)
{
    NSUInteger noteCount = [updateBlocks count];
    NSUInteger noteIndex = 0;
    ASSERT_OWPipeline_Locked();

    // This double loop is to reduce the number of times we add and remove exception handlers in the common, no-exception-raised case.
    while (noteIndex < noteCount) {
        @try {
            while (noteIndex < noteCount) {
                void (^updateBlock)(void) = [updateBlocks objectAtIndex:noteIndex++];
                updateBlock();
            }
            ASSERT_OWPipeline_Locked();
        } @catch (NSException *localException) {
            NSLog(@"*** Exception raised in pipeline notification, ignoring (%@ %lu/%lu) %@",
                  [updateBlocks objectAtIndex:noteIndex - 1], noteIndex - 1, noteCount, localException);
        }
    }
}

static void addBlocksToQueue(NSMutableArray *blockQueue, NSArray *pipelines, void (^updateBlock)(OWPipeline *))
{
    updateBlock = [updateBlock copy];
    for (OWPipeline *pipeline in pipelines) {
        [blockQueue addObject:^{
            updateBlock(pipeline);
        }];
    }
}

+ (void)_blockAndPostNotifications
{
    acquireLockMutexAlreadyHeld(NO, YES);
    [self unlock];
}

+ (void)postUpdateToPipelines:(NSArray *)pipelines withBlock:(void (^)(OWPipeline *))updateBlock;
{
    BOOL acquiredLockLocally;
    
    if (updateBlock == nil || pipelines == nil)
        return;
    NSUInteger targetCount = [pipelines count];
    if (targetCount == 0)
        return;
    
    pthread_mutex_lock(&globalCacheLock);
            
    if (globalCacheLockThread == NULL) {
        // Nobody has the lock right now, so go ahead and process all the notifications.
        acquireLockMutexAlreadyHeld(YES, YES);
        acquiredLockLocally = YES;
        // Fall through to direct posting
    } else if (pthread_equal(globalCacheLockThread, pthread_self())) {
        // We already have the lock. Problem: should we process everyone else's notifications? If yes, then the caller might end up with things changing unexpectedly. If no, then we deliver notifications out of order.
        NSArray *deliverThese = pendingCacheNotifications;
        pendingCacheNotifications = [[NSMutableArray alloc] init];
        pthread_mutex_unlock(&globalCacheLock);
        lockedPostUpdates(deliverThese);
        acquiredLockLocally = NO;
        // Fall through to direct posting
    } else {
        // Someone else has the lock. Add our note to the queue, and if we're the first one in line, fire off an invocation to make sure we get processed.
        BOOL wasEmpty = ( [pendingCacheNotifications count] == 0 );
        addBlocksToQueue(pendingCacheNotifications, pipelines, updateBlock);
        pthread_mutex_unlock(&globalCacheLock);
        if (wasEmpty)
            [[OWProcessor processorQueue] queueSelector:@selector(_blockAndPostNotifications) forObject:(id)self];
        return;
    }

    // This double loop is to reduce the number of times we add and remove exception handlers in the common, no-exception-raised case.
    NSUInteger targetIndex = 0;
    do {
        @try {
            while (targetIndex < targetCount) {
                OWPipeline *aPipeline = [pipelines objectAtIndex:targetIndex++];
                updateBlock(aPipeline);
            }
        } @catch (NSException *localException) {
            NSLog(@"*** Exception raised in pipeline notification, ignoring (target=%p %lu/%lu)",
                  [pipelines objectAtIndex:targetIndex - 1], targetIndex - 1, targetCount);
        }
    } while (targetIndex < targetCount);

    if (acquiredLockLocally)
        [self unlock];
}

// Utility methods

+ (NSString *)stringForTargetContentOffer:(OWTargetContentOffer)offer;
{
    switch (offer) {
        case OWContentOfferDesired: return @"desired";
        case OWContentOfferAlternate: return @"alternate";
        case OWContentOfferError: return @"error";
        case OWContentOfferFailure: return @"failure";
    }
    OBASSERT_NOT_REACHED("switch should handle all conditions");
    return [NSString stringWithFormat:@"<unknown type %d>", offer];
}

// Init and dealloc

+ (void)startPipelineWithAddress:(OWAddress *)anAddress target:(id <OWTarget, NSObject>)aTarget;
{
    OWPipeline *pipeline = [[self alloc] initWithAddress:anAddress target:aTarget];
    [pipeline startProcessingContent];
}

- (id)initWithAddress:(OWAddress *)anAddress target:(id <OWTarget, NSObject>)aTarget;
{
    OWContent *initialContent = anAddress != nil ? [OWContent contentWithAddress:anAddress] : nil;

#ifdef DEBUG_kc
    if (anAddress != nil && [[anAddress addressString] isEqualToString:[[NSUserDefaults standardUserDefaults] stringForKey:@"OWPipelineDebugAddress"]])
        flags.debug = YES;
#endif
    
    return [self initWithContent:initialContent target:aTarget];
}

- (id)initWithContent:(OWContent *)aContent target:(id <OWTarget, NSObject>)aTarget;
{
    OWContentInfo *referringContentInfo = nil;
    NSString *sourceRange = nil;
    
    // TODO - Should we eliminate the use of OWWebPipelineReferringContentInfoKey in OWAddress? Right now it's mostly used within OmniWebKit to keep track of the referrer long enough to use it for site-based filtering and the Referer[sic] header. 
    if ([aContent isAddress]) {
        OWAddress *startAddress = [aContent address];
        referringContentInfo = [[startAddress contextDictionary] objectForKey:OWWebPipelineReferringContentInfoKey];
        if (referringContentInfo != nil)
            aContent = [OWContent contentWithAddress:[startAddress addressWithContextObject:nil forKey:OWWebPipelineReferringContentInfoKey]];
        
        sourceRange = [[startAddress contextDictionary] objectForKey:OWAddressSourceRangeContextKey];
    }
    
    NSArray *initialContent;
    if (aContent != nil)
        initialContent = [NSArray arrayWithObject:aContent];
    else
        initialContent = nil;
    
    OWPipeline *newPipeline = [self initWithCacheGroup:nil content:initialContent arcs:nil target:aTarget];
    if (newPipeline != nil) {
        [newPipeline setContextObject:[NSNumber numberWithBool:NO] forKey:OWCacheArcUseCachedErrorContentKey];
        if (referringContentInfo != nil)
            [newPipeline setReferringContentInfo:referringContentInfo];
        if (sourceRange != nil)
            [newPipeline setContextObject:sourceRange forKey:OWAddressSourceRangeContextKey];
    }

    return newPipeline;
}

- (id)initWithCacheGroup:(OWContentCacheGroup *)someCaches content:(NSArray *)someContent arcs:(NSArray *)someArcs target:(id <OWTarget, NSObject>)aTarget;  // Designated initializer
{
    if (!(self = [super init]))
        return nil;

    state = OWPipelineInit;
    flags.contentError = NO;
    flags.everHadContentError = NO;
    flags.processingError = NO;
    flags.traversingLastArc = NO;
    flags.delayedNotificationWaitingArc = NO;

    costEstimates = [[NSMutableDictionary alloc] init];
    rejectedArcs = [[NSMutableSet alloc] init];
    followedArcs = [[NSMutableArray alloc] init];
    followedArcsWithThreads = [[NSMutableSet alloc] init];
    followedContent = [[NSMutableArray alloc] init];
    activeArcs = [[NSMutableArray alloc] init];
    targetAcceptableContentTypes = nil;
    firstErrorContent = NSNotFound;
    mostRecentAddress = nil;
    
    NSUInteger contentCount = [someContent count];
    
    // Check to see that we're being initialized with content (that's the point of this initializer!)
    OBASSERT(someContent != nil && contentCount > 0);
    if (someContent == nil || contentCount < 1) {
        [NSException raise:NSInvalidArgumentException format:@"Attempt to create a pipeline with no content"];
    }

    // We're guaranteed to have at least 1 object in someContent now
    [followedContent addObject:[someContent objectAtIndex:0]];
    
    // Find most recent address (for -lastAddress)
    NSUInteger contentIndex = contentCount;
    while (contentIndex--) {
        OWContent *content = [someContent objectAtIndex:contentIndex];
        if ([content isAddress]) {
            addressCount++;
            if (mostRecentAddress == nil)
                mostRecentAddress = content;
        }
    }

    /* Strongly retain our target for the duration of our init method */
    _weakTarget = aTarget;
    if (OWPipelineDebug || flags.debug)
        NSLog(@"%@: init, target = %@", [self shortDescription], OBShortObjectDescription(aTarget));

    if (someCaches != nil)
        caches = someCaches;
    else if ([_weakTarget respondsToSelector:@selector(defaultCacheGroup)])
        caches = [(id <OWOptionalTarget>)_weakTarget defaultCacheGroup];
    else
        caches = [OWContentCacheGroup defaultCacheGroup];

    if (someArcs) {
        NSUInteger arcIndex;
        NSUInteger arcCount = [someArcs count];

        givenArcs = [[NSMutableArray alloc] init];
        
        for (arcIndex = 0; arcIndex < arcCount; arcIndex ++) {
            id <OWCacheArc> thisArc = [someArcs objectAtIndex:arcIndex];

#ifdef OMNI_ASSERTIONS_ON
            OBASSERT([[thisArc source] isEqual:[someContent objectAtIndex:arcIndex]]);
            if (arcIndex + 1 < contentCount) {
                OBASSERT([[thisArc object] isEqual:[someContent objectAtIndex:arcIndex+1]]);
            }
#endif

            [givenArcs addObject:thisArc];
            if ([thisArc resultIsSource]) {
                mostRecentArcProducingSource = thisArc;
            }
        }
    }

    OBINVARIANT([followedArcs count]+1 == [followedContent count] ||
                [followedArcs count]   == [followedContent count]);
    
    context = [[NSMutableDictionary alloc] init];
    _deallocationObserverReferences = [[NSMutableArray alloc] init];
    contextLock = [[NSLock alloc] init];
    [self setContentInfo:[[followedContent lastObject] contentInfo]];

#define CHECK_RESPONDS_TO(flag, sel_expr)  targetRespondsTo. flag = [aTarget respondsToSelector:sel_expr]?1:0
    CHECK_RESPONDS_TO(pipelineDidBegin,          @selector(pipelineDidBegin:));
    CHECK_RESPONDS_TO(pipelineDidEnd,            @selector(pipelineDidEnd:));
    CHECK_RESPONDS_TO(pipelineTreeDidActivate,   @selector(pipelineTreeDidActivate:));
    CHECK_RESPONDS_TO(pipelineTreeDidDeactivate, @selector(pipelineTreeDidDeactivate:));
    CHECK_RESPONDS_TO(updateStatusForPipeline,   @selector(updateStatusForPipeline:));
    CHECK_RESPONDS_TO(expectedContentDescriptionString, @selector(expectedContentDescriptionString));
    CHECK_RESPONDS_TO(pipelineHasNewMetadata,    @selector(pipeline:hasNewMetadata:));
    CHECK_RESPONDS_TO(preferenceForKey,          @selector(preferenceForKey:));
#undef CHECK_RESPONDS_TO

    /* Convert our strong retain of the target into a weak retain, but make sure it doesn't go away before we're done with this method */

    NS_DURING {
        [[self class] _addPipeline:self forTarget:_weakTarget];
        [self setParentContentInfo:[_weakTarget parentContentInfo]];
        OBASSERT(parentContentInfo != nil);

        [self _computeAcceptableContentTypes];
        targetTypeFormatString = [_weakTarget targetTypeFormatString];
        [self _rebuildCompositeTypeString];
        if (targetRespondsTo.pipelineDidBegin)
            [(id <OWOptionalTarget>)_weakTarget pipelineDidBegin:self];

        [self _notifyTargetOfTreeActivation:_weakTarget];
    } NS_HANDLER {
        NSLog(@"%@: exception during init: %@", [self shortDescription], localException);
        [self invalidate];
    } NS_ENDHANDLER;

    return self;
}

- (void)dealloc;
{
    [self _invalidateWeakRetains];

    OBPRECONDITION(_weakTarget == nil);
    OBPRECONDITION(cacheSearch == nil);
    
    if (OWPipelineDebug || flags.debug)
	NSLog(@"%@: dealloc", [self shortDescription]);

    [followedArcs makeObjectsPerformSelector:@selector(removeArcObserver:) withObject:self];

    OBASSERT(continuationEvent == nil);
}


// OWTask subclass

- (OWAddress *)lastAddress;
{
    OWAddress *retainedAddress = nil;

    @try {
        [contextLock lock];
        retainedAddress = [mostRecentAddress address];
    } @finally {
        [contextLock unlock];
    }
        
    return retainedAddress;
}

- (BOOL)treeHasActiveChildren;
{
    return (state != OWPipelineInit && state != OWPipelineInvalidating && state != OWPipelineDead) || [super treeHasActiveChildren];
}

- (void)activateInTree;
{
    if (OWPipelineDebug || flags.debug)
        NSLog(@"%@: tree activation", [self shortDescription]);
    
    [super activateInTree];
    [self _notifyTargetOfTreeActivation];
}

- (void)deactivateInTree;
{
    if (OWPipelineDebug || flags.debug)
        NSLog(@"%@: tree deactivation", [self shortDescription]);

    if (errorDelayDate != nil && [errorDelayDate timeIntervalSinceNow] > 0.0) {
        // We had an error, wait around to display it.
        if (!flags.delayedForError) {
            if (OWPipelineDebug || flags.debug)
                NSLog(@"%@: delay for error: %@", [self shortDescription], errorDelayDate);
            flags.delayedForError = YES;
            [[OFScheduler mainScheduler] scheduleSelector:@selector(treeActiveStatusMayHaveChanged) onObject:self withObject:nil atDate:errorDelayDate];
        }
        return;
    } else {
        // No error, or we've already delayed to display it.
        [super deactivateInTree];
        
        [self _notifyTargetOfTreeDeactivation];
        [self _cleanupPipelineIfDead];
    }
}

- (void)abortTask;
{
    if (OWPipelineDebug || flags.debug)
        NSLog(@"%@ %@ state=%d", OBShortObjectDescription(self), NSStringFromSelector(_cmd), state);

    if (state == OWPipelineAborting || state == OWPipelineDead || state == OWPipelineInvalidating) {
        if (OWPipelineDebug || flags.debug)
            NSLog(@"%@ %@ - short circuit (already in state %d)", OBShortObjectDescription(self), NSStringFromSelector(_cmd), state);
        return;
    }

#ifdef DEBUG_kc0
    flags.debug = YES;
#endif

    [OWPipeline lock];
    NS_DURING {
        NSUInteger arcIndex;
        BOOL aborted = NO;

        OWPipelineSetState(self, OWPipelineAborting);
        if (!flags.processingError)
            [self setErrorName:@"UserAbort" reason:nil];

        if (OWPipelineDebug)
            NSLog(@"%@ %@ - scanning %ld arcs", OBShortObjectDescription(self), NSStringFromSelector(_cmd), [followedArcs count]);

        for (arcIndex = 0; arcIndex < [followedArcs count]; arcIndex ++) {
            id <OWCacheArc> anArc = [followedArcs objectAtIndex:arcIndex];
            OWProcessorStatus arcStatus;

            arcStatus = [anArc status];
            if (arcStatus == OWProcessorAborting || arcStatus == OWProcessorRetired)
                continue;
            
#if 0
            // Disabling the following test because it makes it impossible to abort tasks that were started in another pipeline (like downloads)--even if that other pipeline no longer exists
            if ([anArc isKindOfClass:[OWProcessorCacheArc class]] && ![(OWProcessorCacheArc *)anArc isOwnedByPipeline:self]) {
                if (OWPipelineDebug || flags.debug)
                    NSLog(@"%@ %@ - not aborting #%d %@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), arcIndex, [(NSObject *)anArc shortDescription]);
                continue;
            }
#endif

            if (OWPipelineDebug || flags.debug)
                NSLog(@"%@ %@ - aborting #%ld %@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), arcIndex, [(NSObject *)anArc shortDescription]);

            aborted = [anArc abortArcTask];
            if (aborted) {
                // [self _incorporateOneEntry:[anArc entriesWithRelation:OWCacheArcObject] fromArc:anArc];
                break;
            }
        }

        // We may have aborted something (in which case we'll contain some error content describing this fact) or we may not have (if we had no ongoing processes, there's nothing to abort, and -abortArcTask has no effect).
        
#warning if we didnt abort anything, but we havent finished, we need to somehow transition to an aborting state correctly

        // We no longer expect any results from arcs
        [activeArcs removeAllObjects];

        if (OWPipelineDebug)
            NSLog(@"%@ %@ - aborted=%d", OBShortObjectDescription(self), NSStringFromSelector(_cmd), aborted);

    } NS_HANDLER {
        [OWPipeline unlock];
#ifdef DEBUG_toon
        NSLog(@"Exception raised during -abortTask %@", localException);
#endif        
        [localException raise];
    } NS_ENDHANDLER;
    [OWPipeline unlock];
    [self _deactivateIfPipelineHasNoProcessors];
    // [[self class] activeTreeHasChanged];
}

- (NSTimeInterval)estimatedRemainingTimeInterval;
{
    id <OWCacheArc> sourceArc = [self _mostRecentArcProducingSource];
    if (sourceArc == nil)
        return 0.0;

    NSDate *firstBytesDate = [sourceArc firstBytesDate];
    size_t workDone = [sourceArc bytesProcessed];
    size_t workToBeDone = [sourceArc totalBytes];

    if (firstBytesDate == nil || workDone == 0 || workToBeDone == 0 || workDone >= workToBeDone)
        return 0.0;
    
    return -[firstBytesDate timeIntervalSinceNow] * (workToBeDone - workDone) / workDone;
}

- (BOOL)hadError;
{
#warning Implement this
    return flags.everHadContentError || flags.processingError || (firstErrorContent != NSNotFound);
}

- (BOOL)isRunning;
{
    if ([self hadError])
        return NO;

    switch (state) {
        case OWPipelineInit:
        case OWPipelineAborting:
        case OWPipelineInvalidating:
        case OWPipelineDead:
            return NO;
        default:
            return YES;
    }
}

- (BOOL)hasThread;
{
    return threadsUsedCount > 0;
}

- (NSString *)errorNameString;
{
    return errorNameString;
}

- (NSString *)errorReasonString;
{
    return errorReasonString;
}

- (NSString *)compositeTypeString;
{
    NSString *string;

    OFSimpleLock(&displayablesSimpleLock); {
        string = compositeTypeString;
    } OFSimpleUnlock(&displayablesSimpleLock);

    return string;
}

- (size_t)workDone;
{
    id <OWCacheArc> sourceArc = [self _mostRecentArcProducingSource];
    size_t result = [sourceArc bytesProcessed];
    if (result == 0)
        result = maximumWorkToBeDone;
        
    return result;
}

- (size_t)workToBeDone;
{
    id <OWCacheArc> sourceArc = [self _mostRecentArcProducingSource];
    size_t result = [sourceArc totalBytes];
    if (result == 0)
        result = maximumWorkToBeDone;
    else if (result > maximumWorkToBeDone)
        maximumWorkToBeDone = result;
        
    return result;
}

- (NSString *)statusString;
{
    NSString *string = nil;

    if (errorReasonString)
        string = errorReasonString;
    else if ([activeArcs count])
        string = [[activeArcs objectAtIndex:0] statusString];

    if (string)
        return string;
    
    switch (state) {
        case OWPipelineInit:
            return NSLocalizedStringFromTableInBundle(@"Beginning fetch", @"OWF", OWF_Bundle, "pipeline status");
        case OWPipelineBuilding:
            return NSLocalizedStringFromTableInBundle(@"Waiting", @"OWF", OWF_Bundle, "pipeline status");
        case OWPipelineRunning:
            return NSLocalizedStringFromTableInBundle(@"Fetching", @"OWF", OWF_Bundle, "pipeline status");
        case OWPipelineAborting:
        case OWPipelineInvalidating:
            return NSLocalizedStringFromTableInBundle(@"Fetch aborted", @"OWF", OWF_Bundle, "pipeline status");
        case OWPipelineDead:
            return [super statusString];
    }
    return nil; // NOTREACHED
}

- (void)setContentInfo:(OWContentInfo *)newContentInfo;
{
    if ([self contentInfo] == newContentInfo)
        return;
    [super setContentInfo:newContentInfo];
    [self _rebuildCompositeTypeString];
}

- (OFMessageQueueSchedulingInfo)messageQueueSchedulingInfo;
{
    // Give higher priority to longer pipelines, since we really want to finish what we start before we start another pipeline.  This fixes OmniWeb so if you hit a page with, say, 50 inline images, you don't have to wait for all the images to load before any of them start to display.  With this hack, images that are loaded will immediately start imaging.

    OFMessageQueueSchedulingInfo messageQueueSchedulingInfo = [super messageQueueSchedulingInfo];
    messageQueueSchedulingInfo.priority -= [followedArcs count];
    return messageQueueSchedulingInfo;
}

// Pipeline management

- (void)startProcessingContent;
{
    [[OWProcessor processorQueue] queueSelector:@selector(_startProcessingContentInThread) forObject:self];
}

- (void)fetch;
{
    if (state == OWPipelineInit)
        [self startProcessingContent];
    else
        [NSException raise:NSInternalInconsistencyException format:@"Cannot restart an already-run pipeline"];
}

// Target

- (id <OWTarget, NSObject>)target;
{
    id <OWTarget, NSObject> retainedTarget;

    OFSimpleLock(&displayablesSimpleLock);
    retainedTarget = _weakTarget;
    OFSimpleUnlock(&displayablesSimpleLock);
    
    return retainedTarget;
}


- (void)invalidate;
{
    if (OWPipelineDebug || flags.debug)
        NSLog(@"%@: invalidate %@", [self shortDescription], [[self lastAddress] addressString]);

    flags.contentError = NO;
    [OWPipeline lock];
    OFSimpleLock(&displayablesSimpleLock);
    __strong id oldTarget = _weakTarget;
    _weakTarget = nil;
    OFSimpleUnlock(&displayablesSimpleLock);
    NS_DURING {
        if (oldTarget != nil) {
            OBASSERT(state != OWPipelineInvalidating);
            if (state != OWPipelineDead)
                OWPipelineSetState(self, OWPipelineInvalidating);
            [[self class] _removePipeline:self forTarget:oldTarget];
            [self setParentContentInfo:[OWContentInfo orphanParentContentInfo]];
        }
    } NS_HANDLER {
        NSLog(@"-[%@ %@]: caught exception %@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), [localException reason]);
    } NS_ENDHANDLER;

    OBASSERT(_weakTarget == nil);
    OBASSERT(state == OWPipelineInvalidating || state == OWPipelineDead);

    [OWPipeline unlock];

    oldTarget = nil;

    [self _cleanupPipelineIfDead];

    OBPOSTCONDITION(_weakTarget == nil);
    OBPOSTCONDITION(state == OWPipelineInvalidating || state == OWPipelineDead);
}

- (void)parentContentInfoLostContent;
{
    @autoreleasepool {
        id <OWTarget, OWOptionalTarget, NSObject> targetSnapshot = (id)[self target];
        if ([targetSnapshot respondsToSelector:@selector(parentContentInfoLostContent)])
            [targetSnapshot parentContentInfoLostContent];
    }
}

- (void)updateStatusOnTarget;
{
    @autoreleasepool {
        [self _updateStatusOnTarget:[self target]];
    }
}

- (void)setErrorName:(NSString *)newName reason:(NSString *)newReason;
{
    flags.processingError = YES;
    errorNameString = newName;
    errorReasonString = newReason;
    
    if (errorReasonString != nil)
        NSLog(@"Error loading <%@>: %@", [[self lastAddress] addressString], errorReasonString);
    
    /*
    [errorDelayDate release];
    errorDelayDate = [[NSDate alloc] initWithTimeIntervalSinceNow:OWPipelineErrorDisplayInterval];
    */
}

// Content

- (id)contextObjectForKey:(NSString *)key;
{
    return [self contextObjectForKey:key arc:nil];
}

- (id)contextObjectForKey:(NSString *)key arc:(id <OWCacheArc>)arc;
{
    if ([key isEqualToString:OWCacheArcTargetTypesKey]) {
        return targetAcceptableContentTypes;
    }
    if ([key isEqualToString:OWCacheArcSourceAddressKey]) {
        if (arc == nil)
            return nil;
        
        // Short circuit if the source address is obvious.
        // This also handles some rare but legitimate cases where the arc is not in our followedArcs yet.
        if ([[arc source] isAddress])
            return [[arc source] address];
            
        NSUInteger arcIndex = [followedArcs indexOfObjectIdenticalTo:arc];
        OBASSERT(arcIndex != NSNotFound);
        if (arcIndex == NSNotFound)
            return nil;
        OBASSERT(arcIndex < [followedContent count]);
        if (arcIndex >= [followedContent count])
            return nil;
        OBASSERT([[arc source] isEqual:[followedContent objectAtIndex:arcIndex]]);
        for (NSUInteger sourceContentIndex = arcIndex;;) {
            OWContent *previousContent = [followedContent objectAtIndex:sourceContentIndex];
            if ([previousContent isAddress])
                return [previousContent address];
            if (sourceContentIndex == 0)
                return nil;
            sourceContentIndex --;
        }
        OBASSERT_NOT_REACHED("no exit");
    }
    if ([key isEqualToString:OWCacheArcSourceURLKey]) {
        return [[self contextObjectForKey:OWCacheArcSourceAddressKey arc:arc] url];
    }
    if ([key isEqualToString:OWCacheArcApplicableCookiesContentKey]) {
        OWURL *sourceURL = [self contextObjectForKey:OWCacheArcSourceURLKey arc:arc];
#ifdef DEBUG_kc0
        NSLog(@"COOKIES: %@ %s%@ = <%@> -> %@", OBShortObjectDescription(self), _cmd, key, [sourceURL compositeString], [OWCookieDomain cookieHeaderStringForURL:sourceURL]);
#endif
        if (sourceURL != nil)
            return [OWCookieDomain cookieHeaderStringForURL:sourceURL];
        else
            return nil;
    }

    id retainedContextObject;

    [contextLock lock]; {
        retainedContextObject = [context objectForKey:key];
    } [contextLock unlock];

    if (retainedContextObject == nil && [key isEqualToString:OWCacheArcReferringAddressKey]) {
        OWContentInfo *referringContent = [self contextObjectForKey:OWCacheArcReferringContentKey arc:arc];
        return [referringContent address];
    }

    if (retainedContextObject == nil && [[OFPreference registeredKeys] containsObject:key]) {
        OFPreference *preference = [self preferenceForKey:key arc:arc];
        if (preference != nil)
            return [preference objectValue];
    }

    return retainedContextObject;
}

- (OFPreference *)preferenceForKey:(NSString *)key arc:(id <OWCacheArc>)arc;
{
    OWSitePreference *sitePreference = nil;
    if (targetRespondsTo.preferenceForKey) {
        @autoreleasepool {
            sitePreference = [(id <OWOptionalTarget>)[self target] preferenceForKey:key];
        }
    }

    // TODO - We're looking up the site preference according to the URL the item was loaded from, as opposed to the URL of the outermost containing object (which is what "site preferences" is typically keyed off of). Is this wrong?
    // Note that in the common display-in-browser case, the target will respond to preferenceForKey: and so this is only here as a fallback anyway.
    if (sitePreference == nil)
        sitePreference = [OWSitePreference preferenceForKey:key address:[self contextObjectForKey:OWCacheArcSourceAddressKey arc:arc]];

    return [sitePreference _preferenceForReading];
}

- (void)setContextObject:(id)anObject forKey:(NSString *)key;
{
    id retainedPreviousContextObject;

    [contextLock lock]; {
        retainedPreviousContextObject = [context objectForKey:key];
        if (anObject != nil)
            [context setObject:anObject forKey:key];
        else
            [context removeObjectForKey:key];
    } [contextLock unlock];
    retainedPreviousContextObject = nil; // Release this outside the lock to avoid any possibility of deadlock
}

- (id)setContextObjectNoReplace:(id)anObject forKey:(NSString *)key;
{
    id existingObject;
    
    [contextLock lock]; {
        existingObject = [context objectForKey:key];
        if (existingObject == nil && anObject != nil) {
            [context setObject:anObject forKey:key];
            existingObject = anObject;
        }
    } [contextLock unlock];
    return existingObject;
}

- (NSDictionary *)contextDictionary;
{
    NSDictionary *snapshotContextDictionary;

    [contextLock lock];
    snapshotContextDictionary = [[NSDictionary alloc] initWithDictionary:context];
    [contextLock unlock];
    return snapshotContextDictionary;
}

- (void)setReferringAddress:(OWAddress *)anAddress;
{
    [self setContextObject:anAddress forKey:OWCacheArcReferringAddressKey];
}

- (void)setReferringContentInfo:(OWContentInfo *)anInfo
{
    [self setContextObject:anInfo forKey:OWCacheArcReferringContentKey];
    [self setContextObject:nil forKey:OWCacheArcReferringAddressKey];
}

- (NSDate *)fetchDate
{
#warning Either make this return something useful, or get rid of it
    return [NSDate date];
}

- (OWHeaderDictionary *)headerDictionary;
{
    return [self _headerDictionaryWaitForCompleteHeaders:NO];
}

- (NSArray *)validator;
{
    // This is one of those methods that probably belongs on the "pipeline fossil" object once we figure out exactly what that is and implement it. (OBS #12542)
    OWHeaderDictionary *pipelineHeaders = [self headerDictionary];
    
    NSString *validatorKey = [pipelineHeaders lastStringForKey:OWContentValidatorMetadataKey];
    if (validatorKey != nil) {
        NSString *validatorValue = [pipelineHeaders lastStringForKey:validatorKey];
        return [NSArray arrayWithObjects:validatorKey, validatorValue, nil];
    }

    return nil;
}
    
- (void)_invalidateWeakRetains;
{
    OBPRECONDITION(state == OWPipelineInvalidating || state == OWPipelineDead);

    if (OWPipelineDebug || flags.debug)
        NSLog(@"%@: _invalidateWeakRetains", [self shortDescription]);

    [self _notifyDeallocationObservers];

    [OWPipeline lock];

    // Invalidate the weak retains from processor cache arcs
    [followedArcs makeObjectsPerformSelector:@selector(removeArcObserver:) withObject:self];
    [followedArcs removeAllObjects];
    [followedContent removeAllObjects];  // to keep the invariants valid
    [givenArcs removeAllObjects];
    [rejectedArcs removeAllObjects];
    [followedArcsWithThreads removeAllObjects];
    cacheSearch = nil;
    mostRecentArcProducingSource = nil;

    [OWPipeline unlock];
}

- (OWPipeline *)cloneWithTarget:(id <OWTarget, NSObject>)aTarget;
{
    OWPipeline *newPipeline = nil;

    @autoreleasepool {
        [OWPipeline lock];
        @try {
            newPipeline = [[[self class] alloc] initWithCacheGroup:caches content:followedContent arcs:followedArcs target:aTarget];
            @try {
                [contextLock lock];
                [newPipeline->context addEntriesFromDictionary:context];
            } @finally {
                [contextLock unlock];
            }
        } @finally {
            [OWPipeline unlock];
        }
    }

    return newPipeline;
}

- (NSNumber *)estimateCostFromType:(OWContentType *)aType
{
    id nsCost = [costEstimates objectForKey:aType];
    if (nsCost)
        return nsCost;

    float cost = COST_OF_REJECTION;
    OWContentType *deliveredType = nil;

    if (aType == [OWContentType wildcardContentType]) {
        cost = COST_OF_UNCERTAINTY;
    } else {
        OWConversionPathElement *path = [aType bestPathForTargetContentType:[OWContentType wildcardContentType]];
        if (path != nil)
            cost = MIN(cost, [path totalCost] + COST_OF_UNCERTAINTY);
    }

    for (OWContentType *targetType in [targetAcceptableContentTypes keyEnumerator]) {
        float thisCost = [[targetAcceptableContentTypes objectForKey:targetType] floatValue];

        if (targetType != aType) {
            OWConversionPathElement *path = [aType bestPathForTargetContentType:targetType];
            thisCost += path? [path totalCost] : COST_OF_REJECTION;
        }

        if (thisCost < cost) {
            cost = thisCost;
            deliveredType = targetType;
        }

        if (cost == 0)
            break; // can't get cheaper than this
    }

    if (OWPipelineDebug || flags.debug)
        NSLog(@"estimate cost from %@ (delivering %@) = %g", [aType contentTypeString], [deliveredType contentTypeString], cost);

    nsCost = [NSNumber numberWithFloat:cost];
    [costEstimates setObject:nsCost forKey:aType];

    return nsCost;
}

- (void)arcHasStatus:(NSDictionary *)info
{
#ifdef DEBUG_kc0
    NSLog(@"-[%@ %s]: %@", OBShortObjectDescription(self), _cmd, note);
#endif

    ASSERT_OWPipeline_Locked();

    switch (state) {
        case OWPipelineAborting:
        case OWPipelineInvalidating:
            [self _deactivateIfPipelineHasNoProcessors];
            return;
        case OWPipelineDead:
            return;
        default:
            break;
    }

    id <OWCacheArc, NSObject> thisArc = [info objectForKey:@"arc"];
    OBASSERT(thisArc != nil);
    NSUInteger thisArcIndex = [followedArcs indexOfObjectIdenticalTo:thisArc];
    if (thisArcIndex == NSNotFound)
        return;

    BOOL thisArcHasThread = [thisArc status] == OWProcessorRunning; // TODO - store this in note info dict?
    if (thisArcHasThread)
        [followedArcsWithThreads addObject:thisArc];
    else
        [followedArcsWithThreads removeObject:thisArc];
    threadsUsedCount = [followedArcsWithThreads count];

    if (/* [info intForKey:OWCacheArcHasThreadChangeInfoKey defaultValue:0] || */ OWPipelineDebug || flags.debug)
        NSLog(@"%@ <%@> %@ %@ / %@%@ (threadsUsedCount=%ld, delta=%d)", OBShortObjectDescription(self), [[self lastAddress] addressString], [(NSObject *)thisArc shortDescription], [info objectForKey:OWCacheArcStatusStringNotificationInfoKey],  [info objectForKey:OWPipelineHasErrorNotificationErrorNameKey],
              [info boolForKey:OWCacheArcIsFinishedNotificationInfoKey defaultValue:NO]?@" (finished)":@"", threadsUsedCount, [info intForKey:OWCacheArcHasThreadChangeInfoKey defaultValue:0]);

    NSString *errorName = [info objectForKey:OWCacheArcErrorNameNotificationInfoKey];
    if (errorName != nil) {
        NSNotification *forwardedErrorNotification;
        NSMutableDictionary *forwardedNoteInfo;

        if (thisArcIndex != NSNotFound && (firstErrorContent == NSNotFound || firstErrorContent >= thisArcIndex)) {
            [self setErrorName:errorName reason:[info objectForKey:OWCacheArcErrorReasonNotificationInfoKey]];
            firstErrorContent = thisArcIndex;
        }

        // Objects outside of the pipeline system listen for OWPipelineHasErrorNotificationName notifications
        forwardedNoteInfo = [info mutableCopy];
        [forwardedNoteInfo removeObjectForKey:@"arc"];
        [forwardedNoteInfo setObject:self forKey:OWPipelineHasErrorNotificationPipelineKey];
        forwardedErrorNotification = [NSNotification notificationWithName:OWPipelineHasErrorNotificationName object:self userInfo:forwardedNoteInfo];
        [[OWProcessor processorQueue] queueSelectorOnce:@selector(postNotification:) forObject:[NSNotificationCenter defaultCenter] withObject:forwardedErrorNotification];
    }

    [self updateStatusOnTarget];

    if ([info boolForKey:OWCacheArcIsFinishedNotificationInfoKey defaultValue:NO])
        [self _arcFinished:thisArc];
}

- (void)arcHasResult:(NSDictionary *)info;
{
    id <OWCacheArc, NSObject> productiveArc;
    BOOL productiveArcIsWaitingArc;
    BOOL gotContent;

#ifdef DEBUG_kc0
    NSLog(@"-[%@ %s]: %@", OBShortObjectDescription(self), _cmd, note);
#endif

    ASSERT_OWPipeline_Locked();

    switch (state) {
        case OWPipelineAborting:
        case OWPipelineInvalidating:
            [self _deactivateIfPipelineHasNoProcessors];
            return;
        case OWPipelineDead:
            return;
        default:
            break;
    }

    productiveArc = [info objectForKey:@"arc"];
    OBASSERT(productiveArc != nil);

    productiveArcIsWaitingArc = ( [followedArcs lastObject] == (id)productiveArc ) &&
        ( [followedArcs count] == [followedContent count] );

    /* Tell pipeline observers about this arc, if it's interesting to outsiders */
    [self _sendPipelineFetchNotificationForArc:productiveArc];

    if (flags.traversingLastArc && productiveArcIsWaitingArc) {
        flags.delayedNotificationWaitingArc = 1;
        return;
    }

    gotContent = [self _incorporateOneEntry:[productiveArc entriesWithRelation:OWCacheArcObject] fromArc:productiveArc];

    if (productiveArcIsWaitingArc) {
        OBASSERT(continuationEvent == nil);
        OBASSERT(!flags.traversingLastArc);
        if (gotContent) {
            // Got some new content. Go ahead and deal with it.
            cacheSearch = nil;
            [self _processContent];
        } else {
            // The arc we're waiting on has finished but either it didn't produce anything or it didn't produce anything we haven't seen before. We're probably stuck, but call _processContent again in case it comes up with something.
#ifdef DEBUG_kc
            if (flags.debug)
                NSLog(@"-[%@ %@]: arc has result, but _incorporateOneEntry:fromArc: failed, forgetting arc %@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), OBShortObjectDescription(productiveArc));
#endif
            [self _forgetArc:productiveArc];  // deregister as an observer of this arc

            [self _processContent];
        }
        if (continuationEvent)
            [[OWProcessor processorQueue] addQueueEntry:continuationEvent];
    } else {
        // _incorporateOneEntry: will not return YES if the arc that produced the content was not our last (pending) arc; instead it will clone us and have our clone deal with the new content.
        OBASSERT(!gotContent);

        // Possibly, some previously-traversed arc produced some content we already had. Ignore it.
    }
}

// Some objects are interested in knowing when we're about to deallocate

- (void)addDeallocationObserver:(id <OWPipelineDeallocationObserver>)anObserver;
{
    [contextLock lock];
    [OFWeakReference add:anObserver toReferences:_deallocationObserverReferences];
    [contextLock unlock];
}

- (void)removeDeallocationObserver:(id <OWPipelineDeallocationObserver>)anObserver;
{
    id <OWPipelineDeallocationObserver> strongObserverReference = anObserver; // Don't deallocate the observer while holding our lock
    [contextLock lock];
    [OFWeakReference remove:anObserver fromReferences:_deallocationObserverReferences];
    [contextLock unlock];
    strongObserverReference = nil;
}

@end

@implementation OWPipeline (SubclassesOnly)

- (void)deactivate;
{
    OBPRECONDITION(state == OWPipelineDead);
        
    @autoreleasepool {
        id <OWTarget, OWOptionalTarget, NSObject> targetSnapshot;

        if (OWPipelineDebug || flags.debug)
            NSLog(@"%@: deactivate", [self shortDescription]);

        targetSnapshot = (id)[self target];
        if (targetSnapshot != nil && targetRespondsTo.pipelineDidEnd)
            [targetSnapshot pipelineDidEnd:self];

        [self treeActiveStatusMayHaveChanged]; // Will call -deactivateInTree
    }
}


@end


@implementation OWPipeline (Private)

// Status monitors

+ (void)_updateStatusMonitors:(NSTimer *)timer;
{
    for (OWPipeline *pipeline in [OWContentInfo allActiveTasks]) {
        if ([pipeline isKindOfClass:[OWPipeline class]])
            [pipeline updateStatusOnTarget];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OWPipelineTreePeriodicUpdateNotificationName object:nil];
    
    activeTreeHasUndisplayedChanges = NO;
}


// Methods managing the targetPipelinesMapTable

+ (void)_addPipeline:(OWPipeline *)aPipeline forTarget:(id <OWTarget>)aTarget;
{
    OBPRECONDITION(aTarget != nil);
    OBPRECONDITION(aPipeline != nil);

    OFSimpleLock(&targetPipelinesMapTableLock); {
    
        NSMutableArray *pipelines = [targetPipelinesMapTable objectForKey:aTarget];
        if (pipelines == nil) {
            pipelines = [[NSMutableArray alloc] init];
            [targetPipelinesMapTable setObject:pipelines forKey:aTarget];
        }

        OBASSERT(![pipelines containsObjectIdenticalTo:aPipeline]);
        [pipelines addObject:aPipeline];

    } OFSimpleUnlock(&targetPipelinesMapTableLock);
}

+ (void)_reorderPipeline:(OWPipeline *)aPipeline forTarget:(id <OWTarget>)aTarget nextToPipeline:(OWPipeline *)parentPipeline placeBefore:(BOOL)shouldPlaceBefore;
{
    OBPRECONDITION(aPipeline != nil);
    OBPRECONDITION(parentPipeline != nil);
    OBPRECONDITION(aPipeline != parentPipeline);

    if (aTarget == nil)
        return; // Our target is invalidating itself (-strongRetain apparently returned nil), but hasn't gotten around to notifying us yet

    OFSimpleLock(&targetPipelinesMapTableLock); {
    
        NSMutableArray *pipelines = [targetPipelinesMapTable objectForKey:aTarget];
        OBASSERT(pipelines != nil);

        OWPipeline *retainedPipeline = aPipeline;

        OBASSERT([pipelines containsObjectIdenticalTo:aPipeline]);
        [pipelines removeObjectIdenticalTo:aPipeline];

        NSUInteger parentPipelineIndex = [pipelines indexOfObjectIdenticalTo:parentPipeline];
        OBASSERT(parentPipelineIndex != NSNotFound);

        if (shouldPlaceBefore)
            [pipelines insertObject:aPipeline atIndex:parentPipelineIndex];
        else
            [pipelines insertObject:aPipeline atIndex:parentPipelineIndex + 1];

        retainedPipeline = nil;

    } OFSimpleUnlock(&targetPipelinesMapTableLock);
}

+ (void)_removePipeline:(OWPipeline *)aPipeline forTarget:(id <OWTarget>)aTarget;
{
    OBPRECONDITION(aTarget != nil);
    OBPRECONDITION(aPipeline != nil);

    OFSimpleLock(&targetPipelinesMapTableLock); {

        NSMutableArray *pipelines = [targetPipelinesMapTable objectForKey:aTarget];
        OBPRECONDITION(pipelines != nil && [pipelines indexOfObjectIdenticalTo:aPipeline] != NSNotFound);

        OBRetainAutorelease(aPipeline);
        [pipelines removeObjectIdenticalTo:aPipeline];
        if ([pipelines count] == 0)
            [targetPipelinesMapTable removeObjectForKey:aTarget];

    } OFSimpleUnlock(&targetPipelinesMapTableLock);
}

+ (void)_target:(id <OWTarget>)aTarget acceptedContentFromPipeline:(OWPipeline *)acceptedPipeline;
{
    NSArray *pipelines;
    NSUInteger pipelineIndex, pipelineCount;

    // Nullify the targets of all pipelines that were created BEFORE this one with the same target, because we don't want them returning content later and overwriting our content.  Pipelines created AFTER us are left alone, so if they ever return valid content they'll steal our target as their own.
    pipelines = [self pipelinesForTarget:aTarget];
    pipelineCount = [pipelines count];
    for (pipelineIndex = 0; pipelineIndex < pipelineCount; pipelineIndex++) {
        OWPipeline *aPipeline;

        aPipeline = [pipelines objectAtIndex:pipelineIndex];
        if (aPipeline == acceptedPipeline)
            return;
        [aPipeline invalidate];
    }
#ifdef DEBUG
    NSLog(@"PROGRAM ERROR: _target:acceptedContentFromPipeline: called with a pipeline that isn't registered for the target");
    OBASSERT(NO);
#endif
}

//
- (void)_deactivateIfPipelineHasNoProcessors;
{
    [[OWProcessor processorQueue] queueSelectorOnce:@selector(__deactivateIfPipelineHasNoProcessors) forObject:self];
}

- (void)__deactivateIfPipelineHasNoProcessors;
{
    BOOL shouldDeactivate = YES;

    if (OWPipelineDebug || flags.debug)
        NSLog(@"%@: %@", [self shortDescription], NSStringFromSelector(_cmd));

    [OWPipeline lock];
    NS_DURING {
        if (state == OWPipelineDead) {
            // Already dead or dying.
            if (OWPipelineDebug || flags.debug)
                NSLog(@"%@: %@: already dead", [self shortDescription], NSStringFromSelector(_cmd));
            shouldDeactivate = NO;
        } else if (state == OWPipelineBuilding || continuationEvent != nil || flags.traversingLastArc) {
            // We're in the middle of doing something right now.
            if (OWPipelineDebug || flags.debug)
                NSLog(@"%@: %@: continuationEvent=%@, traversingLastArc=%d", [self shortDescription], NSStringFromSelector(_cmd), [continuationEvent shortDescription], flags.traversingLastArc);
            shouldDeactivate = NO;
        } else if ([activeArcs count] != 0) {
            // We still have active arc notifications pending:  the arcs themselves may have already switched over to the 'retired' state, but their notifications are still pending
            if (OWPipelineDebug || flags.debug)
                NSLog(@"%@: %@: activeArcs=%@", [self shortDescription], NSStringFromSelector(_cmd), [activeArcs description]);
            shouldDeactivate = NO;
        } else {
            // compute whether we have any active or queued processes associated with us
            // this differs from -hasThread in that it counts queued-but-not-started processors
            OFForEachInArray(followedArcs, id <OWCacheArc>, anArc,
                             if ([anArc status] != OWProcessorRetired) {
                                 if (OWPipelineDebug || flags.debug)
                                     NSLog(@"%@: %@: arc is not retired: %@ (status=%d)", [self shortDescription], NSStringFromSelector(_cmd), anArc, [anArc status]);
                                 shouldDeactivate = NO;
                                 break;
                             }
                             );
        }
    } NS_HANDLER {
        [OWPipeline unlock];
#ifdef DEBUG_toon
        NSLog(@"Exception raised during -_deactivateIfPipelineHasNoProcessors %@", localException);
#endif        
        [localException raise];
    } NS_ENDHANDLER;

    if (shouldDeactivate) {
        OBASSERT(state != OWPipelineDead);
        OWPipelineSetState(self, OWPipelineDead);
    }

    [OWPipeline unlock];

    if (shouldDeactivate) {
        [self deactivate];
    }

}


- (void)_cleanupPipelineIfDead;
{
    BOOL treeHasActiveChildren = [self treeHasActiveChildren];
    if (OWPipelineDebug || flags.debug)
        NSLog(@"%@: %@ - target=%@ treeHasActiveChildren=%d", [self shortDescription], NSStringFromSelector(_cmd), OBShortObjectDescription([self target]), treeHasActiveChildren);

    // Note: This non-locked access to target should be fine because even if we're half-way through a write our equality test will still give a reasonable result
    if ([self target] != nil || treeHasActiveChildren)
        return;

    [OWPipeline lock];
    if (state == OWPipelineInit)
        OWPipelineSetState(self, OWPipelineDead); // We never started processing anything, so we don't need to abort it
    [OWPipeline unlock];

    OBRetainAutorelease(self); // Ensure we stick around for a little while yet
    [self setParentContentInfo:nil];
    [self setContentInfo:nil];

    [self _notifyDeallocationObservers];
}

- (void)_startProcessingContentWithCloneParent:(OWPipeline *)cloneParent insertBefore:(BOOL)shouldPlaceBefore
{
    switch (state) {
        case OWPipelineAborting:
        case OWPipelineInvalidating:
        case OWPipelineDead:
            return;
        default:
            break;
    }

    OFInvocation *continuation = nil;

    @autoreleasepool {
        if (OWPipelineDebug || flags.debug)
            NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));

        [OWPipeline lock];
        @try {
            switch (state) {
                case OWPipelineInit:
                    if (cloneParent != nil) {
                        // We're already registered as a pipeline for our target, but we want to change our ordering
                        [[self class] _reorderPipeline:self forTarget:[self target] nextToPipeline:cloneParent placeBefore:shouldPlaceBefore];
                    }

                    OWPipelineSetState(self, OWPipelineBuilding);

                    // NO BREAK

                case OWPipelineBuilding:

                    if (cloneParent != nil) {
                        NSNotification *note = [NSNotification notificationWithName:OWPipelineHasBuddedNotificationName object:cloneParent userInfo:[NSDictionary dictionaryWithObject:self forKey:OWPipelineChildPipelineKey]];
                        [[NSNotificationCenter defaultCenter] postNotification:note];
                    }

                    if (continuationEvent == nil)
                        continuation = [self _processContent];

                    break;

                case OWPipelineRunning:

                    // We've already delivered content, why process more?
                    OBASSERT(state != OWPipelineRunning);
                    break;

                case OWPipelineAborting:
                case OWPipelineInvalidating:
                case OWPipelineDead:

                    // We shouldn't be trying to process anything at this point
                    break;
            }
        } @finally {
            [OWPipeline unlock];
        }
    }

    [self treeActiveStatusMayHaveChanged];
    
    if (continuation != nil)
        [[OWProcessor processorQueue] addQueueEntry:continuationEvent];
}

- (OWCacheArcTraversalResult)_traverseArcFromSearch:(id <OWCacheArc>)possibleArc
{
    NSArray *newlyFoundContent;
    BOOL given;
    unsigned invalidity;

#ifdef DEBUG_kc0
    if ([lastEntry contentType] == [OWContentType unknownContentType])
        flags.debug = YES;
#endif

    ASSERT_OWPipeline_Locked();

    newlyFoundContent = nil;

    [followedArcs addObject:possibleArc];
    if ([possibleArc status] == OWProcessorRunning)
        [followedArcsWithThreads addObject:possibleArc];
    threadsUsedCount = [followedArcsWithThreads count];
    // Note - we need to call addObserver:/removeObserver: whenever we modify followedArcs. Normally we call it at the same time; here we call it a few lines later, after we've verified we won't be immediately removing the arc from followedArcs again.

    given = [givenArcs containsObjectIdenticalTo:possibleArc];

    if (given) {
        invalidity = 0;  // Arcs we've been given in -init get a free pass.
        if (OWPipelineDebug || flags.debug)
            NSLog(@"%@: following given arc %@", OBShortObjectDescription(self), [(OFObject *)possibleArc shortDescription]);
    } else {
        // -invalidInPipeline: sometimes requires us to have already placed the arc into followedArcs
        invalidity = [possibleArc invalidInPipeline:self];
    }

    if (invalidity != 0) {
        if (OWPipelineDebug || flags.debug)
            NSLog(@"%@: rejecting possible arc %@: 0x%x", OBShortObjectDescription(self), [(OFObject *)possibleArc shortDescription], invalidity);
        OBASSERT([followedArcs lastObject] == (id)possibleArc);
        [followedArcs removeLastObject];
        [followedArcsWithThreads removeObject:possibleArc];
        threadsUsedCount = [followedArcsWithThreads count];
        [rejectedArcs addObject:possibleArc];
        return OWCacheArcTraversal_Failed;
    }

    [possibleArc addArcObserver:self];
    OBASSERT([followedArcs count] == [followedContent count]);
    OBASSERT(!flags.traversingLastArc);
    flags.traversingLastArc = 1;
    flags.delayedNotificationWaitingArc = 0;

    if (OWPipelineDebug || flags.debug)
        NSLog(@"%@: traversing %@", [self shortDescription], OBShortObjectDescription(possibleArc));

    OWCacheArcTraversalResult progress = [possibleArc traverseInPipeline:self];

    OBASSERT(possibleArc == [followedArcs lastObject]);
    OBASSERT(flags.traversingLastArc);
    flags.traversingLastArc = 0;
    if (flags.delayedNotificationWaitingArc) {
        OBASSERT(progress != OWCacheArcTraversal_Failed);
        progress = OWCacheArcTraversal_HaveResult;
    }

    switch (progress) {
        default:
            OBASSERT_NOT_REACHED("Invalid result from -traverseInPipeline:");
            progress = OWCacheArcTraversal_Failed;
            /* FALL THROUGH */
        case OWCacheArcTraversal_Failed:
            break;
        case OWCacheArcTraversal_HaveResult:
            newlyFoundContent = [possibleArc entriesWithRelation:OWCacheArcObject];
            if ([self _incorporateOneEntry:newlyFoundContent fromArc:possibleArc]) {
                OBASSERT([followedArcs count]+1 == [followedContent count]);

                /* Tell pipeline observers about this arc, if it's interesting to outsiders */
                [self _sendPipelineFetchNotificationForArc:possibleArc];
            } else {
                progress = OWCacheArcTraversal_Failed;
            }
            break;
        case OWCacheArcTraversal_WillNotify:
            OBASSERT([followedArcs count] == [followedContent count]);
            [activeArcs addObject:possibleArc];
            break;
    }

    switch (progress) {
        default:
        case OWCacheArcTraversal_Failed:
#ifdef DEBUG_kc
            if (OWPipelineDebug || flags.debug)
                NSLog(@"-[%@ %@]: traversal failed, forgetting arc %@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), OBShortObjectDescription(possibleArc));
#endif
            [self _forgetArc:possibleArc];
            OBASSERT([followedArcs count]+1 == [followedContent count]);
            break;
        case OWCacheArcTraversal_HaveResult:
        case OWCacheArcTraversal_WillNotify:
            if ([possibleArc resultIsSource]) {
                [contextLock lock];
                id <OWCacheArc> previousArc = mostRecentArcProducingSource; // Inherit retain
                mostRecentArcProducingSource = possibleArc;
                [contextLock unlock];
                previousArc = nil; // Release outside the lock to avoid a deadlock when the arc tries to remove itself as a deallocation observer
            }
            break;
    }


    if (OWPipelineDebug || flags.debug)
        NSLog(@"-[%@ %@]: end (progress=%d)", OBShortObjectDescription(self), NSStringFromSelector(_cmd), progress);
    return progress;
}

- (BOOL)_incorporateOneEntry:(NSArray *)newlyFoundContent fromArc:(id <OWCacheArc>)producer
{
    id <OWCacheArc> waitingOnArc;
    unsigned invalidity;
    BOOL given;
    
    if ([followedArcs count] == [followedContent count])
        waitingOnArc = [followedArcs lastObject];
    else
        waitingOnArc = nil;

    given = [givenArcs containsObjectIdenticalTo:producer];

    // An arc can become invalid, if it's a processor arc owned by another pipeline who has different context from us. In this case we have to keep looking.
    if (given)
        invalidity = 0;  // Arcs we've been given in -init get a free pass.
    else
        invalidity = [producer invalidInPipeline:self];
#ifdef DEBUG_kc
    if (flags.debug)
        NSLog(@"%@ - hoping to incorporate %@ from %@, invalid=0x%x", OBShortObjectDescription(self), [(NSObject *)newlyFoundContent shortDescription], [(NSObject *)producer shortDescription], invalidity);
#endif
    if (invalidity & (OWCacheArcInvalidContext|OWCacheArcStale))
        return NO;

    NSUInteger newlyFoundContentIndex = [newlyFoundContent count];
    while (newlyFoundContentIndex--) {
        OWContent *newlyFoundContentEntry = [newlyFoundContent objectAtIndex:newlyFoundContentIndex];

        if (![newlyFoundContentEntry contentIsValid])
            continue;

        if ([followedContent indexOfObjectIdenticalTo:newlyFoundContentEntry] == NSNotFound) {
            if (producer == waitingOnArc) {
                // The arc we're waiting on has produced some content. Add it to our list of followed content, and update the variables which cache information about our content (firstErrorContent and mostRecentAddress).
                if ([newlyFoundContentEntry isAddress]) {
                    BOOL addressCountTooBig = NO;

                    [contextLock lock];
                    addressCount++;
                    addressCountTooBig = (addressCount > 10);
                    if (!addressCountTooBig) {
                        mostRecentAddress = newlyFoundContentEntry;
                    }
                    [contextLock unlock];
                    if (addressCountTooBig) {
                        newlyFoundContentEntry = [OWContent contentWithConcreteCacheEntry:[NSException exceptionWithName:@"Too Many Redirects" reason:[NSString stringWithFormat:@"Too many redirects, last redirect was from <%@> to <%@>", [[mostRecentAddress address] addressString], [[newlyFoundContentEntry address] addressString]] userInfo:nil]];
                        // return YES;
                    }
                    [rejectedArcs removeAllObjects];
                }
                [followedContent addObject:newlyFoundContentEntry];
                if (firstErrorContent == NSNotFound && [producer resultIsError])
                    firstErrorContent = [followedContent count]-1;
                    
                [self setContentInfo:[newlyFoundContentEntry contentInfo]];
                
                if (OWPipelineDebug || flags.debug)
                    NSLog(@"%@: added content %@: %@ from arc %@; content count = %ld, arc count = %ld",
                          OBShortObjectDescription(self), [[newlyFoundContentEntry contentType] contentTypeString], newlyFoundContentEntry, OBShortObjectDescription(producer),                           [followedContent count], [followedArcs count]);
                OBASSERT([followedContent count] == [followedArcs count]+1);
                return YES;
            } else {
                NSUInteger arcIndex = [followedArcs indexOfObjectIdenticalTo:producer];

                if (arcIndex == NSNotFound) {
                    OBASSERT_NOT_REACHED("Incorporating content from unexpected arc");
                    return NO;
                }
                OBASSERT(arcIndex + 1 < [followedContent count]);

                // Some arc we've already traversed has spit out some new content. We want to start over again from the new content. So, we create a clone of ourselves which starts over from the point at which the arc produced the new content.

                // See <bug://bugs/14679>: When we clone a pipeline to handle a processor exception, the clone ignores the exception and restarts the processor, yielding an endless stream of failing pipeline clones.
                // To work around this for now (until we come up with a better solution), let's test whether the content in question is an exception, and if so we'll just log the exception to the console rather than cloning a pipeline to deliver the error to our target.
                if ([newlyFoundContentEntry isException]) {
                    NSException *exception = [newlyFoundContentEntry objectValue];
                    NSLog(@"Warning: <%@>: %@: %@", [[self lastAddress] addressString], [exception name], [exception reason]);
                } else {
                    // Some arc we've already traversed has spit out some new content. We want to start over again from the new content. So, we create a clone of ourselves which starts over from the point at which the arc produced the new content.
                    [self _spawnCloneThroughArc:arcIndex addingContent:newlyFoundContentEntry beforeSelf:NO];
                }

                return NO;
            }
        }
    }
    return NO;
}

- (void)_spawnCloneThroughArc:(NSUInteger)arcIndex addingContent:(OWContent *)newContent beforeSelf:(BOOL)precedes
{
    NSRange laterContent, reusedArcs;
    NSMutableArray *newPipelineContent;
    NSArray *newPipelineArcs;
    OWPipeline *newPipeline;
    id <OWTarget, NSObject> targetSnapshot = [self target];

    ASSERT_OWPipeline_Locked();

    if (OWPipelineDebug || flags.debug)
        NSLog(@"%@: spawning clone: %ld arcs, new content = %@, precedes=%d, target = %@",
              OBShortObjectDescription(self), arcIndex+1,
              OBShortObjectDescription(newContent), precedes,
              OBShortObjectDescription(targetSnapshot));

    if (targetSnapshot == nil)
        return;

    OBASSERT(arcIndex+1 < [followedContent count]);

    laterContent.location = arcIndex + 1;
    laterContent.length = [followedContent count] - (arcIndex + 1);
    reusedArcs.location = 0;
    reusedArcs.length = arcIndex + 1;

    newPipelineContent = [followedContent mutableCopy];
    [newPipelineContent removeObjectsInRange:laterContent];
    if (newContent)
        [newPipelineContent addObject:newContent];

    newPipelineArcs = [followedArcs subarrayWithRange:reusedArcs];

    newPipeline = [[[self class] alloc] initWithCacheGroup:caches content:newPipelineContent arcs:newPipelineArcs target:targetSnapshot];
    [contextLock lock];
    [newPipeline->context addEntriesFromDictionary:context];
    [contextLock unlock];
    [newPipeline _startProcessingContentWithCloneParent:self insertBefore:precedes];
}

- (void)_arcFinished:(id <OWCacheArc, NSObject>)anArc
{
    BOOL finishedArcIsWaitingArc;

    finishedArcIsWaitingArc = ( [followedArcs lastObject] == (id)anArc ) &&
                              ( [followedArcs count] == [followedContent count] );
    
    // If we were waiting for an arc to produce content, and it didn't, we have a problem and need to deal with it.
    if (finishedArcIsWaitingArc) {
        if (OWPipelineDebug || flags.debug)
            NSLog(@"%@: Waiting on %@ but it finished with no output", OBShortObjectDescription(self), [(NSObject *)anArc shortDescription]);

        if (flags.traversingLastArc && finishedArcIsWaitingArc) {
            flags.delayedNotificationWaitingArc = 1;
        } else {
#ifdef DEBUG_kc0
            NSLog(@"-[%@ %s]: processor status notification, forgetting arc %@", OBShortObjectDescription(self), _cmd, OBShortObjectDescription(productiveArc));
#endif
            [self _forgetArc:anArc];  // deregister as an observer of this arc
            [[OWProcessor processorQueue] queueSelector:@selector(_blockThenProcess) forObject:self]; // do some more stuff
        }
        return;
    }

    // Migrate arcs into the longer-term cache.
    [[OWProcessor processorQueue] queueSelector:@selector(_migrateArc:) forObject:self withObject:anArc];

    [self _removeActiveArc:anArc];
}

- (void)_migrateArc:(id <OWCacheArc>)anArc;
{
    NSUInteger replacementArcIndex;
    id <OWCacheArc> replacementArc;
    id <OWCacheArcProvider, OWCacheContentProvider> destinationCache;

    OBASSERT([anArc status] == OWProcessorRetired);

    [OWPipeline lock];
    NS_DURING {

        replacementArcIndex = [followedArcs indexOfObjectIdenticalTo:anArc];
        destinationCache = [caches resultCache];

        // Migrate completed, nonerroneous arcs into the longer-term cache.
        if ((firstErrorContent == NSNotFound || firstErrorContent > [followedArcs indexOfObjectIdenticalTo:anArc])
            && [destinationCache canStoreArc:anArc]) {

            if ([anArc respondsToSelector:@selector(addToCache:)]) {
                // We just verified that anArc implements this method, so the cast is valid
                replacementArc = [(id)anArc addToCache:destinationCache];
            } else {
                OBASSERT([anArc isKindOfClass:[OWStaticArc class]]);
                replacementArc = [destinationCache addArc:(OWStaticArc *)anArc];
            }
                
            if (OWPipelineDebug || flags.debug)
                NSLog(@"%@ Migrating arc %@ to cache %@ --> %@",
                      OBShortObjectDescription(self), [(NSObject *)anArc shortDescription],
                      OBShortObjectDescription(destinationCache), [(NSObject *)replacementArc shortDescription]);

            // Replace our reference to the arc with a reference to the new arc (if different).
            if (replacementArc != nil && replacementArc != anArc && replacementArcIndex != NSNotFound) {
                // Deal with notifications
                [replacementArc addArcObserver:self];
                [anArc removeArcObserver:self];
                [followedArcsWithThreads removeObject:anArc];
                OBASSERT([replacementArc status] != OWProcessorRunning); // If this isn't true, we'd need to add it to followedArcsWithThreads, but it should always be true at the moment
                threadsUsedCount = [followedArcsWithThreads count];
                [followedArcs replaceObjectAtIndex:replacementArcIndex withObject:replacementArc];
                [self _removeActiveArc:anArc];
            }
        }

        OBASSERT([anArc isKindOfClass:[OWProcessorCacheArc class]]);
        // Completed processor arcs should either be in the memory cache if non-erroneous, or forgotten if erroneous. Now that the arc has possibly been stored in the memory cache, remove it from the processor cache.
        [(OWProcessorCacheArc *)anArc removeFromCache];            
    } NS_HANDLER {
        [OWPipeline unlock];
#ifdef DEBUG_toon        
        NSLog(@"Exception during _migrateArc: %@", localException);
#endif        
        [localException raise];
    } NS_ENDHANDLER;

    [OWPipeline unlock];
}

- (void)_removeActiveArc:(id <OWCacheArc>)anArc;
{
    [rejectedArcs addObject:anArc]; // don't try this same arc again, we hate it, pfui!
    [cacheSearch rejectArc:anArc];
    [activeArcs removeObjectIdenticalTo:anArc];
    [self _deactivateIfPipelineHasNoProcessors];
}

- (void)_forgetArc:(id <OWCacheArc>)anArc;
{
    [self _removeActiveArc:anArc];

    NSUInteger arcIndex = [followedArcs indexOfObjectIdenticalTo:anArc];
    OBASSERT(arcIndex != NSNotFound);
    // OBASSERT(arcIndex + 1 == [followedArcs count]); // Otherwise, a future arc is derived from the one we're forgetting (and we ought to forget it too?).  TODO: This assertion fails when loading <http://www.WorldofWarcraft.com>, where we end up with two OWHTTPProcessor arcs.
    if (OWPipelineDebug || flags.debug)
        NSLog(@"%@: forgetting arc at index %ld (of %ld arcs); content count = %ld",
              OBShortObjectDescription(self),
              arcIndex, [followedArcs count], [followedContent count]);
#ifdef DEBUG_kc
    if (OWPipelineDebug || flags.debug)
        NSLog(@"%@: forgetting arc %@ of %@",
              OBShortObjectDescription(self),
              anArc, followedArcs);
#endif
    [anArc removeArcObserver:self];
    [followedArcsWithThreads removeObject:anArc];
    threadsUsedCount = [followedArcsWithThreads count];
    [followedArcs removeObjectAtIndex:arcIndex];

    OBINVARIANT(!([followedArcs count] > [followedContent count]));
    OBINVARIANT(!([followedArcs count]+1 < [followedContent count]));

    [self _deactivateIfPipelineHasNoProcessors];
}

// _weAreAtAnImpasse is called through an OFMessageQueue invocation
- (void)_weAreAtAnImpasse;
{
    OWContent *lastContent = nil;
    id <OWTarget> targetSnapshot = nil;
    OWTargetContentDisposition disposition;

    [OWPipeline lock];
    NS_DURING {
#ifdef DEBUG_kc0
	if (state != OWPipelineBuilding)
	    flags.debug = YES;
#endif

        if (OWPipelineDebug || flags.debug)
            NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));

        OBPRECONDITION(continuationEvent != nil && [continuationEvent selector] == _cmd);
        OBPRECONDITION([followedArcs count] <= [followedContent count]);
        OBPRECONDITION(state == OWPipelineBuilding);
        OBPRECONDITION(cacheSearch == nil);

        continuationEvent = nil;

        targetSnapshot = [self target];
        lastContent = [followedContent lastObject];

        if (OWPipelineDebug || flags.debug) {
            NSLog(@"%@ targetSnapshot=%@ state=%d", OBShortObjectDescription(self), OBShortObjectDescription(targetSnapshot), state);
            NSLog(@"%@ content=%@", OBShortObjectDescription(self), [followedContent description]);
            NSLog(@"%@ acceptables=%@", OBShortObjectDescription(self), [targetAcceptableContentTypes description]);
        }
    } NS_HANDLER {
        [OWPipeline unlock];
#ifdef DEBUG_toon
        NSLog(@"Exception raised during -_weAreAtAnImpasse %@", localException);
#endif        
        [localException raise];
    } NS_ENDHANDLER;
    [OWPipeline unlock];

    OBASSERT(![OWPipeline isLockHeldByCallingThread]);
    if (targetSnapshot == nil) {
        disposition = OWTargetContentDisposition_ContentRejectedCancelPipeline;
    } else {
        NS_DURING {
#ifndef DEBUG_kc
            if (OWPipelineDebug || flags.debug)
#endif
                NSLog(@"%@: delivering content (OWContentOfferFailure) to %@", [self shortDescription], [(NSObject *)targetSnapshot shortDescription]);
            disposition = [targetSnapshot pipeline:self hasContent:lastContent flags:OWContentOfferFailure];
        } NS_HANDLER {
            disposition = OWTargetContentDisposition_ContentRejectedCancelPipeline;
            NSLog(@"Exception \"%@\" raised while failing to deliver content to target %@: %@",
                  [localException name], [(NSObject *)targetSnapshot shortDescription], [localException description]);
        } NS_ENDHANDLER;
    }

    switch (disposition) {
        case OWTargetContentDisposition_ContentUpdatedOrTargetChanged:
            [self startProcessingContent];
            break;
        case OWTargetContentDisposition_ContentRejectedContinueProcessing:
            /* TODO: Generate an error content in this situation? there really isn't much more we can do */
            /* FALLTHROUGH for now */
        case OWTargetContentDisposition_ContentRejectedAbortAndSavePipeline:
            [self abortTask];
            break;
        case OWTargetContentDisposition_ContentRejectedCancelPipeline:
            [self invalidate];
            break;
        case OWTargetContentDisposition_ContentAccepted:
            [OWPipeline lock];
            NS_DURING {
                if (state == OWPipelineBuilding) {
                    OWPipelineSetState(self, OWPipelineRunning);
                    [[self class] _target:targetSnapshot acceptedContentFromPipeline:self];
                }
                [self _deactivateIfPipelineHasNoProcessors];
            } NS_HANDLER {
                [OWPipeline unlock];
#ifdef DEBUG_toon
                NSLog(@"Exception raised during -_weAreAtAnImpasse(2) %@", localException);
#endif      
                [localException raise];
            } NS_ENDHANDLER;
            [OWPipeline unlock];
            break;
    }

    [self updateStatusOnTarget];
    [[self class] activeTreeHasChanged];
    [self treeActiveStatusMayHaveChanged];
}

- (void)_startProcessingContentInThread;
{
    [self _startProcessingContentWithCloneParent:nil insertBefore:NO];
}

- (OFInvocation *)_processContent
{
    OBPRECONDITION(state == OWPipelineBuilding);
    OBPRECONDITION(continuationEvent == nil);
    
    if (state != OWPipelineBuilding) {
#ifdef DEBUG_kc
	NSLog(@"-[%@ %@]: state=%d", OBShortObjectDescription(self), NSStringFromSelector(_cmd), state);
	flags.debug = YES;
#endif
	return nil;
    }

    ASSERT_OWPipeline_Locked();

    [self estimateCostFromType:[OWContentType wildcardContentType]];
    [self estimateCostFromType:[OWContentType sourceContentType]];

    while ([self target] != nil) {
        OWContent *interimContent;
        id <OWCacheArc> possibleArc;
        OWCacheArcTraversalResult progress;

        OBASSERT(!flags.traversingLastArc);
        OBASSERT(continuationEvent == nil);

        // This assertion verifies that we haven't followed an arc from our most recent content yet
        OBASSERT([followedArcs count]+1 == [followedContent count]);

        // This shouldn't ever happen (any more)
        if ([followedContent count] == 0) {
            NSLog(@"-[%@ %@]: followedContent is empty", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
            continuationEvent = [[OFInvocation alloc] initForObject:self selector:@selector(_weAreAtAnImpasse)];
            return continuationEvent;
        }

        // If we don't have a cacheSearch going on already, create a search state from our mostRecentContent.
        if (cacheSearch == nil) {
            OWContent *mostRecentContent = [followedContent lastObject];
            float deliveryCost;

            // If the content is expensive to examine, do so outside the cache lock
            if (![mostRecentContent checkForAvailability:NO]) {
                continuationEvent = [[OFInvocation alloc] initForObject:self selector:@selector(_blockThenProcess)];
                return continuationEvent;
            }

            // Consider the possibility of offering to the target instead of processing it more
            if (mostRecentContent == mostRecentlyOffered) {
                // no, don't offer it more than once
                deliveryCost = COST_OF_REJECTION;
            } else {
                NSNumber *acceptability = [self _deliveryCostOfContent:mostRecentContent];
                if (acceptability != nil)
                    deliveryCost = [acceptability floatValue];
                else
                    deliveryCost = COST_OF_REJECTION;
            }

            if (deliveryCost <= 0) {
                // We have what you want, what you really, really want
                continuationEvent = [[OFInvocation alloc] initForObject:self selector:@selector(_offerContentToTarget)];
                return continuationEvent;
            } 

            // Create a new cache search
            cacheSearch = [[OWCacheSearch alloc] initForRelation:OWCacheArcSubject toEntry:mostRecentContent inPipeline:self];
            [cacheSearch addCaches:[caches caches]];
            [cacheSearch addFreeArcs:givenArcs];
            [cacheSearch setRejectedArcs:rejectedArcs];
            [cacheSearch setCostLimit:deliveryCost];  // don't consider arcs more expensive than delivery
#ifdef DEBUG_kc
            if (flags.debug)
                NSLog(@"-[%@ %@]: %@ searching for an arc from content type %@, cacheSearch=%@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), [[self lastAddress] addressString], [[mostRecentContent contentType] contentTypeString], cacheSearch);
#endif
        }

        // Get the next arc matching the search parameters.
        OBASSERT([cacheSearch source] == [followedContent lastObject]);
        possibleArc = [cacheSearch nextArcWithoutBlocking];

        // If the cache search might block before giving us the next arc, then do that outside the pipeline lock.
        if (possibleArc == nil && ![cacheSearch endOfData]) {
            continuationEvent = [[OFInvocation alloc] initForObject:self selector:@selector(_blockThenProcess)];
            return continuationEvent;
        }
        
        if (possibleArc == nil) {
            /* We ran out of things to try. Darn. */
            NSNumber *acceptability;
            OWContent *mostRecentContent = [followedContent lastObject];

            OBASSERT(mostRecentContent == [cacheSearch source]);
            acceptability = [self _deliveryCostOfContent:mostRecentContent];
            if (acceptability != nil && mostRecentContent != mostRecentlyOffered) {
                /* Our cache search stopped because it would be cheaper to deliver what we have. */
                /* (Our content might still return ContentRejectedContinueProcessing, in which case we'll start up another cache search for this content.) */
                continuationEvent = [[OFInvocation alloc] initForObject:self selector:@selector(_offerContentToTarget)];
            } else {
                /* Our cache search stopped because we ran out of things to try. */
#ifdef DEBUG_kc
                NSLog(@"-[%@ %@]: %@ failed to traverse any arc from content type %@ (state=%d), cacheSearch=%@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), [[self lastAddress] addressString], [[mostRecentContent contentType] contentTypeString], state, OBShortObjectDescription(cacheSearch));
#endif
                /* TODO: Should we back up and try again with earlier entries? (probably not) */
                continuationEvent = [[OFInvocation alloc] initForObject:self selector:@selector(_weAreAtAnImpasse)];
            }

            cacheSearch = nil;

            return continuationEvent;
        }

        // Try to traverse the arc.
        progress = [self _traverseArcFromSearch:possibleArc];
        switch (progress) {
            default:
                OBASSERT_NOT_REACHED("Invalid result from -_traverseArcFromEntry:");
                /* FALL THROUGH */
            case OWCacheArcTraversal_Failed:
                /* This arc didn't work for us, but our cacheSearch might still have some more possibilities. */
                break;
            case OWCacheArcTraversal_HaveResult:
                /* We got something from this traversal immediately. Go ahead and process it. */
                cacheSearch = nil; /* we're done with this search */
                break;
            case OWCacheArcTraversal_WillNotify:
                /* The arc didn't have anything immediately, but it will call us back. */
                /* If there's interim content, might as well display it while we wait */
                interimContent = [[followedContent lastObject] lastObjectForKey:OWContentInterimContentMetadataKey];
                if (interimContent != nil) {
                    [self _spawnCloneThroughArc:[followedArcs count] - 1 addingContent:interimContent beforeSelf:YES];
                }
                /* Wait for _arcProducedContent: to be invoked */
                return nil;
        }
    }

    [self _cleanupPipelineIfDead];
    return nil;
}

- (NSNumber *)_deliveryCostOfContent:(OWContent *)someContent
{
    OWContentType *offeringType;
    NSNumber *acceptability, *wildcardAcceptability;

    ASSERT_OWPipeline_Locked();

    offeringType = [someContent contentType];
    if (offeringType == nil)
        acceptability = nil;
    else
        acceptability = [targetAcceptableContentTypes objectForKey:offeringType];

#ifdef DEBUG_kc0
    NSLog(@"%@ %s%@ (original) = %@", [self shortDescription], _cmd, [[someContent contentType] contentTypeString], acceptability);
#endif

    if ([someContent isSource]) {
        NSNumber *sourceAcceptability = [targetAcceptableContentTypes objectForKey:[OWContentType sourceContentType]];
        if (sourceAcceptability && (acceptability == nil || [acceptability floatValue] > [sourceAcceptability floatValue]))
            acceptability = sourceAcceptability;
    }

#ifdef DEBUG_kc0
    NSLog(@"%@ %s%@ (source) = %@", [self shortDescription], _cmd, [[someContent contentType] contentTypeString], acceptability);
#endif

    wildcardAcceptability = [targetAcceptableContentTypes objectForKey:[OWContentType wildcardContentType]];
    if (wildcardAcceptability && (acceptability == nil || [acceptability floatValue] > [wildcardAcceptability floatValue]))
        acceptability = wildcardAcceptability;

#ifdef DEBUG_kc0
    NSLog(@"%@ %s%@ (wildcard) = %@", [self shortDescription], _cmd, [[someContent contentType] contentTypeString], acceptability);
#endif

    return acceptability;
}

- (void)_offerContentToTarget;
{
    NSNumber *offerAcceptability;
    OWTargetContentOffer offerType;
    OWContent *someContent;
    OWTargetContentDisposition disposition;
    id <OWTarget> targetSnapshot;

    [OWPipeline lock];
    NS_DURING {

        if (OWPipelineDebug || flags.debug)
            NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));

        OBPRECONDITION(continuationEvent != nil && [continuationEvent selector] == _cmd);
        OBPRECONDITION([followedArcs count] < [followedContent count]);
        OBPRECONDITION(state == OWPipelineBuilding || state == OWPipelineAborting || state == OWPipelineInvalidating);

        someContent = [followedContent lastObject];
        OBASSERT(someContent != mostRecentlyOffered);
        offerAcceptability = [self _deliveryCostOfContent:someContent];
        mostRecentlyOffered = someContent;

        if (firstErrorContent != NSNotFound) {
            OBASSERT(firstErrorContent < [followedContent count]);
            offerType = OWContentOfferError;
        } else if (offerAcceptability == nil)
            offerType = OWContentOfferFailure;
        else if ([offerAcceptability floatValue] > 0)
            offerType = OWContentOfferAlternate;
        else
            offerType = OWContentOfferDesired;

        targetSnapshot = [self target];

        if (targetSnapshot == nil)
            disposition = OWTargetContentDisposition_ContentRejectedCancelPipeline;
        else if (offerType == OWContentOfferFailure)
            disposition = OWTargetContentDisposition_ContentRejectedContinueProcessing;
        else {
            [OWPipeline unlock];
            NS_DURING {
                if (OWPipelineDebug || flags.debug)
                    NSLog(@"%@: delivering %@ content to %@", [self shortDescription], [[self class] stringForTargetContentOffer:offerType], [(NSObject *)targetSnapshot shortDescription]);
                disposition = [targetSnapshot pipeline:self hasContent:someContent flags:offerType];
            } NS_HANDLER {
                disposition = OWTargetContentDisposition_ContentRejectedCancelPipeline;
                NSLog(@"Exception \"%@\" raised while delivering %@ content %@ to target %@: %@",
                      [localException name], [[self class] stringForTargetContentOffer:offerType], [someContent shortDescription], [(NSObject *)targetSnapshot shortDescription], [localException description]);
            } NS_ENDHANDLER;
            [OWPipeline lock];
        }

        OBASSERT(continuationEvent != nil && [continuationEvent selector] == _cmd);
        continuationEvent = nil;

        switch (state) {
            case OWPipelineAborting:
            case OWPipelineInvalidating:
                [self _deactivateIfPipelineHasNoProcessors];
                [OWPipeline unlock];
                NS_VOIDRETURN;
            case OWPipelineDead:
                [OWPipeline unlock];
                NS_VOIDRETURN;
            default:
                break;
        }

        if (OWPipelineDebug || flags.debug)
            NSLog(@"%@: contentDisposition=%d", [self shortDescription], disposition);
        switch (disposition) {
            case OWTargetContentDisposition_ContentAccepted:
                [[self class] _target:targetSnapshot acceptedContentFromPipeline:self];
                OWPipelineSetState(self, OWPipelineRunning);
                break;
            case OWTargetContentDisposition_ContentRejectedAbortAndSavePipeline:
                [self abortTask];
                OBPOSTCONDITION(state == OWPipelineAborting || state == OWPipelineDead);
                break;
            case OWTargetContentDisposition_ContentRejectedCancelPipeline:
            default:
                [self invalidate];
                OBPOSTCONDITION(state == OWPipelineInvalidating || state == OWPipelineDead);
                break;
            case OWTargetContentDisposition_ContentUpdatedOrTargetChanged:
                // The content or target has changed, do more processing
                // FALLTHROUGH
            case OWTargetContentDisposition_ContentRejectedContinueProcessing:
                // Do more processing
                [self _processContent];
                if (continuationEvent)
                    [[OWProcessor processorQueue] addQueueEntry:continuationEvent];
                break;
        }

        [self updateStatusOnTarget];
        [self _deactivateIfPipelineHasNoProcessors];

    } NS_HANDLER {
        [OWPipeline unlock];
#ifdef DEBUG
        NSLog(@"Exception raised during _offerContentToTarget %@", localException);
#endif        
        [localException raise];
    } NS_ENDHANDLER;
    [OWPipeline unlock];
    [[self class] activeTreeHasChanged];
}

- (void)_blockThenProcess;
{
    OBASSERT(![OWPipeline isLockHeldByCallingThread]);

    NS_DURING {
        OFForEachInArray(followedContent, OWContent *, aContent, [aContent checkForAvailability:YES]);
    } NS_HANDLER {
#warning TODO [wiml nov2003] - We have no good way to pass along this error to the target.
        NSLog(@"%@ %@", OBShortObjectDescription(self), localException);
        [self _weAreAtAnImpasse];
        return;
    } NS_ENDHANDLER;

    if (cacheSearch != nil)
        [cacheSearch waitForAvailability];
    
    [OWPipeline lock];
    NS_DURING {
        OBASSERT(continuationEvent == nil || [continuationEvent selector] == _cmd);
        continuationEvent = nil;
        
        if (state == OWPipelineBuilding)
            [self _processContent];

        if (continuationEvent != nil)
            [[OWProcessor processorQueue] addQueueEntry:continuationEvent];
        else
            [self _deactivateIfPipelineHasNoProcessors];
    } NS_HANDLER {
        [OWPipeline unlock];
#ifdef DEBUG_toon
        NSLog(@"Exception raised during _blockThenProcess %@", localException);
#endif        
        [localException raise];
    } NS_ENDHANDLER;
    [OWPipeline unlock];
    [self treeActiveStatusMayHaveChanged];
}

- (void)_computeAcceptableContentTypes
{
    id target = [self target];
    OWContentType *mainContentType = [target targetContentType];

    targetAcceptableContentTypes = nil;
    [costEstimates removeAllObjects];
    
    if ([target respondsToSelector:@selector(targetAlternateContentTypes)]) {
        NSDictionary *otherContentTypes = [(id <OWOptionalTarget>)target targetAlternateContentTypes];
        NSMutableDictionary *workingDict;

        workingDict = [otherContentTypes mutableCopy];
        [workingDict setObject:OWZeroNumber forKey:mainContentType];
        targetAcceptableContentTypes = [workingDict copy];
    } else {
        targetAcceptableContentTypes = [[NSDictionary alloc] initWithObjectsAndKeys:OWZeroNumber, mainContentType, nil];
    }

    [self estimateCostFromType:[OWContentType sourceContentType]];
}

- (id <OWCacheArc>)_mostRecentArcProducingSource;
{
    [contextLock lock];
    id <OWCacheArc> sourceArc = mostRecentArcProducingSource;
    [contextLock unlock];
    
    return sourceArc;
}

- (void)_sendPipelineFetchNotificationForArc:(id <OWCacheArc>)productiveArc;
{
    NSNotification *note;
    NSDictionary *info;
    OWAddress *subjectAddress;

    /* [Wiml] It would be reasonable to send notifications for any arc whose subject is an address *or* which has produced source content. At the moment, though, we only handle the first case. I'm not sure that the second one ever occurs with our current set of processors, and our only observer for this notification (OWBookmark) probably wouldn't care. */
    if (![[productiveArc subject] isAddress])
        return;

    subjectAddress = [[productiveArc subject] address];
    info = [NSDictionary dictionaryWithObjectsAndKeys:

        // subject/source address of the result content. currently this is the same as the subject/source of this arc.
        subjectAddress,
        OWPipelineFetchLastAddressKey,
        
        // the arc that produced the content
        productiveArc,
        OWPipelineFetchNewArcKey,
        
        // the arc's result. not strictly necessary, but retrieving it here can avoid having to lock the pipeline later.
        [productiveArc object],
        OWPipelineFetchNewContentKey,
        
        nil];
        
    note = [NSNotification notificationWithName:[subjectAddress cacheKey] object:self userInfo:info];
    // Send notifications in the main thread, since notification centers aren't thread-safe (they send messages to unretained observers).
    [fetchedContentNotificationCenter queueSelectorOnce:@selector(postNotification:) withObject:note];
}

- (void)_notifyDeallocationObservers;
{
    [contextLock lock];
    NSArray <OFWeakReference *> *deallocationObserversSnapshot = [[NSArray alloc] initWithArray:_deallocationObserverReferences];
    [contextLock unlock];

    for (OFWeakReference *deallocationObserverReference in deallocationObserversSnapshot) {
        [deallocationObserverReference.object pipelineWillDeallocate:self];
    }
    
#ifdef DEBUG_kc
    [contextLock lock];
    OBPOSTCONDITION(_deallocationObserverReferences.count == 0);
    [contextLock unlock];
#endif
}

// Target stuff

- (void)_notifyTargetOfTreeActivation;
{
    @autoreleasepool {
        [self _notifyTargetOfTreeActivation:[self target]];
    }
}

- (void)_notifyTargetOfTreeDeactivation;
{
    @autoreleasepool {
        [self _notifyTargetOfTreeDeactivation:[self target]];
    }
}

- (void)_notifyTargetOfTreeActivation:(id <OWTarget>)aTarget;
{
    NSNotification *activationNotification;

    if (OWPipelineDebug || flags.debug)
        NSLog(@"-[%@ %@%@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd), OBShortObjectDescription(aTarget));

    [self _updateStatusOnTarget:aTarget];

    activationNotification = [NSNotification notificationWithName:OWPipelineTreeActivationNotificationName object:self];
    if (targetRespondsTo.pipelineTreeDidActivate)
        [(id <OWOptionalTarget>)aTarget pipelineTreeDidActivate:activationNotification];
        
#warning This is never observed!
//    [[NSNotificationCenter defaultCenter] postNotification:activationNotification];
}

- (void)_notifyTargetOfTreeDeactivation:(id <OWTarget>)aTarget;
{
    NSNotification *deactivationNote;

    if (OWPipelineDebug || flags.debug)
        NSLog(@"-[%@ %@%@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd), OBShortObjectDescription(aTarget));

    [self _updateStatusOnTarget:aTarget];

    deactivationNote = [NSNotification notificationWithName:OWPipelineTreeDeactivationNotificationName object:self];
    if (targetRespondsTo.pipelineTreeDidDeactivate)
        [(id <OWOptionalTarget>)aTarget pipelineTreeDidDeactivate:deactivationNote];

#warning This is never observed!
//    [[NSNotificationCenter defaultCenter] postNotification:deactivationNote];
}

- (void)_updateStatusOnTarget:(id <OWTarget>)aTarget;
{
    id <OWTarget, OWOptionalTarget, NSObject> optionalTarget = (id)aTarget;
    id  target = [self target];
    
    if (optionalTarget == (id)target && targetRespondsTo.updateStatusForPipeline)
        [optionalTarget updateStatusForPipeline:self];
    else if (optionalTarget != (id)target &&
             [optionalTarget respondsToSelector:@selector(updateStatusForPipeline:)])
        [optionalTarget updateStatusForPipeline:[[self class] lastActivePipelineForTarget:optionalTarget]];
}

// NB The string (compositeTypeString) built by this method should be in the user's current language.
- (void)_rebuildCompositeTypeString;
{
    NSString *contentTypeString, *newCompositeTypeString;

    contentTypeString = [[self contentInfo] typeString];
    if (!contentTypeString) {
        id <OWTarget, OWOptionalTarget, NSObject> targetSnapshot;
    
        targetSnapshot = (id)[self target];
        if (targetRespondsTo.expectedContentDescriptionString)
            contentTypeString = [targetSnapshot expectedContentDescriptionString];

        if (contentTypeString == nil) {
            OWAddress *lastAddress;

            lastAddress = [self lastAddress];
            if (lastAddress != nil)
                contentTypeString = [[lastAddress probableContentTypeBasedOnPath] readableString];

            if (contentTypeString == nil)
                contentTypeString = @"www/unknown";
        }
    }

    if (targetTypeFormatString)
        newCompositeTypeString = [[NSString alloc] initWithFormat:targetTypeFormatString, contentTypeString];
    else
        newCompositeTypeString = contentTypeString;

    OFSimpleLock(&displayablesSimpleLock); {
        compositeTypeString = newCompositeTypeString;
    } OFSimpleUnlock(&displayablesSimpleLock);
}

- (OWHeaderDictionary *)_headerDictionaryWaitForCompleteHeaders:(BOOL)shouldWaitForCompleteHeaders;
{
#warning do this a better way
    // Probably we want to have a method like -lastHeaderValue(s)ForName:... content:... which scans backwards through the followedContent?
    
    OWHeaderDictionary *result = [[OWHeaderDictionary alloc] init];
    NSArray *contentCopy = nil;
    
    [OWPipeline lock];
    NS_DURING { // can't imagine anything going wrong here, but let's be thorough...
        contentCopy = [NSArray arrayWithArray:followedContent];
    } NS_HANDLER {
        [OWPipeline unlock];
#ifdef DEBUG_toon
        NSLog(@"Exception raised during -headerDictionary %@", localException);
#endif        
        [localException raise];
    } NS_ENDHANDLER;
    [OWPipeline unlock];
    
    OFForEachInArray(contentCopy, OWContent *, aContent,
                     {
                         if (shouldWaitForCompleteHeaders)
                             [aContent waitForEndOfHeaders];
                         [result addStringsFromDictionary:[aContent headers]];
                     });
    
    return result;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];

    if ([self target])
        [debugDictionary setObject:[(NSObject *)[self target] shortDescription] forKey:@"target"];
//    if (_lastContent)
//        [debugDictionary setObject:[(NSObject *)_lastContent shortDescription] forKey:@"lastContent"];
//    if (processorArray)
//        [debugDictionary setObject:processorArray forKey:@"processorArray"];
    if (context)
        [debugDictionary setObject:context forKey:@"context"];

    return debugDictionary;
}

@end

NSString * const OWPipelineHasErrorNotificationName = @"OWPipelineHasError";
NSString * const OWPipelineHasErrorNotificationPipelineKey = @"pipeline";
NSString * const OWPipelineHasErrorNotificationProcessorKey = @"processor";
NSString * const OWPipelineHasErrorNotificationErrorNameKey = @"errorName";
NSString * const OWPipelineHasErrorNotificationErrorReasonKey = @"errorReason";
NSString * const OWPipelineTreeActivationNotificationName = @"OWPipelineTreeActivation";
NSString * const OWPipelineTreeDeactivationNotificationName = @"OWPipelineTreeDeactivation";
NSString * const OWPipelineTreePeriodicUpdateNotificationName = @"OWPipelineTreePeriodicUpdateNotificationName";
NSString * const OWPipelineHasBuddedNotificationName = @"OWPipelineHasBudded";
NSString * const OWPipelineChildPipelineKey = @"child";
NSString * const OWPipelineFetchLastAddressKey = @"address";
NSString * const OWPipelineFetchNewContentKey = @"content";
NSString * const OWPipelineFetchNewArcKey = @"arc";
