// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

#import <CoreFoundation/CFRunLoop.h>
#import <OmniDataObjects/ODOFeatures.h>
#import <dispatch/queue.h>

#import <Foundation/NSNotification.h>

NS_ASSUME_NONNULL_BEGIN

@class NSDate, NSSet, NSUndoManager, NSMutableSet;
@class ODODatabase, ODOObject, ODOFetchRequest, ODOObjectID, ODORelationship;

@interface ODOEditingContext : NSObject

- (instancetype)initWithDatabase:(ODODatabase *)database;

- (void)assumeOwnershipWithQueue:(dispatch_queue_t)queue;
- (void)relinquishOwnerhip;
- (BOOL)executeWithTemporaryOwnership:(dispatch_queue_t)temporaryOwner operation:(BOOL (^)(void))operation;

@property (nonatomic, readonly) ODODatabase *database;

@property (nonatomic, nullable, strong) NSUndoManager *undoManager;

// Schedules a runloop observer in the current runloop to process pending changes. Only set this if the instance it being used by a single runloop.
@property(nonatomic) BOOL automaticallyProcessPendingChanges;

- (void)reset;
- (void)_insertObject:(ODOObject *)object;
- (BOOL)deleteObject:(ODOObject *)object error:(NSError **)outError;
- (BOOL)processPendingChanges;

- (NSSet *)insertedObjects;
- (NSSet *)updatedObjects;
- (NSSet *)deletedObjects;
- (NSDictionary *)registeredObjectByID;

- (BOOL)isInserted:(ODOObject *)object;
- (BOOL)isUpdated:(ODOObject *)object;
- (BOOL)isDeleted:(ODOObject *)object;
- (BOOL)isRegistered:(ODOObject *)object;

- (BOOL)saveWithDate:(NSDate *)saveDate error:(NSError **)outError;
@property (nonatomic, readonly) BOOL isSaving;
@property (nonatomic, readonly) NSDate *saveDate; // Should only be accessed inside of -saveWithDate:error:

@property (nonatomic, readonly) BOOL hasChanges;
@property (nonatomic, readonly) BOOL hasUnprocessedChanges;

- (nullable ODOObject *)objectRegisteredForID:(ODOObjectID *)objectID;

- (nullable NSArray *)executeFetchRequest:(ODOFetchRequest *)fetch error:(NSError **)outError;

- (__kindof ODOObject *)insertObjectWithEntityName:(NSString *)entityName;
- (nullable __kindof ODOObject *)fetchObjectWithObjectID:(ODOObjectID *)objectID error:(NSError **)outError NS_REFINED_FOR_SWIFT;

/// Support for bulk fetching any uncleared to-many relationship faults in the source objects. All teh source objects must have the same entity as the source of the relationship. The fetched objects are returned (so, if a source object already had cleared its relationship, those objects will not be in the result).
- (nullable NSArray <__kindof ODOObject *> *)fetchToManyRelationship:(ODORelationship *)relationship forSourceObjects:(NSSet <ODOObject *> *)sourceObjects error:(NSError **)outError;

/// Debugging label for differentiating between multiple editing contexts.
@property (nonatomic, copy) NSString *label;

// Incremented each time ODOEditingContextObjectsDidChangeNotification is posted.
@property(nonatomic,readonly) NSUInteger objectDidChangeCounter;

@end

extern void ODOEditingContextAssertOwnership(ODOEditingContext *context);

/// Sent from `-deleteObject:error:` and undo of the creation of an inserted object, passing the objects to be deleted in the `ODODeletedObjectsKey` user info key, including those any propagated deletes. The object passed to `-deleteObject:error:` will have already been sent `prepareForDeletion`, but will not have relationships nullfied or report itself as deleted.
extern NSNotificationName const ODOEditingContextObjectsPreparingToBeDeletedNotification;

/// Sent from -deleteObject:error: and undo of undo of the creation of an inserted object, passing the objects to be deleted in the `ODODeletedObjectsKey` key, including those that will be included due to delete propagation. The objects will have received `prepareForDeletion` before this notification.  The objects are provisionally marked as deleted (they will return `YES` for `isDeleted` and will not appear in fetches). During receipt of this notification, it is still allowed to query properties on the deleted objects. Snapshots of the last committed state of deleted objects are also passed in the `ODODeletedObjectPropertySnapshotsKey` user info key.
extern NSNotificationName const ODOEditingContextObjectsWillBeDeletedNotification;

extern NSNotificationName const ODOEditingContextObjectsDidChangeNotification;
extern NSNotificationName const ODOEditingContextWillSaveNotification; // Receivers of the notification should not make any changes to the context
extern NSNotificationName const ODOEditingContextDidSaveNotification;

extern NSString * const ODOInsertedObjectsKey;
extern NSString * const ODOUpdatedObjectsKey; // All the updated objects
extern NSString * const ODOMateriallyUpdatedObjectsKey; // A subset of the updated objects where each object has -changedNonDerivedChangedValue
extern NSString * const ODOMateriallyUpdatedObjectPropertiesKey; // An NSMapTable whose keys are the materially updated objects (see above) and whose values are dictionaries indicating the changed key/value pairs on the key object(s)
extern NSString * const ODODeletedObjectsKey;
extern NSString * const ODODeletedObjectPropertySnapshotsKey; // An NSDictionary mapping ODOObjectIDs for deleted objects to ODOObjectSnapshots, representing the last state those objects were in before deletion

extern NSNotificationName const ODOEditingContextWillResetNotification;
extern NSNotificationName const ODOEditingContextDidResetNotification;

NS_ASSUME_NONNULL_END
