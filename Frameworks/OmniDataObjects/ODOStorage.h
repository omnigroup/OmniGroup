// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOObject.h>

#import "ODOAttribute-Internal.h"

NS_ASSUME_NONNULL_BEGIN

/*
 Raw accessors for packed storage for use by ODOObject and ODOObjectSnapshot.
 */

static inline void _ODOStorageCheckBase(const void *base)
{
    // We assume that the base is aligned to the largest type we support (and actually, it should be 16-byte aligned due to using the platform malloc, which supports vectors).
    OBASSERT(((uintptr_t)base & 0xf) == 0);
}

static inline void _ODOStorageCheckType_(ODOEntity *entity, ODOStorageKey storageKey, ODOAttributeType attributeType, ODOStorageType storageType)
{
    assert(storageKey.type == storageType);

#ifdef OMNI_ASSERTIONS_ON
    ODOProperty *prop = [entity propertyWithSnapshotIndex:storageKey.snapshotIndex];
    ODOASSERT_ATTRIBUTE_OF_TYPE(prop, attributeType);
    OBASSERT(ODOPropertyGetStorageType(prop) == storageKey.type);
#endif
}

#define _ODOStorageCheckType(entity, storageKey, typeSuffix) _ODOStorageCheckType_(entity, storageKey, ODOAttributeType ## typeSuffix, ODOStorageType ## typeSuffix)

static inline void _ODOStorageCheckObjectType(ODOEntity *entity, ODOStorageKey storageKey)
{
    assert(storageKey.type == ODOStorageTypeObject);

#ifdef OMNI_ASSERTIONS_ON
    ODOProperty *prop = [entity propertyWithSnapshotIndex:storageKey.snapshotIndex];
    OBASSERT(ODOPropertyGetStorageType(prop) == ODOStorageTypeObject);
    struct _ODOPropertyFlags flags = ODOPropertyFlags(prop);
    if (flags.relationship) {
        // object typed
    } else {
        ODOAttribute *attr = (ODOAttribute *)prop;
        OBASSERT(![attr isPrimaryKey]);

        ODOAttributeType type = attr.type;
        OBASSERT(type == ODOAttributeTypeUndefined || type == ODOAttributeTypeString || type == ODOAttributeTypeDate || type == ODOAttributeTypeXMLDateTime || type == ODOAttributeTypeData);
    }
#endif
}

// Special cases for snapshots

static inline void ODOStorageRetainObject(ODOEntity *entity, void *storageBase, ODOStorageKey storageKey)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckObjectType(entity, storageKey);

    id *storage = &((id *)storageBase)[storageKey.storageIndex];
    [*storage retain];
}

static inline void ODOStorageReleaseObject(ODOEntity *entity, void *storageBase, ODOStorageKey storageKey)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckObjectType(entity, storageKey);

    id *storage = &((id *)storageBase)[storageKey.storageIndex];
    [*storage release];
}

static inline void ODOStorageSetObjectWithoutReleasingOldValue(ODOEntity *entity, void *storageBase, ODOStorageKey storageKey, id _Nullable value)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckObjectType(entity, storageKey);

    id *storage = &((id *)storageBase)[storageKey.storageIndex];

    // We don't early out if the slot already has this pointer since we need the retain
    
    *storage = [value retain];
}

static inline void ODOStorageCopy(ODOEntity *entity, void *destinationStorage, const void *sourceStorage, size_t storageSize)
{
    _ODOStorageCheckBase(destinationStorage);
    _ODOStorageCheckBase(sourceStorage);
    OBASSERT(entity.snapshotSize == storageSize); // Passing this in since callers will have looked it up already.

    memcpy(destinationStorage, sourceStorage, storageSize);

    // Retain the object-typed values. We expect that the values in the snapshot are already immutable copies. Otherwise we'd have to do "x = copy(x)" for each slot (which'd be slightly slower).
    for (ODOProperty *property in entity.snapshotProperties) {
        ODOStorageKey storageKey = property->_storageKey;
        if (storageKey.type == ODOStorageTypeObject) {
            ODOStorageRetainObject(entity, destinationStorage, storageKey);
        }
    }
}

// Private helpers for accessing packed bits.
static inline BOOL _ODOStorageGetBit(const void *storageBase, NSUInteger bitIndex)
{
    uint8_t *storage = &((uint8_t *)storageBase)[bitIndex / 8];
    uint8_t byte = *storage;
    uint8_t bit = (byte >> (bitIndex % 8)) & 0x1;
    return bit;
}

static inline void _ODOStorageSetBit(void *storageBase, NSUInteger bitIndex, BOOL value)
{
    uint8_t *storage = &((uint8_t *)storageBase)[bitIndex / 8];
    uint8_t byte = *storage;

    uint8_t bit = (1 << (bitIndex % 8));

    if (value) {
        byte |= bit;
    } else {
        byte &= ~bit;
    }

    *storage = byte;
}

// Special case for optional scalars. There is no ODOProperty for the bit, so the assertions in ODOStorageGetBoolean would fail.

static void _ODOStorageCheckNonNullIndex(ODOEntity *entity, NSUInteger nonNullIndex)
{
    // Some optional scalar property should have this index as their nonNullIndex.
#ifdef OMNI_ASSERTIONS_ON
    OBPRECONDITION(nonNullIndex != ODO_STORAGE_KEY_NON_SNAPSHOT_PROPERTY_INDEX);
    
    BOOL found = NO;
    for (ODOProperty *prop in entity.snapshotProperties) {
        ODOStorageKey storageKey = prop->_storageKey;
        if (storageKey.type == ODOStorageTypeObject) {
            continue;
        }
        
        OBASSERT(prop->_flags.optional == (storageKey.nonNullIndex != ODO_STORAGE_KEY_NON_SNAPSHOT_PROPERTY_INDEX));
        
        if (prop->_flags.optional && storageKey.nonNullIndex == nonNullIndex) {
            found = YES;
            break;
        }
    }
    OBASSERT(found);
#endif
}

static inline BOOL ODOStorageGetNonNull(ODOEntity *entity, const void *storageBase, NSUInteger nonNullIndex)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckNonNullIndex(entity, nonNullIndex);

    return _ODOStorageGetBit(storageBase, nonNullIndex);
}

static inline void ODOStorageSetNonNull(ODOEntity *entity, void *storageBase, NSUInteger nonNullIndex, BOOL value)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckNonNullIndex(entity, nonNullIndex);

    return _ODOStorageSetBit(storageBase, nonNullIndex, value);
}

// Getters

static inline id _Nullable ODOStorageGetObject(ODOEntity *entity, const void *storageBase, ODOStorageKey storageKey)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckObjectType(entity, storageKey);

    const id *storage = &((const id *)storageBase)[storageKey.storageIndex];
    return *storage;
}

static inline BOOL ODOStorageGetBoolean(ODOEntity *entity, const void *storageBase, ODOStorageKey storageKey)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckType(entity, storageKey, Boolean);

    return _ODOStorageGetBit(storageBase, storageKey.storageIndex);
}

static inline int16_t ODOStorageGetInt16(ODOEntity *entity, const void *storageBase, ODOStorageKey storageKey)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckType(entity, storageKey, Int16);

    const int16_t *storage = &((const int16_t *)storageBase)[storageKey.storageIndex];
    return *storage;
}

static inline int32_t ODOStorageGetInt32(ODOEntity *entity, const void *storageBase, ODOStorageKey storageKey)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckType(entity, storageKey, Int32);

    const int32_t *storage = &((const int32_t *)storageBase)[storageKey.storageIndex];
    return *storage;
}

static inline int64_t ODOStorageGetInt64(ODOEntity *entity, const void *storageBase, ODOStorageKey storageKey)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckType(entity, storageKey, Int64);

    const int64_t *storage = &((const int64_t *)storageBase)[storageKey.storageIndex];
    return *storage;
}

static inline float ODOStorageGetFloat32(ODOEntity *entity, const void *storageBase, ODOStorageKey storageKey)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckType(entity, storageKey, Float32);

    const float *storage = &((const float *)storageBase)[storageKey.storageIndex];
    return *storage;
}

static inline double ODOStorageGetFloat64(ODOEntity *entity, const void *storageBase, ODOStorageKey storageKey)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckType(entity, storageKey, Float64);

    const double *storage = &((const double *)storageBase)[storageKey.storageIndex];
    return *storage;
}

// Setters

static inline void ODOStorageSetObject(ODOEntity *entity, void *storageBase, ODOStorageKey storageKey, id _Nullable value)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckObjectType(entity, storageKey);

    id *storage = &((id *)storageBase)[storageKey.storageIndex];

    if (value == *storage)
        return;

    [*storage release];
    *storage = [value retain];
}

static inline void ODOStorageSetBoolean(ODOEntity *entity, void *storageBase, ODOStorageKey storageKey, BOOL value)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckType(entity, storageKey, Boolean);

    _ODOStorageSetBit(storageBase, storageKey.storageIndex, value);
}

static inline void ODOStorageSetInt16(ODOEntity *entity, void *storageBase, ODOStorageKey storageKey, int16_t value)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckType(entity, storageKey, Int16);

    int16_t *storage = &((int16_t *)storageBase)[storageKey.storageIndex];
    *storage = value;
}

static inline void ODOStorageSetInt32(ODOEntity *entity, void *storageBase, ODOStorageKey storageKey, int32_t value)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckType(entity, storageKey, Int32);

    int32_t *storage = &((int32_t *)storageBase)[storageKey.storageIndex];
    *storage = value;
}

static inline void ODOStorageSetInt64(ODOEntity *entity, void *storageBase, ODOStorageKey storageKey, int64_t value)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckType(entity, storageKey, Int64);

    int64_t *storage = &((int64_t *)storageBase)[storageKey.storageIndex];
    *storage = value;
}

static inline void ODOStorageSetFloat32(ODOEntity *entity, void *storageBase, ODOStorageKey storageKey, float value)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckType(entity, storageKey, Float32);

    float *storage = &((float *)storageBase)[storageKey.storageIndex];
    *storage = value;
}

static inline void ODOStorageSetFloat64(ODOEntity *entity, void *storageBase, ODOStorageKey storageKey, double value)
{
    _ODOStorageCheckBase(storageBase);
    _ODOStorageCheckType(entity, storageKey, Float64);

    double *storage = &((double *)storageBase)[storageKey.storageIndex];
    *storage = value;
}

// Boxed value conversion

static inline id _Nullable ODOStorageGetObjectValue(ODOEntity *entity, const void *storageBase, ODOStorageKey storageKey)
{
    if (storageKey.nonNullIndex != ODO_STORAGE_KEY_NON_SNAPSHOT_PROPERTY_INDEX) {
        BOOL nonNull = ODOStorageGetNonNull(entity, storageBase, storageKey.nonNullIndex);
        if (!nonNull) {
            return nil;
        }
    }

    switch (storageKey.type) {
        case ODOStorageTypeObject:
            return ODOStorageGetObject(entity, storageBase, storageKey);

        case ODOStorageTypeBoolean:
            return @(ODOStorageGetBoolean(entity, storageBase, storageKey));

        case ODOStorageTypeInt16:
            return @(ODOStorageGetInt16(entity, storageBase, storageKey));

        case ODOStorageTypeInt32:
            return @(ODOStorageGetInt32(entity, storageBase, storageKey));

        case ODOStorageTypeInt64:
            return @(ODOStorageGetInt64(entity, storageBase, storageKey));

        case ODOStorageTypeFloat32:
            return @(ODOStorageGetFloat32(entity, storageBase, storageKey));

        case ODOStorageTypeFloat64:
            return @(ODOStorageGetFloat64(entity, storageBase, storageKey));

        default:
            NSLog(@"Unknown type %d", storageKey.type);
            abort();
    }
}

static inline void ODOStorageSetObjectValue(ODOEntity *entity, void *storageBase, ODOStorageKey storageKey, id _Nullable value)
{
    BOOL optional = (storageKey.nonNullIndex != ODO_STORAGE_KEY_NON_SNAPSHOT_PROPERTY_INDEX);
    
    if (optional) {
        OBASSERT(storageKey.type != ODOStorageTypeObject, "Objects are implicitily considered nullable");
        
        if (value == nil) {
            ODOStorageSetNonNull(entity, storageBase, storageKey.nonNullIndex, NO);
            return;
        } else {
            ODOStorageSetNonNull(entity, storageBase, storageKey.nonNullIndex, YES);
            // continue on to set the scalar value...
        }
    }

    switch (storageKey.type) {
        case ODOStorageTypeObject:
            ODOStorageSetObject(entity, storageBase, storageKey, value);
            break;

        case ODOStorageTypeBoolean:
            ODOStorageSetBoolean(entity, storageBase, storageKey, [value boolValue]);
            break;

        case ODOStorageTypeInt16:
            ODOStorageSetInt16(entity, storageBase, storageKey, [value shortValue]);
            break;

        case ODOStorageTypeInt32:
            ODOStorageSetInt32(entity, storageBase, storageKey, [value intValue]);
            break;

        case ODOStorageTypeInt64:
            ODOStorageSetInt64(entity, storageBase, storageKey, [value longLongValue]);
            break;

        case ODOStorageTypeFloat32:
            ODOStorageSetFloat32(entity, storageBase, storageKey, [value floatValue]);
            break;

        case ODOStorageTypeFloat64:
            ODOStorageSetFloat64(entity, storageBase, storageKey, [value doubleValue]);
            break;

        default:
            NSLog(@"Unknown type %d", storageKey.type);
            abort();
    }
}

NS_ASSUME_NONNULL_END

