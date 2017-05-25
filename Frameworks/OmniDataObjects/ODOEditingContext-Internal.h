// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOEditingContext.h>

NS_ASSUME_NONNULL_BEGIN

@interface ODOEditingContext () {
  @private
    ODODatabase *_database;
    NSUndoManager *_undoManager;
    
    NSMutableDictionary *_registeredObjectByID;
    
    CFRunLoopObserverRef _runLoopObserver;
    
    // Two sets of changes.  One for processed changes (notifications have been sent) and one for recent changes.
    NSMutableSet *_processedInsertedObjects;
    NSMutableSet *_processedUpdatedObjects;
    NSMutableSet *_processedDeletedObjects;
    
    NSMutableSet *_recentlyInsertedObjects;
    ODOObject *_nonretainedLastRecentlyInsertedObject;
    NSMutableSet *_recentlyUpdatedObjects;
    NSMutableSet *_recentlyDeletedObjects;
    
    // This value is filled in only for the window of time that we are sending the ODOEditingContextObjectsWillBeDeletedNotification notification.
    NSSet *_objectsForObjectsWillBeDeletedNotification;
    
    NSMutableDictionary *_objectIDToCommittedPropertySnapshot; // ODOObjectID -> NSArray of property values for only those objects that have been edited.  The values in the dictionary are the database committed values.
    NSMutableDictionary *_objectIDToLastProcessedSnapshot; // Like the committed value snapshot, but this has the differences from the last time -processPendingChanges completed.  In particular, this can contain pre-update snapshots for inserted objects, where _objectIDToCommittedPropertySnapshot will never contain snapshots for inserted objects.
    
    BOOL _isSendingWillSave;
    BOOL _isValidatingAndWritingChanges;
    BOOL _inProcessPendingChanges;
    BOOL _isResetting;
    
    BOOL _avoidSettingSaveDates;
    NSDate *_saveDate;
}
@end

@interface ODOEditingContext (Internal)
#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
- (BOOL)_isValidatingAndWritingChanges;
#endif
- (void)_objectWillBeUpdated:(ODOObject *)object;
- (void)_registerObject:(ODOObject *)object;
- (void)_snapshotObjectPropertiesIfNeeded:(ODOObject *)object;
- (nullable NSArray *)_lastProcessedPropertySnapshotForObjectID:(ODOObjectID *)objectID;
- (nullable NSArray *)_committedPropertySnapshotForObjectID:(ODOObjectID *)objectID;

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_isBeingDeleted:(ODOObject *)object;
#endif

- (BOOL)_isSendingObjectsWillBeDeletedNotificationForObject:(ODOObject *)object;

@end

@class NSPredicate;
@class ODOEntity, ODORelationship;

ODOObject * ODOEditingContextLookupObjectOrRegisterFaultForObjectID(ODOEditingContext *self, ODOObjectID *objectID) OB_HIDDEN;

NSMutableSet * ODOEditingContextCreateRecentSet(ODOEditingContext *self) OB_HIDDEN;

void ODOUpdateResultSetForInMemoryChanges(ODOEditingContext *self, NSMutableArray *results, ODOEntity *entity, NSPredicate *predicate) OB_HIDDEN;

void ODOFetchObjectFault(ODOEditingContext *self, ODOObject *object) OB_HIDDEN;
NSMutableSet * ODOFetchSetFault(ODOEditingContext *self, ODOObject *owner, ODORelationship *rel) OB_HIDDEN;

BOOL ODOEditingContextObjectIsInsertedNotConsideringDeletions(ODOEditingContext *self, ODOObject *object) OB_HIDDEN;

static inline BOOL _queryUniqueSet(NSSet *set, ODOObject *query)
{
    id obj = [set member:query];
    OBASSERT(obj == nil || obj == query);
    return obj != nil;
}

NS_ASSUME_NONNULL_END
