// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODOSnapshotDictionary.h"

#import <OmniDataObjects/ODOObjectID.h>
#import <OmniDataObjects/ODORelationship.h>

#import "ODOProperty-Internal.h"
#import "ODOEntity-Internal.h"

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOSnapshotDictionary.m 104583 2008-09-06 21:23:18Z kc $")

@implementation ODOSnapshotDictionary

- initWithObjectID:(ODOObjectID *)objectID snapshot:(NSArray *)snapshot;
{
    OBPRECONDITION(objectID);
    OBPRECONDITION(snapshot);
    OBPRECONDITION([[[objectID entity] snapshotProperties] count] == [snapshot count]);

    // TODO: Should add a -snapshotProperties method that excludes the primary key rather than having this damn -1 all over the place.
    
    _objectID = [objectID retain];
    _snapshot = [snapshot copy];
    return self;
}

#pragma mark NSDictionary

- (unsigned)count;
{
    return [[[_objectID entity] snapshotProperties] count];
}

- (NSEnumerator *)keyEnumerator;
{
    OBRequestConcreteImplementation(self, _cmd);
    return nil;
}

- (id)objectForKey:(id)aKey;
{
    ODOEntity *entity = [_objectID entity];

    ODOProperty *prop = [entity propertyNamed:aKey];
    if (!prop)
        return nil;
    OBASSERT(![prop isTransient]); // CoreData's version only returns persistent properties supposedly.  We shouldn't be asking for transient stuffs.
    
    unsigned int snapshotIndex = ODOPropertySnapshotIndex(prop);
    if (snapshotIndex == ODO_PRIMARY_KEY_SNAPSHOT_INDEX)
        return [_objectID primaryKey];
    
    if ([prop isKindOfClass:[ODORelationship class]]) {
        // Need to deal with un-created realtionship faults
        OBRequestConcreteImplementation(self, _cmd);
        return nil;
    }

    OBASSERT(snapshotIndex < [_snapshot count]);
    id value = [_snapshot objectAtIndex:snapshotIndex];
    if (OFISNULL(value))
        value = nil;
    return value;
}

@end
