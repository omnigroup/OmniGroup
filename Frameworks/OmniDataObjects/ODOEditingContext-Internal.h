// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOEditingContext.h>

NS_ASSUME_NONNULL_BEGIN

@class ODOObjectSnapshot;

@interface ODOEditingContext () {
  @private

    // When non-NULL, only the owning queue may access this context. When NULL, the only allowed operation should be to assume ownership of the context.
    dispatch_queue_t _owningQueue;

    ODODatabase *_database;
    NSUndoManager *_undoManager;
    
    NSMutableDictionary *_registeredObjectByID;

    // Two sets of changes.  One for processed changes (notifications have been sent) and one for recent changes.
    NSMutableSet *_processedInsertedObjects;
    NSMutableSet *_processedUpdatedObjects;
    NSMutableSet *_processedDeletedObjects;
    
    NSMutableSet *_recentlyInsertedObjects;
    NSMutableSet *_recentlyUpdatedObjects;
    NSMutableSet *_recentlyDeletedObjects;
    
    NSMutableSet *_reinsertedObjects;
    
    ODOObject *_nonretainedLastRecentlyInsertedObject;

    NSMutableDictionary <ODOObjectID *, ODOObjectSnapshot *> *_objectIDToCommittedPropertySnapshot; // ODOObjectID -> snapshot of property values for only those objects that have been edited.  The values in the dictionary are the database committed values.
    NSMutableDictionary <ODOObjectID *, ODOObjectSnapshot *> *_objectIDToLastProcessedSnapshot; // Like the committed value snapshot, but this has the differences from the last time -processPendingChanges completed.  In particular, this can contain pre-update snapshots for inserted objects, where _objectIDToCommittedPropertySnapshot will never contain snapshots for inserted objects.
    
    BOOL _isSendingWillSave;
    BOOL _isValidatingAndWritingChanges;
    BOOL _isDeletingObjects;
    BOOL _inProcessPendingChanges;
    BOOL _isResetting;
    
    BOOL _avoidSettingSaveDates;
    NSDate *_saveDate;
}

- (void)_insertObject:(ODOObject *)object;

@end

// Temporarily yield's ownership to invoke the block and then reassumes ownership.
extern BOOL ODOEditingContextExecuteWithOwnership(ODOEditingContext *self, dispatch_queue_t temporaryOwner, BOOL (^ NS_NOESCAPE action)(void));

@interface ODOEditingContext (Internal)
#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
- (BOOL)_isValidatingAndWritingChanges;
#endif
- (void)_objectWillBeUpdated:(ODOObject *)object;
- (void)_registerObject:(ODOObject *)object;
- (void)_snapshotObjectPropertiesIfNeeded:(ODOObject *)object;
- (nullable ODOObjectSnapshot *)_lastProcessedPropertySnapshotForObjectID:(ODOObjectID *)objectID;
- (nullable ODOObjectSnapshot *)_committedPropertySnapshotForObjectID:(ODOObjectID *)objectID;

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_isBeingDeleted:(ODOObject *)object;
#endif

@end

@class NSPredicate;
@class ODOEntity, ODORelationship;

ODOObject * ODOEditingContextLookupObjectOrRegisterFaultForObjectID(ODOEditingContext *self, ODOObjectID *objectID) OB_HIDDEN;

NSMutableSet * ODOEditingContextCreateRecentSet(ODOEditingContext *self) OB_HIDDEN;

void ODOUpdateResultSetForInMemoryChanges(ODOEditingContext *self, NSMutableArray *results, ODOEntity *entity, NSPredicate *predicate) OB_HIDDEN;

void ODOFetchObjectFault(ODOEditingContext *self, ODOObject *object) OB_HIDDEN;
NSMutableSet * ODOFetchSetFault(ODOEditingContext *self, ODOObject *owner, ODORelationship *rel) OB_HIDDEN;
NSMutableArray <__kindof ODOObject *> * _Nullable ODOFetchObjects(ODOEditingContext *self, ODOEntity *entity, NSPredicate *predicate, NSString *reason, NSError **outError) OB_HIDDEN;

BOOL ODOEditingContextObjectIsInsertedNotConsideringDeletions(ODOEditingContext *self, ODOObject *object) OB_HIDDEN;

static inline BOOL _queryUniqueSet(NSSet *set, ODOObject *query)
{
    id obj = [set member:query];
    OBASSERT(obj == nil || obj == query);
    return obj != nil;
}

NS_ASSUME_NONNULL_END
