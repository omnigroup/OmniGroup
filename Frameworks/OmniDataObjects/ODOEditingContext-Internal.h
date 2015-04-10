// Copyright 2008-2015 Omni Development, Inc. All rights reserved.
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
- (BOOL)_isValidatingAndWritingChanges;
#endif
- (void)_objectWillBeUpdated:(ODOObject *)object;
- (void)_registerObject:(ODOObject *)object;
- (void)_snapshotObjectPropertiesIfNeeded:(ODOObject *)object;
- (NSArray *)_committedPropertySnapshotForObjectID:(ODOObjectID *)objectID;

#ifdef OMNI_ASSERTIONS_ON
- (BOOL)_isBeingDeleted:(ODOObject *)object;
#endif

@end

@class NSPredicate;
@class ODOEntity, ODORelationship;

ODOObject *ODOEditingContextLookupObjectOrRegisterFaultForObjectID(ODOEditingContext *self, ODOObjectID *objectID) OB_HIDDEN;

NSMutableSet *ODOEditingContextCreateRecentSet(ODOEditingContext *self) OB_HIDDEN;

void ODOUpdateResultSetForInMemoryChanges(ODOEditingContext *self, NSMutableArray *results, ODOEntity *entity, NSPredicate *predicate) OB_HIDDEN;

void ODOFetchObjectFault(ODOEditingContext *self, ODOObject *object) OB_HIDDEN;
NSMutableSet *ODOFetchSetFault(ODOEditingContext *self, ODOObject *owner, ODORelationship *rel) OB_HIDDEN;

BOOL ODOEditingContextObjectIsInsertedNotConsideringDeletions(ODOEditingContext *self, ODOObject *object) OB_HIDDEN;

static inline BOOL _queryUniqueSet(NSSet *set, ODOObject *query)
{
    id obj = [set member:query];
    OBASSERT(obj == nil || obj == query);
    return obj != nil;
}

