// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOEditingContext-Internal.h"

#import <OmniDataObjects/ODOObjectID.h>
#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/NSPredicate-ODOExtensions.h>

#import "ODODatabase-Internal.h"
#import "ODOEntity-SQL.h"
#import "ODOObject-Internal.h"
#import "ODOSQLStatement.h"

#if ODO_SUPPORT_UNDO
#import <Foundation/NSUndoManager.h>
#endif

#import <sqlite3.h>

RCS_ID("$Id$")

@implementation ODOEditingContext (Internal)

#ifdef OMNI_ASSERTIONS_ON

static void _checkRegisteredObject(const void *key, const void *value, void *context)
{
    ODOObjectID *objectID = (ODOObjectID *)key;
    ODOObject *object = (ODOObject *)value;
    ODOEditingContext *self = context;
    
    OBASSERT([object isInvalid] == NO);
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
    
    if ([_recentlyUpdatedObjects member:object]) {
        OBASSERT([_objectIDToCommittedPropertySnapshot objectForKey:[object objectID]] || [_objectIDToLastProcessedSnapshot objectForKey:[object objectID]] || [_processedInsertedObjects member:object]); // should have a snapshot already, unless this is a recent update to a processed insert
        return; // Already been marked updated this round.
    }

    if ([_recentlyInsertedObjects member:object])
        // Ignore updates from recently inserted objects; once they are processed, then we can notify them as updated.        
        return;
    
    if (!_recentlyUpdatedObjects)
        _recentlyUpdatedObjects = ODOEditingContextCreateRecentSet(self);
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
    
    if ([_objectIDToLastProcessedSnapshot objectForKey:objectID]) {
        // This object has already been snapshotted this editing processing cycle.
        // Inserted objects can be 'updated' in the recent set.  Can't use -isUpdated in our assertion since that will return NO for inserted objects that have been updated since being first processed.
#ifdef OMNI_ASSERTIONS_ON
        BOOL isInserted = ([_processedInsertedObjects member:object] != nil) || ([_recentlyInsertedObjects member:object] != nil);
        
        if (isInserted) {
            // Should be no committed snapshot for inserted objects
            OBASSERT([_objectIDToCommittedPropertySnapshot objectForKey:objectID] == nil);
        } else {
            // Object must be inserted or deleted since it isn't inserted.  Updated or deleted objects should have gotten their committed snapshot filled out the first time they passed through here
            OBASSERT([object isUpdated] || [object isDeleted]);
            OBASSERT([_objectIDToCommittedPropertySnapshot objectForKey:objectID] != nil);
        }
#endif
        return;
    }
    
    if (!_objectIDToLastProcessedSnapshot)
        _objectIDToLastProcessedSnapshot = [[NSMutableDictionary alloc] init];

    NSArray *snapshot = _ODOObjectCreatePropertySnapshot(object);
    [_objectIDToLastProcessedSnapshot setObject:snapshot forKey:objectID];
    [snapshot release];
    
    // The first edit to a database-resident object (non-inserted) should make a committed value snapshot too
    if ([_objectIDToCommittedPropertySnapshot objectForKey:objectID] == nil) {
        if (![object isInserted]) {
            if (!_objectIDToCommittedPropertySnapshot)
                _objectIDToCommittedPropertySnapshot = [[NSMutableDictionary alloc] init];
            [_objectIDToCommittedPropertySnapshot setObject:snapshot forKey:objectID];
        }
    }
}

- (NSArray *)_committedPropertySnapshotForObjectID:(ODOObjectID *)objectID;
{
    OBPRECONDITION(objectID);
#ifdef OMNI_ASSERTIONS_ON
    ODOObject *object = [_registeredObjectByID objectForKey:objectID]; // Might be nil if we have the id for something that would be a fault, were it require to be created.
#endif
    
    NSArray *snapshot = [_objectIDToCommittedPropertySnapshot objectForKey:objectID];
#ifdef OMNI_ASSERTIONS_ON
    if (!snapshot && object) {
        OBASSERT(![object isUpdated]);
        OBASSERT(![object isDeleted]);
    }
#endif
    
    return snapshot;
}

- (void)_undoGroupStarterHack;
{
    // Nothing
}

ODOObject *ODOEditingContextLookupObjectOrRegisterFaultForObjectID(ODOEditingContext *self, ODOObjectID *objectID)
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

NSMutableSet *ODOEditingContextCreateRecentSet(ODOEditingContext *self)
{
    OBPRECONDITION([self isKindOfClass:[ODOEditingContext class]]);
    
#if ODO_SUPPORT_UNDO
    // We don't log an undo until -processPendingChanges, but we want to at least start a group here.
    // TODO: OmniFocus is a NSUndoManager observer and will call -processPendingChanges and -save: on use when the group is about to close.  But we should really do the -processPendingChanges ourselves for apps other than OmniFocus.
    if (self->_undoManager && !self->_recentlyInsertedObjects && !self->_recentlyUpdatedObjects && !self->_recentlyDeletedObjects) {
        OBASSERT([self->_undoManager groupsByEvent]);
        if ([self->_undoManager groupingLevel] == 0)
            //[self->_undoManager beginUndoGrouping];  // Horrifying.  If -groupsByEvent is set, calling this will create an undo grouping and we'll end up at level 2.
            [[self->_undoManager prepareWithInvocationTarget:self] _undoGroupStarterHack];
    }
#endif
    
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

static void _updateResultSetForChanges(NSMutableArray *results, ODOEntity *entity, NSPredicate *predicate, NSSet *inserted, NSSet *updated, NSSet *deleted)
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
            if ([updated member:object] && ![predicate evaluateWithObject:object])
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

static BOOL _fetchObjectCallback(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError)
{
    ODORowFetchContext *ctx = context;
    
    OBASSERT(sqlite3_column_count(statement->_statement) == (int)[ctx->schemaProperties count]); // should just be the primary keys we fetched
    
    // Get the primary key first
    OBASSERT(ctx->primaryKeyColumnIndex <= INT_MAX); // sqlite3 sensisibly only allows a few billion columns.
    id value = nil;
    if (!ODOSQLStatementCreateValue(sqlite, statement, (int)ctx->primaryKeyColumnIndex, &value, [ctx->primaryKeyAttribute type], [ctx->primaryKeyAttribute valueClass], outError))
        return NO;
    
    // Unique the fetch vs the registered objects.
    ODOObjectID *objectID = [[ODOObjectID alloc] initWithEntity:ctx->entity primaryKey:value];
    [value release];
    
    ODOEditingContext *editingContext = ctx->editingContext;
    ODOObject *object = [editingContext objectRegisteredForID:objectID];
    if (!object) {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Fetch for fault returned object with ID '%@' and no such object was registered.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), objectID];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to fulfill fault.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToFetchFault, description, reason);
    } else if ([object isFault]) {
        // Create the values array to take the values we are about to fetch
        _ODOObjectCreateNullValues(object);

        // Object was previously created as a fault, but hasn't been filled in yet.  Let's do so and mark it cleared.
        if (!ODOExtractNonPrimaryKeySchemaPropertiesFromRowIntoObject(sqlite, statement, object, ctx, outError)) {
            [objectID release];
            return NO; // object will remain a fault but might have some values in it.  they'll get reset if we get fetched again.  might be nice to clean them out, though.
        }
        [object _setIsFault:NO];
    } else {
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Fetch for fault returned object with ID '%@', but that object has already had its fault cleared.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), objectID];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to fulfill fault.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToFetchFault, description, reason);
    }
    
    [ctx->results addObject:object];
    [objectID release];
    
    return YES;
}

static BOOL FetchObjectFaultWithContext(ODOEditingContext *self, ODOObject *object, ODORowFetchContext *ctx, NSError **outError)
{
    OBPRECONDITION(!self->_isResetting); // Can't clear object faults at all while resetting

    ODODatabase *database = self->_database;

    ODOSQLStatement *query = [ctx->entity _queryByPrimaryKeyStatement:outError database:database];
    if (!query)
        return NO;
    
    sqlite3 *sqlite = [database _sqlite];
    OBASSERT(sqlite); // Can't clear faults while disconnected

    ODOObjectID *objectID = [object objectID];
    id primaryKey = [objectID primaryKey];
    OBASSERT(primaryKey);

    if (!PrepareQueryByKey(query, sqlite, primaryKey, outError))
        return NO;
    
    ODOSQLStatementCallbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.row = _fetchObjectCallback;

    if (!ODOSQLStatementRun(sqlite, query, callbacks, ctx, outError))
        return NO;

    // Wait until the fetch is done and reset before awaking the object, in case it causes further fetching/faulting in its subclass method.
    OBASSERT([object isFault] == NO);
    ODOObjectAwakeSingleObjectFromFetch(object);

    OBASSERT([ctx->results count] == 1);
    OBASSERT(object == [ctx->results lastObject]);
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
    
    if (ODOLogSQL)
        ODOSQLStatementLogSQL(@"/* object fault %@ */ ", [object shortDescription]);

    ODORowFetchContext ctx;
    memset(&ctx, 0, sizeof(ctx));
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
        [NSException raise:NSObjectInaccessibleException format:NSLocalizedStringFromTableInBundle(@"Unable to fulfill fault: %@", @"OmniDataObjects", OMNI_BUNDLE, @"faulting exception"), [error toPropertyList]];
    }
}

static BOOL _fetchPrimaryKeyCallback(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError)
{
    ODORowFetchContext *ctx = context;
    
    OBASSERT(sqlite3_column_count(statement->_statement) == (int)[ctx->schemaProperties count]); // should just be the primary keys we fetched
    
    // Get the primary key
    OBASSERT(ctx->primaryKeyColumnIndex <= INT_MAX); // sqlite3 sensisibly only allows a few billion columns.
    id value = nil;
    if (!ODOSQLStatementCreateValue(sqlite, statement, (int)ctx->primaryKeyColumnIndex, &value, [ctx->primaryKeyAttribute type], [ctx->primaryKeyAttribute valueClass], outError))
        return NO;
    
    // Unique the fetch vs the registered objects.
    ODOObjectID *objectID = [[ODOObjectID alloc] initWithEntity:ctx->entity primaryKey:value];
    [value release];
    
    ODOEditingContext *editingContext = ctx->editingContext;
    
    ODOObject *object = ODOEditingContextLookupObjectOrRegisterFaultForObjectID(editingContext, objectID);
    [objectID release];
    
    // Deleted objects are now turned into faults until they are saved.  So, we drop them when fetching.
    if ([object isDeleted])
        object = nil;
    
    if (object)
        [ctx->results addObject:object];
    
    return YES;
}

static BOOL FetchSetFaultWithContext(ODOEditingContext *self, ODOObject *owner, ODORelationship *rel, ODORowFetchContext *ctx, NSError **outError)
{
    ODODatabase *database = self->_database;
    
    if (![database connectedURL] || [database isFreshlyCreated])
        // We are working in memory.  Nothing to do.
        return YES;
    
    ODOSQLStatement *query = [database _queryForDestinationPrimaryKeysByDestinationForeignKeyStatement:rel error:outError];
    if (!query)
        return NO;

    ODOObjectID *ownerID = [owner objectID];    
    id ownerPrimaryKey = [ownerID primaryKey];
    OBASSERT(ownerPrimaryKey);
    sqlite3 *sqlite = [database _sqlite];
    
    if (!PrepareQueryByKey(query, sqlite, ownerPrimaryKey, outError))
        return NO;

    ODOSQLStatementCallbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.row = _fetchPrimaryKeyCallback;

    if (!ODOSQLStatementRun(sqlite, query, callbacks, ctx, outError))
        return NO;
    
    return YES;
}

// Fetches the primary keys across the relationship, uniquing previously registered objects.  Updates the results for in progress edits and creates faults for the remainder.
NSMutableSet *ODOFetchSetFault(ODOEditingContext *self, ODOObject *owner, ODORelationship *rel)
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
    
    if (ODOLogSQL)
        ODOSQLStatementLogSQL(@"/* to-many fault %@.%@ */ ", [owner shortDescription], [rel name]);
    
    
    ODORowFetchContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.entity = [rel destinationEntity];
    ctx.instanceClass = [ctx.entity instanceClass];
    ctx.primaryKeyAttribute = [ctx.entity primaryKeyAttribute];
    ctx.schemaProperties = [NSArray arrayWithObject:ctx.primaryKeyAttribute];
    ctx.primaryKeyColumnIndex = 0;
    ctx.editingContext = self;
    ctx.results = [NSMutableArray array];
    
    NSError *error = nil;
    if (!FetchSetFaultWithContext(self, owner, rel, &ctx, &error)) {
        // CoreData raises when faulting fails.  We'd like to avoid that, but for now we'll mimic it.
        [NSException raise:NSObjectInaccessibleException format:NSLocalizedStringFromTableInBundle(@"Unable to fulfill fault: %@", @"OmniDataObjects", OMNI_BUNDLE, @"faulting exception"), [error toPropertyList]];
    }

    // TODO: Since we lazily clear the fault, we might need to treat undo specially.  For example, A->>B.  Fetch an A and a B w/o clearing the fault.  Delete the B.  Process changes.  Clear the fault (A->>Bs won't contain the B we deleted).  Undo.  If we clear the reverse fault when doing delete propagation, then this should just work if we snapshot the to-many.  But, if we snapshot the nil (lazy fault not yet created) and then undo after clearing, then the cleared set will be incorrect.
    
    // We are going to avoid clearing inverse to-many faults when updating to-one relationships.  So, the local edits need to be consulted.
    if ([self hasChanges]) {
        NSString *inverseKey = [[rel inverseRelationship] name];
        NSPredicate *predicate = ODOKeyPathEqualToValuePredicate(inverseKey, owner);
        ODOUpdateResultSetForInMemoryChanges(self, ctx.results, [rel destinationEntity], predicate);
    }
    
    return [NSMutableSet setWithArray:ctx.results];
}

@end

