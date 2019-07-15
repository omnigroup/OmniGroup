// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <Foundation/NSArray.h>
#import <OWF/OWContentCacheProtocols.h>

@class OFPreference, OFScheduler;

@interface OWContentCacheGroup : NSObject
{
    NSMutableArray *caches;
    id <OWCacheArcProvider, OWCacheContentProvider> resultCache;
}

// API

+ (OWContentCacheGroup *)defaultCacheGroup;
+ (OFScheduler *)scheduler;
+ (OFPreference *)cacheValidationPreference;

+ (void)addContentCacheObserver:(id)anObject;
+ (void)removeContentCacheObserver:(id)anObject;
+ (void)invalidateResource:(OWURL *)resource beforeDate:(NSDate *)invalidationDate;

- (void)addCache:(id <OWCacheArcProvider>)aCache atStart:(BOOL)before;
- (void)removeCache:(id <OWCacheArcProvider>)aCache;
- (void)setResultCache:(id <OWCacheArcProvider, OWCacheContentProvider>)aCache;

- (NSArray *)caches;
- (id <OWCacheArcProvider, OWCacheContentProvider>)resultCache;

@end

@class OWAddress;

