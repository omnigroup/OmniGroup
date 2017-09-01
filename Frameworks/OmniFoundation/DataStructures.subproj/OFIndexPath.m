// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFIndexPath.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

// OFIndexPath is a NSIndexPath workalike.
//
// It doesn't have the thread safety and pathological performance problems NSIndexPath suffers due to uniquing.
//
// These issues appear to be resolved on OS X 10.8 and later, and iOS 6.0 and later.
// When our base system requirements allow, we can consider deprecating OFIndexPath.

@implementation OFIndexPath {
  @private
    OFIndexPath *_parent;
    NSUInteger _index, _length;
}

static OFIndexPath *emptyIndexPath = nil;

+ (void)initialize;
{
    OBINITIALIZE;

    emptyIndexPath = [[self alloc] _initWithParent:nil index:0 length:0];
}

- (void)dealloc;
{
    [_parent release];
    [super dealloc];
}

+ (OFIndexPath *)emptyIndexPath;
{
    OBPRECONDITION(emptyIndexPath != nil);
    return emptyIndexPath;
}

+ (OFIndexPath *)indexPathWithIndex:(NSUInteger)anIndex;
{
    return [emptyIndexPath indexPathByAddingIndex:anIndex];
}

- (OFIndexPath *)indexPathByAddingIndex:(NSUInteger)anIndex;
{
    return [[[[self class] alloc] _initWithParent:self index:anIndex length:_length + 1] autorelease];
}

- (OFIndexPath *)indexPathByRemovingLastIndex;
{
    return _parent;
}

- (NSUInteger)indexAtPosition:(NSUInteger)position;
{
    if (position + 1 == _length)
        return _index;
    else {
        OBASSERT(_parent != nil);
        return [_parent indexAtPosition:position];
    }
}

- (NSUInteger)length;
{
    return _length;
}

static void _getIndexes(OFIndexPath *indexPath, NSUInteger *indexes, NSUInteger length)
{
    OBPRECONDITION(indexPath->_length == length);
    
    NSUInteger slot = length;
    while (slot--) {
        indexes[slot] = indexPath->_index;
        indexPath = indexPath->_parent;
    }
}

- (void)getIndexes:(NSUInteger *)indexes;
{
    _getIndexes(self, indexes, _length);
}

- (void)enumerateIndexesUsingBlock:(void (^)(NSUInteger index, BOOL *stop))block;
{
    NSUInteger indexes[_length];

    _getIndexes(self, indexes, _length);
    
    for (NSUInteger i = 0; i < _length; i++) {
        BOOL stop = NO;
        block(indexes[i], &stop);
        if (stop) {
            break;
        }
    }
}

- (NSComparisonResult)_compare:(OFIndexPath *)otherObject orderParentsFirst:(BOOL)shouldOrderParentsFirst;
{
    OBPRECONDITION([otherObject isKindOfClass:[OFIndexPath class]]);

    if (otherObject == self)
        return NSOrderedSame;

    if (otherObject == nil || ![otherObject isKindOfClass:[OFIndexPath class]])
        return NSOrderedAscending;

    NSUInteger length = _length;
    NSUInteger otherLength = [otherObject length];
    NSUInteger componentIndex, componentCount = MIN(length, otherLength);
    if (componentCount > 0) {
        NSUInteger indexes[length], otherIndexes[otherLength];

        // clang-sa doesn't know that -getIndexes: fills the full array. The IPA can determine this with the inlined version, though.
        _getIndexes(self, indexes, length);
        _getIndexes(otherObject, otherIndexes, otherLength);

        for (componentIndex = 0; componentIndex < componentCount; componentIndex++) {
            NSUInteger component = indexes[componentIndex];
            NSUInteger otherComponent = otherIndexes[componentIndex];

            if (component < otherComponent)
                return NSOrderedAscending;
            else if (component > otherComponent)
                return NSOrderedDescending;
        }
    }

    if (length == otherLength)
        return NSOrderedSame;
    else if (length < otherLength)
        return shouldOrderParentsFirst ? NSOrderedAscending : NSOrderedDescending;
    else
        return shouldOrderParentsFirst ? NSOrderedDescending : NSOrderedAscending;
}

- (NSUInteger)hash;
{
    // Multiple the parent has by a prime number to cause a bit shift/more entropy in the hash
    return (13 * [_parent hash]) ^ _index;
}

- (BOOL)isEqual:(id)otherObject;
{
    return [self _compare:otherObject orderParentsFirst:YES] == NSOrderedSame;
}

- (NSComparisonResult)compare:(OFIndexPath *)otherObject;
{
    return [self _compare:otherObject orderParentsFirst:YES];
}

- (NSComparisonResult)parentsLastCompare:(OFIndexPath *)otherObject;
{
    return [self _compare:otherObject orderParentsFirst:NO];
}

- (NSString *)description;
{
    NSMutableString *description = [NSMutableString string];
    NSUInteger indexCount = _length;
    if (indexCount > 0) {
        NSUInteger indexes[indexCount];
        
        // clang-sa doesn't know that -getIndexes: fills the full array. The IPA can determine this with the inlined version, though.
        // http://llvm.org/bugs/show_bug.cgi?id=14877 -- a warning gets emitted here anyway, even though the inlined _getIndexes() fixes the warnings that were in -_compare:orderParentsFirst:.
        // -description shouldn't be in a performance critical path, so lets zero the array here to quiet the warning for now.
        memset(indexes, 0, sizeof(NSUInteger) * indexCount);
        _getIndexes(self, indexes, indexCount);

        for (NSUInteger indexIndex = 0; indexIndex < indexCount; indexIndex++) {
            NSUInteger indexValue = indexes[indexIndex];
            if (indexIndex == 0)
                [description appendFormat:@"%lu", indexValue];
            else
                [description appendFormat:@".%lu", indexValue];
        }
    }
    return description;
}

- (NSString *)descriptionWithLocale:(id)locale indent:(NSUInteger)level;
{
    return [self description];
}

#pragma mark NSCopying

- (id)copyWithZone:(nullable NSZone *)zone;
{
    // Instance are immutable.
    return [self retain];
}

#pragma mark Private

- (id)_initWithParent:(nullable OFIndexPath *)parent index:(NSUInteger)anIndex length:(NSUInteger)aLength;
{
    _parent = [parent retain];
    _index = anIndex;
    _length = aLength;
    return self;
}

@end

#pragma mark -

@implementation OFIndexPath (PropertyListSerialization)

+ (OFIndexPath *)indexPathWithPropertyListRepresentation:(NSArray<NSNumber *> *)propertyListRepresentation;
{
    OFIndexPath *indexPath = [OFIndexPath emptyIndexPath];
    
    for (NSNumber *value in propertyListRepresentation) {
        OBASSERT([value isKindOfClass:[NSNumber class]]);
        NSUInteger index = value.unsignedIntegerValue;
        indexPath = [indexPath indexPathByAddingIndex:index];
    }
    
    return indexPath;
}

- (NSArray<NSNumber *> *)propertyListRepresentation;
{
    NSMutableArray *propertyListRepresentation = [NSMutableArray array];
    
    [self enumerateIndexesUsingBlock:^(NSUInteger index, BOOL * _Nonnull stop) {
        [propertyListRepresentation addObject:@(index)];
    }];
    
    return propertyListRepresentation;
}

@end

NS_ASSUME_NONNULL_END

