// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

#import <CoreFoundation/CFArray.h>
#import <OmniDataObjects/ODOFeatures.h>
#import <OmniDataObjects/ODOChangeActions.h>
#import <OmniDataObjects/ODOObjectSnapshot.h>
#import <OmniBase/macros.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString, NSArray, NSError, NSMutableIndexSet, NSMutableSet;
@class ODOEntity, ODOEditingContext, ODOObjectID, ODOProperty, ODORelationship;

typedef NS_ENUM(NSUInteger, ODOAwakeEvent) {
    ODOAwakeEventReinsertion = 0, // deleted an object, then inserted a "new" object with the same object ID
    ODOAwakeEventUndoneDeletion, // deleted an object, then performed an undo
};

typedef NS_ENUM(NSUInteger, ODOFaultEvent) {
    // Some caller just wanted the object to be faulted to free up memory or possibly allow cycles to be cleared up.
    ODOFaultEventGeneric = 0,

    // Invalidated by the containing ODOEditingContext being reset.
    ODOFaultEventInvalidation,
};

typedef NS_ENUM(NSUInteger, ODOWillDeleteEvent) {
    // An actual delete operation will be saved
    ODOWillDeleteEventMaterial,

    // This deletion is a cancelled insert and no actual save of the original object was ever done.
    ODOWillDeleteEventCancelledInsert,
};

@interface ODOObject : OFObject {
  @package
    ODOEditingContext *_editingContext;
    ODOObjectID *_objectID;
    void *_observationInfo;

    // Packed buffer of scalar- and object-typed values
    void *_valueStorage;
}

+ (BOOL)objectIDShouldBeUndeletable:(ODOObjectID *)objectID;
+ (BOOL)shouldIncludeSnapshotForTransientCalculatedProperty:(ODOProperty *)property;

// Called on each implementation class that is used in a model, once the model is fully loaded.
+ (void)entityLoaded:(ODOEntity *)entity;

@property (class, nonatomic, readonly) ODOEntity *entity; // The entity represented by this subclass. It is only legal to query the entity of leaf subclasses which represents a single entity in the model.
@property (class, nonatomic, readonly) NSString *entityName; // The name of the entity represented by this subclass. The restrictions on the entity property apply here.

- (instancetype)initWithEntity:(ODOEntity *)entity primaryKey:(nullable id)primaryKey insertingIntoEditingContext:(ODOEditingContext *)context;

- (instancetype)initWithContext:(ODOEditingContext *)context; // Convenience insertion initializer which looks up the entity. It is only legal to send to leaf subclases which represents a single entity in the model. Calls through to -initWithEntity:primaryKey:insertingIntoEditingContext:.
- (instancetype)initWithContext:(ODOEditingContext *)context primaryKey:(nullable id)primaryKey; // See description for -initWithContext:.

- (void)willAccessValueForKey:(nullable NSString *)key;

- (nullable id)primitiveValueForKey:(NSString *)key; // do not subclass
- (void)setPrimitiveValue:(nullable id)value forKey:(NSString *)key; // do not subclass

- (nullable id)calculateValueForProperty:(ODOProperty *)property NS_REQUIRES_SUPER;
- (void)invalidateCalculatedValueForKey:(NSString *)key;

+ (void)addDefaultAttributeValueActions:(ODOObjectSetDefaultAttributeValueActions *)actions entity:(ODOEntity *)entity;
- (void)setDefaultAttributeValues;

+ (void)addChangeActionsForProperty:(ODOProperty *)property willActions:(ODOChangeActions *)willActions didActions:(ODOChangeActions *)didActions;

@property (nonatomic, readonly, getter=isAwakingFromInsert) BOOL awakingFromInsert;
- (void)awakeFromInsert;

@property (nonatomic, readonly, getter=isAwakingFromFetch) BOOL awakingFromFetch;
- (void)awakeFromFetch;
- (void)didAwakeFromFetch;

@property (nonatomic, readonly, getter=isAwakingFromUnarchive) BOOL awakingFromUnarchive;
- (void)awakeFromUnarchive; // Never called by the framework; for subclasses and apps that implement archiving

@property (nonatomic, readonly, getter=isAwakingFromReinsertionAfterUndoneDeletion) BOOL awakingFromReinsertionAfterUndoneDeletion;

/// Potentially called on any insertion path, depending on whether previous snapshots exist for an object with the same object ID. (This implies a previous delete followed by an insert, either via undo or by specifying the same object ID for a "new" object.) This call does not replace -awakeFromInsert; rather, it may be called after -awakeFromInsert.
- (void)awakeFromEvent:(ODOAwakeEvent)snapshotEvent snapshot:(nullable ODOObjectSnapshot *)snapshot;

@property (nonnull, nonatomic, readonly) ODOEntity *entity; // do not subclass
@property (nonnull, nonatomic, readonly) ODOEditingContext *editingContext; // do not subclass
@property (nonnull, nonatomic, readonly) ODOObjectID *objectID; // do not subclass

- (void)willSave NS_REQUIRES_SUPER;
- (void)willInsert NS_REQUIRES_SUPER; // Just calls -willSave
- (void)willUpdate NS_REQUIRES_SUPER; // Just calls -willSave
- (void)willDelete:(ODOWillDeleteEvent)event NS_REQUIRES_SUPER; // Just calls -willSave

- (void)prepareForDeletion; // Nothing; for subclasses

// Send when the editing context is being reset
- (void)prepareForReset;

- (void)didSave; // Currently no -didInsert or -didUpdate.

- (BOOL)validateForSave:(NSError **)outError;
- (BOOL)validateForInsert:(NSError **)outError; // Just calls -validateForSave:
- (BOOL)validateForUpdate:(NSError **)outError; // Just calls -validateForSave:

@property (nonatomic, readonly, getter=isFault) BOOL fault;

- (void)willTurnIntoFault:(ODOFaultEvent)faultEvent NS_REQUIRES_SUPER;

- (void)turnIntoFault;

- (BOOL)hasFaultForRelationship:(ODORelationship *)relationship;
- (BOOL)hasFaultForRelationshipNamed:(NSString *)key; 
- (BOOL)toOneRelationship:(ODORelationship *)relationship isToObject:(ODOObject *)destinationObject;

- (void)willNullifyRelationships:(NSSet<ODORelationship *> *)relationships;
- (void)didNullifyRelationships:(NSSet<ODORelationship *> *)relationships;

@property (nonatomic, readonly, getter=isInserted) BOOL inserted;
@property (nonatomic, readonly, getter=isDeleted) BOOL deleted;
@property (nonatomic, readonly, getter=isUpdated) BOOL updated;

@property (nonatomic, readonly, getter=isInvalid) BOOL invalid;
@property (nonatomic, readonly, getter=isUndeletable) BOOL undeletable;

@property (nonatomic,readonly) BOOL hasBeenDeleted;
@property (nonatomic,readonly) BOOL hasBeenDeletedOrInvalidated;

- (BOOL)hasChangedKeySinceLastSave:(NSString *)key NS_SWIFT_NAME(hasChangedKeySinceLastSave(_:));
@property (nonatomic, nullable, readonly) NSDictionary<NSString *, id> *changedValues;
@property (nonatomic, nullable, readonly) NSDictionary<NSString *, id> *changedNonDerivedValues;

- (nullable id)lastProcessedValueForKey:(NSString *)key;
- (nullable id)committedValueForKey:(NSString *)key;
// - (NSDictionary *)committedValuesForKeys:(NSArray *)keys;

+ (void)addDerivedPropertyNames:(NSMutableSet<NSString *> *)set withEntity:(ODOEntity *)entity;
@property (nonatomic, readonly) BOOL hasChangedNonDerivedChangedValue;

+ (void)computeNonDateModifyingPropertyNameSet:(NSMutableSet<NSString *> *)set withEntity:(ODOEntity *)entity;
- (BOOL)shouldChangeDateModified;

#if !OMNI_BUILDING_FOR_SERVER
@property(nonatomic,nullable,strong) id objectDidChangeStorage;
#endif

@end

// Helper functions that handle the guts of most common custom property setter/getter methods.
extern BOOL ODOSetPropertyIfChanged(ODOObject *object, NSString *key, _Nullable id value, _Nullable id * _Nullable outOldValue);
extern BOOL ODOSetInt32PropertyIfChanged(ODOObject *object, NSString *key, int32_t value, int32_t * _Nullable outOldValue);

// Property-based KVC accessor that are used by -valueForKey: and -setValue:forKey: when the key maps to a property. But if you have the property already, you can use these.
extern id _Nullable ODOObjectValueForProperty(ODOObject *self, ODOProperty *prop);
extern void ODOObjectSetValueForKey(ODOObject *self, id _Nullable value, ODOProperty *prop);

extern id ODOGetPrimitiveProperty(ODOObject *object, NSString *key);
extern BOOL ODOSetPrimitivePropertyWithKeyIfChanged(ODOObject *object, NSString *key, _Nullable id value, _Nullable id * _Nullable outOldValue);
extern BOOL ODOSetPrimitivePropertyIfChanged(ODOObject *object, ODOProperty *prop, _Nullable id value, _Nullable id * _Nullable outOldValue);

typedef _Nullable id (^ODOObjectSnapshotFallbackLookupHandler)(ODOObjectID *objectID);

typedef _Nullable id (^ODOObjectSnapshotFallbackLookupHandler)(ODOObjectID *objectID);

/// Returns the value of the given key for the object by reading the given snapshot, instead of querying the object directly. Useful if you have taken a snapshot of the object at some earlier point in time, and care about what the value of a particular key was at that point.
@class ODOObjectSnapshot;
extern _Nullable id ODOObjectSnapshotValueForKey(ODOObject *self, ODOEditingContext *editingContext, ODOObjectSnapshot *snapshot, NSString *key, _Nullable ODOObjectSnapshotFallbackLookupHandler fallbackLookupHandler);

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// We wouldn't implement this -- we need to switch to the newer API on the iPhone.  But, this will let things compile for now.
@interface NSObject (KVCCrud)
+ (void)setKeys:(NSArray *)keys triggerChangeNotificationsForDependentKey:(NSString *)dependentKey;
@end
#endif

// Helper functions for support -awakeFromUnarchive.
// Clients should dispatch through here rather than sending -awakeFromUnarchive directly, so that -isAwakingFromUnarchive returns the correct value.

void ODOObjectAwakeSingleObjectFromUnarchive(ODOObject *object);
void ODOObjectAwakeSingleObjectFromUnarchiveWithMessage(ODOObject *object, SEL sel, id arg);

void ODOObjectAwakeObjectsFromUnarchive(id <NSFastEnumeration> objects);
void ODOObjectAwakeObjectsFromUnarchiveWithMessage(id <NSFastEnumeration> objects, SEL sel, id arg);


NS_ASSUME_NONNULL_END
