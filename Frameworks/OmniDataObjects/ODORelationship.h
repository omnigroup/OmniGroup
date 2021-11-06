// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOProperty.h>

@class ODOEntity;

typedef NS_ENUM(NSInteger, ODORelationshipDeleteRule) {
    ODORelationshipDeleteRuleInvalid = -1,
    ODORelationshipDeleteRuleNullify,
    ODORelationshipDeleteRuleCascade,
    ODORelationshipDeleteRuleDeny,
};

enum {
    ODORelationshipDeleteRuleCount = ODORelationshipDeleteRuleDeny + 1
};

@interface ODORelationship : ODOProperty {
@private
    ODOEntity *_destinationEntity;
    ODORelationshipDeleteRule _deleteRule;
    ODORelationship *_inverseRelationship;
    BOOL _shouldPrefetch;
@package
    NSString *_queryByForeignKeyStatementKey;
}

@property (nonatomic, readonly, getter=isToMany) BOOL toMany;
@property (nonatomic, readonly) BOOL shouldPrefetch;
@property (nonatomic, readonly) ODOEntity *destinationEntity;
@property (nonatomic, readonly) ODORelationship *inverseRelationship;

@property (nonatomic, readonly) ODORelationshipDeleteRule deleteRule;

@end
