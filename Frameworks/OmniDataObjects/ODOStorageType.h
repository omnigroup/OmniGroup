// Copyright 2018-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

typedef NS_ENUM(uint8_t, ODOStorageType) {
    ODOStorageTypeObject,
    ODOStorageTypeBoolean,
    ODOStorageTypeInt16,
    ODOStorageTypeInt32,
    ODOStorageTypeInt64,
    ODOStorageTypeFloat32,
    ODOStorageTypeFloat64,
};

// We currently only emit 64 accessor functions..
#define ODO_STORAGE_KEY_INDEX_WIDTH (8)

#define ODO_STORAGE_KEY_PRIMARY_KEY_SNAPSHOT_INDEX ((NSUInteger)((1<<ODO_STORAGE_KEY_INDEX_WIDTH)-1)) // Only have ODO_STORAGE_KEY_INDEX_WIDTH bits
#define ODO_STORAGE_KEY_NON_SNAPSHOT_PROPERTY_INDEX ((NSUInteger)((1<<ODO_STORAGE_KEY_INDEX_WIDTH)-2)) // Only have ODO_STORAGE_KEY_INDEX_WIDTH bits


typedef struct _ODOStorageKey {
    ODOStorageType type;

    // The index of the property in the ODOEntity's snapshotProperties array.
    uint8_t snapshotIndex;

    // For scalar properties, if they are optional this will be a bit index for a null flag in the storage. Otherwise, this will be ODO_STORAGE_KEY_NON_SNAPSHOT_PROPERTY_INDEX for object or non-nullable scalars.
    uint8_t nonNullIndex;
    
    // For booleans, this is the number of bits from the beginning of the storage. For other types, it is the offset of this item in units of the right type (that is, if type is Int32 and storageIndex is 2, then the value is stored 8 bytes into the storage).
    uint8_t storageIndex;
} ODOStorageKey;
