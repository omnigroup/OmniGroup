// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWContentCacheGroup.h>

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContent.h>
#import "OWProcessorCache.h"
#import <OWF/OWMemoryCache.h>
#import <OWF/OWFilteredAddressCache.h>

RCS_ID("$Id$");

@implementation OWContentCacheGroup

static OWContentCacheGroup *defaultCacheGroup = nil;
static OFScheduler *cacheActivityScheduler = nil;

static CFMutableArrayRef observers = NULL;
static os_unfair_lock observersLock = OS_UNFAIR_LOCK_INIT;

+ (void)initialize;
{
    OBINITIALIZE;

    // Allocate the observers array
    observers = CFArrayCreateMutable(NULL, 0, &OFNonOwnedPointerArrayCallbacks);

    // Set up the enumeration for the cache validity preference before +cacheValidationPreference is called
    {
        OFEnumNameTable *validationBehaviors = [[OFEnumNameTable alloc] initWithDefaultEnumValue:OWCacheValidation_DefaultBehavior];
        [validationBehaviors setName:@"always" forEnumValue:OWCacheValidation_Always];
        [validationBehaviors setName:@"rarely" forEnumValue:OWCacheValidation_Infrequent];
        [validationBehaviors setName:@"unless-explicit-control" forEnumValue:OWCacheValidation_UnlessCacheControl];
        
        // This makes sure the preference is associated with the given enumeration
        [OFPreference preferenceForKey:OWCacheValidationBehaviorPreferenceKey enumeration:validationBehaviors];
    }

    if (cacheActivityScheduler == nil) {
        OFDedicatedThreadScheduler *scheduler = [[OFDedicatedThreadScheduler alloc] init];
        cacheActivityScheduler = scheduler;
        [scheduler setInvokesEventsInMainThread:NO];
        [scheduler runScheduleForeverInNewThread];
    }

    if (defaultCacheGroup == nil) {
        defaultCacheGroup = [[OWContentCacheGroup alloc] init];

#warning this sucks. kill me.

        OWProcessorCache *procCache = [[OWProcessorCache alloc] init];
        [defaultCacheGroup addCache:procCache atStart:YES];

        OWMemoryCache *memoryCache = [[OWMemoryCache alloc] init];
        [memoryCache setFlush:YES];
        [defaultCacheGroup addCache:memoryCache atStart:NO];
        [defaultCacheGroup setResultCache:memoryCache];

        OWFilteredAddressCache *filterCache = [[OWFilteredAddressCache alloc] init];
        [defaultCacheGroup addCache:filterCache atStart:YES];
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

+ (void)addContentCacheObserver:(id)anObject;
{
    os_unfair_lock_lock(&observersLock);
    CFArrayAppendValue(observers, (__bridge const void *)(anObject));
    os_unfair_lock_unlock(&observersLock);
}

+ (void)removeContentCacheObserver:(id)anObject;
{
    os_unfair_lock_lock(&observersLock);
    CFIndex where = CFArrayGetLastIndexOfValue(observers, (CFRange){0, CFArrayGetCount(observers)}, (__bridge const void *)(anObject));
    if (where != kCFNotFound)
        CFArrayRemoveValueAtIndex(observers, where);
    os_unfair_lock_unlock(&observersLock);
}

+ (void)invalidateResource:(OWURL *)resource beforeDate:(NSDate *)invalidationDate;
{
    os_unfair_lock_lock(&observersLock);
    NSArray *observersSnapshot = [[NSArray alloc] initWithArray:(__bridge NSArray *)observers];
    os_unfair_lock_unlock(&observersLock);
    [observersSnapshot makeObjectsPerformSelector:_cmd withObject:resource withObject:invalidationDate];
}

// Init and dealloc

- init;
{
    if (!(self = [super init]))
        return nil;

    caches = [[NSMutableArray alloc] init];

    return self;
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
        resultCache = nil;
    }
}

- (void)setResultCache:(id <OWCacheArcProvider, OWCacheContentProvider>)aCache
{
    OBASSERT([caches containsObjectIdenticalTo:aCache]);
    OBASSERT([aCache conformsToProtocol:@protocol(OWCacheContentProvider)]);
    OBPRECONDITION(resultCache == nil);

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

NSString * const OWContentCacheFlushNotification = @"OWFlushCachesNotification";

