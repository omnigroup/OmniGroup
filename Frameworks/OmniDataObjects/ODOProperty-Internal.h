// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOProperty-Internal.h 104583 2008-09-06 21:23:18Z kc $

#import <OmniDataObjects/ODOProperty.h>

#import "ODOEntity-Internal.h"

extern NSString * const ODOPropertyNameAttributeName;
extern NSString * const ODOPropertyOptionalAttributeName;
extern NSString * const ODOPropertyTransientAttributeName;

@interface ODOProperty (Internal)
- (id)initWithCursor:(OFXMLCursor *)cursor entity:(ODOEntity *)entity baseFlags:(struct _ODOPropertyFlags)flags error:(NSError **)outError;
#ifdef OMNI_ASSERTIONS_ON
- (SEL)_setterSelector;
#endif
@end


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

__private_extern__ id ODOPropertyGetValue(ODOObject *object, ODOProperty *property);
__private_extern__ void ODOPropertySetValue(ODOObject *object, ODOProperty *property, id value);

