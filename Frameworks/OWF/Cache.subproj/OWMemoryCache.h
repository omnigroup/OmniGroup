// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class /* Foundation */ NSMutableDictionary, NSMutableSet, NSLock;
@class /* OmniFoundation */ OFMultiValueDictionary, OFScheduledEvent;
@class /* OWF */ OWStaticArc;

#import <OWF/OWContentCacheProtocols.h> // For OWCacheArcProvider and OWCacheContentProvider

@interface OWMemoryCache : OFObject <OWCacheArcProvider, OWCacheContentProvider>
{
    NSLock *lock;

    // Memory cache is organized by subject.
    NSMutableDictionary *arcsBySubject;
    NSMutableSet *knownOtherContent;
    
    // Cache arcs and content soon get migrated over to the persistent cache (if it exists).
    id <OWCacheArcProvider, OWCacheContentProvider> backingCache;

    // Scheduled cleanup sweep.
    OFScheduledEvent *expireEvent;
}

- (void)setResultCache:(id <OWCacheArcProvider, OWCacheContentProvider>)newBackingCache;
- (id <OWCacheArcProvider>)resultCache;

- (void)setFlush:(BOOL)flushable;

@end
