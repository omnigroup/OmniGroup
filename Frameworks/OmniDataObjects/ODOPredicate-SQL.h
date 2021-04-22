// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOPredicate.h>
#import <Foundation/NSComparisonPredicate.h>

@class NSArray, NSError, NSString, NSMutableString;
@class ODOEntity;

NS_ASSUME_NONNULL_BEGIN

@interface ODOSQLTable : NSObject

- init NS_UNAVAILABLE;
- initWithEntity:(ODOEntity *)entity;

// The most recently added entity
@property(nonnull,nonatomic,readonly) ODOEntity *currentEntity;
@property(nonnull,nonatomic,readonly) NSString *currentAlias;

- (void)withEntities:(NSArray <ODOEntity *> *)entities perform:(void (NS_NOESCAPE ^)(void))action;

- (nullable NSString *)aliasForEntity:(ODOEntity *)entity;

@end

@interface NSPredicate (ODO_SQL)
- (BOOL)appendSQL:(NSMutableString *)sql table:(ODOSQLTable *)table constants:(NSMutableArray *)constants error:(NSError **)outError;
@end
@interface NSExpression (ODO_SQL)
- (BOOL)appendSQL:(NSMutableString *)sql table:(ODOSQLTable *)table constants:(NSMutableArray *)constants error:(NSError **)outError;
@end

//
@interface ODORelationshipMatchingCountPredicate : NSPredicate

- initWithSourceEntity:(ODOEntity *)sourceEntity relationshipKeyPath:(NSString *)relationshipKeyPath destinationPredicate:(nullable NSPredicate *)destinationPredicate comparison:(NSPredicateOperatorType)comparison comparisonValue:(NSUInteger)comparisonValue;

@property(nonatomic,readonly) ODOEntity *sourceEntity;
@property(nonatomic,readonly) NSString *relationshipKeyPath;
@property(nullable,nonatomic,readonly) NSPredicate *destinationPredicate;
@property(nonatomic,readonly) NSPredicateOperatorType comparison;
@property(nonatomic,readonly) NSUInteger comparisonValue;

@end


OB_HIDDEN extern const char * const ODOComparisonPredicateStartsWithFunctionName;
OB_HIDDEN extern const char * const ODOComparisonPredicateContainsFunctionName;

NS_ASSUME_NONNULL_END
