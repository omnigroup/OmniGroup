// Copyright 2008-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOObjectSnapshot.h>

#import "ODOProperty-Internal.h"

@import OmniBase;

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation ODOObjectSnapshot
{
    NSUInteger _propertyCount;
}

- (nullable id)valueForProperty:(ODOProperty *)property;
{
    NSUInteger propertyIndex = ODOPropertySnapshotIndex(property);
    OBASSERT(propertyIndex < _propertyCount);
    return ODOObjectSnapshotGetValueAtIndex(self, propertyIndex);
}

- (void)dealloc;
{
    id *values = object_getIndexedIvars(self);

    NSUInteger propertyIndex = _propertyCount;
    while (propertyIndex--) {
        [values[propertyIndex] release];
    }

    [super dealloc];
}

ODOObjectSnapshot *ODOObjectSnapshotCreate(NSUInteger propertyCount)
{
    ODOObjectSnapshot *snapshot = NSAllocateObject([ODOObjectSnapshot class], sizeof(id)*propertyCount, NULL);
    snapshot->_propertyCount = propertyCount;
    return snapshot;
}

NSUInteger ODOObjectSnapshotValueCount(ODOObjectSnapshot *snapshot)
{
    OBPRECONDITION(snapshot);

    return snapshot->_propertyCount;
}

void ODOObjectSnapshotSetValueAtIndex(ODOObjectSnapshot *snapshot, NSUInteger propertyIndex, id _Nullable value)
{
    OBPRECONDITION(snapshot);
    OBPRECONDITION(propertyIndex < snapshot->_propertyCount);

    id *values = object_getIndexedIvars(snapshot);
    if (values[propertyIndex] != value) {
        OBASSERT(values[propertyIndex] == nil); // We should be setting these up once
        [values[propertyIndex] release];
        values[propertyIndex] = [value retain];
    }
}

id _Nullable ODOObjectSnapshotGetValueAtIndex(ODOObjectSnapshot *snapshot, NSUInteger propertyIndex)
{
    OBPRECONDITION(snapshot);
    OBPRECONDITION(propertyIndex < snapshot->_propertyCount);

    id *values = object_getIndexedIvars(snapshot);
    return values[propertyIndex];
}

@end

NS_ASSUME_NONNULL_END

