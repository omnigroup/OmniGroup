// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOObject-Internal.h 104583 2008-09-06 21:23:18Z kc $

#import <OmniDataObjects/ODOObject.h>

@interface ODOObject (Internal)
- (id)initWithEditingContext:(ODOEditingContext *)context objectID:(ODOObjectID *)objectID isFault:(BOOL)isFault;
- (id)initWithEditingContext:(ODOEditingContext *)context objectID:(ODOObjectID *)objectID snapshot:(CFArrayRef)snapshot;
- (void)_setIsFault:(BOOL)isFault;
- (void)_turnIntoFault:(BOOL)deleting;
- (NSArray *)_createPropertySnapshot;
- (void)_invalidate;

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_odo_checkInvariants;
#endif
@end

@class ODORelationship;

__private_extern__ void ODOObjectCreateNullValues(ODOObject *self);
__private_extern__ void ODOObjectClearValues(ODOObject *self, BOOL deleting);

__private_extern__ void ODOObjectSetInternalValueForProperty(ODOObject *self, id value, ODOProperty *prop);

__private_extern__ void ODOObjectPrepareForAwakeFromFetch(ODOObject *self);
__private_extern__ void ODOObjectPerformAwakeFromFetchWithoutRegisteringEdits(ODOObject *self);
__private_extern__ void ODOObjectFinalizeAwakeFromFetch(ODOObject *self);

__private_extern__ void ODOObjectAwakeSingleObjectFromFetch(ODOObject *object);
__private_extern__ void ODOObjectAwakeObjectsFromFetch(NSArray *objects);

__private_extern__ BOOL ODOObjectToManyRelationshipIsFault(ODOObject *self, ODORelationship *rel);
__private_extern__ NSMutableSet *ODOObjectToManyRelationshipIfNotFault(ODOObject *self, ODORelationship *rel);

__private_extern__ void ODOObjectSetChangeProcessingEnabled(ODOObject *self, BOOL enabled);
__private_extern__ BOOL ODOObjectChangeProcessingEnabled(ODOObject *self);

__private_extern__ CFArrayRef ODOObjectCreateDifferenceRecordFromSnapshot(ODOObject *self, CFArrayRef snapshot);
__private_extern__ void ODOObjectApplyDifferenceRecord(ODOObject *self, CFArrayRef diff);

// Make it more clear what we mean when we compare to nil.
#define ODO_OBJECT_LAZY_TO_MANY_FAULT_MARKER (nil)
static inline BOOL ODOObjectValueIsLazyToManyFault(id value)
{
    return (value == ODO_OBJECT_LAZY_TO_MANY_FAULT_MARKER);
}

