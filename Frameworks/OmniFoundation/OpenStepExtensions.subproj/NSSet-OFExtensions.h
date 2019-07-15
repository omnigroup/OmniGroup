// Copyright 2005-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSSet.h>

@interface NSSet<__covariant ObjectType> (OFExtensions)

typedef NSComparisonResult (^OFSetObjectComparator)(__kindof ObjectType object1, __kindof ObjectType object2);
typedef BOOL (^OFSetObjectPredicate)(__kindof ObjectType object);
typedef id (^OFSetObjectMap)(__kindof ObjectType object);

/// Returns YES if set is nil or is empty.
+ (BOOL)isEmptySet:(NSSet *)set;

+ (instancetype)setByEnumerating:(NSEnumerator<ObjectType> *)enumerator;

- (NSSet *)setByPerformingSelector:(SEL)aSelector;
- (NSSet *)setByPerformingBlock:(OFSetObjectMap)block;

- (NSSet<ObjectType> *)setByRemovingObject:(ObjectType)anObject;

- (NSArray<ObjectType> *)sortedArrayUsingSelector:(SEL)comparator;
- (NSArray<ObjectType> *)sortedArrayUsingComparator:(OFSetObjectComparator)comparator;

- (void)applyFunction:(CFSetApplierFunction)applier context:(void *)context;

- (ObjectType)any:(OFSetObjectPredicate)predicate;
- (BOOL)all:(OFSetObjectPredicate)predicate;

- (ObjectType)min:(OFSetObjectComparator)comparator;
- (ObjectType)max:(OFSetObjectComparator)comparator;

- (ObjectType)minValueForKey:(NSString *)key comparator:(OFSetObjectComparator)comparator;
- (ObjectType)maxValueForKey:(NSString *)key comparator:(OFSetObjectComparator)comparator;

- (NSSet<ObjectType> *)select:(OFSetObjectPredicate)predicate;

- (NSDictionary *)indexByBlock:(OFSetObjectMap)blk;

- (BOOL)containsObjectIdenticalTo:(ObjectType)anObject;
- (BOOL)isIdenticalToSet:(NSSet *)otherSet;

@end

#define OFSetByGettingProperty(set, cls, prop) [(set) setByPerformingBlock:^id(cls *item){ return item.prop; }]
