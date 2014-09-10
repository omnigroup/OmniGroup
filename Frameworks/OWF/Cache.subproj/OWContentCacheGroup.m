// Copyright 2003-2005, 2010-2011, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWContentCacheGroup.h"

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "OWContent.h"
#import "OWProcessorCache.h"
#import "OWMemoryCache.h"
#import "OWFilteredAddressCache.h"

RCS_ID("$Id$");

@implementation OWContentCacheGroup

static OWContentCacheGroup *defaultCacheGroup = nil;
static OFScheduler *cacheActivityScheduler = nil;

static CFMutableArrayRef observers = NULL;
static OFSimpleLockType observersLock;

+ (void)initialize;
{
    OBINITIALIZE;

    // Allocate the observers array
    observers = CFArrayCreateMutable(NULL, 0, &OFNonOwnedPointerArrayCallbacks);
    OFSimpleLockInit(&observersLock);

    // Set up the enumeration for the cache validity preference before +cacheValidationPreference is called
    {
        OFEnumNameTable *validationBehaviors;

        validationBehaviors = [[OFEnumNameTable alloc] initWithDefaultEnumValue:OWCacheValidation_DefaultBehavior];
        [validationBehaviors setName:@"always" forEnumValue:OWCacheValidation_Always];
        [validationBehaviors setName:@"rarely" forEnumValue:OWCacheValidation_Infrequent];
        [validationBehaviors setName:@"unless-explicit-control" forEnumValue:OWCacheValidation_UnlessCacheControl];
        
        // This makes sure the preference is associated with the given enumeration
        [OFPreference preferenceForKey:OWCacheValidationBehaviorPreferenceKey enumeration:validationBehaviors];

        [validationBehaviors release];
    }

    if (cacheActivityScheduler == nil) {
        OFDedicatedThreadScheduler *scheduler;
        
        scheduler = [[OFDedicatedThreadScheduler alloc] init];
        cacheActivityScheduler = scheduler;
        [scheduler setInvokesEventsInMainThread:NO];
        [scheduler runScheduleForeverInNewThread];
    }

    if (defaultCacheGroup == nil) {
        OWProcessorCache *procCache;
        OWMemoryCache *memoryCache;
        OWFilteredAddressCache *filterCache;

        defaultCacheGroup = [[OWContentCacheGroup alloc] init];

#warning this sucks. kill me.

        procCache = [[OWProcessorCache alloc] init];
        [defaultCacheGroup addCache:procCache atStart:YES];
        [procCache release];

        memoryCache = [[OWMemoryCache alloc] init];
        [memoryCache setFlush:YES];
        [defaultCacheGroup addCache:memoryCache atStart:NO];
        [defaultCacheGroup setResultCache:memoryCache];
        [memoryCache release];

        filterCache = [[OWFilteredAddressCache alloc] init];
        [defaultCacheGroup addCache:filterCache atStart:YES];
        [filterCache release];
    }

}

+ (OWContentCacheGroup *)defaultCacheGroup;
{
    return defaultCacheGroup;
}

+ (OFScheduler *)scheduler
{
    return cacheActivityScheduler;
}

+ (OFPreference *)cacheValidationPreference;
{
    return [OFPreference preferenceForKey:OWCacheValidationBehaviorPreferenceKey];
}

+ (void)addObserver:(id)anObject;
{
    OFSimpleLock(&observersLock);
    CFArrayAppendValue(observers, anObject);
    OFSimpleUnlock(&observersLock);
}

+ (void)removeObserver:(id)anObject;
{
    OFSimpleLock(&observersLock);
    CFIndex where = CFArrayGetLastIndexOfValue(observers, (CFRange){0, CFArrayGetCount(observers)}, anObject);
    if (where != kCFNotFound)
        CFArrayRemoveValueAtIndex(observers, where);
    OFSimpleUnlock(&observersLock);
}

+ (void)invalidateResource:(OWURL *)resource beforeDate:(NSDate *)invalidationDate;
{
    OFSimpleLock(&observersLock);
    NSArray *observersSnapshot = [[NSArray alloc] initWithArray:(NSArray *)observers];
    OFSimpleUnlock(&observersLock);
    [observersSnapshot makeObjectsPerformSelector:_cmd withObject:resource withObject:invalidationDate];
    [observersSnapshot release];
}

// Init and dealloc

- init;
{
    if (!(self = [super init]))
        return nil;

    caches = [[NSMutableArray alloc] init];

    return self;
}

- (void)dealloc;
{
    [caches release];
    [resultCache release];
    [super dealloc];
}

// API

- (void)addCache:(id <OWCacheArcProvider>)aCache atStart:(BOOL)before;
{
    if (aCache == nil)
        return;
    
    if (before)
        [caches insertObject:aCache atIndex:0];
    else
        [caches addObject:aCache];
}
    
- (void)removeCache:(id <OWCacheArcProvider>)aCache;
{
    [caches removeObjectIdenticalTo:aCache];
    if (aCache == resultCache) {
        [resultCache release];
        resultCache = nil;
    }
}

- (void)setResultCache:(id <OWCacheArcProvider, OWCacheContentProvider>)aCache
{
    OBASSERT([caches containsObjectIdenticalTo:aCache]);
    OBASSERT([aCache conformsToProtocol:@protocol(OWCacheContentProvider)]);
    OBPRECONDITION(resultCache == nil);

    [aCache retain];
    resultCache = aCache;
}

- (NSArray *)caches;
{
    return [NSArray arrayWithArray:caches];
}

- (id <OWCacheArcProvider, OWCacheContentProvider>)resultCache;
{
    return resultCache;
}

@end

NSString *OWContentCacheFlushNotification = @"OWFlushCachesNotification";

