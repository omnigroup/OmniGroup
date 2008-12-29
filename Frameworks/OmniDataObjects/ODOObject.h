// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOObject.h 104600 2008-09-07 21:25:37Z bungi $

#import <OmniFoundation/OFObject.h>

#import <CoreFoundation/CFArray.h>
#import <OmniDataObjects/ODOFeatures.h>

@class NSString, NSArray, NSMutableDictionary, NSError, NSSet;
@class ODOEntity, ODOEditingContext, ODOObjectID, ODOProperty, ODORelationship;

@interface ODOObject : OFObject
{
@private
    ODOEditingContext *_editingContext;
    ODOObjectID *_objectID;
    void *_observationInfo;

    CFMutableArrayRef _valueArray; // One for each -snapshotProperty on the ODOEntity.
    
    struct {
        unsigned int isFault : 1;
        unsigned int changeProcessingDisabled : 1;
        unsigned int invalid : 1;
        unsigned int needsAwakeFromFetch : 1;
        unsigned int hasChangedInterestingToManyRelationshipSinceLastSave : 1;
    } _flags;
}

- (id)initWithEditingContext:(ODOEditingContext *)context entity:(ODOEntity *)entity primaryKey:(id)primaryKey;

- (void)willAccessValueForKey:(NSString *)key;
- (void)didAccessValueForKey:(NSString *)key;

- (void)setPrimitiveValue:(id)value forProperty:(ODOProperty *)property;
- (id)primitiveValueForProperty:(ODOProperty *)property;

- (void)setPrimitiveValue:(id)value forKey:(NSString *)key; // do not subclass; this calls the 'forProperty' version
- (id)primitiveValueForKey:(NSString *)key;

- (void)setDefaultAttributeValues;

- (void)awakeFromInsert;
- (void)awakeFromFetch;
- (ODOEntity *)entity;
- (ODOEditingContext *)editingContext;
- (ODOObjectID *)objectID;

- (void)willSave;
- (void)willInsert; // Just calls -willSave
- (void)willUpdate; // Just calls -willSave
- (void)willDelete; // Just calls -willSave

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

- (BOOL)hasChangedKeySinceLastSave:(NSString *)key;
- (NSDictionary *)changedValues;

- (id)committedValueForKey:(NSString *)key;
- (NSDictionary *)committedValuesForKeys:(NSArray *)keys;

+ (NSSet *)derivedPropertyNameSet;
- (BOOL)changedNonDerivedChangedValue;

@end

// Helper functions that handle the guts of most common custom property setter/getter methods.
extern BOOL ODOSetPropertyIfChanged(ODOObject *object, NSString *key, id value, id *outOldValue);
extern BOOL ODOSetUnsignedIntPropertyIfChanged(ODOObject *object, NSString *key, unsigned int value, unsigned int *outOldValue);

extern id ODOGetPrimitiveProperty(ODOObject *object, NSString *key);
extern BOOL ODOSetPrimitivePropertyIfChanged(ODOObject *object, NSString *key, id value, id *outOldValue);

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// We wouldn't implement this -- we need to switch to the newer API on the iPhone.  But, this will let things compile for now.
@interface NSObject (KVCCrud)
+ (void)setKeys:(NSArray *)keys triggerChangeNotificationsForDependentKey:(NSString *)dependentKey;
@end
#endif
