// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOProperty.h>

#import "ODOEntity-Internal.h"

extern void ODOPropertyInit(ODOProperty *self, NSString *name, struct _ODOPropertyFlags flags, BOOL optional, BOOL transient, SEL get, SEL set);

@class ODOObject;
__private_extern__ BOOL ODOPropertyHasIdenticalName(ODOProperty *property, NSString *name);

#define ODO_PRIMARY_KEY_SNAPSHOT_INDEX ((unsigned)((1<<ODO_PROPERTY_SNAPSHOT_INDEX_WIDTH)-1)) // Only have ODO_PROPERTY_SNAPSHOT_INDEX_WIDTH bits
#define ODO_NON_SNAPSHOT_PROPERTY_INDEX ((unsigned)((1<<ODO_PROPERTY_SNAPSHOT_INDEX_WIDTH)-2)) // Only have ODO_PROPERTY_SNAPSHOT_INDEX_WIDTH bits

__private_extern__ void ODOPropertySnapshotAssignSnapshotIndex(ODOProperty *property, unsigned int snapshotIndex);

static inline unsigned ODOPropertySnapshotIndex(ODOProperty *property)
{
    OBPRECONDITION([property isKindOfClass:[ODOProperty class]]);
    
    struct _ODOPropertyFlags flags = ODOPropertyFlags(property);
    unsigned snapshotIndex = flags.snapshotIndex;
    OBASSERT(snapshotIndex == ODO_PRIMARY_KEY_SNAPSHOT_INDEX || snapshotIndex < [[[property entity] snapshotProperties] count]);
    
    return snapshotIndex;
}

__private_extern__ SEL ODOPropertyGetterSelector(ODOProperty *property);
__private_extern__ SEL ODOPropertySetterSelector(ODOProperty *property);
__private_extern__ ODOPropertyGetter ODOPropertyGetterImpl(ODOProperty *property);
__private_extern__ ODOPropertySetter ODOPropertySetterImpl(ODOProperty *property);
