// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOEditingContext.h>

@interface ODOEditingContext (Internal)
#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_checkInvariants;
#endif
- (void)_objectWillBeUpdated:(ODOObject *)object;
- (void)_registerObject:(ODOObject *)object;
- (void)_snapshotObjectPropertiesIfNeeded:(ODOObject *)object;
- (NSArray *)_committedPropertySnapshotForObjectID:(ODOObjectID *)objectID;

@end

@class NSPredicate;
@class ODOEntity, ODORelationship;

__private_extern__ ODOObject *ODOEditingContextLookupObjectOrRegisterFaultForObjectID(ODOEditingContext *self, ODOObjectID *objectID);

__private_extern__ NSMutableSet *ODOEditingContextCreateRecentSet(ODOEditingContext *self);

__private_extern__ void ODOUpdateResultSetForInMemoryChanges(ODOEditingContext *self, NSMutableArray *results, ODOEntity *entity, NSPredicate *predicate);

__private_extern__ void ODOFetchObjectFault(ODOEditingContext *self, ODOObject *object);
__private_extern__ NSMutableSet *ODOFetchSetFault(ODOEditingContext *self, ODOObject *owner, ODORelationship *rel);

