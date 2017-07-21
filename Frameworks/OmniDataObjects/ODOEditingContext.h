// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <CoreFoundation/CFRunLoop.h>
#import <OmniDataObjects/ODOFeatures.h>

#import <Foundation/NSNotification.h>

NS_ASSUME_NONNULL_BEGIN

@class NSDate, NSSet, NSUndoManager, NSMutableSet;
@class ODODatabase, ODOObject, ODOFetchRequest, ODOObjectID;

@interface ODOEditingContext : NSObject

- (instancetype)initWithDatabase:(ODODatabase *)database;

@property (nonatomic, readonly) ODODatabase *database;

@property (nonatomic, nullable, strong) NSUndoManager *undoManager;

- (void)reset;
- (void)insertObject:(ODOObject *)object;
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

@property (nonatomic) BOOL shouldSetSaveDates;

- (BOOL)saveWithDate:(NSDate *)saveDate error:(NSError **)outError;
@property (nonatomic, readonly) NSDate *saveDate; // Should only be accessed inside of -saveWithDate:error:

@property (nonatomic, readonly) BOOL hasChanges;
@property (nonatomic, readonly) BOOL hasUnprocessedChanges;

- (nullable ODOObject *)objectRegisteredForID:(ODOObjectID *)objectID;

- (nullable NSArray *)executeFetchRequest:(ODOFetchRequest *)fetch error:(NSError **)outError;

- (__kindof ODOObject *)insertObjectWithEntityName:(NSString *)entityName;
- (nullable __kindof ODOObject *)fetchObjectWithObjectID:(ODOObjectID *)objectID error:(NSError **)outError NS_REFINED_FOR_SWIFT;

@end

extern NSNotificationName const ODOEditingContextObjectsWillBeDeletedNotification;

extern NSNotificationName const ODOEditingContextObjectsDidChangeNotification;
extern NSNotificationName const ODOEditingContextWillSaveNotification; // Receivers of the notification should not make any changes to the context
extern NSNotificationName const ODOEditingContextDidSaveNotification;

extern NSString * const ODOInsertedObjectsKey;
extern NSString * const ODOUpdatedObjectsKey; // All the updated objects
extern NSString * const ODOMateriallyUpdatedObjectsKey; // A subset of the updated objects where each object has -changedNonDerivedChangedValue
extern NSString * const ODOMateriallyUpdatedObjectPropertiesKey; // An NSMapTable whose keys are the materially updated objects (see above) and whose values are dictionaries indicating the changed key/value pairs on the key object(s)
extern NSString * const ODODeletedObjectsKey;
extern NSString * const ODODeletedObjectPropertySnapshotsKey; // An NSDictionary mapping ODOObjectIDs for deleted objects to NSArray property snapshots, representing the last state those objects were in before deletion

extern NSNotificationName ODOEditingContextWillResetNotification;
extern NSNotificationName ODOEditingContextDidResetNotification;

NS_ASSUME_NONNULL_END
