// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOEditingContext.h>

#import <OmniDataObjects/ODOEditingContext-Subclass.h>
#import <OmniDataObjects/ODOFetchRequest.h>
#import <OmniDataObjects/ODOObject.h>
#import <OmniDataObjects/ODOObjectID.h>
#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/NSPredicate-ODOExtensions.h>
#import <OmniDataObjects/ODOModel.h>
#import <OmniDataObjects/Errors.h>

@import OmniBase;
@import OmniFoundation;
@import Foundation;

#import "ODOProperty-Internal.h"
#import "ODOEditingContext-Internal.h"
#import "ODOObject-Accessors.h"
#import "ODOObject-Internal.h"
#import "ODODatabase-Internal.h"
#import "ODOEntity-SQL.h"
#import "ODOSQLStatement.h"
#import "ODOInternal.h"

#if TARGET_OS_IPHONE
#import <objc/message.h>
#endif

#if 0 && defined(DEBUG)
    #define DEBUG_DELETE(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_DELETE(format, ...) do {} while (0)
#endif

#import <sqlite3.h>

RCS_ID("$Id$")

OFDeclareDebugLogLevel(ODOEditingContextOwnershipCheckingDisabled);

NS_ASSUME_NONNULL_BEGIN

@implementation ODOEditingContext
{
    // Remember the runloop we added an observer on for assertions.
    CFRunLoopRef _runLoopForObserver;
    CFRunLoopObserverRef _runLoopObserver;
}

- (instancetype)initWithDatabase:(ODODatabase *)database;
{
    OBPRECONDITION(database);
    
    if (!(self = [super init]))
        return nil;

    // TODO: Register with the database so we can ensure there is only one editing context at a time (not supporting edit merging).
    _database = [database retain];
    
    // If the database is disconnected from its file, we need to forget our contents.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_databaseConnectionDidChange:) name:ODODatabaseConnectedURLChangedNotification object:_database];
    
    _registeredObjectByID = [[NSMutableDictionary alloc] init];
    

    OBINVARIANT([self _checkInvariants]);
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(_owningQueue == NULL);
    OBPRECONDITION(_saveDate == nil);
    OBINVARIANT([self _checkInvariants]);

    // TODO: Deregister with the database so we can ensure there is only one editing context at a time (not supporting edit merging).
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ODODatabaseConnectedURLChangedNotification object:_database];
    [_database release];
    [_undoManager removeAllActionsWithTarget:self];
    [_undoManager release];

    if (_runLoopObserver) {
        [self _removeRunLoopObserver];
    }

    [_registeredObjectByID release];
    
    OBASSERT([_processedInsertedObjects count] == 0);
    OBASSERT([_processedUpdatedObjects count] == 0);
    OBASSERT([_processedDeletedObjects count] == 0);
    [_processedInsertedObjects release];
    [_processedUpdatedObjects release];
    [_processedDeletedObjects release];
    
    OBASSERT([_recentlyInsertedObjects count] == 0);
    OBASSERT([_recentlyUpdatedObjects count] == 0);
    OBASSERT([_recentlyDeletedObjects count] == 0);
    [_recentlyInsertedObjects release];
    [_recentlyUpdatedObjects release];
    [_recentlyDeletedObjects release];
    
    [_label release];
    
    [super dealloc];
}

- (void)assumeOwnershipWithQueue:(dispatch_queue_t)queue;
{
    if (ODOEditingContextOwnershipCheckingDisabled > 0) {
        return;
    }

    OBRecordBacktraceWithContext("Assume ownership", OBBacktraceBuffer_Generic, self);

    assert(_owningQueue == NULL);
    assert(queue != NULL);
    dispatch_assert_queue(queue);
    dispatch_retain(queue);
    _owningQueue = queue;
}

- (void)relinquishOwnerhip;
{
    if (ODOEditingContextOwnershipCheckingDisabled > 0) {
        return;
    }

    OBRecordBacktraceWithContext("Relinquish ownership", OBBacktraceBuffer_Generic, self);

    assert(_owningQueue != NULL);
    dispatch_assert_queue(_owningQueue);
    dispatch_release(_owningQueue);
    _owningQueue = NULL;
}

void ODOEditingContextAssertOwnership(ODOEditingContext *context)
{
    if (ODOEditingContextOwnershipCheckingDisabled > 0) {
        return;
    }
    dispatch_assert_queue(context->_owningQueue);
}

BOOL ODOEditingContextExecuteWithOwnership(ODOEditingContext *self, dispatch_queue_t temporaryOwner, BOOL (^ NS_NOESCAPE action)(void))
{
    if (ODOEditingContextOwnershipCheckingDisabled > 0) {
        return action();
    }

    // This could be done with methods above, but this will log fewer backtrace buffers and will be slightly more efficient, if it matters.
//    OBRecordBacktraceWithContext("Yield ownership", OBBacktraceBuffer_Generic, self);

    // Make sure we start out on the current owning queue and then swap in the new owner.
    // We *probably* don't need to retain the temporary owner, but will for now.
    dispatch_queue_t originalQueue = self->_owningQueue; // still retained
    dispatch_assert_queue(originalQueue);

    self->_owningQueue = temporaryOwner;
    dispatch_retain(temporaryOwner);

    // This is assumed to dispatch to the temporary owner queue to do some work and synchronously wait for the result.
    BOOL result = action();

    dispatch_release(temporaryOwner);
    self->_owningQueue = originalQueue; // still retained from above

    return result;
}

- (BOOL)executeWithTemporaryOwnership:(dispatch_queue_t)temporaryOwner operation:(BOOL (^)(void))operation;
{
    return ODOEditingContextExecuteWithOwnership(self, temporaryOwner, operation);
}

- (ODODatabase *)database;
{
    ODOEditingContextAssertOwnership(self);
    OBPRECONDITION(_database);
    return _database;
}

- (nullable NSUndoManager *)undoManager;
{
    ODOEditingContextAssertOwnership(self);
    return _undoManager;
}
- (void)setUndoManager:(nullable NSUndoManager *)undoManager;
{
    OBRecordBacktraceWithContext("Editing context", OBBacktraceBuffer_Generic, (const void *)self);
    OBRecordBacktraceWithContext("Set undo manager", OBBacktraceBuffer_Generic, (const void *)undoManager);

    ODOEditingContextAssertOwnership(self);

    if (_undoManager != nil) {
        [_undoManager removeAllActionsWithTarget:self];
        [_undoManager release];
        _undoManager = nil;
    }
    
    _undoManager = [undoManager retain];
}

- (BOOL)automaticallyProcessPendingChanges;
{
    ODOEditingContextAssertOwnership(self);
    return _runLoopObserver != NULL;
}

- (void)setAutomaticallyProcessPendingChanges:(BOOL)automaticallyProcessPendingChanges;
{
    ODOEditingContextAssertOwnership(self);
    if (automaticallyProcessPendingChanges && _runLoopObserver == NULL) {
        [self _addRunLoopObserver];
    } else if (!automaticallyProcessPendingChanges && _runLoopObserver != NULL) {
        [self _removeRunLoopObserver];
    }
}

// Empties the reciever of all objects.
- (void)reset;
{
    ODOEditingContextAssertOwnership(self);
    OBINVARIANT([self _checkInvariants]);

    // This cleanup can cause us to be deallocated if there are no other strong references
    OBRetainAutorelease(self);
    
    // Give observers a chance to clear caches of objects we are about to obliterate.  During this time, if any fetching is attempted on us, we'll return nil.  It's important to do the reset in two phases like this for the case of cascading caches; clearing cache A may invoke KVO that would cause messages to objects in cache B.  If the objects in B are already invalidated, then bad things happen.  This lets everyone shut down and then start up again.
    _isResetting = YES;
    @try {
        [[NSNotificationCenter defaultCenter] postNotificationName:ODOEditingContextWillResetNotification object:self];
        
        // Let objects know that the entire context is going away
        for (ODOObject *object in [_registeredObjectByID objectEnumerator]) {
            [object prepareForReset];
        }

        // Clear any undos we have logged
        [_undoManager removeAllActionsWithTarget:self];
        
        // get rid of pending, processed changes and snapshots
        [_objectIDToCommittedPropertySnapshot release];
        _objectIDToCommittedPropertySnapshot = nil;

        [_objectIDToLastProcessedSnapshot release];
        _objectIDToLastProcessedSnapshot = nil;
        
        [_processedInsertedObjects release];
        _processedInsertedObjects = nil;

        [_processedUpdatedObjects release];
        _processedUpdatedObjects = nil;
        
        [_processedDeletedObjects release];
        _processedDeletedObjects = nil;
        
        [_recentlyInsertedObjects release];
        _recentlyInsertedObjects = nil;
        
        [_recentlyUpdatedObjects release];
        _recentlyUpdatedObjects = nil;
        
        [_recentlyDeletedObjects release];
        _recentlyDeletedObjects = nil;
        
        [_reinsertedObjects release];
        _reinsertedObjects = nil;
        
        _nonretainedLastRecentlyInsertedObject = nil;

        // get rid of database metadata changes
        [_database _discardPendingMetadataChanges];
        
        // invalidate all registered objects
        for (ODOObject *object in [_registeredObjectByID objectEnumerator])
            [object _invalidate];
        [_registeredObjectByID removeAllObjects];

        if (_runLoopObserver) {
            [self _removeRunLoopObserver];
        }
    } @finally {
        _isResetting = NO;
    }
    
    // Give observers a chance to refill caches now that all listeners have had a chance to clear their caches.
    [[NSNotificationCenter defaultCenter] postNotificationName:ODOEditingContextDidResetNotification object:self];
}

static void ODOEditingContextInternalInsertObject(ODOEditingContext *self, ODOObject *object, ODOObjectSnapshot **outMostRecentSnapshot)
{
    OBPRECONDITION([self isKindOfClass:[ODOEditingContext class]]);
    OBPRECONDITION([object isKindOfClass:[ODOObject class]]);
    OBPRECONDITION([object editingContext] == self);
    
    OBPRECONDITION(!self->_isValidatingAndWritingChanges); // Can't make edits in the validation methods
    OBPRECONDITION(![self->_processedInsertedObjects member:object]);
    OBPRECONDITION(![self->_recentlyInsertedObjects member:object]);
    OBPRECONDITION(![self->_processedUpdatedObjects member:object]);
    OBPRECONDITION(![self->_recentlyUpdatedObjects member:object]);
    OBPRECONDITION(![self->_processedDeletedObjects member:object]);
    OBPRECONDITION(![self->_recentlyDeletedObjects member:object]);
    
    // TODO: Verify that the object being inserted isn't some old dead invalidated object (previously deleted and a save happened since then).

    // Check to see if we are re-inserting something which was previously marked for deletion
    
    ODOObject *previouslyRegisteredObject = [self->_registeredObjectByID objectForKey:[object objectID]];
    if (previouslyRegisteredObject != nil) {
        // Assert that the object we are trying to "replace" has been deleted. If this is not the case, we'll be severely messing up the lifecycle messages, so this is a hard assert.
        assert([self->_recentlyDeletedObjects containsObject:previouslyRegisteredObject] || [self->_processedDeletedObjects containsObject:previouslyRegisteredObject]);

        // This can't be a cancelled insert since those never make it into the deleted objects sets.
        // Do this before altering the sets so that -willSave will set _flags.hasStartedDeletion.
        [previouslyRegisteredObject willDelete:ODOWillDeleteEventMaterial];

        [self->_recentlyDeletedObjects removeObject:previouslyRegisteredObject];
        [self->_processedDeletedObjects removeObject:previouslyRegisteredObject];

        ODOEditingContextDidDeleteObjects(self, [NSSet setWithObject:previouslyRegisteredObject]);
        
        if (outMostRecentSnapshot != NULL) {
            // Try last-processed first, falling back to committed, since that's effectively "reverse chronological"
            ODOObjectSnapshot *mostRecentSnapshot = self->_objectIDToLastProcessedSnapshot[previouslyRegisteredObject.objectID];
            if (mostRecentSnapshot == nil) {
                mostRecentSnapshot = self->_objectIDToCommittedPropertySnapshot[previouslyRegisteredObject.objectID];
            }
            *outMostRecentSnapshot = [[mostRecentSnapshot retain] autorelease];
        }
        
        self->_objectIDToLastProcessedSnapshot[previouslyRegisteredObject.objectID] = nil;
        self->_objectIDToCommittedPropertySnapshot[previouslyRegisteredObject.objectID] = nil;
        
        // Record this object as a re-insert so we can do the right thing at save time
        
        if (self->_reinsertedObjects == nil) {
            self->_reinsertedObjects = [[NSMutableSet alloc] init];
        }
        
        [self->_reinsertedObjects addObject:object];
    }

    // Register and add it to the recent set
    
    if (self->_recentlyInsertedObjects == nil) {
        self->_recentlyInsertedObjects = ODOEditingContextCreateRecentSet(self);
    }

    [self->_recentlyInsertedObjects addObject:object];
    self->_nonretainedLastRecentlyInsertedObject = object;
    [self _registerObject:object];
}

// This is the global first-time insertion hook.  This should only be called with *new* objects.  That is, the undo of a delete should *not* go through here since that would re-call the -awakeFromInsert method.
- (void)_insertObject:(ODOObject *)object;
{
    ODOEditingContextAssertOwnership(self);
    OBINVARIANT([self _checkInvariants]);

    // We don't allow re-inserted previously deleted objects. Even on undo of a delete, we make a new object and apply a snapshot to it.
    OBASSERT(object->_flags.isFault == NO);
    OBASSERT(object->_flags.hasStartedDeletion == NO);
    OBASSERT(object->_flags.hasFinishedDeletion == NO);
    OBASSERT(object.isDeleted == NO);

    // Record the pointers of objects being inserted in case save validation fails and we need to know where it came from.
    OBRecordBacktraceWithContext(class_getName(object_getClass(object)), OBBacktraceBuffer_Generic, (const void *)object);

    // If we want an undeletable object, we need to make sure it can't be deleted via undo of this insert
    BOOL undeletable = _ODOObjectIsUndeletable(object);
    if (undeletable) {
        // Close out this undo group
        while ([self hasUnprocessedChanges])
            [self processPendingChanges];
        
        // Disable undo
        [_undoManager disableUndoRegistration];
    }
    
    @try {
        ODOObjectSnapshot *priorSnapshot = nil;
        ODOEditingContextInternalInsertObject(self, object, &priorSnapshot);
        
        OBASSERT(![object _isAwakingFromInsert]);
        [object _setIsAwakingFromInsert:YES];
        @try {
            [object awakeFromInsert];
            
            if ([_reinsertedObjects containsObject:object]) {
                [object awakeFromEvent:ODOAwakeEventReinsertion snapshot:priorSnapshot];
            }
        } @finally {
            [object _setIsAwakingFromInsert:NO];
        }
        
        // If this was to be undeletable, make sure it gets processed while undo is off
        if (undeletable) {
            while (_recentlyInsertedObjects || _recentlyUpdatedObjects || _recentlyDeletedObjects) {
                [self processPendingChanges];
            }
        }
    } @finally {
        if (undeletable)
            [_undoManager enableUndoRegistration];
    }
    
    OBINVARIANT([self _checkInvariants]);
}

static void _addNullify(ODOObject *owner, NSString *toOneKey, NSMutableDictionary *relationshipsToNullifyByObjectID)
{
    OBPRECONDITION(owner);
    OBPRECONDITION(toOneKey);
    OBPRECONDITION([[[owner entity] relationshipsByName] objectForKey:toOneKey]);
    OBPRECONDITION([[[[owner entity] relationshipsByName] objectForKey:toOneKey] isToMany] == NO);
    OBPRECONDITION(relationshipsToNullifyByObjectID);
    
    ODOObjectID *ownerID = [owner objectID];
    NSMutableArray *keys = [relationshipsToNullifyByObjectID objectForKey:ownerID];
    if (!keys) {
        keys = [[NSMutableArray alloc] initWithObjects:&toOneKey count:1];
        [relationshipsToNullifyByObjectID setObject:keys forKey:ownerID];
        [keys release];
    } else
        [keys addObject:toOneKey];
}

// Adds a note that object.rel->dest would deny.
static void _addDenyNote(ODOObject *object, ODORelationship *rel, ODOObject *dest, NSMutableDictionary *denyObjectIDToReferer)
{
    OBPRECONDITION(object);
    OBPRECONDITION(rel);
    OBPRECONDITION(dest);
    OBPRECONDITION(denyObjectIDToReferer);
    OBPRECONDITION([object editingContext] == [dest editingContext]);
    OBPRECONDITION([object entity] == [rel entity]);
    OBPRECONDITION([rel destinationEntity] == [dest entity]);
    OBPRECONDITION([rel deleteRule] == ODORelationshipDeleteRuleDeny);
    
    // We are unable to delete object due to the presence of 'dest' across the relationship 'rel'.  Make a note of this for later.
    // If there are multiple reasons to deny the deletion of 'object', only the last one will be noted for now.
    // Note that the object that is the cause of the deny is the one used for the key; the one being denied is in the value.  This makes it easy to clean up the case where the cause-of-deny object was deleted already.
    NSArray *info = [[NSArray alloc] initWithObjects:[rel name], [object objectID], nil];
    [denyObjectIDToReferer setObject:info forKey:[dest objectID]];
    [info release];
}


typedef struct {
    ODOEditingContext *self;
    BOOL fail;
    NSError * _Nullable error;
    NSMutableSet *toDelete;
    NSMutableDictionary *relationshipsToNullifyByObjectID;
    NSMutableDictionary *denyObjectIDToReferer;
} TraceForDeletionContext;

static void _traceForDeletion(ODOObject *object, TraceForDeletionContext *ctx);

static void _traceToManyRelationship(ODOObject *object, ODORelationship *rel, TraceForDeletionContext *ctx)
{
    OBPRECONDITION([rel isToMany]);
    
    // This is what to do to the *destination* of the relationship
    ODORelationshipDeleteRule rule = [rel deleteRule];

    ODORelationship *inverseRel = [rel inverseRelationship];
    NSString *forwardKey = [rel name];
    NSString *inverseKey = [inverseRel name];

    if (rule == ODORelationshipDeleteRuleDeny) {
        OBASSERT([inverseRel isToMany] == NO); // We don't allow many-to-many relationships in the model loading code
        OBFinishPorting; // Handle once we have a test case
    }

    BOOL alsoCascade;
    if (rule == ODORelationshipDeleteRuleNullify) {
        alsoCascade = NO;
    } else if (rule == ODORelationshipDeleteRuleCascade) {
        alsoCascade = YES;
    } else {
        OBASSERT_NOT_REACHED("Expected to identify the delete rule in question"); // unknown delete rule
    }
    
    // Nullify all the inverse to-ones.
    OBASSERT([inverseRel isToMany] == NO); // We don't allow many-to-many relationships in the model loading code
    OBASSERT([inverseRel isCalculated] == NO); // since the to-many is effectively calculated from the to-one, this would be silly.

    NSSet *targets = [object valueForKey:forwardKey];
    OBASSERT([targets isKindOfClass:[NSSet class]]);
    
    for (ODOObject *target in targets) {
        if (![inverseRel isCalculated])
            _addNullify(target, inverseKey, ctx->relationshipsToNullifyByObjectID);
        if (alsoCascade && !_ODOObjectIsUndeletable(target))
            _traceForDeletion(target, ctx);
    }
}

static void _traceToOneRelationship(ODOObject *object, ODORelationship *rel, TraceForDeletionContext *ctx)
{
    OBPRECONDITION(![rel isToMany]);
    
    // This is what to do to the *destination* of the relationship
    ODORelationshipDeleteRule rule = [rel deleteRule];

    ODORelationship *inverseRel = [rel inverseRelationship];
    NSString *forwardKey = [rel name];
    NSString *inverseKey = [inverseRel name];
    
    if (rule == ODORelationshipDeleteRuleNullify) {
        if ([inverseRel isToMany]) {
            // We have a to-one and we need to remove ourselves from the inverse to-many. In the past, we used to force clearing the inverse to-many fault, even if our to-one itself was a fault. But, if our to-one is still a fault, it can't hold a reference back to us (and any future fetches will get filtered vs. the deleted objects). Forcing the inverse to-many to be cleared may not be necessary here either.
            ODOObject *dest = [object valueForKey:forwardKey];
            if (dest) {
                if (![dest isFault]) {
#ifdef OMNI_ASSERTIONS_ON
                    NSSet *inverseSet =
#endif
                    [dest valueForKey:inverseKey]; // clears the fault
                    OBASSERT([inverseSet member:object] == object);
                }
                
                _addNullify(object, forwardKey, ctx->relationshipsToNullifyByObjectID);
            }
        } else {
            // one-to-one relationship. one side should be marked as calculated.
            OBASSERT([rel isCalculated] || [inverseRel isCalculated]);
            
            ODOObject *dest = [object valueForKey:forwardKey];
            if (dest) {
                // nullify the side that isn't calculated.  we could maybe not do the nullify it is is the forward relationship (since the owner is getting entirely deleted).
                if (![rel isCalculated])
                    _addNullify(object, forwardKey, ctx->relationshipsToNullifyByObjectID);
                if (![inverseRel isCalculated])
                    _addNullify(dest, inverseKey, ctx->relationshipsToNullifyByObjectID);
            }
        }
        return;
    }
    
    // We treat cascading a delete onto an undeletable object as a nullify instead.
    // Also, when cascading will nullify to-one relationships too. This ensures that any KVO registrations can be cleaned up properly.
    if (rule == ODORelationshipDeleteRuleCascade) {
        ODOObject *dest = [object valueForKey:forwardKey];
        if (dest) {
            if (![rel isCalculated])
                _addNullify(object, forwardKey, ctx->relationshipsToNullifyByObjectID);
            if (!_ODOObjectIsUndeletable(dest))
                _traceForDeletion(dest, ctx);
        }
        return;
    }
    
    if (rule == ODORelationshipDeleteRuleDeny) {
        ODOObject *dest = [object valueForKey:forwardKey];
        if (dest)
            _addDenyNote(object, rel, dest, ctx->denyObjectIDToReferer);
        return;
    }
    
    OBASSERT_NOT_REACHED("Expected to identify the delete rule in question"); // unknown delete rule
}

static void _traceForDeletion(ODOObject *object, TraceForDeletionContext *ctx)
{
    OBPRECONDITION(!_ODOObjectIsUndeletable(object));

    // Someone already failed?
    if (ctx->fail)
        return;
    
    // Avoid problems with cycles
    if ([ctx->toDelete member:object])
        return;
    
    [ctx->toDelete addObject:object];
    
    ODOEntity *entity = [object entity];
    NSArray *relationships = [entity relationships];
    for (ODORelationship *rel in relationships) {        
        if ([rel isToMany])
            _traceToManyRelationship(object, rel, ctx);
        else
            _traceToOneRelationship(object, rel, ctx);
        if (ctx->fail)
            return; // no point going on.
    }
}

// Turns out none of our objects implement -validateForDelete: right now.
#if 0
typedef struct {
    BOOL failed;
    NSError *error;
} ValidateForDeleteApplierContext;

static void _validateForDeleteApplier(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    ValidateForDeleteApplierContext *ctx = context;
    
    if (ctx->failed)
        return;
    
    if (![object validateForDelete:&ctx->error])
        ctx->failed = YES;
}
#endif

- (void)_snapshotObjectForDeletion:(ODOObject *)object;
{
    // Reject if object is undeletable... should not have gotten this far. This means all undeletable objects must be inserted w/o undo enabled or having undo flushed afterwards.
    if (_ODOObjectIsUndeletable(object))
        OBRejectInvalidCall(self, _cmd, @"Undeletable objects should not be deleted!");
    
#ifdef OMNI_ASSERTIONS_ON
    // All the to-one relationships must be nil at this point. Otherwise, observation across a keyPath won't trigger due to objects along that keyPath being deleted and we might leak observation info.  Additionally, when a 'did delete' notification goes out and the observer removes its observed keyPath, the crossings of to-one relationships can return nil and be correct w/o asserting about asserting that we aren't doing KVC on deleted objects.
    for (ODORelationship *rel in object.entity.toOneRelationships) {
        ODOObject *destination = _ODOObjectGetObjectValueForProperty(object, rel);
        OBASSERT(destination == nil);
    }
#endif
    
    // Might have been snapshotted if we had a recent or processed update. Since we are about to delete it, it is already in the _recentlyDeletedObjects set and has been remove from _recentlyUpdatedObjects.
    // OBASSERT(([_objectIDToCommittedPropertySnapshot objectForKey:[object objectID]] == nil && [_objectIDToLastProcessedSnapshot objectForKey:[object objectID]] == nil) == ([_recentlyUpdatedObjects member:object] == nil && [_processedUpdatedObjects member:object] == nil));
    
    [self _snapshotObjectPropertiesIfNeeded:object];

    // We used to turn deleted objects into faults here and release all their properties. But SwiftUI Views that are given access to ODOObjects can end up being evaluated  again unpredictably, causing crashes that are difficult to solve. Instead, deleted objects now are left with their properties intact and relationships cleared (firing KVO to clean up dependent key path observations, but *not* propagating those changes to the ObjectWillChangePublisher and possibly provoking more View evaluations).
}

static void _removeDenyApplier(const void *value, void *context)
{
    ODOObject *deletedObject = (ODOObject *)value;
    NSMutableDictionary *denyObjectIDToReferer = (NSMutableDictionary *)context;
    [denyObjectIDToReferer removeObjectForKey:[deletedObject objectID]];
}

static void _nullifyRelationships(const void *dictKey, const void *dictValue, void *context)
{
    ODOObjectID *objectID = (ODOObjectID *)dictKey;
    NSArray *toOneKeys = (NSArray *)dictValue;
    TraceForDeletionContext *ctx = context;
    
    DEBUG_DELETE(@"DELETE: nullify %@ %@", [objectID shortDescription], toOneKeys);
    
    ODOObject *object = [ctx->self->_registeredObjectByID objectForKey:objectID];
    OBASSERT(object != nil);
    if (object == nil) {
        return;
    }
        
    // Any objects that were to get relationships nullified don't need to be nullified if they are also getting deleted.
    // Actually, this is false.  If we have an to-one, we need to nullify it so that the inverse to-many has a KVO cycle.  Otherwise, the to-many holder won't get in the updated set, or advertise its change.  Also, we need to publicize the to-one going to nil so that multi-stage KVO keyPath observations will stop their subpath observing.
    
    //if ([ctx->toDelete member:object])
    //return;

    NSMutableSet<ODORelationship *> *toOneRelationships = [NSMutableSet set];
    NSDictionary<NSString *, ODORelationship *> *relationshipsByName = object.entity.relationshipsByName;
    
    for (NSString *key in toOneKeys) {
        ODORelationship *relationship = relationshipsByName[key];
        OBASSERT(relationship != nil);
        OBASSERT([relationship isToMany] == NO);
        if (relationship != nil && ![relationship isToMany]) {
            [toOneRelationships addObject:relationship];
        }
    }

    [object willNullifyRelationships:toOneRelationships];

    for (ODORelationship *rel in toOneRelationships) {
        NSString *key = rel.name;
        
        // If we are getting deleted, then use the internal path for clearing the forward relationship instead of calling the setter. But, if we are going to stick around (we are on the fringe of the delete cloud), call the setter.
        if ([ctx->toDelete member:object]) {
            [object willChangeValueForKey:key];
            ODOObjectSetPrimitiveValueForProperty(object, nil, rel);
            [object didChangeValueForKey:key];
        } else {
            [object setValue:nil forKey:key];
        }
    }
    
    [object didNullifyRelationships:toOneRelationships];
}

// This just registers the deletes and gathers snapshots for them.  Used both in the public API and in the undo support
static void ODOEditingContextInternalDeleteObjects(ODOEditingContext *self, NSSet *toDelete)
{
    DEBUG_DELETE(@"DELETE: internal delete %@", [toDelete setByPerformingSelector:@selector(shortDescription)]);

    // Before calling out to our observer with the "will be deleted" notification, add the object we're deleting to our set of recently deleted objects--and remove it from our recently updated objects.  This means that it's safe for the observer to call -processPendingChanges without getting a bogus "object changed" notification.
    // (In <bug:///98546> (Crash updating forecast/inbox badge after sync? -[HomeController _forecastCount]), the observer was the OFMLiveFetch for overdue objects, and it removed the deleted object from its object set.  Great, this is what we want.  This fired off the OFMLiveFetchObjectsBinding, which was seen by HomeController and triggered a refresh of the badges for visible nodes.  HomeController was asking AppController for the set of overdue tasks.  Still, so far so good.  But then -overdueTasks was calling back to our -processPendingChanges which was firing off a notification which included this deleted object in its update set (failing an assertion, since this method was supposed to guarantee that couldn't happen).  So then the OFMLiveFetch for overdue tasks saw the update for our not-yet-deleted object, and added it back to its set.  After -processPendingChanges returned, -overdueTasks tried to sort the returned task by due date and hit this deleted object and... kaboom!)
    if (!self->_recentlyDeletedObjects)
        self->_recentlyDeletedObjects = ODOEditingContextCreateRecentSet(self);
    
    // Before this, the objects shouldn't claim to be deleted.
#ifdef OMNI_ASSERTIONS_ON
    for (ODOObject *object in toDelete)
        OBASSERT(![object isDeleted]);
#endif
    
    // Still shouldn't have any insertions, but we might have some locally created updates.  Some of these may now be overridden by our deletions (but the updates to their inverses won't be).
    OBASSERT(!self->_recentlyInsertedObjects);
    [self->_recentlyDeletedObjects unionSet:toDelete];
    [self->_recentlyUpdatedObjects minusSet:toDelete];

    // Now they should so that observers of the notification can't remove objects in response to the notification, then trigger a fetch that would find the objects and accidentally re-add them. A possibly better long-term fix for this would be to have a pending-deletes list that we'd use to filter fetches and such.
#ifdef OMNI_ASSERTIONS_ON
    for (ODOObject *object in toDelete) {
        OBASSERT([object isDeleted]);
        OBASSERT([self _isBeingDeleted:object]);
    }
#endif
    
    // If someone calls back into -processPendingChanges, we're going to try to register undos for objects from our set of recently deleted objects.  Those undos will need to reference snapshots, so we'd better add those snapshots now.  Fixes <bug:///99138> (Regression: Exception when trying to syncing after deleting an inbox task (Assert failed: requires snapshot) [_registerUndoForRecentChanges]).
    for (ODOObject *object in toDelete) {
        // Record the pointers of objects being deleted in case someone accesses one soon and crashes
        OBRecordBacktraceWithContext(class_getName(object_getClass(object)), OBBacktraceBuffer_Generic, (const void *)object);

        [self _snapshotObjectPropertiesIfNeeded:object];
    }
    
    // Some objects (I'm looking at you NSArrayController) are dumb as posts and if you clear their content, they'll ask their old content questions like, "Hey; what's your value for this key?".  That doesn't work well for deleted objects.  CoreData has some hack into NSArrayController to avoid this, we need something of the like.  For now we'll post a note before finalizing the deletion.

    NSDictionary *userInfo = _createChangeSetNotificationUserInfo(nil, nil, toDelete, self->_objectIDToCommittedPropertySnapshot, self->_objectIDToLastProcessedSnapshot);
    [[NSNotificationCenter defaultCenter] postNotificationName:ODOEditingContextObjectsWillBeDeletedNotification object:self userInfo:userInfo];
    [userInfo release];
    
    for (ODOObject *object in toDelete) {
        [self _snapshotObjectForDeletion:object];
    }
}

// Since we do delete propagation immediately, and since there is no other good point, we have an out NSError argument here for the results from -validateForDelete:.
- (BOOL)deleteObject:(ODOObject *)object error:(NSError **)outError;
{
    ODOEditingContextAssertOwnership(self);
    DEBUG_DELETE(@"DELETE: object:%@", [object shortDescription]);
    
    OBINVARIANT([self _checkInvariants]);
    OBPRECONDITION(!_isValidatingAndWritingChanges); // Can't make edits in the validation methods
    OBPRECONDITION(!_isDeletingObjects);
    OBPRECONDITION(object);
    OBPRECONDITION([object editingContext] == self);
    OBPRECONDITION([_registeredObjectByID objectForKey:[object objectID]] == object); // has to be registered
    OBPRECONDITION(![_undoManager isUndoingOrRedoing]); // this public API shouldn't be called to undo/redo.  Only to 'do'.

    // Bail on objects that are already deleted or invalid instead of crashing.  This can easily happen if UI code can select both a parent and child and delete them w/o knowing that the deletion of the parent will get the child too.  Nice if the UI handles it, but shouldn't crash or do something crazy otherwise.
    if (!object) {
        DEBUG_DELETE(@"DELETE: given nil object");
        return YES; // maybe return a user-cancelled error?
    }
    if (object.hasBeenDeletedOrInvalidated) {
        DEBUG_DELETE(@"DELETE: %@ already invalid:%d deleted:%d hasStartedDeletion:%d hasFinishedDeletion:%d -- bailing", [object shortDescription], [object isInvalid], [object isDeleted], object->_flags.hasStartedDeletion, object->_flags.hasFinishedDeletion);
        return YES; // maybe return a user-cancelled error?
    }
    
    if (_ODOObjectIsUndeletable(object)) {
        // Whether this is right is debatable.  Maybe we should do the deletion as normal with propagation nullifying the relationships.  On the down side, that could result in no updates and just nullifications (but we have the problem of -prepareForDeletion doing edits when the deletion is rejected anyway...)
        // Returning a user-cancelled error here since, unlike the the invalid/deleted case, we return with 'object' still being live.
        DEBUG_DELETE(@"DELETE: undeletable -- bailing");
        OBUserCancelledError(outError);
        return NO;
    }
    
    OBASSERT(!object.hasBeenDeletedOrInvalidated);
    OBASSERT([_processedDeletedObjects member:object] == nil); // can't be deleted already
    OBASSERT([_recentlyDeletedObjects member:object] == nil); // or recently

    // Inform the object being deleted.  It can update itself or any related object, possibly to avoid delete propagation, so do this before tracing relationships.
    [object prepareForDeletion];
    
    // See below; we can't have any unprocessed inserts or updates.  Any updates from the -prepareForDeletion above would be fine, but they'd confuse our assertions.
    while (_recentlyInsertedObjects || _recentlyUpdatedObjects) {
        DEBUG_DELETE(@"DELETE: processing pending changes...");
        [self processPendingChanges];
    }
    OBASSERT(!_recentlyInsertedObjects);
    OBASSERT(!_recentlyUpdatedObjects);

    _isDeletingObjects = YES;
    
    @try {
        // We do delete propagation immediately rather than delaying it until -processPendingChanges.  Not 100% sure what CoreData does.  For now, only the externally initialized delete will go through public API.  That is, subclasses won't get a -deleteObject: for propagated deletes.
        
        // Trace the object graph figuring out what we need to cascade, nullify and deny.  This operation should make NO changes in case there is an error detected.
        TraceForDeletionContext ctx;
        memset(&ctx, 0, sizeof(ctx));
        ctx.self = self;
        ctx.toDelete = [NSMutableSet set]; // Objects that have been cascaded
        ctx.relationshipsToNullifyByObjectID = [NSMutableDictionary dictionary]; // objectID -> array of to-one relationship keys
        ctx.denyObjectIDToReferer = [NSMutableDictionary dictionary];

        ctx.error = nil;
        
        _traceForDeletion(object, &ctx);
        if (ctx.fail) {
            if (outError != NULL)
                *outError = ctx.error;
            return NO;
        }
        DEBUG_DELETE(@"DELETE: toDelete: %@", [ctx.toDelete setByPerformingSelector:@selector(shortDescription)]);
        DEBUG_DELETE(@"DELETE: relationshipsToNullifyByObjectID: %@", ctx.relationshipsToNullifyByObjectID);
        DEBUG_DELETE(@"DELETE: denyObjectIDToReferer: %@", ctx.denyObjectIDToReferer);
        
        // Before making any changes, check for deny.  CoreData had deletions supercedeing deny.  That is, if we have (not so hypoteticalliy) a one-to-one between Project and Task with Project->Task being cascade and Task->Project being deny, then if we start the delete at Project, we'll then cascade to Task and find a deny pointing back to Project.  We'll make a note of this when tracing the object graph.  But, since the Project is getting deleted, we'll ignore the deny.  Thus, deny only applies if the object being denied isn't getting deleted.
        if ([ctx.denyObjectIDToReferer count] > 0) {
            CFSetApplyFunction((CFSetRef)ctx.toDelete, _removeDenyApplier, ctx.denyObjectIDToReferer);
            
            // If there are still denies in place, log an error and bail
            if ([ctx.denyObjectIDToReferer count] > 0) {
                OBRequestConcreteImplementation(self, _cmd);
            }
        }

        // Before nullifying relationships and marking the objects as deleted, post an early notification for observers that want to be notified before these changes.
        [[NSNotificationCenter defaultCenter] postNotificationName:ODOEditingContextObjectsPreparingToBeDeletedNotification object:self userInfo:@{ODODeletedObjectsKey:ctx.toDelete}];

        // Turns out none of our objects implement -validateForDelete: right now.
    #if 0
        // Validate deletion of all the objects that got collected.  Note that the objects and their neighbors will be in their pre-deletion state.
        // TODO: Need a general 'disallow edits' flag.  -validateForDelete: should not add more edits.
        OBASSERT([toDelete count] >= 1);
        ValidateForDeleteApplierContext ctx;
        memset(&ctx, 0, sizeof(ctx));
        CFSetApplyFunction((CFSetRef)toDelete, _validateForDeleteApplier, &ctx);
        if (ctx.failed) {
            if (outError)
                *outError = ctx.error;
            return NO;
        }
    #endif
        
        // We CANNOT have recent insertions or updates, as it turns out.  If we do, then someone who has fetched against us, and gotten back a match due to in-memory updates of results sets, will be confused if we don't send a deletion notification.  So, above, we've called -processPendingChanges to ensure that everything has been notified and flattened into the processed changes.  After the _nullifyRelationships application, though, we will likely have recently updated objects.
        OBASSERT(!_recentlyInsertedObjects);
        OBASSERT(!_recentlyUpdatedObjects);
        
        // Take a snapshot of this object, if needed, before nullifying relationships and deleting
        [self _snapshotObjectPropertiesIfNeeded:object];
        
        CFDictionaryApplyFunction((CFDictionaryRef)ctx.relationshipsToNullifyByObjectID, _nullifyRelationships, &ctx);
        
        ODOEditingContextInternalDeleteObjects(self, ctx.toDelete);
        
        OBINVARIANT([self _checkInvariants]);
    } @finally {
        _isDeletingObjects = NO;
    }

    return YES;
}

static void ODOEditingContextDidDeleteObjects(ODOEditingContext *self, NSSet *deleted)
{
    // We used to also call _invalidate on deleted objects, but do not any longer to allow SwiftUI Views to access their values.

    NSMutableDictionary *objectByID = self->_registeredObjectByID;

    for (ODOObject *object in deleted) {
        // Mark the object as having finished deletion. Property changes past this point will be ignored and produce an assertion failure.
        OBASSERT(object->_flags.hasStartedDeletion);
        OBASSERT(!object->_flags.hasFinishedDeletion);
        object->_flags.hasFinishedDeletion = 1;

        // Forget the deleted object.
        ODOObjectID *objectID = [object objectID];
        OBASSERT([objectByID objectForKey:objectID] == object);
        [objectByID removeObjectForKey:objectID];

        // Clear its backpointer to us. We used to get this from calling -_invalidate.
        [object->_editingContext release];
        object->_editingContext = nil;

        // Clients should hear about the deletion viw KVO/notifications or the like and should have no reason to keep this object
        OBExpectDeallocation(object);
    }
}

static NSDictionary *_createChangeSetNotificationUserInfo(NSSet * _Nullable insertedObjects, NSSet * _Nullable updatedObjects, NSSet * _Nullable deletedObjects, NSDictionary <ODOObjectID *, ODOObjectSnapshot *> *committedPropertySnapshotByObjectID, NSDictionary <ODOObjectID *, ODOObjectSnapshot *> *lastProcessedPropertySnapshotByObjectID)
{
    // Making copies of these sets since we mutate _recentlyUpdatedObjects below while merging (at least for the call from -_internal_processPendingChanges
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];

    if (insertedObjects != nil) {
        NSSet *set = [insertedObjects copy];
        userInfo[ODOInsertedObjectsKey] = set;
        [set release];
    }
    
    if (updatedObjects != nil) {
        NSSet *set = [updatedObjects copy];
        userInfo[ODOUpdatedObjectsKey] = set;
        [set release];
        
        // Build a subset of the objects that have material edits.
        NSMapTable *materiallyUpdatedValues = nil;
        for (ODOObject *object in updatedObjects) {
            // Might be called for a recent update of a processed insert and -changedNonDerivedChangedValue currently does OBRequestConcreteImplementation() for inserted objects since its meaning is unclear in general.  Here we'll contend that an 'insert' is a material update (even if no recent updates are material).
            if ([object isInserted] || [object hasChangedNonDerivedChangedValue]) {
                if (materiallyUpdatedValues == nil) {
                    materiallyUpdatedValues = [NSMapTable strongToStrongObjectsMapTable];
                }
                
                [materiallyUpdatedValues setObject:[object changedNonDerivedValues] forKey:object];
#if 0 && defined(DEBUG_bungi)
                NSLog(@"material update to %@: %@", [object shortDescription], [object isInserted] ? (id)object : (id)[object changedValues]);
#endif
            } else {
#if 0 && defined(DEBUG_bungi)
                NSLog(@"dropping phantom update to %@; changes = %@", [object shortDescription], [object changedValues]);
#endif
            }
        }
        
        if (materiallyUpdatedValues != nil) {
            userInfo[ODOMateriallyUpdatedObjectPropertiesKey] = materiallyUpdatedValues;
            
            NSSet *materialUpdates = [NSSet setByEnumerating:[materiallyUpdatedValues keyEnumerator]];
            userInfo[ODOMateriallyUpdatedObjectsKey] = materialUpdates;
        }
    }
    
    if (deletedObjects != nil) {
        NSSet *set = [deletedObjects copy];
        userInfo[ODODeletedObjectsKey] = set;
        
        NSMutableDictionary *deletedSnapshots = [[NSMutableDictionary alloc] init];
        for (ODOObject *deletedObject in set) {
            ODOObjectID *deletedID = deletedObject.objectID;
            ODOObjectSnapshot *snapshot = lastProcessedPropertySnapshotByObjectID[deletedID];
            if (snapshot == nil) {
                snapshot = committedPropertySnapshotByObjectID[deletedID];
            }
            
            deletedSnapshots[deletedID] = snapshot;
        }

        userInfo[ODODeletedObjectPropertySnapshotsKey] = deletedSnapshots;

        [deletedSnapshots release];
        [set release];
    }
    
    return userInfo;
}

// The 'processed' ivars have the sets of objects that have been registered in the undo manager and had change notifications posted regarding their state changes.  Here we move recent changes to the processed state, logging undos and notifications.  Returns YES if there were any recent changes, NO otherwise.
- (BOOL)_internal_processPendingChanges;
{
    // NOTE: We can't delay delete propagation to here since OmniFocusModel depends on immediate delete propagation.  -[OFMTreeObject _updateChildrenCounts] used to call -processPendingChanges to force delete propagation, but that could cause recursive calls to -processPendingChanges.  Since we delete immediately, this isn't necessary in OmniDataObjects.
    
    // TODO: Notify all the objects that are about to be processed (something that CoreData doesn't do).  We can use this to calclate summarized values before the ODOEditingContextObjectsDidChangeNotification notification goes out to listeners that might want to read them.
    
    // TODO: Handle the case where an object is inserted, processed, updated, deleted.  That is -deleteObject: should prune objects from the recent updates so that -isUpdated and -updatedObjects don't have to consider that (and we don't need/want the undo/notification to have an object in both the updated and deleted sets).

    // Send notifications for inserts, updates and deletes based on the pending edits (i.e., a previously inserted object can be the subject of a update notification and a previous insert/update can be the subject of a delete).    
    NSDictionary *userInfo = _createChangeSetNotificationUserInfo(_recentlyInsertedObjects, _recentlyUpdatedObjects, _recentlyDeletedObjects, _objectIDToCommittedPropertySnapshot, _objectIDToLastProcessedSnapshot);
    NSNotification *notification = [NSNotification notificationWithName:ODOEditingContextObjectsDidChangeNotification object:self userInfo:userInfo];
    [userInfo release];

    // Register undos based on the recent changes, if we have an undo manager, along with any snapshots necessary to get back into the right state after undoing.
    // TODO: Record only the object IDs and snapshots?
    // TODO: These snapshots aren't right -- they are from the last *save* but we need snapshots from the last -processPendingChanges.
    if (_undoManager != nil) {
        [self _registerUndoForRecentChanges];
    }
    
    //
    // Merge the recent changes into the processed changes.
    //
    
    // Our recent snapshots can be thrown away (any time after the undo is logged really).  In fact, maybe we shouldn't keep this if we don't have an undo manager/on iPhone.
    [_objectIDToLastProcessedSnapshot release];
    _objectIDToLastProcessedSnapshot = nil;
    
    // Any updates that are to processed inserts (i.e., an object was inserted, changes processed and then updated) are irrelevant as far as -save: is concerned (though undo and notifications care above).
    [_recentlyUpdatedObjects minusSet:_processedInsertedObjects];
    
    // Any previously processed inserts or updates that have recently been deleted are also now irrelevant for -save:.
    if (_recentlyDeletedObjects != nil) {
        // Also, any processed inserts are irrelevant for -save:.  That is, the processed insert and recent delete cancel out.
        // TODO: We don't actually allow re-inserts and should clean out lingering support for it.
        // However, if the processed insert was actual a re-insert, the delete does not cancel it out; we must preserve the delete as a material delete.
        if ([_processedInsertedObjects intersectsSet:_recentlyDeletedObjects]) {
            // Anything that was inserted, but not reinserted can just be cancelled; a material delete is not required
            NSMutableSet *cancelledInserts = [[NSMutableSet alloc] initWithSet:_recentlyDeletedObjects];
            [cancelledInserts intersectSet:_processedInsertedObjects];
            [cancelledInserts minusSet:_reinsertedObjects];

            for (ODOObject *object in cancelledInserts) {
                [object willDelete:ODOWillDeleteEventCancelledInsert];
            }

            // Anything that was re-inserted must be preserved as a material delete
            NSMutableSet *uncancellableInserts = [[NSMutableSet alloc] initWithSet:_recentlyDeletedObjects];
            [uncancellableInserts intersectSet:_reinsertedObjects];

            // Cancelled inserts are no longer inserted or deleted
            [_recentlyDeletedObjects minusSet:cancelledInserts];
            [_processedInsertedObjects minusSet:cancelledInserts];

            // Both cancelled and uncancelled inserts are no longer reinserted.
            // This is most clearly expressed as:
            //
            //    [_reinsertedObjects minusSet:cancelledInserts];
            //    [_reinsertedObjects minusSet:uncancellableInserts];
            //
            // but can be expressed as this single set operation as long as it is done before mutating _recentlyDeletedObjects
            [_reinsertedObjects minusSet:_recentlyDeletedObjects];

            // Uncancellable inserts are no longer inserted, but do stick around as material deletes
            [_processedInsertedObjects minusSet:uncancellableInserts];
            [_recentlyDeletedObjects unionSet:uncancellableInserts];


            // These canceled inserts are now gone forever!  Update our state the same as if we'd saved the deletes
            ODOEditingContextDidDeleteObjects(self, cancelledInserts);
            
            [cancelledInserts release];
            [uncancellableInserts release];
        }
        
        [_processedUpdatedObjects minusSet:_recentlyDeletedObjects];
    }
    
    // Any remaining recent operations should merge right across.  If we didn't have changes in a category, steal the recent set rather than building a new one.
    _nonretainedLastRecentlyInsertedObject = nil;

    if (_processedInsertedObjects) {
        [_processedInsertedObjects unionSet:_recentlyInsertedObjects];
    } else  {
        _processedInsertedObjects = _recentlyInsertedObjects;
        _recentlyInsertedObjects = nil;
    }
    
    if (_processedUpdatedObjects) {
        [_processedUpdatedObjects unionSet:_recentlyUpdatedObjects];
    } else {
        _processedUpdatedObjects = _recentlyUpdatedObjects;
        _recentlyUpdatedObjects = nil;
    }
    
    if (_processedDeletedObjects) {
        [_processedDeletedObjects unionSet:_recentlyDeletedObjects];
    } else {
        _processedDeletedObjects = _recentlyDeletedObjects;
        _recentlyDeletedObjects = nil;
    }
    
    [_recentlyInsertedObjects release];
    _recentlyInsertedObjects = nil;

    [_recentlyUpdatedObjects release];
    _recentlyUpdatedObjects = nil;
    
    [_recentlyDeletedObjects release];
    _recentlyDeletedObjects = nil;

    OBINVARIANT([self _checkInvariants]);

    // As our final act, post the notification (since we have now processed the changes).  Additionally, this means that listeners can provoke further changes.
    //NSLog(@"note = %@", note);

    _objectDidChangeCounter++;
    [[NSNotificationCenter defaultCenter] postNotification:notification];
    
    return YES;
}

- (BOOL)processPendingChanges;
{
    ODOEditingContextAssertOwnership(self);
    OBINVARIANT([self _checkInvariants]);
    OBPRECONDITION(!_isSendingWillSave); // See -_sendWillSave:
    OBPRECONDITION(!_isValidatingAndWritingChanges); // Can't call -processPendingChanges while validating.  Would be pointless anyway since it has already been called and we don't allow making edits paste -_sendWillSave:
    OBPRECONDITION(!_isDeletingObjects); // Don't call this while inside a delete handler because it causes us to turn objects into faults before we're done with the delete work and validation.
    OBPRECONDITION(![_recentlyInsertedObjects intersectsSet:_recentlyUpdatedObjects]);
    OBPRECONDITION(![_recentlyInsertedObjects intersectsSet:_recentlyDeletedObjects]);
    OBPRECONDITION(![_recentlyUpdatedObjects intersectsSet:_recentlyDeletedObjects]);
    
    @autoreleasepool {
        if (!_recentlyInsertedObjects && !_recentlyUpdatedObjects && !_recentlyDeletedObjects)
            return NO;
        
        OBASSERT(_inProcessPendingChanges == NO);
        
        BOOL success = YES;
        _inProcessPendingChanges = YES;
        @try {
            success = [self _internal_processPendingChanges];
        } @finally {
            _inProcessPendingChanges = NO;
        }
        return success;
    }
}

// These reflect the total current set of unsaved edits, including unprocessed changes.  Note that since we need to send 'updated' notifications when an inserted object gets further edits, the recently updated set might contain inserted objects.  This doesn't mean the object is in the inserted state as far as what will happen when -save: is called, though.
- (NSSet *)insertedObjects;
{
    ODOEditingContextAssertOwnership(self);

    if (!_recentlyInsertedObjects && !_recentlyDeletedObjects) {
        if (!_processedInsertedObjects)
            return [NSSet set]; // return nil, or at least a shared instance?
        return [NSSet setWithSet:_processedInsertedObjects];
    }
    
    NSMutableSet *result = [NSMutableSet setWithSet:_processedInsertedObjects];
    [result unionSet:_recentlyInsertedObjects];
    [result minusSet:_recentlyDeletedObjects];

    return result;
}

// This one is tricky since, as noted above, the recent updates might include objects that are really inserted.
- (NSSet *)updatedObjects;
{
    ODOEditingContextAssertOwnership(self);

    if (!_recentlyUpdatedObjects && !_recentlyDeletedObjects) {
        if (!_processedUpdatedObjects)
            return [NSSet set]; // return nil, or at least a shared instance?
        return [NSSet setWithSet:_processedUpdatedObjects];
    }
    
    // Here is the canonical fallback case.  Note that we don't consider the recent inserts since we only allow processed inserts to be recently updated (so we can send the updated notification)
    NSMutableSet *result = [NSMutableSet setWithSet:_processedUpdatedObjects];
    [result unionSet:_recentlyUpdatedObjects]; // might contain inserts
    [result minusSet:_processedInsertedObjects]; // ... which we now remove
    [result minusSet:_recentlyDeletedObjects]; // and finally, kill off any recent deletes

    return result;
}

- (NSSet *)deletedObjects;
{
    ODOEditingContextAssertOwnership(self);

    // Deleted objects can't become alive again w/o an undo, so we don't need to check the recent updates or inserts here.
    if (!_recentlyDeletedObjects) {
        if (!_processedDeletedObjects)
            return [NSSet set]; // return nil, or at least a shared instance?
        return [NSSet setWithSet:_processedDeletedObjects];
    }
    
    NSMutableSet *result = [NSMutableSet setWithSet:_processedDeletedObjects];
    [result unionSet:_recentlyDeletedObjects];
    return result;
}

// TODO: -reset/-undo should remove inserted objects from the registered objects.  Redo should likewise update the registered objects.

- (NSDictionary *)registeredObjectByID;
{
    ODOEditingContextAssertOwnership(self);

    // Deleted objects shouldn't be unregistered until the save.
    return [NSDictionary dictionaryWithDictionary:_registeredObjectByID];
}

BOOL ODOEditingContextObjectIsInsertedNotConsideringDeletions(ODOEditingContext *self, ODOObject *object)
{
    ODOEditingContextAssertOwnership(self);

    return _queryUniqueSet(self->_processedInsertedObjects, object) || _queryUniqueSet(self->_recentlyInsertedObjects, object);
}

- (BOOL)isInserted:(ODOObject *)object;
{
    ODOEditingContextAssertOwnership(self);

    // Pending delete that might kill the insert when processed?
    if (_queryUniqueSet(_recentlyDeletedObjects, object))
        return NO;
    return ODOEditingContextObjectIsInsertedNotConsideringDeletions(self, object);
}

// As with -updatedObjects, this is tricky since processed inserts can be recently updated for notification/undo purposes.
- (BOOL)isUpdated:(ODOObject *)object;
{
    ODOEditingContextAssertOwnership(self);

    // Pending delete that might kill the update when processed?
    if (_queryUniqueSet(_recentlyDeletedObjects, object))
        return NO;

    // Really an update from the start?
    if (_queryUniqueSet(_processedUpdatedObjects, object))
        return YES;
        
    // Recent update that isn't also a processed insert?
    return _queryUniqueSet(_recentlyUpdatedObjects, object) && ! _queryUniqueSet(_processedInsertedObjects, object);
}

- (BOOL)isDeleted:(ODOObject *)object;
{
    ODOEditingContextAssertOwnership(self);

    // Objects can't be reinserted or updated once they have been deleted without an undo.  So our recent inserts/updates aren't relevant here.
    return _queryUniqueSet(_processedDeletedObjects, object) || _queryUniqueSet(_recentlyDeletedObjects, object);
}

- (BOOL)isRegistered:(ODOObject *)object;
{
    ODOEditingContextAssertOwnership(self);
    OBPRECONDITION(object);
    
    ODOObjectID *objectID = [object objectID];
    ODOObject *registered = [_registeredObjectByID objectForKey:objectID];
    OBASSERT(registered == nil || registered == object);
    return registered != nil;
}

- (BOOL)saveWithDate:(NSDate *)saveDate error:(NSError **)outError;
{
    ODOEditingContextAssertOwnership(self);
    OBPRECONDITION(_saveDate == nil);
    OBINVARIANT([self _checkInvariants]);

    //NSLog(@"saving...");
    
    _saveDate = [saveDate copy];

    BOOL willSaveSuccess;
    NSError *willSaveError = nil;
    @autoreleasepool {
        willSaveSuccess = [self _sendWillSave:&willSaveError];
        if (!willSaveSuccess) {
            [willSaveError retain];
        }
    }
    if (!willSaveSuccess) {
        OBINVARIANT([self _checkInvariants]);
        if (outError)
            *outError = [willSaveError autorelease];
        [_saveDate release];
        _saveDate = nil;
        return NO;
    }
    
    BOOL success = YES;
    // Edits past this point are forbidden.  That is, -validateForFoo: can't make any changes to the objects.  That should all be done in -willSave.
    _isValidatingAndWritingChanges = YES;
    @try {
        //NSLog(@"inserts: %@", _processedInsertedObjects);
        //NSLog(@"updates: %@", _processedUpdatedObjects);
        //NSLog(@"deletes: %@", _processedDeletedObjects);
        
        if (![self _validateInsertsAndUpdates:outError]) {
            OBINVARIANT([self _checkInvariants]);
            return NO;
        }
        
        // TODO: CoreData will (erroneously IMO) resend -validateForInsert:, -validateForUpdate: for *redone* changes (undo followed by a redo).  It would be nice to avoid that if we can... of course, with our prohibitin on changes in validation the real issue is re-sending -willSave to redone changes.  Either way, if a redo can make edits, then the undo/redo stack can get b0rked.
        
        // TODO: Batch deletes for the same entity with DELETE from Foo where pk in (...)?  On the other hand, maybe it is faster to have a single prepared statement and issue it multiple times?  Maybe we can have one for the IN case and one for the = case.  Or maybe the IN case is just as fast as the "=" case for single values.  Not even sure we can prepare a statement and bind multiple values into the IN clause with one '?'.
        
        // note: docs for -[NSManagedObject willSave] have been updated to say that you should not use -setValue:forKey: but only -setPrimitiveValue:forKey: if you make changes since the former will generated more change notifications.  Of course, you have changed the object, so any listeners would really want to know about that!  Presumably, they want you to manually KVO and use primitive values to avoid telling the NSMOC that the object is edited while in the middle of saving.

        // Form a notification that specifies what we are going to do, but don't post it unless we sucessfully do so.
        NSDictionary *userInfo = _createChangeSetNotificationUserInfo(_processedInsertedObjects, _processedUpdatedObjects, _processedDeletedObjects, _objectIDToCommittedPropertySnapshot, _objectIDToLastProcessedSnapshot);
        NSNotification *note = [NSNotification notificationWithName:ODOEditingContextDidSaveNotification object:self userInfo:userInfo];
        [userInfo release];

        //
        // Ask ODODatabase to write (but not clear) its _pendingMetadataChanges
        //

        BOOL transactionSuccess = ODOEditingContextExecuteWithOwnership(self, _database.connectionQueue, ^{
            return [_database _performTransactionWithError:outError block:^(struct sqlite3 *sqlite, NSError **blockError) {
                NSError *databaseError = nil;
                if (![_database _queue_writeMetadataChangesToSQLite:sqlite error:&databaseError]) {
                    // <bug:///102226> (Discussion: Are at least some of the recent SQL error reports being caused by Clean My Mac, MacKeeper, etc.?)
                    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to save changes to database", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
                    NSString *reason;
                    BOOL underlyingErrorRequiresReopen = [databaseError hasUnderlyingErrorDomain:ODOSQLiteErrorDomain code:SQLITE_IOERR];
                    if (underlyingErrorRequiresReopen)
                        reason = NSLocalizedStringFromTableInBundle(@"The cache database was removed while it was still open. Close and reopen the database to recover.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason");
                    else
                        reason = [databaseError localizedFailureReason];

                    NSInteger code = (underlyingErrorRequiresReopen ? ODOUnableToSaveTryReopen : ODOUnableToSave);
                    ODOError(&databaseError, code, description, reason);
                    if (blockError != NULL)
                        *blockError = databaseError;

                    return NO;
                }
            
                if (![self _queue_writeProcessedEditsToSQLite:sqlite error:blockError]) {
                    return NO;
                }

                return YES;
            }];
        });

        if (!transactionSuccess) {
            OBINVARIANT([self _checkInvariants]);
            return NO;
        }
        
        // Remove committed snapshots -- the objects are in their saved state and are their own snapshots until the next time they are modified
        [_objectIDToCommittedPropertySnapshot release];
        _objectIDToCommittedPropertySnapshot = nil;
        OBASSERT(_objectIDToLastProcessedSnapshot == nil);
        
        [_database _committedPendingMetadataChanges];
        [_database didSave]; // Note that we have some chance of having something in the database now.
        
        // Send -didSave to the inserts & updates.  This will be inside the _isValidatingAndWritingChanges flag, ensuring that -didSave doesn't append more edits.
        // Clear our local set of inserted and updated objects before doing so, so that -isInserted and -isUpdate is NO inside of -didSave.

        NSSet *inserted = _processedInsertedObjects;
        NSSet *updated = _processedUpdatedObjects;
        NSSet *deleted = _processedDeletedObjects;
        
        NSSet *reinserted = _reinsertedObjects;

        _processedInsertedObjects = nil;
        _processedUpdatedObjects = nil;
        _processedDeletedObjects = nil;
        _reinsertedObjects = nil;

        [inserted makeObjectsPerformSelector:@selector(didSave)];
        [inserted release];

        [updated makeObjectsPerformSelector:@selector(didSave)];
        [updated release];
        
        // No notiication for re-insertion
        [reinserted release];
        
        // Deleted objects currently get -willDelete, but no -didSave.
        if (deleted != nil) {
            ODOEditingContextDidDeleteObjects(self, deleted);
            [deleted release];
        }

        // Finally, post our notification (still inside the _isValidatingAndWritingChanges block).
        [[NSNotificationCenter defaultCenter] postNotification:note];
        OBINVARIANT([self _checkInvariants]);
    } @catch (NSException *exc) {
        OBINVARIANT([self _checkInvariants]);
        NSLog(@"Exception raised while sending -willSave: %@", exc);
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Exception raised while saving: %@", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), [exc reason]];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to save.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToSave, description, reason);
        success = NO;
    } @finally {
        [_saveDate release];
        _saveDate = nil;
        _isValidatingAndWritingChanges = NO;
    }
    
    return success;
}

- (BOOL)isSaving;
{
    ODOEditingContextAssertOwnership(self);
    return _saveDate != nil;
}

- (NSDate *)saveDate;
{
    ODOEditingContextAssertOwnership(self);
    OBPRECONDITION(_saveDate); // Set only during -saveWithDate:error:; shouldn't be called outside of that method
    return _saveDate;
}

- (BOOL)hasChanges;
{
    ODOEditingContextAssertOwnership(self);

    // This might lie if we've had a insert followed by a delete that got rid of it w/o a -processPendingChanges.  Does CoreData handle that?
    if (_recentlyInsertedObjects || _recentlyUpdatedObjects || _recentlyDeletedObjects)
        return YES;
    if (_processedInsertedObjects || _processedUpdatedObjects || _processedDeletedObjects)
        return YES;
    return NO;
}

- (BOOL)hasUnprocessedChanges;
{
    ODOEditingContextAssertOwnership(self);

    if (_recentlyInsertedObjects || _recentlyUpdatedObjects || _recentlyDeletedObjects)
        return YES;
    return NO;
}

- (nullable ODOObject *)objectRegisteredForID:(ODOObjectID *)objectID;
{
    ODOEditingContextAssertOwnership(self);

    return [_registeredObjectByID objectForKey:objectID];
}

- (nullable NSArray *)executeFetchRequest:(ODOFetchRequest *)fetch error:(NSError **)outError;
{
    ODOEditingContextAssertOwnership(self);

    NSMutableArray <__kindof ODOObject *> *results = ODOFetchObjects(self, fetch.entity, fetch.predicate, fetch.reason, outError);
    if (!results) {
        return nil;
    }

    NSArray *sortDescriptors = fetch.sortDescriptors;
    if ([sortDescriptors count] > 0) {
        [results sortUsingDescriptors:sortDescriptors];
    }
    
    return results;
}

- (__kindof ODOObject *)insertObjectWithEntityName:(NSString *)entityName;
{
    ODOEditingContextAssertOwnership(self);

    ODOEntity *entity = [self.database.model entityNamed:entityName];
    ODOObject *object = [[[entity instanceClass] alloc] initWithEntity:entity primaryKey:nil insertingIntoEditingContext:self];
    return [object autorelease];
}

- (nullable __kindof ODOObject *)fetchObjectWithObjectID:(ODOObjectID *)objectID error:(NSError **)outError;
{
    ODOEditingContextAssertOwnership(self);
    OBPRECONDITION(objectID);
    
    ODOObject * (^missingObjectErrorReturn)(void) = ^{
        NSString *format = NSLocalizedStringFromTableInBundle(@"No object with id %@ exists.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason");
        NSString *reason = [NSString stringWithFormat:format, objectID];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to find object.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToFindObjectWithID, description, reason);
        return (ODOObject *)nil;
    };

    ODOObject * (^objectScheduledForDeletionErrorReturn)(void) = ^{
        NSString *format = NSLocalizedStringFromTableInBundle(@"The object with id %@ is scheduled for deletion.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason");
        NSString *reason = [NSString stringWithFormat:format, objectID];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Object is scheduled for deletion.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        ODOError(outError, ODORequestedObjectIsScheduledForDeletion, description, reason);
        return (ODOObject *)nil;
    };

    ODOEntity *entity = [objectID entity];
    if (entity == nil) {
        OBASSERT(entity != nil);
        return nil;
    }
    
    ODOObject *object = (ODOObject *)[self objectRegisteredForID:objectID];
    if (object != nil) {
        if ([object isDeleted]) {
            // Object is scheudled for deletion
            return objectScheduledForDeletionErrorReturn();
        }

        if (object.hasBeenDeletedOrInvalidated) {
            OBASSERT_NOT_REACHED("Maybe should have been purged from the registered objects?");
            // ... but maybe it is in the undo stack or otherwise not deallocated.  At any rate, this is happening, so let's be defensive.  See <bug://45150> (Clicking URL to recently deleted task can crash)
            return missingObjectErrorReturn();
        }

        OBASSERT([[object objectID] isEqual:objectID]);
        return object;
    }
    
    if ([_database isFreshlyCreated]) {
        return missingObjectErrorReturn();
    }

    ODOFetchRequest *fetch = [[[ODOFetchRequest alloc] init] autorelease];
    [fetch setEntity:entity];
    [fetch setPredicate:ODOKeyPathEqualToValuePredicate([[entity primaryKeyAttribute] name], [objectID primaryKey])];
    
    NSArray *objects = [self executeFetchRequest:fetch error:outError];
    if (objects == nil) {
        // error filled in by fetch request
        return nil;
    }
    
    if (objects.count == 0) {
        return missingObjectErrorReturn();
    }
    
    OBASSERT([objects count] == 1);
    
    object = [objects objectAtIndex:0];
    OBASSERT([self objectRegisteredForID:objectID] == object);
    
    return object;
}

- (nullable NSArray <__kindof ODOObject *> *)fetchToManyRelationship:(ODORelationship *)relationship forSourceObjects:(NSSet <ODOObject *> *)sourceObjects error:(NSError **)outError;
{
    OBPRECONDITION(relationship.isToMany);

    NSSet <ODOObject *> *needingFetch = [sourceObjects select:^(ODOObject *object) {
        OBASSERT(object.entity == relationship.entity);
        return [object hasFaultForRelationship:relationship];
    }];

    if (needingFetch.count == 0) {
        return @[];
    }

    ODORelationship *inverseRelationship = relationship.inverseRelationship;
    ODOFetchRequest *fetch = [[ODOFetchRequest alloc] init];
    fetch.entity = relationship.entity;
    fetch.predicate = [NSPredicate predicateWithFormat:@"%K in %@", inverseRelationship.name, needingFetch];

    NSArray *fetchedObjects = [self executeFetchRequest:fetch error:outError];
    [fetch release];

    if (fetchedObjects == nil) {
        return nil;
    }

    // Now that we have the fetch completed successfully. Bucket the results into the source objects that need it.

    for (ODOObject *object in needingFetch) {
        _ODOObjectSetObjectValueForProperty(object, relationship, [NSMutableSet set]);
    }

    for (ODOObject *fetched in fetchedObjects) {
        ODOObject *sourceObject = ODOObjectPrimitiveValueForProperty(fetched, inverseRelationship);
        OBASSERT([needingFetch containsObject:sourceObject]);

        NSMutableSet *toMany = ODOObjectPrimitiveValueForProperty(sourceObject, relationship);
        [toMany addObject:fetched];
    }

    return fetchedObjects;
}

- (ODOEditingContextFaultErrorRecovery)handleFaultFulfillmentError:(NSError *)error;
{
    ODOEditingContextAssertOwnership(self);

    // Don't attempt anything in the base class. Subclasses can try to recover in an app-specific manner.
    return ODOEditingContextFaultErrorUnhandled;
}

NSNotificationName const ODOEditingContextObjectsPreparingToBeDeletedNotification = @"ODOEditingContextObjectsPreparingToBeDeletedNotification";
NSNotificationName const ODOEditingContextObjectsWillBeDeletedNotification = @"ODOEditingContextObjectsWillBeDeletedNotification";
NSNotificationName const ODOEditingContextObjectsDidChangeNotification = @"ODOEditingContextObjectsDidChangeNotification";
NSNotificationName const ODOEditingContextDidSaveNotification = @"ODOEditingContextDidSaveNotification";
NSNotificationName const ODOEditingContextWillSaveNotification = @"ODOEditingContextWillSaveNotification";

NSString * const ODOInsertedObjectsKey = @"ODOInsertedObjectsKey";
NSString * const ODOUpdatedObjectsKey = @"ODOUpdatedObjectsKey";
NSString * const ODOMateriallyUpdatedObjectsKey = @"ODOMateriallyUpdatedObjectsKey";
NSString * const ODOMateriallyUpdatedObjectPropertiesKey = @"ODOMateriallyUpdatedObjectPropertiesKey";
NSString * const ODODeletedObjectsKey = @"ODODeletedObjectsKey";
NSString * const ODODeletedObjectPropertySnapshotsKey = @"ODODeletedObjectPropertySnapshotsKey";

NSNotificationName const ODOEditingContextWillResetNotification = @"ODOEditingContextWillReset";
NSNotificationName const ODOEditingContextDidResetNotification = @"ODOEditingContextDidReset";

#pragma mark - NSObject subclass

- (NSString *)debugDescription;
{
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([self class]), self, self.label ?: @"(null)"];
}

#pragma mark - Private

static void _runLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info)
{
    // End-of-event processing.  This will provoke an undo group if one isn't already open.
    ODOEditingContext *self = info;
    ODOEditingContextAssertOwnership(self);

    if (self->_recentlyInsertedObjects || self->_recentlyUpdatedObjects || self->_recentlyDeletedObjects)
        [self processPendingChanges];
}

- (void)_addRunLoopObserver;
{
    // For now, ensure this is on the main run loop
    OBPRECONDITION([NSRunLoop currentRunLoop] == [NSRunLoop mainRunLoop]);

    OBPRECONDITION(_runLoopForObserver == NULL);
    OBPRECONDITION(_runLoopObserver == NULL);

    _runLoopForObserver = CFRunLoopGetCurrent();
    CFRetain(_runLoopForObserver);

    CFRunLoopObserverContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.info = self;
    ctx.copyDescription = OFNSObjectCopyDescription;
    _runLoopObserver = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopBeforeWaiting, true/*repeats*/, 0/*order*/, _runLoopObserverCallBack, &ctx);
    CFRunLoopAddObserver(CFRunLoopGetCurrent(), _runLoopObserver, kCFRunLoopCommonModes);
}

- (void)_removeRunLoopObserver;
{
    OBPRECONDITION(_runLoopForObserver != NULL);
    OBPRECONDITION(_runLoopObserver != NULL);

    CFRunLoopRemoveObserver(_runLoopForObserver, _runLoopObserver, kCFRunLoopCommonModes);
    CFRelease(_runLoopForObserver);
    _runLoopForObserver = NULL;
    CFRelease(_runLoopObserver);
    _runLoopObserver = NULL;
}

- (void)_databaseConnectionDidChange:(NSNotification *)note;
{
    ODOEditingContextAssertOwnership(self);

    [self reset];
}

- (BOOL)_sendWillSave:(NSError **)outError;
{
    ODOEditingContextAssertOwnership(self);

    // Inform the inserted and updated object that they -willSave.  The deleted objects are dead, dead, dead (unless undo happens) so they don't get a -willSave.  Edits are allowed in -willSave, though CoreData says that they should only use the primitive setters.  Let's not have that weird restriction.
    
    BOOL success = YES;
    
    @try {
        // Process our changes once before sending -willSave to anything.
        [self processPendingChanges];
        
        NSUInteger tries = 0;
        while (YES) {
            // Notify our processed objects.  If they make changes during this, they'll go into the recent changes.  The objects themselves must not call -processPendingChanges while we are looping.  We might be able to lift this restriction, but if we don't make a copy of the sets being iterated here, then we'd end up with them mutating a set we are enumerating.  On the other hand, if we do make a copy and they mutate the set, we'd lose track of the fact that there were recent changes and those objects wouldn't get a -willSave!  So, we set a flag here and assert that it isn't set in -processPendingChanges.
            _isSendingWillSave = YES;
            {
                for (ODOObject *object in _processedInsertedObjects) {
                    [object willInsert];
                }
                for (ODOObject *object in _processedUpdatedObjects) {
                    [object willUpdate];
                }
                 // OmniFocusModel, in particular OFMProjectInfo's metadata support, wants to be notified when a delete is saved, as opposed to happening in memory (-prepareForDeletion)
                for (ODOObject *object in _processedDeletedObjects) {
                    [object willDelete:ODOWillDeleteEventMaterial];
                }
            }
            _isSendingWillSave = NO;
            
            // Process any further changes.  If there were none, we are done.
            BOOL wereRecentEdits = [self processPendingChanges];
            if (!wereRecentEdits)
                break;
            
#if 0 && defined(DEBUG)
            // This seems to be the approach CoreData takes to detect ping-ponging edits.  We should do our best to minimize the number of tries it takes to stabilize.
            NSLog(@"changes made while sending -willSave on try %d", tries);
#endif
            tries++;
            if (tries > 100) {
                NSString *reason = NSLocalizedStringFromTableInBundle(@"Tried 100 times to settle -willSave, but edits kept being made.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason");
                NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to save.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
                ODOError(outError, ODOUnableToSave, description, reason);
                return NO;
            }
        }
        
        // Send a final, context-wide will save.
        
        _isSendingWillSave = YES;
        {
            NSDictionary *userInfo = _createChangeSetNotificationUserInfo(_processedInsertedObjects, _processedUpdatedObjects, _processedDeletedObjects, _objectIDToCommittedPropertySnapshot, _objectIDToLastProcessedSnapshot);
            NSNotification *notification = [NSNotification notificationWithName:ODOEditingContextWillSaveNotification object:self userInfo:userInfo];
            [[NSNotificationCenter defaultCenter] postNotification:notification];
            [userInfo release];
        }
        _isSendingWillSave = NO;
        
        // Modifying the context during ODOEditingContextWillSaveNotification is disallowed
        BOOL hasEdits = [self processPendingChanges];
        assert(!hasEdits);

    } @catch (NSException *exc) {
        _isSendingWillSave = NO;
        
        NSLog(@"Exception raised while sending -willSave: %@", exc);
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Exception raised while sending -willSave: %@", @"OmniDataObjects", OMNI_BUNDLE, @"error reason"), [exc reason]];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to save.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToSave, description, reason);
        success = NO;
    }
    
    return success;
}

// Delete validation occurs when -deleteObject: is called
- (BOOL)_validateInsertsAndUpdates:(NSError **)outError;
{
    OBPRECONDITION(!_recentlyInsertedObjects);
    OBPRECONDITION(!_recentlyUpdatedObjects);
    OBPRECONDITION(!_recentlyDeletedObjects);
    
    NSMutableArray <NSError *> *validationErrors = [NSMutableArray array];
    __block NSError *localError = nil;
    
    void(^checkSuccess)(BOOL isSuccess) = ^(BOOL isSuccess) {
        if (!isSuccess) {
            [validationErrors addObject:localError];
        }
        localError = nil;
    };
    
    for (ODOObject *object in _processedInsertedObjects) {
        checkSuccess([object validateForInsert:&localError]);
    }
    
    for (ODOObject *object in _processedUpdatedObjects) {
        checkSuccess([object validateForUpdate:&localError]);
    }
    
    if (validationErrors.count == 0) {
        return YES;
    }
    
    if (validationErrors.count == 1) {
        if (outError != NULL) {
            *outError = [validationErrors lastObject];
        }
    } else {
#ifdef DEBUG
        NSArray *errors = validationErrors;
        for (NSError *error in errors) {
            NSLog(@"Validation error: %@", error);
        }
#endif
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Multiple validation errors occurred while saving.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to save.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        ODOErrorWithInfo(outError, ODOUnableToSave, description, reason, ODODetailedErrorsKey, validationErrors, nil);
    }
    
    return NO;
}

typedef struct {
    ODODatabase *database;
    NSSet *reinsertedObjects;
    sqlite3 *sqlite;
    BOOL errorOccurred;
    NSError **outError;
} WriteSQLApplierContext;

static void _writeInsertApplier(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    WriteSQLApplierContext *ctx = context;
    
    if (ctx->errorOccurred) {
        return;
    }
    
    BOOL isReinsert = ([ctx->reinsertedObjects member:object] == object);
    
    if (isReinsert) {
        if (![object.entity _writeUpdate:ctx->sqlite database:ctx->database object:object error:ctx->outError]) {
            ctx->errorOccurred = YES;
        }
    } else {
        if (![object.entity _writeInsert:ctx->sqlite database:ctx->database object:object error:ctx->outError]) {
            ctx->errorOccurred = YES;
        }
    }
}

static void _writeUpdateApplier(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    WriteSQLApplierContext *ctx = context;
    
    if (ctx->errorOccurred) {
        return;
    }

    if (![object.entity _writeUpdate:ctx->sqlite database:ctx->database object:object error:ctx->outError]) {
        ctx->errorOccurred = YES;
    }
}

static void _writeDeleteApplier(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    WriteSQLApplierContext *ctx = context;
    
    if (ctx->errorOccurred) {
        return;
    }

    if (![object.entity _writeDelete:ctx->sqlite database:ctx->database object:object error:ctx->outError]) {
        ctx->errorOccurred = YES;
    }
}

// Writes the changes, but doesn't clear them (the transaction may fail).
- (BOOL)_queue_writeProcessedEditsToSQLite:(struct sqlite3 *)sqlite error:(NSError **)outError;
{
    OBPRECONDITION(_recentlyInsertedObjects == nil);
    OBPRECONDITION(_recentlyUpdatedObjects == nil);
    OBPRECONDITION(_recentlyDeletedObjects == nil);
    OBPRECONDITION(_objectIDToLastProcessedSnapshot == nil);
   
    OBPRECONDITION([_database.connection checkExecutingOnDispatchQueue]);
    OBPRECONDITION([_database.connection checkIsManagedSQLite:sqlite]);
    
    // For deletes, there might be a speed advantage to grouping by entity and then issuing a delete where pk in (...) but binding values wouldn't let us bind the set of values.  Maybe we could have a prepared statement for 'delete 10 things' and use that until we had < 10.  Or fill out the last N bindings in the statement with repeated PKs.  Also, angels on a pinhead.
    WriteSQLApplierContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.database = _database;
    ctx.reinsertedObjects = _reinsertedObjects;
    ctx.sqlite = sqlite;
    ctx.outError = outError;
    
    if (_processedInsertedObjects != nil) {
        CFSetApplyFunction((CFSetRef)_processedInsertedObjects, _writeInsertApplier, &ctx);
    }
    
    if (ctx.errorOccurred) {
        return NO;
    }
    
    if (_processedUpdatedObjects != nil) {
        CFSetApplyFunction((CFSetRef)_processedUpdatedObjects, _writeUpdateApplier, &ctx);
    }
    
    if (ctx.errorOccurred) {
        return NO;
    }

    if (_processedDeletedObjects != nil) {
        CFSetApplyFunction((CFSetRef)_processedDeletedObjects, _writeDeleteApplier, &ctx);
    }
    
    if (ctx.errorOccurred) {
        return NO;
    }

    return YES;
}

static void _appendObjectID(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    CFMutableArrayRef objectIDs = (CFMutableArrayRef)context;
    CFArrayAppendValue(objectIDs, [object objectID]);
}

static NSArray * _Nullable _copyCollectObjectIDs(NSSet *objects)
{
    if (objects == nil) {
        return nil;
    }
    
    // Fixed length array for small savings
    CFIndex count = CFSetGetCount((CFSetRef)objects);
    CFMutableArrayRef objectIDs = CFArrayCreateMutable(kCFAllocatorDefault, count, &OFNSObjectArrayCallbacks);
    CFSetApplyFunction((CFSetRef)objects, _appendObjectID, objectIDs);
    return (NSArray *)objectIDs;
}

typedef struct {
    NSDictionary *objectIDToLastProcessedSnapshot;
    NSMutableArray *results;
} CollectObjectIDsAndSnapshotsToInsertContext;

static void _collectObjectIDsAndSnapshotsToInsert(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    CollectObjectIDsAndSnapshotsToInsertContext *ctx = context;
    
    ODOObjectID *objectID = [object objectID];
    OBASSERT(objectID);
    NSArray *snapshot = [ctx->objectIDToLastProcessedSnapshot objectForKey:objectID];
    OBASSERT(snapshot);
    
    [ctx->results addObject:objectID];
    [ctx->results addObject:snapshot];
}

typedef struct {
    NSDictionary *objectIDToLastProcessedSnapshot;
    NSMutableArray *results;
} RecordChangesToUndoUpdateContext;

static void _recordChangesToUndoUpdate(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    RecordChangesToUndoUpdateContext *ctx = context;
    
    ODOObjectID *objectID = [object objectID];
    ODOObjectSnapshot *snapshot = ctx->objectIDToLastProcessedSnapshot[objectID];

    // Might return NULL if all the 'changes' to this object are to to-many relationships.
    CFArrayRef diff = ODOObjectCreateDifferenceRecordFromSnapshot(object, snapshot);
    if (diff) {
        [ctx->results addObject:(id)diff];
        CFRelease(diff);
    }
}

// Need to log deletes for the inserts, inserts for the deletes and inverted updates.
- (void)_registerUndoForRecentChanges;
{
    OBPRECONDITION(_undoManager);
    
    // No point setting this up if it'll just be trashed
    if (![_undoManager isUndoRegistrationEnabled])
        return;
    
    // Any of our deletes need to be inserted with their snapshot before deleting.  Build an array of objectID,snapshot pairs.
    NSArray *objectIDsAndSnapshotsToInsert = nil;
    if (_recentlyDeletedObjects) {
        CollectObjectIDsAndSnapshotsToInsertContext ctx = {
            .objectIDToLastProcessedSnapshot = _objectIDToLastProcessedSnapshot,
            .results = [[NSMutableArray alloc] init]
        };
        CFSetApplyFunction((CFSetRef)_recentlyDeletedObjects, _collectObjectIDsAndSnapshotsToInsert, &ctx);
        
        objectIDsAndSnapshotsToInsert = [ctx.results copy];
        [ctx.results release];
    }
    
    // Our inserts should be deleted.  No need to pass along our existing state as snapshots.
    NSArray *objectIDsToDelete = _copyCollectObjectIDs(_recentlyInsertedObjects);
    
    // Finally, our updates need to be reversed.
    NSArray *updates = nil;
    if (_recentlyUpdatedObjects) {
        RecordChangesToUndoUpdateContext ctx = {
            .objectIDToLastProcessedSnapshot = _objectIDToLastProcessedSnapshot,
            .results = [[NSMutableArray alloc] init]
        };
        CFSetApplyFunction((CFSetRef)_recentlyUpdatedObjects, _recordChangesToUndoUpdate,  &ctx);
        
        if ([ctx.results count] > 0) { // Might have only updated to-many relationships, which we don't record for undo.
            updates = [ctx.results copy];
        }
        [ctx.results release];
    }
    
    BOOL hasChanges = NO;
    DEBUG_UNDO(@"Registering operation during %@:", [_undoManager isUndoing] ? @"undo" : ([_undoManager isRedoing] ? @"redo" : @"'doing'"));
    if (objectIDsAndSnapshotsToInsert) {
        DEBUG_UNDO(@"  objectIDsAndSnapshotsToInsert = %@", [(id)CFCopyDescription(objectIDsAndSnapshotsToInsert) autorelease]);
        hasChanges = YES;
    }
    if (updates) {
        DEBUG_UNDO(@"  updates = %@", [(id)CFCopyDescription(updates) autorelease]);
        hasChanges = YES;
    }
    if (objectIDsToDelete) {
        DEBUG_UNDO(@"  objectIDsToDelete = %@", objectIDsToDelete);
        hasChanges = YES;
    }
    
    if (hasChanges)
        [[_undoManager prepareWithInvocationTarget:self] _undoWithObjectIDsAndSnapshotsToInsert:objectIDsAndSnapshotsToInsert updates:updates objectIDsToDelete:objectIDsToDelete];
	else
        DEBUG_UNDO(@"  ... no changes to report");

    [updates release];
    [objectIDsToDelete release];
    [objectIDsAndSnapshotsToInsert release];
}

typedef enum {
    ODOEditingContextUndoRelationshipsForInsertion,
    ODOEditingContextUndoRelationshipsForDeletion,
} ODOEditingContextUndoRelationshipsAction;

static void _updateRelationshipsForUndo(ODOObject *object, ODOEntity *entity, ODOEditingContextUndoRelationshipsAction action)
{
    NSArray *toOneRelationships = entity.toOneRelationships;
    NSMutableSet *relationshipsToNullify = nil;
    
    if (action == ODOEditingContextUndoRelationshipsForDeletion) {
        relationshipsToNullify = [NSMutableSet set];
        
        for (ODORelationship *relationship in toOneRelationships) {
            ODORelationship *inverseRelationship = relationship.inverseRelationship;
            
            NSString *forwardKey = relationship.name;
            ODOObject *destinationObject = ODOGetPrimitiveProperty(object, forwardKey);
            if (destinationObject == nil) {
                continue;
            }
            
            if (![inverseRelationship isToMany]) {
                continue;
            }
            
            [relationshipsToNullify addObject:relationship];
        }
    }

    if (action == ODOEditingContextUndoRelationshipsForDeletion && relationshipsToNullify.count > 0) {
        [object willNullifyRelationships:relationshipsToNullify];
    }

    for (ODORelationship *relationship in toOneRelationships) {
        ODORelationship *inverseRelationship = relationship.inverseRelationship;
        
        NSString *forwardKey = relationship.name;
        NSString *inverseKey = inverseRelationship.name;
        ODOObject *destinationObject = ODOGetPrimitiveProperty(object, forwardKey);
        if (destinationObject == nil) {
            continue;
        }
        
        if (![inverseRelationship isToMany]) {
            if (action == ODOEditingContextUndoRelationshipsForDeletion) {
                // one-to-one. nullify the forward key, which should nullify the inverse too.
                if (destinationObject != nil) {
                    [object willChangeValueForKey:forwardKey];
                    ODOObjectSetPrimitiveValueForProperty(object, nil, relationship);
                    [object didChangeValueForKey:forwardKey];
                    
                    OBASSERT([destinationObject valueForKey:inverseKey] == nil);
                }
            } else {
                // The inverse will be restored from the other side's snapshot.
            }
            
            continue;
        }
        
        // Avoid creating/clearing the inverse to-many (our primitive getter would do that).
        NSMutableSet *toManySet = ODOObjectToManyRelationshipIfNotFault(destinationObject, inverseRelationship);
        
        NSSet *change = [NSSet setWithObject:object];
        
        if (action == ODOEditingContextUndoRelationshipsForInsertion) {
            OBASSERT([toManySet member:object] == nil);
            [destinationObject willChangeValueForKey:inverseKey withSetMutation:NSKeyValueUnionSetMutation usingObjects:change];
            [toManySet addObject:object];
            [destinationObject didChangeValueForKey:inverseKey withSetMutation:NSKeyValueUnionSetMutation usingObjects:change];
        } else {
            OBASSERT(action == ODOEditingContextUndoRelationshipsForDeletion);
            OBASSERT(toManySet == nil || [toManySet member:object] != nil); // the relationship should be fully formed before we act, or have never been faulted in
            
            // Need to clear the forward to-ones too, to ensure that on undo/redo, any multi-stage keyPaths get their KVO on sub-paths deregistered. Then, when the outside objects remove observers, our to-one getters can return nil and they can clean up w/o trouble.
            OBASSERT(destinationObject != nil); // checked above
            OBASSERT(![object isFault]);
            
            [object willChangeValueForKey:forwardKey];
            ODOObjectSetPrimitiveValueForProperty(object, nil, relationship);
            [object didChangeValueForKey:forwardKey];

            OBASSERT(toManySet == nil || [toManySet member:object] == nil); // ODOObjectSetPrimitiveValueForProperty should have cleaned up and sent KVO for the inverse to-many too.
        }
    }

    if (action == ODOEditingContextUndoRelationshipsForDeletion && relationshipsToNullify.count > 0) {
        [object didNullifyRelationships:relationshipsToNullify];
    }
}

- (void)_undoWithObjectIDsAndSnapshotsToInsert:(nullable NSArray *)objectIDsAndSnapshotsToInsert updates:(nullable NSArray *)updates objectIDsToDelete:(nullable NSArray *)objectIDsToDelete;
{
    ODOEditingContextAssertOwnership(self);

    DEBUG_UNDO(@"Performing %@ operation:", [_undoManager isUndoing] ? @"undo" : ([_undoManager isRedoing] ? @"redo" : @"WTF?"));
    if (objectIDsAndSnapshotsToInsert) {
        DEBUG_UNDO(@"objectIDsAndSnapshotsToInsert = %@", [(id)CFCopyDescription(objectIDsAndSnapshotsToInsert) autorelease]);
    }
    if (updates) {
        DEBUG_UNDO(@"updates = %@", [(id)CFCopyDescription(updates) autorelease]);
    }
    if (objectIDsToDelete) {
        DEBUG_UNDO(@"objectIDsToDelete = %@", objectIDsToDelete);
    }
    
    OBINVARIANT([self _checkInvariants]);
    OBPRECONDITION(_undoManager);
    OBPRECONDITION([_undoManager isUndoing] || [_undoManager isRedoing]);
    OBPRECONDITION([_undoManager isUndoRegistrationEnabled]);
    OBPRECONDITION(!objectIDsAndSnapshotsToInsert || [objectIDsAndSnapshotsToInsert count] > 0);
    OBPRECONDITION(!updates || [updates count] > 0);
    OBPRECONDITION(!objectIDsToDelete || [objectIDsToDelete count] > 0);
    OBPRECONDITION([objectIDsAndSnapshotsToInsert count] > 0 || [updates count] > 0 || [objectIDsToDelete count] > 0);
    
    OBPRECONDITION(_recentlyInsertedObjects == nil);
    OBPRECONDITION(_recentlyUpdatedObjects == nil);
    OBPRECONDITION(_recentlyDeletedObjects == nil);

    NSMutableSet *toDelete = nil;
    if ([objectIDsToDelete count] > 0) {
        toDelete = [NSMutableSet set];
        for (ODOObjectID *objectID in objectIDsToDelete) {
            ODOObject *object = [self objectRegisteredForID:objectID];
            if (!object) {
                OBASSERT_NOT_REACHED("Should not be able to delete an object that isn't registered");
                continue;
            }

            OBASSERT([toDelete member:object] == nil); // no dups, please
            [toDelete addObject:object];
        }

        // Before making changes, post an early notification for observers that want to be notified before these changes.
        [[NSNotificationCenter defaultCenter] postNotificationName:ODOEditingContextObjectsPreparingToBeDeletedNotification object:self userInfo:@{ODODeletedObjectsKey:toDelete}];
    }

    // Perform the indicated changes.  DO NOT use public API here.  We don't want to re-validate deletes or resend -awakeFromInsert, for example.
    // Additionally, all the changes made/advertised here should be *local* to the objects being edited.  For example, we should not re-nullify relationships on deletions since that's been done already and should be captured in the other undos.
    // The exception to this is KVO & maintainence of already-cleared to-many relationships.  Since to-many relationships are not recorded directly in the deltas, we have to update them here (but still going through internal API).
    
    // Do the inserts first; updates that follow might have been due to nullified relationships for the deletes these represent.
    NSUInteger insertIndex, insertCount = [objectIDsAndSnapshotsToInsert count];
    OBASSERT((insertCount % 2) == 0); // should be objectID/snapshot sets
    for (insertIndex = 0; insertIndex < insertCount; insertIndex += 2) {
        ODOObjectID *objectID = OB_CHECKED_CAST(ODOObjectID, objectIDsAndSnapshotsToInsert[insertIndex+0]);
        ODOObjectSnapshot *snapshot = OB_CHECKED_CAST(ODOObjectSnapshot, objectIDsAndSnapshotsToInsert[insertIndex+1]);

        DEBUG_UNDO(@"  insert objectID:%@ snapshot:%@", objectID, snapshot);
        
        ODOEntity *entity = [objectID entity];
        ODOObject *object = [[[entity instanceClass] alloc] initWithEditingContext:self objectID:objectID snapshot:snapshot];
        ODOEditingContextInternalInsertObject(self, object, NULL);
        [object release];
    }
    
    // After *ALL* the inserts have happened, scan each re-inserted object for non-nil to-one relationships.  If the inverse is to-many, then we need to send KVO and (if the fault has been cleared) update the set.  If we do this incrementally as we insert objects, we might end up inserting object A with a snapshot that has a to-one foreign key pointing to B.  If we scan for updating inverse to-manys, we'd end up creating a fault for B (it not being inserted yet) and then things go down hill.
    for (insertIndex = 0; insertIndex < insertCount; insertIndex += 2) {
        ODOObjectID *objectID = [objectIDsAndSnapshotsToInsert objectAtIndex:insertIndex+0];
        ODOObject *object = [_registeredObjectByID objectForKey:objectID];
        
        OBASSERT([object isInserted]);
        _updateRelationshipsForUndo(object, [objectID entity], ODOEditingContextUndoRelationshipsForInsertion);
        
        [object _setIsAwakingFromReinsertionAfterUndoneDeletion:YES];
        @try {
            [object awakeFromEvent:ODOAwakeEventUndoneDeletion snapshot:nil];
        } @finally {
            [object _setIsAwakingFromReinsertionAfterUndoneDeletion:NO];
        }
        
        DEBUG_UNDO(@"    _recentlyUpdatedObjects now %@", [_recentlyUpdatedObjects setByPerformingSelector:@selector(objectID)]);
    }

    // Do the updates
    NSUInteger updateIndex, updateCount = [updates count];
    for (updateIndex = 0; updateIndex < updateCount; updateIndex++) {
        CFArrayRef update = (CFArrayRef)[updates objectAtIndex:updateIndex];
        
        ODOObjectID *objectID = (ODOObjectID *)CFArrayGetValueAtIndex(update, 0); // Lame to know the structure of this
        ODOObject *object = [self objectRegisteredForID:objectID];
        
        //DEBUG_UNDO(@"  update objectID:%@ update:%@", objectID, [(id)CFCopyDescription(update) autorelease]);

        // This isn't valid.  If we undo a change to a to-one, the inverse to-many will be updated.  If there is another update for that object (so some attribute, say), then we'd spuriously hit this depending on the order of operations.
        //OBASSERT([_recentlyUpdatedObjects member:object] == nil); // shouldn't have been updated yet

        if (!object) {
            OBASSERT_NOT_REACHED("Should not be able to update an object that isn't registered");
            continue;
        }
        
        ODOObjectApplyDifferenceRecord(object, update);
        OBASSERT([_recentlyUpdatedObjects member:object] == object); // now it should be updated by virtue of setting the primitive relationships
        //DEBUG_UNDO(@"    _recentlyUpdatedObjects now %@", [_recentlyUpdatedObjects setByPerformingSelector:@selector(objectID)]);
    }
    
    // Do the deletes
    if (toDelete != nil) {
        for (ODOObject *object in toDelete) {
            // Scan each re-deleted object for non-nil to-one relationships.  If the inverse is to-many, then we need to send KVO and (if the fault has been cleared) update the set.
            // We also need to clear the to-ones to ensure that keyPath observations get dropped and that our to-one accessors can return nil (they'll be called when an observer is removing multi-step keyPath observations).
            _updateRelationshipsForUndo(object, object.entity, ODOEditingContextUndoRelationshipsForDeletion);
        }
        
        OBASSERT([toDelete count] > 0);
        ODOEditingContextInternalDeleteObjects(self, toDelete);
    }

    // Process changes immediately.  This will log our opposite undo/redo action.
    [self processPendingChanges];
}

@end

NS_ASSUME_NONNULL_END
