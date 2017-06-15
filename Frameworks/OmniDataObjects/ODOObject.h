// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <CoreFoundation/CFArray.h>
#import <OmniDataObjects/ODOFeatures.h>
#import <OmniBase/macros.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString, NSArray, NSError, NSMutableSet;
@class ODOEntity, ODOEditingContext, ODOObjectID, ODOProperty, ODORelationship;

@interface ODOObject : OFObject {
  @package
    ODOEditingContext *_editingContext;
    ODOObjectID *_objectID;
    void *_observationInfo;

    OB_STRONG id *_valueStorage; // One for each -snapshotProperty on the ODOEntity.
    
    NSMutableSet<NSString *> *_keysForPropertiesBeingCalculated;
    
    struct {
        unsigned int isFault : 1;
        unsigned int changeProcessingDisabled : 1;
        unsigned int invalid : 1;
        unsigned int isAwakingFromInsert : 1;
        unsigned int needsAwakeFromFetch : 1;
        unsigned int isAwakingFromFetch : 1;
        unsigned int isAwakingFromReinsertionAfterUndoneDeletion : 1;
        unsigned int isAwakingFromUnarchive : 1;
        unsigned int hasChangedModifyingToManyRelationshipSinceLastSave : 1;
        unsigned int undeletable : 1;
    } _flags;
}

+ (BOOL)objectIDShouldBeUndeletable:(ODOObjectID *)objectID;
+ (BOOL)shouldIncludeSnapshotForTransientCalculatedProperty:(ODOProperty *)property;

@property (class, nonatomic, readonly) ODOEntity *entity; // The entity represented by this subclass. It is only legal to query the entity of leaf subclasses which represents a single entity in the model.
@property (class, nonatomic, readonly) NSString *entityName; // The name of the entity represented by this subclass. The restrictions on the entity property apply here.

- (instancetype)initWithEntity:(ODOEntity *)entity primaryKey:(nullable id)primaryKey insertingIntoEditingContext:(ODOEditingContext *)context;

- (instancetype)initWithContext:(ODOEditingContext *)context; // Convenience insertion initializer which looks up the entity. It is only legal to send to leaf subclases which represents a single entity in the model. Calls through to -initWithEntity:primaryKey:insertingIntoEditingContext:.
- (instancetype)initWithContext:(ODOEditingContext *)context primaryKey:(nullable id)primaryKey; // See description for -initWithContext:.

- (void)willAccessValueForKey:(nullable NSString *)key;
- (void)didAccessValueForKey:(NSString *)key;

- (nullable id)primitiveValueForKey:(NSString *)key; // do not subclass
- (void)setPrimitiveValue:(nullable id)value forKey:(NSString *)key; // do not subclass

- (nullable id)calculateValueForKey:(NSString *)key NS_REQUIRES_SUPER;
- (void)invalidateCalculatedValueForKey:(NSString *)key;

- (void)setDefaultAttributeValues;

@property (nonatomic, readonly, getter=isAwakingFromInsert) BOOL awakingFromInsert;
- (void)awakeFromInsert;

@property (nonatomic, readonly, getter=isAwakingFromFetch) BOOL awakingFromFetch;
- (void)awakeFromFetch;
- (void)didAwakeFromFetch;

@property (nonatomic, readonly, getter=isAwakingFromUnarchive) BOOL awakingFromUnarchive;
- (void)awakeFromUnarchive; // Never called by the framework; for subclasses and apps that implement archiving

@property (nonatomic, readonly, getter=isAwakingFromReinsertionAfterUndoneDeletion) BOOL awakingFromReinsertionAfterUndoneDeletion;
- (void)awakeFromReinsertionAfterUndoneDeletion;

@property (nonnull, nonatomic, readonly) ODOEntity *entity; // do not subclass
@property (nonnull, nonatomic, readonly) ODOEditingContext *editingContext; // do not subclass
@property (nonnull, nonatomic, readonly) ODOObjectID *objectID; // do not subclass

- (void)willSave;
- (void)willInsert NS_REQUIRES_SUPER; // Just calls -willSave
- (void)willUpdate NS_REQUIRES_SUPER; // Just calls -willSave
- (void)willDelete NS_REQUIRES_SUPER; // Just calls -willSave

- (void)prepareForDeletion; // Nothing; for subclasses

- (void)didSave; // Currently no -didInsert or -didUpdate.

- (BOOL)validateForSave:(NSError **)outError;
- (BOOL)validateForInsert:(NSError **)outError; // Just calls -validateForSave:
- (BOOL)validateForUpdate:(NSError **)outError; // Just calls -validateForSave:

@property (nonatomic, readonly, getter=isFault) BOOL fault;

- (void)willTurnIntoFault;
- (void)didTurnIntoFault;

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

- (BOOL)hasChangedKeySinceLastSave:(NSString *)key NS_SWIFT_NAME(hasChangedKeySinceLastSave(_:));
@property (nonatomic, nullable, readonly) NSDictionary *changedValues;
@property (nonatomic, nullable, readonly) NSDictionary *changedNonDerivedValues;

- (nullable id)lastProcessedValueForKey:(NSString *)key;
- (nullable id)committedValueForKey:(NSString *)key;
// - (NSDictionary *)committedValuesForKeys:(NSArray *)keys;

+ (void)addDerivedPropertyNames:(NSMutableSet<NSString *> *)set withEntity:(ODOEntity *)entity;
@property (nonatomic, readonly) BOOL hasChangedNonDerivedChangedValue;

+ (void)computeNonDateModifyingPropertyNameSet:(NSMutableSet<NSString *> *)set withEntity:(ODOEntity *)entity;
- (BOOL)shouldChangeDateModified;

@end

// Helper functions that handle the guts of most common custom property setter/getter methods.
extern BOOL ODOSetPropertyIfChanged(ODOObject *object, NSString *key, _Nullable id value, _Nullable id * _Nullable outOldValue);
extern BOOL ODOSetInt32PropertyIfChanged(ODOObject *object, NSString *key, int32_t value, int32_t * _Nullable outOldValue);

extern id ODOGetPrimitiveProperty(ODOObject *object, NSString *key);
extern BOOL ODOSetPrimitivePropertyIfChanged(ODOObject *object, NSString *key, _Nullable id value, _Nullable id * _Nullable outOldValue);

typedef _Nullable id (^ODOObjectSnapshotFallbackLookupHandler)(ODOObjectID *objectID);

typedef _Nullable id (^ODOObjectSnapshotFallbackLookupHandler)(ODOObjectID *objectID);

/// Returns the value of the given key for the object by reading the given snapshot, instead of querying the object directly. Useful if you have taken a snapshot of the object at some earlier point in time, and care about what the value of a particular key was at that point.
extern _Nullable id ODOObjectSnapshotValueForKey(ODOObject *self, ODOEditingContext *editingContext, NSArray *snapshot, NSString *key, _Nullable ODOObjectSnapshotFallbackLookupHandler fallbackLookupHandler);

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
