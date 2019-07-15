// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface OFIndexPath : OFObject <NSCopying>

+ (OFIndexPath *)emptyIndexPath;
+ (OFIndexPath *)indexPathWithIndex:(NSUInteger)anIndex;

- (OFIndexPath *)indexPathByAddingIndex:(NSUInteger)anIndex;
- (OFIndexPath *)indexPathByRemovingLastIndex;

- (NSUInteger)indexAtPosition:(NSUInteger)position;
@property (nonatomic, readonly) NSUInteger length;

- (void)getIndexes:(NSUInteger *)indexes;
- (void)enumerateIndexesUsingBlock:(void (^)(NSUInteger index, BOOL *stop))block;

- (NSComparisonResult)compare:(OFIndexPath *)otherObject;
- (NSComparisonResult)parentsLastCompare:(OFIndexPath *)otherObject;

@end

@interface OFIndexPath (PropertyListSerialization)

+ (OFIndexPath *)indexPathWithPropertyListRepresentation:(NSArray<NSNumber *> *)propertyListRepresentation;
@property (nonatomic, readonly) NSArray<NSNumber *> *propertyListRepresentation;

@end

NS_ASSUME_NONNULL_END
