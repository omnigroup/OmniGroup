// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDataObjects/ODOProperty.h>

@class ODOEntity;

typedef enum {
    ODORelationshipDeleteRuleInvalid = -1,
    ODORelationshipDeleteRuleNullify,
    ODORelationshipDeleteRuleCascade,
    ODORelationshipDeleteRuleDeny,
    //
    ODORelationshipDeleteRuleCount
} ODORelationshipDeleteRule;

@interface ODORelationship : ODOProperty
{
@private
    ODOEntity *_destinationEntity;
    ODORelationshipDeleteRule _deleteRule;
    ODORelationship *_inverseRelationship;
}

@property(readonly) BOOL isToMany;
@property(readonly) ODOEntity *destinationEntity;
@property(readonly) ODORelationship *inverseRelationship;

@property(readonly) ODORelationshipDeleteRule deleteRule;

@end
