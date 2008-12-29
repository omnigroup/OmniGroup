// Copyright 2003-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Cache.subproj/OWMemoryCache.h 79093 2006-09-08 00:05:45Z kc $

#import <OmniFoundation/OFObject.h>

@class /* Foundation */ NSMutableDictionary, NSMutableSet, NSLock;
@class /* OmniFoundation */ OFMultiValueDictionary, OFScheduledEvent;
@class /* OWF */ OWStaticArc;

#import "OWContentCacheProtocols.h" // For OWCacheArcProvider and OWCacheContentProvider

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
