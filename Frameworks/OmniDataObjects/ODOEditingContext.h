// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOEditingContext.h 104583 2008-09-06 21:23:18Z kc $

#import <OmniFoundation/OFObject.h>

#import <CoreFoundation/CFRunLoop.h>
#import <OmniDataObjects/ODOFeatures.h>

@class NSDate, NSSet, NSUndoManager, NSMutableSet;
@class ODODatabase, ODOObject, ODOFetchRequest, ODOObjectID;

@interface ODOEditingContext : OFObject
{
@private
    ODODatabase *_database;
#if ODO_SUPPORT_UNDO
    NSUndoManager *_undoManager;
#endif
    
    NSMutableDictionary *_registeredObjectByID;
    
    CFRunLoopObserverRef _runLoopObserver;
    
    // Two sets of changes.  One for processed changes (notifications have been sent) and one for recent changes.
    NSMutableSet *_processedInsertedObjects;
    NSMutableSet *_processedUpdatedObjects;
    NSMutableSet *_processedDeletedObjects;
    
    NSMutableSet *_recentlyInsertedObjects;
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

#if ODO_SUPPORT_UNDO
- (NSUndoManager *)undoManager;
- (void)setUndoManager:(NSUndoManager *)undoManager;
#endif

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

- (ODOObject *)fetchObjectWithObjectID:(ODOObjectID *)objectID error:(NSError **)outError; // Returns NSNull if the object wasn't found, nil on error.

@end

extern NSString * const ODOEditingContextObjectsWillBeDeletedNotification;

extern NSString * const ODOEditingContextObjectsDidChangeNotification;    
extern NSString * const ODOEditingContextDidSaveNotification;
extern NSString * const ODOInsertedObjectsKey;
extern NSString * const ODOUpdatedObjectsKey; // All the updated objects
extern NSString * const ODOMateriallyUpdatedObjectsKey; // A subset of the updated objects where each object has -changedNonDerivedChangedValue
extern NSString * const ODODeletedObjectsKey;

extern NSString * const ODOEditingContextWillReset;
extern NSString * const ODOEditingContextDidReset;
