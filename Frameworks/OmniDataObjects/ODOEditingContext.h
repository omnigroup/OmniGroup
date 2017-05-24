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

@class NSDate, NSSet, NSUndoManager, NSMutableSet;
@class ODODatabase, ODOObject, ODOFetchRequest, ODOObjectID;

@interface ODOEditingContext : OFObject
{
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
    
    NSMutableDictionary *_objectIDToCommittedPropertySnapshot; // ODOObjectID -> NSArray of property values for only those objects that have been edited.  The values in the dictionary are the database committed values.
    NSMutableDictionary *_objectIDToLastProcessedSnapshot; // Like the committed value snapshot, but this has the differences from the last time -processPendingChanges completed.  In particular, this can contain pre-update snapshots for inserted objects, where _objectIDToCommittedPropertySnapshot will never contain snapshots for inserted objects.
    
    BOOL _isSendingWillSave;
    BOOL _isValidatingAndWritingChanges;
    BOOL _inProcessPendingChanges;
    BOOL _isResetting;
    
    BOOL _avoidSettingSaveDates;
    NSDate *_saveDate;
}

- initWithDatabase:(ODODatabase *)database;

- (ODODatabase *)database;

- (NSUndoManager *)undoManager;
- (void)setUndoManager:(NSUndoManager *)undoManager;

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

- (void)setShouldSetSaveDates:(BOOL)shouldSetSaveDates;
- (BOOL)shouldSetSaveDates;

- (BOOL)saveWithDate:(NSDate *)saveDate error:(NSError **)outError;
- (NSDate *)saveDate;

- (BOOL)hasChanges;
- (BOOL)hasUnprocessedChanges;
- (ODOObject *)objectRegisteredForID:(ODOObjectID *)objectID;

- (NSArray *)executeFetchRequest:(ODOFetchRequest *)fetch error:(NSError **)outError;

- (__kindof ODOObject *)insertObjectWithEntityName:(NSString *)entityName;
- (__kindof ODOObject *)fetchObjectWithObjectID:(ODOObjectID *)objectID error:(NSError **)outError;

@end

extern NSNotificationName ODOEditingContextObjectsWillBeDeletedNotification;

extern NSNotificationName ODOEditingContextObjectsDidChangeNotification;
extern NSNotificationName ODOEditingContextWillSaveNotification; // Receivers of the notification should not make any changes to the context
extern NSNotificationName ODOEditingContextDidSaveNotification;

extern NSString * const ODOInsertedObjectsKey;
extern NSString * const ODOUpdatedObjectsKey; // All the updated objects
extern NSString * const ODOMateriallyUpdatedObjectsKey; // A subset of the updated objects where each object has -changedNonDerivedChangedValue
extern NSString * const ODOMateriallyUpdatedObjectPropertiesKey; // An NSMapTable whose keys are the materially updated objects (see above) and whose values are dictionaries indicating the changed key/value pairs on the key object(s)
extern NSString * const ODODeletedObjectsKey;
extern NSString * const ODODeletedObjectPropertySnapshotsKey; // An NSDictionary mapping ODOObjectIDs for deleted objects to NSArray property snapshots, representing the last state those objects were in before deletion

extern NSNotificationName ODOEditingContextWillResetNotification;
extern NSNotificationName ODOEditingContextDidResetNotification;
