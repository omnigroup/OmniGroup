// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
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

@interface ODOObject : OFObject
{
@package
    ODOEditingContext *_editingContext;
    ODOObjectID *_objectID;
    void *_observationInfo;

    OB_STRONG id *_valueStorage; // One for each -snapshotProperty on the ODOEntity.
    
    struct {
        unsigned int isFault : 1;
        unsigned int changeProcessingDisabled : 1;
        unsigned int invalid : 1;
        unsigned int isAwakingFromInsert : 1;
        unsigned int needsAwakeFromFetch : 1;
        unsigned int isAwakingFromFetch : 1;
        unsigned int hasChangedModifyingToManyRelationshipSinceLastSave : 1;
        unsigned int undeletable : 1;
    } _flags;
}

+ (BOOL)objectIDShouldBeUndeletable:(ODOObjectID *)objectID;

- (id)initWithEditingContext:(ODOEditingContext *)context entity:(ODOEntity *)entity primaryKey:(nullable id)primaryKey;

- (void)willAccessValueForKey:(NSString *)key;
- (void)didAccessValueForKey:(NSString *)key;

- (void)setPrimitiveValue:(nullable id)value forKey:(NSString *)key; // do not subclass
- (nullable id)primitiveValueForKey:(NSString *)key; // do not subclass

- (void)setDefaultAttributeValues;

- (BOOL)isAwakingFromInsert;
- (void)awakeFromInsert;

- (BOOL)isAwakingFromFetch;
- (void)awakeFromFetch;
- (void)didAwakeFromFetch;

- (void)awakeFromUnarchive; // Never called by the framework; for subclasses and apps that implement archiving

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

- (void)willTurnIntoFault;
- (BOOL)isFault;
- (void)turnIntoFault;
- (BOOL)hasFaultForRelationship:(ODORelationship *)rel;
- (BOOL)hasFaultForRelationshipNamed:(NSString *)key; 
- (BOOL)toOneRelationship:(ODORelationship *)rel isToObject:(ODOObject *)destinationObject;

- (BOOL)isInserted;
- (BOOL)isDeleted;
- (BOOL)isUpdated;

- (BOOL)isInvalid;
- (BOOL)isUndeletable;

- (BOOL)hasChangedKeySinceLastSave:(NSString *)key;
- (nullable NSDictionary *)changedValues;
- (nullable NSDictionary *)changedNonDerivedValues;

- (nullable id)committedValueForKey:(NSString *)key;
// - (NSDictionary *)committedValuesForKeys:(NSArray *)keys;

+ (void)addDerivedPropertyNames:(NSMutableSet<NSString *> *)set withEntity:(ODOEntity *)entity;
- (BOOL)changedNonDerivedChangedValue;

+ (void)computeNonDateModifyingPropertyNameSet:(NSMutableSet<NSString *> *)set withEntity:(ODOEntity *)entity;
- (BOOL)shouldChangeDateModified;

@end

// Helper functions that handle the guts of most common custom property setter/getter methods.
extern BOOL ODOSetPropertyIfChanged(ODOObject *object, NSString *key, _Nullable id value, _Nullable id * _Nullable outOldValue);
extern BOOL ODOSetUInt32PropertyIfChanged(ODOObject *object, NSString *key, uint32_t value, uint32_t * _Nullable outOldValue);

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

NS_ASSUME_NONNULL_END
