// Copyright 2008-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOObjectSnapshot.h>

#import "ODOProperty-Internal.h"
#import "ODOEntity-Internal.h"
#import "ODOStorage.h"

@import OmniBase;

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation ODOObjectSnapshot
{
    ODOEntity *_entity;
}

- (nullable id)valueForProperty:(ODOProperty *)property;
{
    return ODOStorageGetObjectValue(_entity, ODOObjectSnapshotGetStorageBase(self), property->_storageKey);
}

- (void)dealloc;
{
    void *storageBase = ODOObjectSnapshotGetStorageBase(self);

    NSUInteger snapshotPropertyCount = _entity->_snapshotPropertyCount;
    for (NSUInteger snapshotIndex = 0; snapshotIndex < snapshotPropertyCount; snapshotIndex++) {
        ODOStorageKey storageKey = ODOEntityStorageKeyForSnapshotIndex(_entity, snapshotIndex);
        if (storageKey.type == ODOStorageTypeObject) {
            ODOStorageReleaseObject(_entity, storageBase, storageKey);
        }
    }

    [_entity release];

    [super dealloc];
}

ODOObjectSnapshot *ODOObjectSnapshotCreate(ODOEntity *entity)
{
    size_t storageSize = entity.snapshotSize;
    ODOObjectSnapshot *snapshot = NSAllocateObject([ODOObjectSnapshot class], storageSize, NULL);
    snapshot->_entity = [entity retain];
    return snapshot;
}

void *ODOObjectSnapshotGetStorageBase(ODOObjectSnapshot *snapshot)
{
    return object_getIndexedIvars(snapshot);
}

ODOEntity *ODOObjectSnapshotGetEntity(ODOObjectSnapshot *snapshot)
{
    OBPRECONDITION(snapshot);

    return snapshot->_entity;
}

id _Nullable ODOObjectSnapshotGetValueForProperty(ODOObjectSnapshot *snapshot, ODOProperty *property)
{
    OBPRECONDITION(snapshot);
    OBPRECONDITION(snapshot->_entity == property.entity);

    void *storageBase = ODOObjectSnapshotGetStorageBase(snapshot);
    return ODOStorageGetObjectValue(snapshot->_entity, storageBase, property->_storageKey);
}

@end

NS_ASSUME_NONNULL_END

