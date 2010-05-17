// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOEditingContext.h>

#import <OmniDataObjects/ODOFetchRequest.h>
#import <OmniDataObjects/ODOObject.h>
#import <OmniDataObjects/ODOObjectID.h>
#import <OmniDataObjects/ODORelationship.h>
#import <OmniDataObjects/NSPredicate-ODOExtensions.h>
#import <OmniDataObjects/ODOModel.h>

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

#if ODO_SUPPORT_UNDO
#import <Foundation/NSUndoManager.h>
#endif
#import <Foundation/FoundationErrors.h>

#if 0 && defined(DEBUG)
    #define DEBUG_DELETE(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_DELETE(format, ...) do {} while (0)
#endif

#import <sqlite3.h>

RCS_ID("$Id$")

@interface ODOEditingContext (/*Private*/)
- (void)_databaseConnectionDidChange:(NSNotification *)note;
- (BOOL)_sendWillSave:(NSError **)outError;
- (BOOL)_validateInsertsAndUpdates:(NSError **)outError;
- (BOOL)_writeProcessedEdits:(NSError **)outError;
#if ODO_SUPPORT_UNDO
- (void)_registerUndoForRecentChanges;
- (void)_undoWithObjectIDsAndSnapshotsToInsert:(NSArray *)objectIDsAndSnapshotsToInsert updates:(NSArray *)updates objectIDsToDelete:(NSArray *)objectIDsToDelete;
#endif
@end

@implementation ODOEditingContext

static void _runLoopObserverCallBack(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info)
{
    // End-of-event processing.  This will provoke an undo group if one isn't already open.
    ODOEditingContext *self = info;
    if (self->_recentlyInsertedObjects || self->_recentlyUpdatedObjects || self->_recentlyDeletedObjects)
        [self processPendingChanges];
}

- initWithDatabase:(ODODatabase *)database;
{
    OBPRECONDITION(database);
    
    // TODO: Register with the database so we can ensure there is only one editing context at a time (not supporting edit merging).
    _database = [database retain];
    
    // If the database is disconnected from its file, we need to forget our contents.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_databaseConnectionDidChange:) name:ODODatabaseConnectedURLChangedNotification object:_database];
    
    _registeredObjectByID = [[NSMutableDictionary alloc] init];
    
    // TODO: Need to register for other times?  What about when the app is sitting idle and a timer fires making changes?  That should be its own undo group.  Actually, in the case of OmniFocus, it's unclear if that should be undoable.  Undoing would put stuff in a weird state (and the change would probably get redone nearly immediately).  It might be nice to be able to mark properties as summaries -- change sets that *only* include these might automatically not have associated undos.
    
    // TODO: Don't schedule an observer until we have recent changes?
    CFRunLoopObserverContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.info = self;
    ctx.copyDescription = OFNSObjectCopyDescription;
    _runLoopObserver = CFRunLoopObserverCreate(kCFAllocatorDefault, kCFRunLoopBeforeWaiting, true/*repeats*/, 0/*order*/, _runLoopObserverCallBack, &ctx);
    CFRunLoopAddObserver(CFRunLoopGetCurrent(), _runLoopObserver, kCFRunLoopCommonModes);

    OBINVARIANT([self _checkInvariants]);
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(_saveDate == nil);
    OBINVARIANT([self _checkInvariants]);

    // TODO: Deregister with the database so we can ensure there is only one editing context at a time (not supporting edit merging).
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ODODatabaseConnectedURLChangedNotification object:_database];
    [_database release];
#if ODO_SUPPORT_UNDO
    [_undoManager removeAllActionsWithTarget:self];
    [_undoManager release];
#endif
    
    if (_runLoopObserver) {
        // Retain the runloop?  Assert we are in the main thread in both?
        CFRunLoopRemoveObserver(CFRunLoopGetCurrent(), _runLoopObserver, kCFRunLoopCommonModes);
        CFRelease(_runLoopObserver);
        _runLoopObserver = NULL;
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
    
    [super dealloc];
}

- (ODODatabase *)database;
{
    OBPRECONDITION(_database);
    return _database;
}

#if ODO_SUPPORT_UNDO
- (NSUndoManager *)undoManager;
{
    return _undoManager;
}
- (void)setUndoManager:(NSUndoManager *)undoManager;
{
    if (_undoManager) {
        [_undoManager removeAllActionsWithTarget:self];
        [_undoManager release];
        _undoManager = nil;
    }
    _undoManager = [undoManager retain];
}
#endif

// Empties the reciever of all objects.
- (void)reset;
{
    OBINVARIANT([self _checkInvariants]);

    // Give observers a chance to clear caches of objects we are about to obliterate.  During this time, if any fetching is attempted on us, we'll return nil.  It's important to do the reset in two phases like this for the case of cascading caches; clearing cache A may invoke KVO that would cause messages to objects in cache B.  If the objects in B are already invalidated, then bad things happen.  This lets everyone shut down and then start up again.
    _isResetting = YES;
    @try {
        [[NSNotificationCenter defaultCenter] postNotificationName:ODOEditingContextWillResetNotification object:self];
        
#if ODO_SUPPORT_UNDO
        // Clear any undos we have logged
        [_undoManager removeAllActionsWithTarget:self];
#endif
        
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
        
        // get rid of database metadata changes
        [_database _discardPendingMetadataChanges];
        
        // invalidate all registered objects
        for (ODOObject *object in [_registeredObjectByID objectEnumerator])
            [object _invalidate];
        [_registeredObjectByID removeAllObjects];
    } @finally {
        _isResetting = NO;
    }
    
    // Give observers a chance to refill caches now that all listeners have had a chance to clear their caches.
    [[NSNotificationCenter defaultCenter] postNotificationName:ODOEditingContextDidResetNotification object:self];
}

static void ODOEditingContextInternalInsertObject(ODOEditingContext *self, ODOObject *object)
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
    
    if (!self->_recentlyInsertedObjects)
        self->_recentlyInsertedObjects = ODOEditingContextCreateRecentSet(self);
    
    [self->_recentlyInsertedObjects addObject:object];
    [self _registerObject:object];
}

// This is the global first-time insertion hook.  This should only be called with *new* objects.  That is, the undo of a delete should *not* go through here since that would re-call the -awakeFromInsert method.
- (void)insertObject:(ODOObject *)object;
{
    OBINVARIANT([self _checkInvariants]);
    
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
        ODOEditingContextInternalInsertObject(self, object);
        [object awakeFromInsert];
        
        // If this was to be undeletable, make sure it gets processed while undo is off
        if (undeletable) {
            while (_recentlyInsertedObjects || _recentlyUpdatedObjects || _recentlyDeletedObjects)
                [self processPendingChanges];
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
    NSError *error;
    NSMutableSet *toDelete;
    NSMutableDictionary *relationshipsToNullifyByObjectID;
    NSMutableDictionary *denyObjectIDToReferer;
} TraceForDeletionContext;

static void _traceForDeletion(ODOObject *object, TraceForDeletionContext *ctx);

static void _traceToManyRelationship(ODOObject *object, ODORelationship *rel, TraceForDeletionContext *ctx)
{
    OBPRECONDITION(rel.isToMany);
    
    // This is what to do to the *destination* of the relationship
    ODORelationshipDeleteRule rule = [rel deleteRule];

    ODORelationship *inverseRel = [rel inverseRelationship];
    NSString *forwardKey = [rel name];
    NSString *inverseKey = [inverseRel name];

    if (rule == ODORelationshipDeleteRuleDeny) {
        OBASSERT([inverseRel isToMany] == NO); // We don't allow many-to-many relationships in the model loading code
        OBRequestConcreteImplementation(object, @selector(_traceToManyRelationship)); // Handle once we have a test case
    }

    BOOL alsoCascade;
    if (rule == ODORelationshipDeleteRuleNullify) {
        alsoCascade = NO;
    } else if (rule == ODORelationshipDeleteRuleCascade) {
        alsoCascade = YES;
    } else {
        OBRequestConcreteImplementation(object, @selector(_traceToManyRelationship)); // unknown delete rule
    }
    
    // Nullify all the inverse to-ones.
    OBASSERT(inverseRel.isToMany == NO); // We don't allow many-to-many relationships in the model loading code
    OBASSERT(inverseRel.isCalculated == NO); // since the to-many is effectively calculated from the to-one, this would be silly.

    NSSet *targets = [object valueForKey:forwardKey];
    OBASSERT([targets isKindOfClass:[NSSet class]]);
    
    for (ODOObject *target in targets) {
        if (!inverseRel.isCalculated)
            _addNullify(target, inverseKey, ctx->relationshipsToNullifyByObjectID);
        if (alsoCascade && !_ODOObjectIsUndeletable(target))
            _traceForDeletion(target, ctx);
    }
}

static void _traceToOneRelationship(ODOObject *object, ODORelationship *rel, TraceForDeletionContext *ctx)
{
    OBPRECONDITION(!rel.isToMany);
    
    // This is what to do to the *destination* of the relationship
    ODORelationshipDeleteRule rule = [rel deleteRule];

    ODORelationship *inverseRel = [rel inverseRelationship];
    NSString *forwardKey = [rel name];
    NSString *inverseKey = [inverseRel name];
    
    if (rule == ODORelationshipDeleteRuleNullify) {
        if ([inverseRel isToMany]) {
            // We have a to-one and we need to remove ourselves from the inverse to-many.  We do this by clearing *our* to-one after faulting the inverse to-many.  Later it might be worth exploring ways to avoid doing this faulting.  Hopefully we can just clear our to-one and then any future fetches will do the right thing.
            ODOObject *dest = [object valueForKey:forwardKey];
            if (dest) {
#ifdef OMNI_ASSERTIONS_ON
                NSSet *inverseSet =
#endif
                [dest valueForKey:inverseKey]; // clears the fault
                OBASSERT([inverseSet member:object] == object);
                
                _addNullify(object, forwardKey, ctx->relationshipsToNullifyByObjectID);
            }
        } else {
            // one-to-one relationship. one side should be marked as calculated.
            OBASSERT(rel.isCalculated || inverseRel.isCalculated);
            
            ODOObject *dest = [object valueForKey:forwardKey];
            if (dest) {
                // nullify the side that isn't calculated.  we could maybe not do the nullify it is is the forward relationship (since the owner is getting entirely deleted).
                if (!rel.isCalculated)
                    _addNullify(object, forwardKey, ctx->relationshipsToNullifyByObjectID);
                if (!inverseRel.isCalculated)
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
            if (!rel.isCalculated)
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
    
    OBRequestConcreteImplementation(object, @selector(_traceForDeletion)); // unknown delete rule
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
        if (rel.isToMany)
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

static void _snapshotAndClearObjectForDeletionApplier(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    ODOEditingContext *self = context;
    
    // Reject if object is undeletable... should not have gotten this far. This means all undeletable objects must be inserted w/o undo enabled or having undo flushed afterwards.
    if (_ODOObjectIsUndeletable(object))
        OBRejectInvalidCall(self, @selector(_snapshotAndClearObjectForDeletionApplier), @"Undeletable objects should not be deleted!");
    
#ifdef OMNI_ASSERTIONS_ON
    // All the to-one relationships must be nil at this point. Otherwise, observation across a keyPath won't trigger due to objects along that keyPath being deleted and we might leak observation info.  Additionally, when a 'did delete' notification goes out and the observer removes its observed keyPath, the crossings of to-one relationships can return nil and be correct w/o asserting about asserting that we aren't doing KVC on deleted objects.
    {
        for (ODORelationship *rel in object.entity.toOneRelationships) {
            struct _ODOPropertyFlags flags = ODOPropertyFlags(rel);
            ODOObject *destination = _ODOObjectValueAtIndex(object, flags.snapshotIndex);
            OBASSERT(destination == nil);
        }
    }
#endif
    
    // Might have been snapshotted if we had a recent or processed update.  Otherwise, it shouldn't have been and we need to snapshot it now.
    OBASSERT(([self->_objectIDToCommittedPropertySnapshot objectForKey:[object objectID]] == nil && [self->_objectIDToLastProcessedSnapshot objectForKey:[object objectID]] == nil) == ([self->_recentlyUpdatedObjects member:object] == nil && [self->_processedUpdatedObjects member:object] == nil));
    [self _snapshotObjectPropertiesIfNeeded:object];
    
    // Turn the object into a fault.  This is what CoreData does, and our OFMTask/OFMProjectInfo mirroring expects this.
    // This also clears our properties.  Some of these may have already been cleared due to delete propagation, but not all of them.  Also, in the case that we are undoing an assertion, delete propagation won't clear any relationships for us in the deleted objects.
    [object _turnIntoFault:YES/*deleting*/];
}

static void _removeDenyApplier(const void *value, void *context)
{
    ODOObject *deletedObject = (ODOObject *)value;
    NSMutableDictionary *denyObjectIDToReferer = (NSMutableDictionary *)context;
    [denyObjectIDToReferer removeObjectForKey:[deletedObject objectID]];
}

static void _nullifyRelationships(const void *key, const void *value, void *context)
{
    ODOObjectID *objectID = (ODOObjectID *)key;
    NSArray *toOneKeys = (NSArray *)value;
    TraceForDeletionContext *ctx = context;
    
    DEBUG_DELETE(@"DELETE: nullify %@ %@", [objectID shortDescription], toOneKeys);
    
    ODOObject *object = [ctx->self->_registeredObjectByID objectForKey:objectID];
    OBASSERT(object);
    if (!object)
        return;
        
    // Any objects that were to get relationships nullified don't need to be nullified if they are also getting deleted.
    // Actually, this is false.  If we have an to-one, we need to nullify it so that the inverse to-many has a KVO cycle.  Otherwise, the to-many holder won't get in the updated set, or advertise its change.  Also, we need to publicize the to-one going to nil so that multi-stage KVO keyPath observations will stop their subpath observing.
    
    //if ([ctx->toDelete member:object])
    //return;
    
    for (NSString *key in toOneKeys) {
        ODORelationship *rel = [[[object entity] relationshipsByName] objectForKey:key];
        OBASSERT(rel);
        OBASSERT(rel.isToMany == NO);
        
        // If we are getting deleted, then use the internal path for clearing the forward relationship instead of calling the setter. But, if we are going to stick around (we are on the fringe of the delete cloud), call the setter.
        if ([ctx->toDelete member:object]) {
            [object willChangeValueForKey:key];
            ODOObjectSetPrimitiveValueForProperty(object, nil, rel);
            [object didChangeValueForKey:key];
        } else {
            [object setValue:nil forKey:key];
        }
    }
}

// This just registers the deletes and gathers snapshots for them.  Used both in the public API and in the undo support
static void ODOEditingContextInternalDeleteObjects(ODOEditingContext *self, NSSet *toDelete)
{
    DEBUG_DELETE(@"DELETE: internal delete %@", [toDelete setByPerformingSelector:@selector(shortDescription)]);

    // Some objects (I'm looking at you NSArrayController) are dumb as posts and if you clear their content, they'll ask their old content questions like, "Hey; what's your value for this key?".  That doesn't work well for deleted objects.  CoreData has some hack into NSArrayController to avoid this, we need something of the like.  For now we'll post a note before finalizing the deletion.
    [[NSNotificationCenter defaultCenter] postNotificationName:ODOEditingContextObjectsWillBeDeletedNotification object:self userInfo:[NSDictionary dictionaryWithObject:toDelete forKey:ODODeletedObjectsKey]];
    
    CFSetApplyFunction((CFSetRef)toDelete, _snapshotAndClearObjectForDeletionApplier, self);
    
    if (!self->_recentlyDeletedObjects)
        self->_recentlyDeletedObjects = ODOEditingContextCreateRecentSet(self);
    
    // Still shouldn't have any insertions, but we might have some locally created updates.  Some of these may now be overridden by our deletions (but the updates to their inverses won't be).
    OBASSERT(!self->_recentlyInsertedObjects);
    [self->_recentlyDeletedObjects unionSet:toDelete];
    [self->_recentlyUpdatedObjects minusSet:toDelete];
}

// Since we do delete propagation immediately, and since there is no other good point, we have an out NSError argument here for the results from -validateForDelete:.
- (BOOL)deleteObject:(ODOObject *)object error:(NSError **)outError;
{
    DEBUG_DELETE(@"DELETE: object:%@", [object shortDescription]);
    
    OBINVARIANT([self _checkInvariants]);
    OBPRECONDITION(!_isValidatingAndWritingChanges); // Can't make edits in the validation methods
    OBPRECONDITION(object);
    OBPRECONDITION([object editingContext] == self);
    OBPRECONDITION([_registeredObjectByID objectForKey:[object objectID]] == object); // has to be registered
#if ODO_SUPPORT_UNDO
    OBPRECONDITION(![_undoManager isUndoing] && ![_undoManager isRedoing]); // this public API shouldn't be called to undo/redo.  Only to 'do'.
#endif
    
    // Bail on objects that are already deleted or invalid instead of crashing.  This can easily happen if UI code can select both a parent and child and delete them w/o knowing that the deletion of the parent will get the child too.  Nice if the UI handles it, but shouldn't crash or do something crazy otherwise.
    if ([object isInvalid] || [object isDeleted]) {
        DEBUG_DELETE(@"DELETE: already invalid:%d deleted:%d -- bailing", [object isInvalid], [object isDeleted]);
        return YES; // maybe return a user-cancelled error?
    }
    
    if (_ODOObjectIsUndeletable(object)) {
        // Whether this is right is debatable.  Maybe we should do the deletion as normal with propagation nullifying the relationships.  On the down side, that could result in no updates and just nullifications (but we have the problem of -prepareForDeletion doing edits when the deletion is rejected anyway...)
        // Returning a user-cancelled error here since, unlike the the invalid/deleted case, we return with 'object' still being live.
        DEBUG_DELETE(@"DELETE: undeletable -- bailing");
        OBUserCancelledError(outError);
        return NO;
    }
    
    OBASSERT(![object isInvalid]);
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
        if (outError)
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
    
    CFDictionaryApplyFunction((CFDictionaryRef)ctx.relationshipsToNullifyByObjectID, _nullifyRelationships, &ctx);
    
    ODOEditingContextInternalDeleteObjects(self, ctx.toDelete);
    
    OBINVARIANT([self _checkInvariants]);

    return YES;
}

static void _forgetObjectApplier(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    NSMutableDictionary *objectByID = (NSMutableDictionary *)context;
    
    ODOObjectID *objectID = [object objectID];
    OBASSERT([objectByID objectForKey:objectID] == object);
    [objectByID removeObjectForKey:objectID];
}

static void ODOEditingContextDidDeleteObjects(ODOEditingContext *self, NSSet *deleted)
{
    [deleted makeObjectsPerformSelector:@selector(_invalidate)]; // Once saved, deleted objects are gone forever.  Unless we resurrect them by pointer for undo.  Might just create new objects.
    
    // Forget the invalidated objects.  They still have their objectID, which is good since we need to remove those keys from our registered objects.
    CFSetApplyFunction((CFSetRef)deleted, _forgetObjectApplier, self->_registeredObjectByID);
}

static NSDictionary *_createChangeSetNotificationUserInfo(NSSet *inserted, NSSet *updated, NSSet *deleted)
{
    // Making copies of these sets since we mutate _recentlyUpdatedObjects below while merging (at least for the call from -_internal_processPendingChanges
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    if (inserted) {
        NSSet *set = [inserted copy];
        [userInfo setObject:set forKey:ODOInsertedObjectsKey];
        [set release];
    }
    if (updated) {
        NSSet *set = [updated copy];
        [userInfo setObject:set forKey:ODOUpdatedObjectsKey];
        [set release];
        
        // Build a subset of the objects that have material edits.
        NSMutableSet *materialUpdates = nil;
        for (ODOObject *object in updated) {
            // Might be called for a recent update of a processed insert and -changedNonDerivedChangedValue currently does OBRequestConcreteImplementation() for inserted objects since its meaning is unclear in general.  Here we'll contend that an 'insert' is a material update (even if no recent updates are material).
            if ([object isInserted] || [object changedNonDerivedChangedValue]) {
                if (!materialUpdates)
                    materialUpdates = [[NSMutableSet alloc] init];
                
                [materialUpdates addObject:object];
#if 0 && defined(DEBUG_bungi)
                NSLog(@"material update to %@: %@", [object shortDescription], [object isInserted] ? (id)object : (id)[object changedValues]);
#endif
            } else {
#if 0 && defined(DEBUG_bungi)
                NSLog(@"dropping phantom update to %@; changes = %@", [object shortDescription], [object changedValues]);
#endif
            }
        }
        if (materialUpdates) {
            [userInfo setObject:materialUpdates forKey:ODOMateriallyUpdatedObjectsKey];
            [materialUpdates release];
        }
    }
    
    if (deleted) {
        NSSet *set = [deleted copy];
        [userInfo setObject:set forKey:ODODeletedObjectsKey];
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
    NSDictionary *userInfo = _createChangeSetNotificationUserInfo(_recentlyInsertedObjects, _recentlyUpdatedObjects, _recentlyDeletedObjects);
    NSNotification *note = [NSNotification notificationWithName:ODOEditingContextObjectsDidChangeNotification object:self userInfo:userInfo];
    [userInfo release];

    // Register undos based on the recent changes, if we have an undo manager, along with any snapshots necessary to get back into the right state after undoing.
    // TODO: Record only the object IDs and snapshots?
    // TODO: These snapshots aren't right -- they are from the last *save* but we need snapshots from the last -processPendingChanges.
#if ODO_SUPPORT_UNDO
    if (_undoManager)
        [self _registerUndoForRecentChanges];
#endif
    
    //
    // Merge the recent changes into the processed changes.
    //
    
    // Our recent snapshots can be thrown away (any time after the undo is logged really).  In fact, maybe we shouldn't keep this if we don't have an undo manager/on iPhone.
    [_objectIDToLastProcessedSnapshot release];
    _objectIDToLastProcessedSnapshot = nil;
    
    // Any updates that are to processed inserts (i.e., an object was inserted, changes processed and then updated) are irrelevant as far as -save: is concerned (though undo and notifications care above).
    [_recentlyUpdatedObjects minusSet:_processedInsertedObjects];
    
    // Any previously processed inserts or updates that have recently been deleted are also now irrelevant for -save:.
    if (_recentlyDeletedObjects) {
        // Also, any processed inserts are irrelevant for -save:.  That is, the processed insert and recent delete cancel out.
        if ([_processedInsertedObjects intersectsSet:_recentlyDeletedObjects]) {
            NSMutableSet *canceledInserts = [[NSMutableSet alloc] initWithSet:_recentlyDeletedObjects];
            [canceledInserts intersectSet:_processedInsertedObjects];
            [_recentlyDeletedObjects minusSet:canceledInserts];
            [_processedInsertedObjects minusSet:canceledInserts];
            
            // These canceled inserts are now gone forever!  Update our state the same as if we'd saved the deletes
            ODOEditingContextDidDeleteObjects(self, canceledInserts);
            [canceledInserts release];
        }
        
        [_processedUpdatedObjects minusSet:_recentlyDeletedObjects];
    }
    
    // Any remaining recent operations should merge right across.  If we didn't have changes in a category, steal the recent set rather than building a new one.
    if (_processedInsertedObjects)
        [_processedInsertedObjects unionSet:_recentlyInsertedObjects];
    else  {
        _processedInsertedObjects = _recentlyInsertedObjects;
        _recentlyInsertedObjects = nil;
    }
    if (_processedUpdatedObjects)
        [_processedUpdatedObjects unionSet:_recentlyUpdatedObjects];
    else {
        _processedUpdatedObjects = _recentlyUpdatedObjects;
        _recentlyUpdatedObjects = nil;
    }
    if (_processedDeletedObjects) 
        [_processedDeletedObjects unionSet:_recentlyDeletedObjects];
    else {
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

    [[NSNotificationCenter defaultCenter] postNotification:note];
    
    return YES;
}

- (BOOL)processPendingChanges;
{
    OBINVARIANT([self _checkInvariants]);
    OBPRECONDITION(!_isSendingWillSave); // See -_sendWillSave:
    OBPRECONDITION(!_isValidatingAndWritingChanges); // Can't call -processPendingChanges while validating.  Would be pointless anyway since it has already been called and we don't allow making edits paste -_sendWillSave:
    OBPRECONDITION(![_recentlyInsertedObjects intersectsSet:_recentlyUpdatedObjects]);
    OBPRECONDITION(![_recentlyInsertedObjects intersectsSet:_recentlyDeletedObjects]);
    OBPRECONDITION(![_recentlyUpdatedObjects intersectsSet:_recentlyDeletedObjects]);
    
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

// These reflect the total current set of unsaved edits, including unprocessed changes.  Note that since we need to send 'updated' notifications when an inserted object gets further edits, the recently updated set might contain inserted objects.  This doesn't mean the object is in the inserted state as far as what will happen when -save: is called, though.
- (NSSet *)insertedObjects;
{
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
    // Deleted objects can't become alive again w/o an undo, so we don't need to check the recent updates or inserts here.
    if (!_recentlyDeletedObjects) {
        if (!_processedDeletedObjects)
            return [NSSet set]; // return nil, or at least a shared instance?
        return [NSSet setWithSet:_processedDeletedObjects];
    }
    
    NSMutableSet *result = [NSMutableSet setWithSet:_processedUpdatedObjects];
    [result unionSet:_recentlyDeletedObjects];
    return result;
}

// TODO: -reset/-undo should remove inserted objects from the registered objects.  Redo should likewise update the registered objects.

- (NSDictionary *)registeredObjectByID;
{
    // Deleted objects shouldn't be unregistered until the save.
    return [NSDictionary dictionaryWithDictionary:_registeredObjectByID];
}

static BOOL _queryUniqueSet(NSSet *set, ODOObject *query)
{
    id obj = [set member:query];
    OBASSERT(obj == nil || obj == query);
    return obj != nil;
}

- (BOOL)isInserted:(ODOObject *)object;
{
    // Pending delete that might kill the insert when processed?
    if (_queryUniqueSet(_recentlyDeletedObjects, object))
        return NO;
    return _queryUniqueSet(_processedInsertedObjects, object) || _queryUniqueSet(_recentlyInsertedObjects, object);
}

// As with -updatedObjects, this is tricky since processed inserts can be recently updated for notification/undo purposes.
- (BOOL)isUpdated:(ODOObject *)object;
{
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
    // Objects can't be reinserted or updated once they have been deleted without an undo.  So our recent inserts/updates aren't relevant here.
    return _queryUniqueSet(_processedDeletedObjects, object) || _queryUniqueSet(_recentlyDeletedObjects, object);
}

- (BOOL)isRegistered:(ODOObject *)object;
{
    OBPRECONDITION(object);
    
    ODOObjectID *objectID = [object objectID];
    ODOObject *registered = [_registeredObjectByID objectForKey:objectID];
    OBASSERT(registered == nil || registered == object);
    return registered != nil;
}

- (void)setShouldSetSaveDates:(BOOL)shouldSetSaveDates;
{
    OBPRECONDITION(_saveDate == nil); // Don't set this in the middle of -save:
    
    // Store the inverse so that the default BOOL of NO preserves the right behavior
    _avoidSettingSaveDates = !shouldSetSaveDates;
}

- (BOOL)shouldSetSaveDates;
{
    return !_avoidSettingSaveDates;
}

- (BOOL)saveWithDate:(NSDate *)saveDate error:(NSError **)outError;
{
    OBPRECONDITION(_saveDate == nil);
    OBINVARIANT([self _checkInvariants]);

    //NSLog(@"saving...");
    
    _saveDate = [saveDate copy];
    
    if (![self _sendWillSave:outError]) {
        OBINVARIANT([self _checkInvariants]);
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
        NSDictionary *userInfo = _createChangeSetNotificationUserInfo(_processedInsertedObjects, _processedUpdatedObjects, _processedDeletedObjects);
        NSNotification *note = [NSNotification notificationWithName:ODOEditingContextDidSaveNotification object:self userInfo:userInfo];
        [userInfo release];

        if (![_database _beginTransaction:outError]) {
            OBINVARIANT([self _checkInvariants]);
            return NO;
        }
        
        // Ask ODODatabase to write (but not clear) its _pendingMetadataChanges
        if (![_database _writeMetadataChanges:outError]) {
            OBINVARIANT([self _checkInvariants]);
            return NO;
        }
        
        if (![self _writeProcessedEdits:outError]) {
            OBINVARIANT([self _checkInvariants]);
            return NO;
        }
        
        if (![_database _commitTransaction:outError]) {
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
        [_processedInsertedObjects makeObjectsPerformSelector:@selector(didSave)];
        [_processedInsertedObjects release];
        _processedInsertedObjects = nil;
        [_processedUpdatedObjects makeObjectsPerformSelector:@selector(didSave)];
        [_processedUpdatedObjects release];
        _processedUpdatedObjects = nil;
        
        // Deleted objects currently get -willDelete, but no -didSave.
        if (_processedDeletedObjects) {
            // Move this aside so that ODOObjectClearValues() doesn't assert on the passed in object being -isDeleted.
            NSSet *deleted = _processedDeletedObjects;
            _processedDeletedObjects = nil;
            
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

- (NSDate *)saveDate;
{
    OBPRECONDITION(_saveDate); // Set only during -saveWithDate:error:; shouldn't be called outside of that method
    return _saveDate;
}

- (BOOL)hasChanges;
{
    // This might lie if we've had a insert followed by a delete that got rid of it w/o a -processPendingChanges.  Does CoreData handle that?
    if (_recentlyInsertedObjects || _recentlyUpdatedObjects || _recentlyDeletedObjects)
        return YES;
    if (_processedInsertedObjects || _processedUpdatedObjects || _processedDeletedObjects)
        return YES;
    return NO;
}

- (BOOL)hasUnprocessedChanges;
{
    if (_recentlyInsertedObjects || _recentlyUpdatedObjects || _recentlyDeletedObjects)
        return YES;
    return NO;
}

- (ODOObject *)objectRegisteredForID:(ODOObjectID *)objectID;
{
    return [_registeredObjectByID objectForKey:objectID];
}

static BOOL _fetchPrimaryKeyCallback(struct sqlite3 *sqlite, ODOSQLStatement *statement, void *context, NSError **outError)
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
        // Object hasn't been created as a fault or a fully realized object yet.  Create a fresh object and fill it out.
        object = [[ctx->instanceClass alloc] initWithEditingContext:editingContext objectID:objectID isFault:NO];
        
        if (!ODOExtractNonPrimaryKeySchemaPropertiesFromRowIntoObject(sqlite, statement, object, ctx, outError)) {
            [object release];
            [objectID release];
            return NO;
        }
        [editingContext _registerObject:object];
        
        OBASSERT(ctx->fetched);
        [ctx->fetched addObject:object];
        [object release];
    } else if ([object isDeleted]) {
        // Deleted objects are now turned into faults until they are saved.  So, we drop them when fetching.
        object = nil;
    } else if ([object isFault]) {
        // Create the values array to take the values we are about to fetch
        _ODOObjectCreateNullValues(object);

        // Object was previously created as a fault, but hasn't been filled in yet.  Let's do so and mark it cleared.
        if (!ODOExtractNonPrimaryKeySchemaPropertiesFromRowIntoObject(sqlite, statement, object, ctx, outError)) {
            [objectID release];
            return NO; // object will remain a fault but might have some values in it.  they'll get reset if we get fetched again.  might be nice to clean them out, though.
        }
        [object _setIsFault:NO];
        
        OBASSERT(ctx->fetched);
        [ctx->fetched addObject:object];
    } else {
        // Object has previously been fetched and we are redundantly fetching it.  
    }
    [objectID release];

    if (object)
        [ctx->results addObject:object];
    
    return YES;
}

- (NSArray *)executeFetchRequest:(ODOFetchRequest *)fetch error:(NSError **)outError;
{
    OBINVARIANT([self _checkInvariants]);

    if (_isResetting) {
        // Act as if we are attached to an empty database
        return [NSArray array];
    }
    
    // TODO: Can't be in the middle of another fetch or we'll b0rk it up.  Add some sort of assertion to check this method vs. itself and faulting.
    
    // It's unclear whether it is worthwhile caching the conversion from SQL to a statement and if so how best to do it.  Instead, we'll build a statement, use it and discard it.  Predicates can have both column expressions and constants.  To avoid quoting issues, we could try to build a SQL string with bindings ('?') and a list of constants in parallel, prepare the statement and then bind the constants.  One problem with this is the IN expression.  The rhs might have any number of values 'foo IN ("a", "b", "c")' so we would have to count the collection to get the right number of slots to bind.
    // TODO: If we *do* start caching the statements we'll need to be wary of the copy semantics for text/blob (mostly text) bindings.  Right now we are copying (safe but slower), but if we try to optimize this uncarefully, we could end up crashing (since qualifiers could be reused and the original bytes might have been deallocated).
    
    // We just select the primary keys and will build faults for any objects that we don't have in memory already.
    ODOEntity *rootEntity = [fetch entity];
    ODOAttribute *primaryKeyAttribute = [rootEntity primaryKeyAttribute];
    NSPredicate *predicate = [fetch predicate];
    
    ODORowFetchContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.entity = rootEntity;
    ctx.instanceClass = [rootEntity instanceClass];
    ctx.schemaProperties = [rootEntity _schemaProperties];
    ctx.primaryKeyAttribute = primaryKeyAttribute;
    ctx.primaryKeyColumnIndex = [ctx.schemaProperties indexOfObjectIdenticalTo:primaryKeyAttribute];
    ctx.editingContext = self;
    ctx.results = [NSMutableArray array];
    ctx.fetched = [NSMutableArray array]; // We need to know about this
    
    OBASSERT(ctx.primaryKeyColumnIndex != NSNotFound);
    
    // Even if we aren't connected, we can still do in-memory operations.  If the database is totally fresh (no saves have been done since the schema was created) doing a fetch is pointless.  This is an optimization for the import case where we fill caches prior to saving for the first time
    if ([_database connectedURL] && ![_database isFreshlyCreated]) {
        //NSLog(@"fetch: %@, predicate = %@, sort = %@", [[fetch entity] name], [fetch predicate], [fetch sortDescriptors]);
        if (ODOLogSQL) {
            NSString *reason = [fetch reason];
            if ([reason length] == 0)
                reason = @"UNKNOWN";
            //ODOSQLStatementLogSQL(@"/* execute fetch: %@  predicate: %@  sort: %@  reason: %@ */", [[fetch entity] name], [fetch predicate], [fetch sortDescriptors], reason);
            ODOSQLStatementLogSQL(@"/* SQL fetch: %@  reason: %@ */ ", [[fetch entity] name], reason);
        }
        
        ODOSQLStatement *query = [[ODOSQLStatement alloc] initSelectProperties:ctx.schemaProperties fromEntity:rootEntity database:_database predicate:predicate error:outError];
        if (!query) {
#ifdef DEBUG
            NSLog(@"Failed to build query: %@", outError ? (id)[*outError toPropertyList] : (id)@"Missing error");
#endif
            OBINVARIANT([self _checkInvariants]);
            return nil;
        }
        
        // TODO: Append the sort descriptors as a 'order by'?  Can't if they have non-schema properties, so for now we can just sort in memory.
        
        BOOL success = NO;
        
        @try {
            ODOSQLStatementCallbacks callbacks;
            memset(&callbacks, 0, sizeof(callbacks));
            callbacks.row = _fetchPrimaryKeyCallback;
            
            success = ODOSQLStatementRun([_database _sqlite], query, callbacks, &ctx, outError);
        } @finally {
            // Having this -autoreleased can mean we have non-finalized queries when trying to disconnect the database.
            [query invalidate];
            [query release];
        }
        
        if (!success) {
#ifdef DEBUG
            NSLog(@"Failed to run query: %@", outError ? (id)[*outError toPropertyList] : (id)@"Missing error");
#endif
            OBINVARIANT([self _checkInvariants]);
            return nil;
        }

        // Inform all the newly fetched objects that they have been fetched.  Do this *outside* running the fetch so that if they cause further fetching/faulting, they won't screw up our fetch in progress.
        ODOObjectAwakeObjectsFromFetch(ctx.fetched);
    }
    
    if ([self hasChanges]) {
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        ODOUpdateResultSetForInMemoryChanges(self, ctx.results, rootEntity, predicate);
        CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();

        if (ODOLogSQL) {
            NSString *reason = [fetch reason];
            if ([reason length] == 0)
                reason = @"UNKNOWN";
            ODOSQLStatementLogSQL(@"/* Memory fetch: %@  reason: %@ */\n/* ... %g sec, count now %d */\n", [[fetch entity] name], reason, end - start, [ctx.results count]);
        }
    }

    NSArray *sortDescriptors = [fetch sortDescriptors];
    if ([sortDescriptors count] > 0)
        [ctx.results sortUsingDescriptors:sortDescriptors];
    
#ifdef DEBUG
    // Help make sure we don't have support for *fetching* a predicate that we'll evaluate differently in memory.
    // This won't detect the inverse case (SQL doesn't match but in memory doesn't).
    if (predicate) {
        for (ODOObject *object in ctx.results)
            OBPOSTCONDITION([predicate evaluateWithObject:object]);
    }
#endif
    
    OBINVARIANT([self _checkInvariants]);
    return ctx.results;
}

- insertObjectWithEntityName:(NSString *)entityName;
{
    ODOEntity *entity = [self.database.model entityNamed:entityName];
    ODOObject *object = [[[[entity instanceClass] alloc] initWithEditingContext:self entity:entity primaryKey:nil] autorelease];
    [self insertObject:object];
    return object;
}

- (ODOObject *)fetchObjectWithObjectID:(ODOObjectID *)objectID error:(NSError **)outError; // Returns NSNull if the object wasn't found, nil on error.
{
    OBPRECONDITION(objectID);
    
    ODOEntity *entity = [objectID entity];
    if (!entity) {
        OBASSERT(entity);
        return nil;
    }
    
    ODOObject *object = (ODOObject *)[self objectRegisteredForID:objectID];
    if (object) {
        if ([object isInvalid]) {
            OBASSERT_NOT_REACHED("Maybe should have been purged from the registered objects?");
            // ... but maybe it is in the undo stack or otherwise not deallocated.  At any rate, this is happening, so let's be defensive.  See <bug://45150> (Clicking URL to recently deleted task can crash)
            return (id)[NSNull null];
        }
        
        OBASSERT([[object objectID] isEqual:objectID]);
        return object;
    }
    
    if ([_database isFreshlyCreated])
        return (id)[NSNull null]; // Don't waste time looking for an object in our empty database

    ODOFetchRequest *fetch = [[[ODOFetchRequest alloc] init] autorelease];
    [fetch setEntity:entity];
    [fetch setPredicate:ODOKeyPathEqualToValuePredicate([[entity primaryKeyAttribute] name], [objectID primaryKey])];
    
    NSArray *objects = [self executeFetchRequest:fetch error:outError];
    if (!objects)
        return nil; // error
    
    if ([objects count] == 0)
        return (id)[NSNull null]; // legitmately not found
    
    OBASSERT([objects count] == 1);
    
    object = [objects objectAtIndex:0];
    OBASSERT([self objectRegisteredForID:objectID] == object);
    
    return object;
}


NSString * const ODOEditingContextObjectsWillBeDeletedNotification = @"ODOEditingContextObjectsWillBeDeletedNotification";
NSString * const ODOEditingContextObjectsDidChangeNotification = @"ODOEditingContextObjectsDidChangeNotification";
NSString * const ODOEditingContextWillSaveNotification = @"ODOEditingContextWillSaveNotification";
NSString * const ODOEditingContextDidSaveNotification = @"ODOEditingContextDidSaveNotification";
NSString * const ODOInsertedObjectsKey = @"ODOInsertedObjectsKey";
NSString * const ODOUpdatedObjectsKey = @"ODOUpdatedObjectsKey";
NSString * const ODOMateriallyUpdatedObjectsKey = @"ODOMateriallyUpdatedObjectsKey";
NSString * const ODODeletedObjectsKey = @"ODODeletedObjectsKey";

NSString * const ODOEditingContextWillResetNotification = @"ODOEditingContextWillReset";
NSString * const ODOEditingContextDidResetNotification = @"ODOEditingContextDidReset";

#pragma mark -
#pragma mark Private

- (void)_databaseConnectionDidChange:(NSNotification *)note;
{
    [self reset];
}

- (BOOL)_sendWillSave:(NSError **)outError;
{
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
                NSDictionary *userInfo = [_createChangeSetNotificationUserInfo(_processedInsertedObjects, _processedUpdatedObjects, _processedDeletedObjects) autorelease];
                [[NSNotificationCenter defaultCenter] postNotificationName:ODOEditingContextWillSaveNotification object:self userInfo:userInfo];
                
                [_processedInsertedObjects makeObjectsPerformSelector:@selector(willInsert)];
                [_processedUpdatedObjects makeObjectsPerformSelector:@selector(willUpdate)];
                [_processedDeletedObjects makeObjectsPerformSelector:@selector(willDelete)]; // OmniFocusModel, in particular OFMProjectInfo's metadata support, wants to be notified when a delete is saved, as opposed to happening in memory (-prepareForDeletion)
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

typedef struct {
    NSMutableArray *validationErrors;
    SEL sel;
} ValidationContext;

typedef BOOL (*validationMethod)(id self, SEL _cmd, NSError **outError);

static void _validateApplier(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    ValidationContext *ctx = context;
    
    NSError *error = nil;
    BOOL success = ((validationMethod)objc_msgSend)(object, ctx->sel, &error);
    if (!success) {
        if (!ctx->validationErrors)
            ctx->validationErrors = [NSMutableArray array];
        [ctx->validationErrors addObject:error];
    }
}

// Delete validation occurs when -deleteObject: is called
- (BOOL)_validateInsertsAndUpdates:(NSError **)outError;
{
    OBPRECONDITION(!_recentlyInsertedObjects);
    OBPRECONDITION(!_recentlyUpdatedObjects);
    OBPRECONDITION(!_recentlyDeletedObjects);
    
    ValidationContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    
    if (_processedInsertedObjects) {
        ctx.sel = @selector(validateForInsert:);
        CFSetApplyFunction((CFSetRef)_processedInsertedObjects, _validateApplier, &ctx);
    }
    if (_processedUpdatedObjects) {
        ctx.sel = @selector(validateForUpdate:);
        CFSetApplyFunction((CFSetRef)_processedUpdatedObjects, _validateApplier, &ctx);
    }
    
    if (!ctx.validationErrors)
        return YES;
    
    // TODO: Should we collect the validation errors into an ivar?  This approach will build an array of arrays of errors rather than a flat array of all errors across all objects.
    if ([ctx.validationErrors count] == 1) {
        if (outError)
            *outError = [ctx.validationErrors lastObject];
    } else {
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Multiple validation errors occurred while saving.", @"OmniDataObjects", OMNI_BUNDLE, @"error reason");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to save.", @"OmniDataObjects", OMNI_BUNDLE, @"error description");
        ODOErrorWithInfo(outError, ODOUnableToSave, description, reason, ODODetailedErrorsKey, ctx.validationErrors, nil);
    }
    
    return NO;
}

typedef struct {
    ODODatabase *database;
    sqlite3 *sqlite;
    BOOL errorOccurred;
    NSError **outError;
} WriteSQLApplierContext;

static void _writeInsertApplier(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    WriteSQLApplierContext *ctx = context;
    
    if (ctx->errorOccurred)
        return;
    if (![[object entity] _writeInsert:ctx->sqlite database:ctx->database object:object error:ctx->outError])
        ctx->errorOccurred = YES;
}

static void _writeUpdateApplier(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    WriteSQLApplierContext *ctx = context;
    
    if (ctx->errorOccurred)
        return;
    if (![[object entity] _writeUpdate:ctx->sqlite database:ctx->database object:object error:ctx->outError])
        ctx->errorOccurred = YES;
}

static void _writeDeleteApplier(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    WriteSQLApplierContext *ctx = context;
    
    if (ctx->errorOccurred)
        return;
    if (![[object entity] _writeDelete:ctx->sqlite database:ctx->database object:object error:ctx->outError])
        ctx->errorOccurred = YES;
}

// Writes the changes, but doesn't clear them (the transaction may fail).
- (BOOL)_writeProcessedEdits:(NSError **)outError;
{
    OBPRECONDITION(_recentlyInsertedObjects == nil);
    OBPRECONDITION(_recentlyUpdatedObjects == nil);
    OBPRECONDITION(_recentlyDeletedObjects == nil);
    OBPRECONDITION(_objectIDToLastProcessedSnapshot == nil);
    
    // For deletes, there might be a speed advantage to grouping by entity and then issuing a delete where pk in (...) but binding values wouldn't let us bind the set of values.  Maybe we could have a prepared statement for 'delete 10 things' and use that until we had < 10.  Or fill out the last N bindings in the statement with repeated PKs.  Also, angels on a pinhead.
    WriteSQLApplierContext ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.database = _database;
    ctx.sqlite = [_database _sqlite];
    ctx.outError = outError;
    
    if (_processedInsertedObjects)
        CFSetApplyFunction((CFSetRef)_processedInsertedObjects, _writeInsertApplier, &ctx);
    if (ctx.errorOccurred)
        return NO;
    
    if (_processedUpdatedObjects)
        CFSetApplyFunction((CFSetRef)_processedUpdatedObjects, _writeUpdateApplier, &ctx);
    if (ctx.errorOccurred)
        return NO;
    
    if (_processedDeletedObjects)
        CFSetApplyFunction((CFSetRef)_processedDeletedObjects, _writeDeleteApplier, &ctx);
    if (ctx.errorOccurred)
        return NO;
    
    return YES;
}

#if ODO_SUPPORT_UNDO

static void _appendObjectID(const void *value, void *context)
{
    ODOObject *object = (ODOObject *)value;
    CFMutableArrayRef objectIDs = (CFMutableArrayRef)context;
    CFArrayAppendValue(objectIDs, [object objectID]);
}

static NSArray *_copyCollectObjectIDs(NSSet *objects)
{
    if (!objects)
        return nil;
    
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
    CFArrayRef snapshot = (CFArrayRef)[ctx->objectIDToLastProcessedSnapshot objectForKey:objectID];

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
    
    DEBUG_UNDO(@"Registering operation during %@:", [_undoManager isUndoing] ? @"undo" : ([_undoManager isRedoing] ? @"redo" : @"'doing'"));
    if (objectIDsAndSnapshotsToInsert) {
        DEBUG_UNDO(@"objectIDsAndSnapshotsToInsert = %@", [(id)CFCopyDescription(objectIDsAndSnapshotsToInsert) autorelease]);
    }
    if (updates) {
        DEBUG_UNDO(@"updates = %@", [(id)CFCopyDescription(updates) autorelease]);
    }
    if (objectIDsToDelete) {
        DEBUG_UNDO(@"objectIDsToDelete = %@", objectIDsToDelete);
    }
    
    [[_undoManager prepareWithInvocationTarget:self] _undoWithObjectIDsAndSnapshotsToInsert:objectIDsAndSnapshotsToInsert updates:updates objectIDsToDelete:objectIDsToDelete];

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
    NSArray *toOneRelationships = [entity toOneRelationships];
    
    for (ODORelationship *rel in toOneRelationships) {
        ODORelationship *inverseRel = [rel inverseRelationship];
        
        NSString *forwardKey = [rel name];
        NSString *invKey = [inverseRel name];
        ODOObject *dest = ODOGetPrimitiveProperty(object, forwardKey);
        if (!dest)
            continue;
        
        if (![inverseRel isToMany]) {
            if (action == ODOEditingContextUndoRelationshipsForDeletion) {
                // one-to-one. nullify the forward key, which should nullify the inverse too.
                if (dest) {
                    [object willChangeValueForKey:forwardKey];
                    ODOObjectSetPrimitiveValueForProperty(object, nil, rel);
                    [object didChangeValueForKey:forwardKey];
                    
                    OBASSERT([dest valueForKey:invKey] == nil);
                }
            } else {
                // The inverse will be restored from the other side's snapshot.
            }
            
            continue;
        }
        
        // Avoid creating/clearing the inverse to-many (our primitive getter would do that).
        NSMutableSet *toManySet = ODOObjectToManyRelationshipIfNotFault(dest, inverseRel);
        
        NSSet *change = [NSSet setWithObject:object];
        
        if (action == ODOEditingContextUndoRelationshipsForInsertion) {
            OBASSERT([toManySet member:object] == nil);
            [dest willChangeValueForKey:invKey withSetMutation:NSKeyValueUnionSetMutation usingObjects:change];
            [toManySet addObject:object];
            [dest didChangeValueForKey:invKey withSetMutation:NSKeyValueUnionSetMutation usingObjects:change];
        } else {
            OBASSERT(action == ODOEditingContextUndoRelationshipsForDeletion);
            OBASSERT([toManySet member:object] != nil); // the relationship should be fully formed before we act
            
            // Need to clear the forward to-ones too, to ensure that on undo/redo, any multi-stage keyPaths get their KVO on sub-paths deregistered. Then, when the outside objects remove observers, our to-one getters can return nil and they can clean up w/o trouble.
            OBASSERT(dest); // checked above
            OBASSERT(![object isFault]);
            [object willChangeValueForKey:forwardKey];
            ODOObjectSetPrimitiveValueForProperty(object, nil, rel);
            [object didChangeValueForKey:forwardKey];

            OBASSERT([toManySet member:object] == nil); // ODOObjectSetPrimitiveValueForProperty should have cleaned up and sent KVO for the inverse to-many too.
        }
    }
}

- (void)_undoWithObjectIDsAndSnapshotsToInsert:(NSArray *)objectIDsAndSnapshotsToInsert updates:(NSArray *)updates objectIDsToDelete:(NSArray *)objectIDsToDelete;
{
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
    
    // Perform the indicated changes.  DO NOT use public API here.  We don't want to re-validate deletes or resend -awakeFromInsert, for example.
    // Additionally, all the changes made/advertised here should be *local* to the objects being edited.  For example, we should not re-nullify relationships on deletions since that's been done already and should be captured in the other undos.
    // The exception to this is KVO & maintainence of already-cleared to-many relationships.  Since to-many relationships are not recorded directly in the deltas, we have to update them here (but still going through internal API).
    
    // Do the inserts first; updates that follow might have been due to nullified relationships for the deletes these represent.
    NSUInteger insertIndex, insertCount = [objectIDsAndSnapshotsToInsert count];
    OBASSERT((insertCount % 2) == 0); // should be objectID/snapshot sets
    for (insertIndex = 0; insertIndex < insertCount; insertIndex += 2) {
        ODOObjectID *objectID = [objectIDsAndSnapshotsToInsert objectAtIndex:insertIndex+0];
        CFArrayRef snapshot = (CFArrayRef)[objectIDsAndSnapshotsToInsert objectAtIndex:insertIndex+1];

        DEBUG_UNDO(@"  insert objectID:%@ snapshot:%@", objectID, [(id)CFCopyDescription(snapshot) autorelease]);
        
        ODOEntity *entity = [objectID entity];
        ODOObject *object = [[[entity instanceClass] alloc] initWithEditingContext:self objectID:objectID snapshot:snapshot];
        ODOEditingContextInternalInsertObject(self, object);
        [object release];
    }
    
    // After *ALL* the inserts have happened, scan each re-inserted object for non-nil to-one relationships.  If the inverse is to-many, then we need to send KVO and (if the fault has been cleared) update the set.  If we do this incrementally as we insert objects, we might end up inserting object A with a snapshot that has a to-one foreign key pointing to B.  If we scan for updating inverse to-manys, we'd end up creating a fault for B (it not being inserted yet) and then things go down hill.
    for (insertIndex = 0; insertIndex < insertCount; insertIndex += 2) {
        ODOObjectID *objectID = [objectIDsAndSnapshotsToInsert objectAtIndex:insertIndex+0];
        ODOObject *object = [_registeredObjectByID objectForKey:objectID];
        
        OBASSERT([object isInserted]);
        _updateRelationshipsForUndo(object, [objectID entity], ODOEditingContextUndoRelationshipsForInsertion);
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
    if ([objectIDsToDelete count] > 0) {
        NSMutableSet *toDelete = [NSMutableSet set];
        for (ODOObjectID *objectID in objectIDsToDelete) {
            ODOObject *object = [self objectRegisteredForID:objectID];
            if (!object) {
                OBASSERT_NOT_REACHED("Should not be able to delete an object that isn't registered");
                continue;
            }
            
            OBASSERT([toDelete member:object] == nil); // no dups, please
            [toDelete addObject:object];

            // Scan each re-deleted object for non-nil to-one relationships.  If the inverse is to-many, then we need to send KVO and (if the fault has been cleared) update the set.
            // We also need to clear the to-ones to ensure that keyPath observations get dropped and that our to-one accessors can return nil (they'll be called when an observer is removing multi-step keyPath observations).
            _updateRelationshipsForUndo(object, [objectID entity], ODOEditingContextUndoRelationshipsForDeletion);
        }
        
        OBASSERT([toDelete count] > 0);
        ODOEditingContextInternalDeleteObjects(self, toDelete);
    }

    // Process changes immediately.  This will log our opposite undo/redo action.
    [self processPendingChanges];
}

#endif

@end

