// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class /* Foundation */ NSCountedSet, NSLock, NSMutableArray, NSMutableSet;
@class /* OmniFoundation */ OFDelayedEvent;
@class /* OmniSQLite */ OSLDatabaseController;

#import <OmniFoundation/OFSimpleLock.h>
#import <OWF/OWContentCacheProtocols.h>

@interface OWDiskCache : OFObject <OWCacheArcProvider, OWCacheContentProvider>
{
    NSString *bundlePath;
    
    OSLDatabaseController *databaseController; // The database on disk
    NSMutableArray *recentlyUsedContent; // Recently-referenced content
    NSLock *dbLock; // Protects access to db and recentlyUsedContent
    NSMutableSet *arcsToRemove; // Arcs we have deleted (but haven't actually removed from the db yet)
    NSMutableSet *contentToGC;  // Content which might no longer have a referring arc
    OFDelayedEvent *preenEvent; // Deferred clean up event 

    NSCountedSet *retainedHandles; // Handles of content which is in use
    OFSimpleLockType retainedHandlesLock; // Protects access to retainedHandles
}

+ (OWDiskCache *)createCacheAtPath:(NSString *)bundlePath;
+ (OWDiskCache *)openCacheAtPath:(NSString *)bundlePath;

- (void)close;
- (void)removeEntriesDominatedByArc:(OWStaticArc *)newArc;

@end
