// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOPredicate.h>
#import <Foundation/NSComparisonPredicate.h>

@class ODOEntity;

NS_ASSUME_NONNULL_BEGIN

@interface ODOSQLTable : NSObject

- init NS_UNAVAILABLE;
- initWithEntity:(ODOEntity *)entity;

@property(nonnull,nonatomic,readonly) ODOEntity *currentEntity;
@property(nonnull,nonatomic,readonly) NSString *currentAlias;

- (void)withEntity:(ODOEntity *)entity perform:(void (NS_NOESCAPE ^)(void))action;

@end

@interface NSPredicate (ODO_SQL)
- (BOOL)appendSQL:(NSMutableString *)sql table:(ODOSQLTable *)table constants:(NSMutableArray *)constants error:(NSError **)outError;
@end
@interface NSExpression (ODO_SQL)
- (BOOL)appendSQL:(NSMutableString *)sql table:(ODOSQLTable *)table constants:(NSMutableArray *)constants error:(NSError **)outError;
@end

//
@interface ODORelationshipMatchingCountPredicate : NSPredicate

- initWithRelationshipKey:(NSString *)relationshipKey predicate:(nullable NSPredicate *)predicate comparison:(NSPredicateOperatorType)comparison comparisonValue:(NSUInteger)comparisonValue;

@property(nonatomic,readonly) NSString *relationshipKey;
@property(nullable,nonatomic,readonly) NSPredicate *relationshipPredicate;
@property(nonatomic,readonly) NSPredicateOperatorType comparison;
@property(nonatomic,readonly) NSUInteger comparisonValue;

@end


OB_HIDDEN extern const char * const ODOComparisonPredicateStartsWithFunctionName;
OB_HIDDEN extern const char * const ODOComparisonPredicateContainsFunctionName;

NS_ASSUME_NONNULL_END
