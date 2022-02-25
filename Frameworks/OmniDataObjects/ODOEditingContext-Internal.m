// Copyright 2008-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOEditingContext-Internal.h"

#import <OmniDataObjects/ODOEditingContext-Subclass.h>
#import <OmniDataObjects/ODOObjectID.h>
#import <OmniDataObjects/ODOObjectSnapshot.h>
#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/NSPredicate-ODOExtensions.h>

#ifdef DEBUG
// Required for a helper method used for assertions.
#import <OmniFoundation/NSPredicate-OFExtensions.h>
#endif

#import "ODODatabase-Internal.h"
#import "ODOEntity-SQL.h"
#import "ODOObject-Internal.h"
#import "ODOSQLStatement.h"
#import "ODOModel-Internal.h"

#import <Foundation/NSUndoManager.h>

#import <sqlite3.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation ODOEditingContext (Internal)

#ifdef OMNI_ASSERTIONS_ON

static void _checkRegisteredObject(const void *key, const void *value, void *context)
{
    ODOObjectID *objectID = (ODOObjectID *)key;
    ODOObject *object = (ODOObject *)value;
    ODOEditingContext *self = context;
    
    OBASSERT([object isInvalid] == NO);
    OBASSERT([object hasBeenDeleted] == NO);
    OBASSERT([object objectID] == objectID);
    OBASSERT([object editingContext] == self);
}

typedef struct {
    ODOEditingContext *editingContext;
    NSDictionary *objectByID;
} CheckObjectRegisteredContext;

static void _checkRegisteredInSet(NSSet *set, CheckObjectRegisteredContext *ctx)
{
    for (ODOObject *object in set) {
        OBASSERT([object editingContext] == ctx->editingContext);
        OBASSERT([ctx->objectByID objectForKey:[object objectID]] == object);
    }
}

static void _addObjectIdForEachObjectInSet(NSMutableSet *objectIDs, NSSet *objects)
{
    for (ODOObject *object in objects)
        [objectIDs addObject:[object objectID]];
}

static void _removeObjectIdForEachObjectInSet(NSMutableSet *objectIDs, NSSet *objects)
{
    for (ODOObject *object in objects)
        [objectIDs removeObject:[object objectID]];
}

static void _checkInvariantsApplier(const void *key, const void *value, void *context)
{
    // OmniFocusModel objects define _checkInvariants and theirs hate being called when ours are.
    [(ODOObject *)value _odo_checkInvariants];
}

- (BOOL)_checkInvariants;
{
    if (!OBEnableExpensiveAssertions)
        return YES;
    
    // All the registered objects should be valid
    CFDictionaryApplyFunction((CFDictionaryRef)_registeredObjectByID, _checkRegisteredObject, self);
    
    // All changed objects should be registered.
    {
        CheckObjectRegisteredContext ctx;
        memset(&ctx, 0, sizeof(ctx));
        ctx.editingContext = self;
        ctx.objectByID = _registeredObjectByID;
        
        _checkRegisteredInSet(_processedInsertedObjects, &ctx);
        _checkRegisteredInSet(_processedUpdatedObjects, &ctx);
        _checkRegisteredInSet(_processedDeletedObjects, &ctx);
        _checkRegisteredInSet(_recentlyInsertedObjects, &ctx);
        _checkRegisteredInSet(_recentlyUpdatedObjects, &ctx);
        _checkRegisteredInSet(_recentlyDeletedObjects, &ctx);
    }
    
    // If an object is recently inserted, it shouln't be considered updated when it mutates.
    // If an object is recently inserted or updated, a delete should be entered and the object removed from the recent inserts/updates.
    OBINVARIANT(![_recentlyInsertedObjects intersectsSet:_recentlyUpdatedObjects]);
    OBINVARIANT(![_recentlyInsertedObjects intersectsSet:_recentlyDeletedObjects]);
    OBINVARIANT(![_recentlyUpdatedObjects intersectsSet:_recentlyDeletedObjects]);
    
    // An object that has a processed insert can't be re-inserted
    OBINVARIANT(![_processedInsertedObjects intersectsSet:_recentlyInsertedObjects]);
    
    // An object that has been deleted can't be re-deleted
    OBINVARIANT(![_processedDeletedObjects intersectsSet:_recentlyDeletedObjects]);
    
    // Can't be in multiple processed states
    OBINVARIANT(![_processedInsertedObjects intersectsSet:_processedDeletedObjects]);
    OBINVARIANT(![_processedInsertedObjects intersectsSet:_processedUpdatedObjects]);
    OBINVARIANT(![_processedUpdatedObjects intersectsSet:_processedDeletedObjects]);
    
    // All registered objects must pass their invariants too.
    if (_registeredObjectByID)
        CFDictionaryApplyFunction((CFDictionaryRef)_registeredObjectByID, _checkInvariantsApplier, NULL);
    
    // Any objects in the recent updates or deletes should have a since-last-processing snapshot, EVEN if it is inserted (this stores the state the object was in after the last processing).  These should be the only snapshots therein.
    // Any objects in the recent OR processed updates or deletes that isn't also an insert (processed inserts can be updated later) should have a committed snapshot
    {
        NSMutableSet *expectedIDs = [NSMutableSet set];
        _addObjectIdForEachObjectInSet(expectedIDs, _recentlyUpdatedObjects);
        _addObjectIdForEachObjectInSet(expectedIDs, _recentlyDeletedObjects);
        NSSet *lastProcessedIDs = [NSSet setWithArray:[_objectIDToLastProcessedSnapshot allKeys]];
        OBINVARIANT([expectedIDs isEqualToSet:lastProcessedIDs]);
        
        _removeObjectIdForEachObjectInSet(expectedIDs, _processedInsertedObjects);
        _addObjectIdForEachObjectInSet(expectedIDs, _processedUpdatedObjects);
        _addObjectIdForEachObjectInSet(expectedIDs, _processedDeletedObjects);
        NSSet *commitedIDs = [NSSet setWithArray:[_objectIDToCommittedPropertySnapshot allKeys]];
        OBINVARIANT([expectedIDs isEqualToSet:commitedIDs]);
    }
    
    
    return YES;
}

- (BOOL)_isValidatingAndWritingChanges;
{
    return _isValidatingAndWritingChanges;
}
#endif

- (void)_objectWillBeUpdated:(ODOObject *)object;
{
    OBINVARIANT([self _checkInvariants]);
    OBPRECONDITION(!_isValidatingAndWritingChanges); // Can't make edits in the validation methods
    OBPRECONDITION(object);
    OBPRECONDITION([object editingContext] == self);
    OBPRECONDITION([_registeredObjectByID objectForKey:[object objectID]] == object);
    OBPRECONDITION(![object isDeleted]);
    
    // Updated objects can be updated again.  Though we should maybe have a flag in the object that says it has sent a update note (which we clear in -processPendingChanges).
    //OBPRECONDITION([_processedUpdatedObjects member:object] == nil || [_recentlyUpdatedObjects member:object] == object);
    
    // Processed inserted objects can be updated again (for notification/undo purposes), but recently inserted objects shouldn't be updated.  Until the object tracks this state, we have to ignore it.
    //OBPRECONDITION([_processedInsertedObjects member:object] == nil || [_processedInsertedObjects member:object] == object);
    
    if (_nonretainedLastRecentlyInsertedObject == object)
        // Ignore updates from the last recently inserted object (as with _recentlyInsertedObjects below)
        return;

    if ([_recentlyUpdatedObjects member:object]) {
        OBASSERT([_objectIDToCommittedPropertySnapshot objectForKey:[object objectID]] || [_objectIDToLastProcessedSnapshot objectForKey:[object objectID]] || [_processedInsertedObjects member:object]); // should have a snapshot already, unless this is a recent update to a processed insert
        return; // Already been marked updated this round.
    }

    if ([_recentlyInsertedObjects member:object]) {
        // Ignore updates from recently inserted objects; once they are processed, then we can notify them as updated.
        return;
    }
    
    if (!_recentlyUpdatedObjects) {
        _recentlyUpdatedObjects = ODOEditingContextCreateRecentSet(self);
    }
    
    [_recentlyUpdatedObjects addObject:object];
    
    // Register a snapshot of committed if we haven't already.  Processed inserts won't have committed snapshots, only things that have been fetched and then modified.  Still, they might have in-memory snapshots.
    [self _snapshotObjectPropertiesIfNeeded:object];

    OBINVARIANT([self _checkInvariants]);
}

- (void)_registerObject:(ODOObject *)object;
{
    OBPRECONDITION(object);
    OBPRECONDITION(_registeredObjectByID);
    OBPRECONDITION([_registeredObjectByID objectForKey:[object objectID]] == nil);
    
    [_registeredObjectByID setObject:object forKey:[object objectID]];

    OBPRECONDITION([_registeredObjectByID objectForKey:[object objectID]] == object);
}

// This maintains snapshots for both the committed values and for the since-last-processed values.
- (void)_snapshotObjectPropertiesIfNeeded:(ODOObject *)object;
{
    ODOObjectID *objectID = [object objectID];
    BOOL isReinserted = [_reinsertedObjects containsObject:object];
    
    if ([_objectIDToLastProcessedSnapshot objectForKey:objectID] != nil) {
        // This object has already been snapshotted this editing processing cycle.
        // Inserted objects can be 'updated' in the recent set.  Can't use -isUpdated in our assertion since that will return NO for inserted objects that have been updated since being first processed.
#ifdef OMNI_ASSERTIONS_ON
        // Here isInserted might mean 'was inserted but we are cancelling that for a deletion'. If we are in the middle of -deleteObject:error:, the object can be in both the processed inserts and the recent deletes. In both the case that the object is inserted and still pending insertion and was inserted but about to go away, we don't want a snapshot registered.
        BOOL isInserted = ODOEditingContextObjectIsInsertedNotConsideringDeletions(self, object);
        
        if (isInserted && !isReinserted) {
            // Should be no committed snapshot for inserted objects
            OBASSERT([_objectIDToCommittedPropertySnapshot objectForKey:objectID] == nil);
        } else {
            // Object must be inserted or deleted since it isn't inserted.  Updated or deleted objects should have gotten their committed snapshot filled out the first time they passed through here
            OBASSERT([object isUpdated] || [object isDeleted] || isReinserted);
            OBASSERT([_objectIDToCommittedPropertySnapshot objectForKey:objectID] != nil);
        }
#endif
        return;
    }
    
    if (_objectIDToLastProcessedSnapshot == nil) {
        _objectIDToLastProcessedSnapshot = [[NSMutableDictionary alloc] init];
    }

    ODOObjectSnapshot *snapshot = _ODOObjectCreatePropertySnapshot(object);
    _objectIDToLastProcessedSnapshot[objectID] = snapshot;
    [snapshot release];
    
    // The first edit to a database-resident object (non-inserted) should make a committed value snapshot too
    if ([_objectIDToCommittedPropertySnapshot objectForKey:objectID] == nil) {
        // As above, -[ODOObject isInserted:] will be NO already for objects that were inserted, but are being deleted.
        if (!ODOEditingContextObjectIsInsertedNotConsideringDeletions(self, object) || isReinserted) {
            if (_objectIDToCommittedPropertySnapshot == nil) {
                _objectIDToCommittedPropertySnapshot = [[NSMutableDictionary alloc] init];
            }

            _objectIDToCommittedPropertySnapshot[objectID] = snapshot;
        }
    }
}

- (nullable ODOObjectSnapshot *)_lastProcessedPropertySnapshotForObjectID:(ODOObjectID *)objectID;
{
    OBPRECONDITION(objectID != nil);
#ifdef OMNI_ASSERTIONS_ON
    ODOObject *object = [_registeredObjectByID objectForKey:objectID]; // Might be nil if we have the id for something that would be a fault, were it require to be created.
#endif
    
    ODOObjectSnapshot *snapshot = _objectIDToLastProcessedSnapshot[objectID];
#ifdef OMNI_ASSERTIONS_ON
    if (snapshot == nil && object != nil) {
        OBASSERT([object isInserted]);
    }
#endif
    
    return snapshot;
}

- (nullable ODOObjectSnapshot *)_committedPropertySnapshotForObjectID:(ODOObjectID *)objectID;
{
    OBPRECONDITION(objectID != nil);
#ifdef OMNI_ASSERTIONS_ON
    ODOObject *object = [_registeredObjectByID objectForKey:objectID]; // Might be nil if we have the id for something that would be a fault, were it require to be created.
#endif
    
    ODOObjectSnapshot *snapshot = _objectIDToCommittedPropertySnapshot[objectID];
#ifdef OMNI_ASSERTIONS_ON
    if (snapshot == nil && object != nil) {
        OBASSERT(![object isUpdated]);
        OBASSERT(![object isDeleted]);
    }
#endif
    
    return snapshot;
}

#ifdef OMNI_ASSERTIONS_ON
// A weaker form of -isDeleted:, only used in assertions right now.
- (BOOL)_isBeingDeleted:(ODOObject *)object;
{
    return _queryUniqueSet(_recentlyDeletedObjects, object);
}
#endif

- (void)_undoGroupStarterHack;
{
    // Nothing
}

ODOObject * ODOEditingContextLookupObjectOrRegisterFaultForObjectID(ODOEditingContext *self, ODOObjectID *objectID)
{
    OBPRECONDITION([self isKindOfClass:[ODOEditingContext class]]);
    OBPRECONDITION([objectID isKindOfClass:[ODOObjectID class]]);
    OBPRECONDITION([[objectID entity] model] == [[self database] model]);
    
    ODOObject *object = [self objectRegisteredForID:objectID];
    if (object)
        return object;
    
    // Need a new fault
    object = [[[[objectID entity] instanceClass] alloc] initWithEditingContext:self objectID:objectID isFault:YES];
    [self _registerObject:object];
    [object release]; // we hold it
    
    return object;
}

NSMutableSet * ODOEditingContextCreateRecentSet(ODOEditingContext *self)
{
    OBPRECONDITION([self isKindOfClass:[ODOEditingContext class]]);
    
    // We don't log an undo until -processPendingChanges, but we want to at least start a group here.
    // TODO: OmniFocus is a NSUndoManager observer and will call -processPendingChanges and -save: on use when the group is about to close.  But we should really do the -processPendingChanges ourselves for apps other than OmniFocus.
    if (self->_undoManager && !self->_recentlyInsertedObjects && !self->_recentlyUpdatedObjects && !self->_recentlyDeletedObjects) {
        OBASSERT([self->_undoManager groupsByEvent]);
        if ([self->_undoManager groupingLevel] == 0)
            //[self->_undoManager beginUndoGrouping];  // Horrifying.  If -groupsByEvent is set, calling this will create an undo grouping and we'll end up at level 2.
            [[self->_undoManager prepareWithInvocationTarget:self] _undoGroupStarterHack];
    }
    
    return [[NSMutableSet alloc] init];
}

typedef struct {
    ODOEntity *entity;
    NSPredicate *predicate;
    NSMutableArray *results;
} InMemoryFetchContext;

static void _addMatchingInserts(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    InMemoryFetchContext *ctx = context;
    
    if (ctx->entity != [object entity])
        return;
    if (ctx->predicate && ![ctx->predicate evaluateWithObject:object])
        return;
    
    [ctx->results addObject:object];
}

static void _addMissingMatchingUpdates(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    InMemoryFetchContext *ctx = context;
    
    if (ctx->entity == [object entity] && [ctx->predicate evaluateWithObject:object]) {
        // Might have previously matched since this is an update.  Inefficient if there are a ton of fetch results.
        if ([ctx->results indexOfObjectIdenticalTo:object] == NSNotFound)
            [ctx->results addObject:object];
    }
}

static void _updateResultSetForChanges(NSMutableArray *results, ODOEntity *entity, NSPredicate *predicate, NSSet * _Nullable inserted, NSSet * _Nullable updated, NSSet * _Nullable deleted)
{
    InMemoryFetchContext memCtx;
    memset(&memCtx, 0, sizeof(memCtx));
    memCtx.entity = entity;
    memCtx.predicate = predicate;
    memCtx.results = results;
    
    NSUInteger resultIndex, resultCount = [results count];
    
    if (updated) {
        // Remove any objects that were fetched but have since been updated to no longer match the predicate
        resultIndex = resultCount;
        while (resultIndex--) { // loop reverse so we can modify the array as we go
            ODOObject *object = [results objectAtIndex:resultIndex];
            if ([updated member:object] && (predicate != nil && ![predicate evaluateWithObject:object]))
                [results removeObjectAtIndex:resultIndex];
        }
        
        // Append any objects of the right entity that *didn't* match the predicate before, but do now.
        CFSetApplyFunction((CFSetRef)updated, _addMissingMatchingUpdates, &memCtx); // Inefficient if there are lots of fetch results
    }
    
    if (inserted) {
        // Append any objects that have right right entity and match the predicate.
        CFSetApplyFunction((CFSetRef)inserted, _addMatchingInserts, &memCtx);
    }
    
    // We've started ignoring these while fetching
#ifdef OMNI_ASSERTIONS_ON
    if (deleted) {
        // Remove any objects from the results that have been deleted in memory (don't need the entity check).
        resultIndex = [results count];
        while (resultIndex--) { // loop reverse so we can modify the array as we go
            ODOObject *object = [results objectAtIndex:resultIndex];
            OBASSERT([deleted member:object] == nil);
        }
    }
#endif
}

void ODOUpdateResultSetForInMemoryChanges(ODOEditingContext *self, NSMutableArray *results, ODOEntity *entity, NSPredicate *predicate)
{
    OBPRECONDITION([self isKindOfClass:[ODOEditingContext class]]);
    OBPRECONDITION(results);
    OBPRECONDITION(entity);
    OBPRECONDITION([entity model] == [[self database] model]);
    
    // Update results for the processed changes and then the recent changes -- thus doing the merging of conflicting edits (first pass might add something that the second pass will remove).
    NSSet *processedInserts = self->_processedInsertedObjects;
    NSSet *processedUpdates = self->_processedUpdatedObjects;
    NSSet *processedDeletes = self->_processedDeletedObjects;
    NSSet *recentInserts = self->_recentlyInsertedObjects;
    NSSet *recentUpdates = self->_recentlyUpdatedObjects;
    NSSet *recentDeletes = self->_recentlyDeletedObjects;
    
    if (recentDeletes && ([processedInserts intersectsSet:recentDeletes] || [processedUpdates intersectsSet:recentDeletes])) {
        // We have to take some extra care in this case.  If we have deleted an object that is in the processed changes, we can't evaluate predicates on those objects.  We need to just delete them.  We could change _updateResultSetForChanges to check whether each object is deleted via -isDeleted, but instead we'll munge the sets here.
        
        // Use temporary processed insert/update sets that have the recent deletes removed.
        if (processedInserts) {
            processedInserts = [NSMutableSet setWithSet:processedInserts];
            [(NSMutableSet *)processedInserts minusSet:recentDeletes];
        }
        if (processedUpdates) {
            processedUpdates = [NSMutableSet setWithSet:processedUpdates];
            [(NSMutableSet *)processedUpdates minusSet:recentDeletes];
        }
    }
    
    if (processedInserts || processedUpdates || processedDeletes)
        _updateResultSetForChanges(results, entity, predicate, processedInserts, processedUpdates, processedDeletes);
    
    if (recentInserts || recentUpdates || recentDeletes)
        _updateResultSetForChanges(results, entity, predicate, recentInserts, recentUpdates, recentDeletes);
}

static BOOL PrepareQueryByKey(ODOSQLStatement *query, sqlite3 *sqlite, id key, NSError **outError)
{
    if (!sqlite) {
        // TODO: Should make it so that objects can't be refaulted while not connected since you'll not be able to get them back.
        
        // Can't fetch while not connected; that's crazy.
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Cannot prepare fetch for key %@ for query %@ while not connected to a database.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), key, query->_sql];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to fulfill fault.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToFetchFault, description, reason);
        return NO;
    }
    
    // Bind the pk to the statement
    OBASSERT(sqlite3_bind_parameter_count(query->_statement) == 1);
    
    if (!ODOSQLStatementBindConstant(query, sqlite, key, 1/*1-indexed*/, outError))
        return NO;
    
    return YES;
}

// Fetching
typedef struct {
    BOOL isFetchingObjectFaults; // YES if we are fulfilling a single object fault or a batch of prefetching faults
    ODOEntity *entity;
    Class instanceClass;
    NSArray *schemaProperties;
    ODOAttribute *primaryKeyAttribute;
    NSUInteger primaryKeyColumnIndex;
    ODOEditingContext *editingContext;
    NSMutableArray *results; // objects that resulted from the fetch.  some might have been previously fetched
    NSMutableArray *fetched; // objects included in the results that are newly fetched and need -awakeFromFetch
} ODORowFetchContext;

static BOOL _fetchObjectCallback(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError)
{
    ODORowFetchContext *ctx = context;
    
#if defined(OMNI_ASSERTIONS_ON)
    int columnCount = sqlite3_column_count(statement->_statement);
    int expectedCount = (int)[ctx->schemaProperties count];
    OBASSERT(columnCount == expectedCount);
#endif
    
    // Get the primary key first
    OBASSERT(ctx->primaryKeyColumnIndex <= INT_MAX); // sqlite3 sensisibly only allows a few billion columns.
    id value = nil;
    if (!ODOSQLStatementCreateValue(sqlite, statement, (int)ctx->primaryKeyColumnIndex, &value, [ctx->primaryKeyAttribute type], [ctx->primaryKeyAttribute valueClass], outError)) {
        return NO;
    }
    
    // Unique the fetch vs the registered objects.
    ODOObjectID *objectID = [[ODOObjectID alloc] initWithEntity:ctx->entity primaryKey:value];
    [value release];
    
    @try {
        ODOEditingContext *editingContext = ctx->editingContext;

        ODOObject *object;
        if (ctx->isFetchingObjectFaults) {
            // The object should be registered already.
            object = [editingContext objectRegisteredForID:objectID];
            if (!object) {
                NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Fetch for fault returned object with ID '%@' and no such object was registered.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), objectID];
                NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to fulfill fault.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
                ODOError(outError, ODOUnableToFetchFault, description, reason);
                return NO;
            }
        } else {
            // Doing a to-many fault fetch or a predicate-based fetch; we might have nothing registered for this identifier, a fault, or an already filled object.
            object = ODOEditingContextLookupObjectOrRegisterFaultForObjectID(editingContext, objectID);
        }
        if ([object isDeleted]) {
            // Deleted objects are now turned into faults until they are saved.  So, we drop them when fetching.
            return YES;
        } else if ([object isFault]) {
            // Create the values array to take the values we are about to fetch
            _ODOObjectCreateNullValues(object);

            // Object was previously created as a fault, but hasn't been filled in yet.  Let's do so and mark it cleared.
            if (!ODOExtractNonPrimaryKeySchemaPropertiesFromRowIntoObject(sqlite, statement, object, ctx->schemaProperties, ctx->primaryKeyColumnIndex, outError)) {
                return NO; // object will remain a fault but might have some values in it.  they'll get reset if we get fetched again.  might be nice to clean them out, though.
            }
            [object _setIsFault:NO];

            // When fetching faults, we already know what objects are being fetched.
            OBASSERT(ctx->isFetchingObjectFaults == (ctx->fetched == nil));
            [ctx->fetched addObject:object];
        } else if (ctx->isFetchingObjectFaults) {
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Fetch for fault returned object with ID '%@', but that object has already had its fault cleared.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), objectID];
            NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to fulfill fault.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
            ODOError(outError, ODOUnableToFetchFault, description, reason);
            return NO;
        } else {
            // This object has been seen before. We ignore the row in favor of the in-memory values.
        }

        [ctx->results addObject:object];
    } @finally {
        [objectID release];
    }

    return YES;
}

static BOOL FetchObjectFaultWithContext(ODOEditingContext *self, ODOObject *object, ODORowFetchContext *ctx, NSError **outError)
{
    OBPRECONDITION(!self->_isResetting); // Can't clear object faults at all while resetting

    ODODatabase *database = self->_database;
    
    ODOObjectID *objectID = [object objectID];
    id primaryKey = [objectID primaryKey];
    OBASSERT(primaryKey);

    ODOSQLConnection *connection = database.connection;
    BOOL success = ODOEditingContextExecuteWithOwnership(self, connection.queue, ^{
        return [connection performSQLAndWaitWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
            ODOSQLStatement *query = [ctx->entity _queryByPrimaryKeyStatement:blockError database:database sqlite:sqlite];
            if (!query)
                return NO;

            if (!PrepareQueryByKey(query, sqlite, primaryKey, blockError))
                return NO;

            ODOSQLStatementCallbacks callbacks;
            memset(&callbacks, 0, sizeof(callbacks));
            callbacks.row = _fetchObjectCallback;

            return ODOSQLStatementRun(sqlite, query, callbacks, ctx, blockError);
        }];
    });

    if (!success) {
        return NO;
    }

    // Was the object reachable?
    if ([object isFault]) {
        OBASSERT([ctx->results count] == 0);
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Object with ID '%@' is inaccessible.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), objectID];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to fulfill fault.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToFetchFault, description, reason);
        return NO;
    }
    
    // Assert that if we did unfault the object, we got back a single result
    OBASSERT([ctx->results count] == 1);
    OBASSERT(object == [ctx->results lastObject]);

    // Wait until the fetch is done and reset before awaking the object, in case it causes further fetching/faulting in its subclass method.
    OBASSERT([object isFault] == NO);
    PrefetchRelationshipsAndAwakeObjects(self, ctx->entity, @[object]);

    return YES;
}

// TODO: Test deleting an object and then resolving a to-one relationship to it that was previously still cached as just the primary key attribute.  The to-one should get nullified (or its owner cascaded).
void ODOFetchObjectFault(ODOEditingContext *self, ODOObject *object)
{
    OBPRECONDITION([self isKindOfClass:[ODOEditingContext class]]);
    OBPRECONDITION([object isKindOfClass:[ODOObject class]]);
    OBPRECONDITION([object editingContext] == self);

    OBPRECONDITION([object isFault]);
    OBPRECONDITION(![object isInserted]);
    OBPRECONDITION(![object isUpdated]);
    OBPRECONDITION(![object isDeleted]);
    
    if (ODOSQLDebugLogLevel > 0)
        ODOSQLStatementLogSQL(@"/* object fault %@ */ ", [object shortDescription]);

    ODORowFetchContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.isFetchingObjectFaults = YES;
    ctx.entity = [object entity];
    ctx.instanceClass = [ctx.entity instanceClass];
    ctx.schemaProperties = [ctx.entity _schemaProperties];
    ctx.primaryKeyAttribute = [ctx.entity primaryKeyAttribute];
    ctx.primaryKeyColumnIndex = [ctx.schemaProperties indexOfObjectIdenticalTo:ctx.primaryKeyAttribute];
    ctx.editingContext = self;
    ctx.results = [NSMutableArray array];

    NSError *error = nil;
    if (!FetchObjectFaultWithContext(self, object, &ctx, &error)) {
        // CoreData raises when faulting fails.  We'd like to avoid that, but for now we'll mimic it.
        NSString *excReason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to fulfill fault: %@", @"OmniDataObjects", OMNI_BUNDLE, @"faulting exception"), error];
        NSException *exc = [NSException exceptionWithName:NSObjectInaccessibleException reason:excReason userInfo:nil];
        
        switch ([self handleFaultFulfillmentError:error]) {
            case ODOEditingContextFaultErrorUnhandled:
                [exc raise];
                break;
            case ODOEditingContextFaultErrorIgnored:
                break;
            case ODOEditingContextFaultErrorRepaired:
                if (!FetchObjectFaultWithContext(self, object, &ctx, &error)) {
                    [exc raise];
                }
                break;
        }
    }
}

static BOOL FetchSetFaultWithContext(ODOEditingContext *self, ODOObject *owner, ODORelationship *rel, ODORowFetchContext *ctx, NSError **outError)
{
    ODODatabase *database = self->_database;
    
    if (![database connectedURL] || [database isFreshlyCreated])
        // We are working in memory.  Nothing to do.
        return YES;
    
    ODOObjectID *ownerID = [owner objectID];
    id ownerPrimaryKey = [ownerID primaryKey];
    OBASSERT(ownerPrimaryKey);

    ODORelationship *inverseToOneRelationship = rel.inverseRelationship;

    ODOSQLConnection *connection = database.connection;
    BOOL success = ODOEditingContextExecuteWithOwnership(self, connection.queue, ^{
        return [connection performSQLAndWaitWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
            ODOSQLStatement *query = [ctx->entity _queryByForeignKeyStatement:blockError relationship:inverseToOneRelationship database:database sqlite:sqlite];
            if (!query)
                return NO;

            if (!PrepareQueryByKey(query, sqlite, ownerPrimaryKey, blockError))
                return NO;

            ODOSQLStatementCallbacks callbacks;
            memset(&callbacks, 0, sizeof(callbacks));
            callbacks.row = _fetchObjectCallback;

            return ODOSQLStatementRun(sqlite, query, callbacks, ctx, blockError);
        }];
    });

    return success;
}

// Fetches the objects across a to-many relationship, uniquing against previously registered objects, and updating the results for in progress edits.
NSMutableSet * ODOFetchSetFault(ODOEditingContext *self, ODOObject *owner, ODORelationship *rel)
{
    OBPRECONDITION([self isKindOfClass:[ODOEditingContext class]]);
    OBPRECONDITION([owner isKindOfClass:[ODOObject class]]);
    OBPRECONDITION([owner editingContext] == self);
    OBPRECONDITION(rel);
    OBPRECONDITION([rel entity] == [owner entity]);
    OBPRECONDITION([[[owner entity] relationshipsByName] objectForKey:[rel name]] == rel);

    if (self->_isResetting) {
        OBASSERT(!self->_isResetting); // Shouldn't try to clear object faults at all while resetting, but we can bail meaningfully here at least
        return [NSMutableSet set];
    }
    
    if (ODOSQLDebugLogLevel > 0)
        ODOSQLStatementLogSQL(@"/* to-many fault %@.%@ */ ", [owner shortDescription], [rel name]);
    
    
    ODORowFetchContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.entity = [rel destinationEntity];
    ctx.instanceClass = [ctx.entity instanceClass];
    ctx.primaryKeyAttribute = [ctx.entity primaryKeyAttribute];
    ctx.schemaProperties = [ctx.entity _schemaProperties];
    ctx.primaryKeyColumnIndex = [ctx.schemaProperties indexOfObjectIdenticalTo:ctx.primaryKeyAttribute];
    ctx.editingContext = self;
    ctx.results = [NSMutableArray array];
    ctx.fetched = [NSMutableArray array]; // Collect newly fetched objects to be send -awakeFromFetch:

    OBASSERT(ctx.primaryKeyColumnIndex != NSNotFound);

    NSError *error = nil;
    if (!FetchSetFaultWithContext(self, owner, rel, &ctx, &error)) {
        // CoreData raises when faulting fails.  We'd like to avoid that, but for now we'll mimic it.
        NSString *excReason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to fulfill fault: %@", @"OmniDataObjects", OMNI_BUNDLE, @"faulting exception"), error];
        NSException *exc = [NSException exceptionWithName:NSObjectInaccessibleException reason:excReason userInfo:nil];
        
        switch ([self handleFaultFulfillmentError:error]) {
            case ODOEditingContextFaultErrorUnhandled:
                [exc raise];
                break;
            case ODOEditingContextFaultErrorIgnored:
                break;
            case ODOEditingContextFaultErrorRepaired:
                if (!FetchSetFaultWithContext(self, owner, rel, &ctx, &error)) {
                    [exc raise];
                }
                break;
        }
    }

    PrefetchRelationshipsAndAwakeObjects(self, ctx.entity, ctx.fetched);

    // TODO: Since we lazily clear the fault, we might need to treat undo specially.  For example, A->>B.  Fetch an A and a B w/o clearing the fault.  Delete the B.  Process changes.  Clear the fault (A->>Bs won't contain the B we deleted).  Undo.  If we clear the reverse fault when doing delete propagation, then this should just work if we snapshot the to-many.  But, if we snapshot the nil (lazy fault not yet created) and then undo after clearing, then the cleared set will be incorrect.
    
    // We are going to avoid clearing inverse to-many faults when updating to-one relationships.  So, the local edits need to be consulted.
    if ([self hasChanges]) {
        NSString *inverseKey = [[rel inverseRelationship] name];
        NSPredicate *predicate = ODOKeyPathEqualToValuePredicate(inverseKey, owner);
        ODOUpdateResultSetForInMemoryChanges(self, ctx.results, [rel destinationEntity], predicate);
    }
    
    return [NSMutableSet setWithArray:ctx.results];
}

NSMutableArray <__kindof ODOObject *> * _Nullable ODOFetchObjects(ODOEditingContext *self, ODOEntity *entity, NSPredicate *predicate, NSString *reason, NSError **outError)
{
    OBINVARIANT([self _checkInvariants]);

    if (self->_isResetting) {
        // Act as if we are attached to an empty database
        return [NSMutableArray array];
    }

    // TODO: Can't be in the middle of another fetch or we'll b0rk it up.  Add some sort of assertion to check this method vs. itself and faulting.

    // It's unclear whether it is worthwhile caching the conversion from SQL to a statement and if so how best to do it.  Instead, we'll build a statement, use it and discard it.  Predicates can have both column expressions and constants.  To avoid quoting issues, we could try to build a SQL string with bindings ('?') and a list of constants in parallel, prepare the statement and then bind the constants.  One problem with this is the IN expression.  The rhs might have any number of values 'foo IN ("a", "b", "c")' so we would have to count the collection to get the right number of slots to bind.
    // TODO: If we *do* start caching the statements we'll need to be wary of the copy semantics for text/blob (mostly text) bindings.  Right now we are copying (safe but slower), but if we try to optimize this uncarefully, we could end up crashing (since qualifiers could be reused and the original bytes might have been deallocated).

    __block ODORowFetchContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.entity = entity;
    ctx.instanceClass = entity.instanceClass;
    ctx.schemaProperties = [entity _schemaProperties];
    ctx.primaryKeyAttribute = entity.primaryKeyAttribute;
    ctx.primaryKeyColumnIndex = (int)[ctx.schemaProperties indexOfObjectIdenticalTo:ctx.primaryKeyAttribute];
    ctx.editingContext = self;
    ctx.results = [NSMutableArray array];
    ctx.fetched = [NSMutableArray array]; // Collect newly fetched objects to be send -awakeFromFetch:

    OBASSERT(ctx.primaryKeyColumnIndex != NSNotFound);

    // Even if we aren't connected, we can still do in-memory operations.  If the database is totally fresh (no saves have been done since the schema was created) doing a fetch is pointless.  This is an optimization for the import case where we fill caches prior to saving for the first time
    ODODatabase *database = self->_database;
    if ([database connection] && ![database isFreshlyCreated]) {
        if (ODOSQLDebugLogLevel > 0) {
            if ([reason length] == 0)
                reason = @"UNKNOWN";
            ODOSQLStatementLogSQL(@"/* SQL fetch: %@  reason: %@ */ ", entity.name, reason);
        }

        ODOSQLStatement *query = [[ODOSQLStatement alloc] initSelectProperties:ctx.schemaProperties fromEntity:entity connection:database.connection predicate:predicate error:outError];
        if (query == nil) {
            OBASSERT_NOT_REACHED("Failed to build query: %@", outError != NULL ? (id)[*outError toPropertyList] : (id)@"Missing error");
            OBINVARIANT([self _checkInvariants]);
            return nil;
        }

        ODOSQLConnection *connection = database.connection;
        BOOL success = ODOEditingContextExecuteWithOwnership(self, connection.queue, ^{
            return [connection performSQLAndWaitWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
                // TODO: Append the sort descriptors as a 'order by'?  Can't if they have non-schema properties, so for now we can just sort in memory.
                ODOSQLStatementCallbacks callbacks;
                memset(&callbacks, 0, sizeof(callbacks));
                callbacks.row = _fetchObjectCallback;

                return ODOSQLStatementRun(sqlite, query, callbacks, &ctx, blockError);
            }];
        });

        [query invalidate];
        [query release];

        if (!success) {
#ifdef DEBUG
            NSLog(@"Failed to run query: %@", outError ? (id)[*outError toPropertyList] : (id)@"Missing error");
#endif
            OBINVARIANT([self _checkInvariants]);
            return nil;
        }

        // Inform all the newly fetched objects that they have been fetched.  Do this *outside* running the fetch so that if they cause further fetching/faulting, they won't screw up our fetch in progress.
        PrefetchRelationshipsAndAwakeObjects(self, entity, ctx.fetched);
    }

    if ([self hasChanges]) {
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        ODOUpdateResultSetForInMemoryChanges(self, ctx.results, entity, predicate);
        CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();

        if (ODOSQLDebugLogLevel > 0) {
            if ([reason length] == 0)
                reason = @"UNKNOWN";
            ODOSQLStatementLogSQL(@"/* Memory fetch: %@  reason: %@ */\n/* ... %g sec, count now %ld */\n", entity.name, reason, end - start, [ctx.results count]);
        }
    }

#ifdef DEBUG
    // Help make sure we don't have support for *fetching* a predicate that we'll evaluate differently in memory.
    // This won't detect the inverse case (SQL doesn't match but in memory doesn't).
    if (predicate != nil) {
        NSMutableSet *keys = [NSMutableSet set];
        [predicate addReferencedKeys:keys];
        
        BOOL canPerformPostconditionCheck = YES;
        for (NSString *key in keys) {
            ODOAttribute *attribute = [entity attributesByName][key];
            if ([attribute valueClass] == [NSDate class] && attribute.type == ODOAttributeTypeXMLDateTime) {
                // The attribute value is an NSDate, but it's stored as an XML string. The fetch query can't be applied to the resulting objects, because the fetch query expects a string value, but the object will supply a date value instead.
                canPerformPostconditionCheck = NO;
            }
        }
        
        if (canPerformPostconditionCheck) {
            for (ODOObject *object in ctx.results) {
                OBPOSTCONDITION([predicate evaluateWithObject:object]); // Might have a predicate supplying a relationship's identifier where it should supply the actual object
            }
        }
    }
#endif

    OBINVARIANT([self _checkInvariants]);
    return ctx.results;
}

static void PrefetchRelationshipsAndAwakeObjects(ODOEditingContext *self, ODOEntity *entity, NSArray <ODOObject *> *fetched)
{
    NSMapTable<ODOEntity *, NSMutableArray <ODOObject *> *> *entityToPrefetchObjects;

    // Might want to go further in avoiding allocating the map table by passing in a NSMapTable** to ODOObjectPrepareObjectsForAwakeFromFetch for it to fill out if it finds any objects needing to be prefetched.
    // TODO: Since we know the possible entities up front that might be prefetched, the model generation could assign an index to each prefetchable entity and we could use an array or the like. Also, we may want to let the model decide what order entities are prefetched to get the best batching.
    if (entity.prefetchRelationships != nil) {
        entityToPrefetchObjects = [[NSMapTable alloc] initWithKeyOptions:NSMapTableObjectPointerPersonality valueOptions:NSMapTableStrongMemory capacity:0];
    } else {
        entityToPrefetchObjects = nil;
    }

    ODOObjectPrepareObjectsForAwakeFromFetch(entity, fetched, entityToPrefetchObjects);

    NSArray *combinedFetched;

    if ([entityToPrefetchObjects count] > 0) {
        // TODO: Instead maybe make this an array of arrays, avoiding extra copying.
        NSMutableArray <ODOObject *> *fetchedSoFar = [NSMutableArray arrayWithArray:fetched];
        NSArray <ODOEntity *> *prefetchEntities = entity.model.prefetchEntities;

        while ([entityToPrefetchObjects count] > 0) {
            ODOEntity *destinationEntity = nil;
            NSMutableArray <ODOObject *> *destinationObjects;

            // Get the higest rank entity to prefetch.
            for (ODOEntity *candidate in prefetchEntities) {
                destinationObjects = [entityToPrefetchObjects objectForKey:candidate];
                if (destinationObjects) {
                    destinationEntity = candidate;
                    break;
                }
            }
            OBASSERT_NOTNULL(destinationEntity);

            __autoreleasing NSError *error = nil;
            if (!PerformPrefetch(self, destinationEntity, destinationObjects, &error)) {
                // This isn't fatal for our *original* fetch, but worrisome still.
                [error log:@"Prefetching failed"];
            }

            for (ODOObject *destinationObject in destinationObjects) {
                OBASSERT(destinationObject->_flags.isFault == NO);
                OBASSERT(destinationObject->_flags.isScheduledForBatchFetch);
                destinationObject->_flags.isScheduledForBatchFetch = NO;
            }

            [destinationObjects retain]; // wouldn't need this if we record an array of batches
            [fetchedSoFar addObjectsFromArray:destinationObjects];

            // Clear this entry in the map table and collect prefetching information from this batch of objects
            [entityToPrefetchObjects removeObjectForKey:destinationEntity];

            ODOObjectPrepareObjectsForAwakeFromFetch(destinationEntity, destinationObjects, entityToPrefetchObjects);
            [destinationObjects release];
        }

        combinedFetched = fetchedSoFar;
    } else {
        combinedFetched = fetched;
    }

    [entityToPrefetchObjects release];

    for (ODOObject *object in combinedFetched) {
        ODOObjectPerformAwakeFromFetchWithoutRegisteringEdits(object);
    }
    for (ODOObject *object in combinedFetched) {
        ODOObjectFinalizeAwakeFromFetch(object);
    }
}

static BOOL PerformPrefetch(ODOEditingContext *self, ODOEntity *entity, NSArray <ODOObject *> *objects, NSError **outError)
{
    OBINVARIANT([self _checkInvariants]);
    OBPRECONDITION(!self->_isResetting, "This is a sub-fetch where the caller should have already checked this");

    // TODO: Add a cached ODOSQLStatement that fetches a fixed number of objects (and if we have fewer, replicate one of the primary keys to fill the extra slots).
    // TODO: Update this to send the list of objects to the background queue and invoke the batching there rather than dispatching to the background multiple times.

    __block ODORowFetchContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.isFetchingObjectFaults = YES;
    ctx.entity = entity;
    ctx.instanceClass = entity.instanceClass;
    ctx.schemaProperties = [entity _schemaProperties];
    ctx.primaryKeyAttribute = entity.primaryKeyAttribute;
    ctx.primaryKeyColumnIndex = (int)[ctx.schemaProperties indexOfObjectIdenticalTo:ctx.primaryKeyAttribute];
    ctx.editingContext = self;
    // Not filling out the results or fetched arrays since we know what is getting fetched

    OBASSERT(ctx.primaryKeyColumnIndex != NSNotFound);

    ODODatabase *database = self->_database;
    if (ODOSQLDebugLogLevel > 0) {
        ODOSQLStatementLogSQL(@"/* SQL batch fault: %@ */ ", entity.name);
    }

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K in %@", ctx.primaryKeyAttribute.name, objects];
    ODOSQLStatement *query = [[ODOSQLStatement alloc] initSelectProperties:ctx.schemaProperties fromEntity:entity connection:database.connection predicate:predicate error:outError];
    if (query == nil) {
        OBASSERT_NOT_REACHED("Failed to build query: %@", outError != NULL ? (id)[*outError toPropertyList] : (id)@"Missing error");
        OBINVARIANT([self _checkInvariants]);
        return NO;
    }

    ODOSQLConnection *connection = database.connection;
    BOOL success = ODOEditingContextExecuteWithOwnership(self, connection.queue, ^{
        return [connection performSQLAndWaitWithError:outError block:^BOOL(struct sqlite3 *sqlite, NSError **blockError) {
            ODOSQLStatementCallbacks callbacks;
            memset(&callbacks, 0, sizeof(callbacks));
            callbacks.row = _fetchObjectCallback;

            return ODOSQLStatementRun(sqlite, query, callbacks, &ctx, blockError);
        }];
    });

    [query invalidate];
    [query release];

    if (!success) {
#ifdef DEBUG
        NSLog(@"Failed to run query: %@", outError ? (id)[*outError toPropertyList] : (id)@"Missing error");
#endif
    }

    OBINVARIANT([self _checkInvariants]);
    return success;
}


@end

NS_ASSUME_NONNULL_END
