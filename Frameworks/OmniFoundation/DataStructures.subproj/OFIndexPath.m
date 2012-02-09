// Copyright 2008-2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFIndexPath.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@interface OFIndexPath (Private)
- (id)_initWithParent:(OFIndexPath *)parent index:(NSUInteger)anIndex length:(NSUInteger)aLength;
@end

@implementation OFIndexPath

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
    return [[[isa alloc] _initWithParent:self index:anIndex length:_length + 1] autorelease];
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

- (void)getIndexes:(NSUInteger *)indexes;
{
    if (_length == 0)
        return;

    indexes[_length - 1] = _index;
    OBASSERT(_parent != nil); // The only time we have a nil parent is if our length is 0
    [_parent getIndexes:indexes];
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

        [self getIndexes:indexes];
        [otherObject getIndexes:otherIndexes];

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
    NSUInteger indexIndex, indexCount = _length;
    if (indexCount > 0) {
        NSUInteger indexes[indexCount];
        [self getIndexes:indexes];
        for (indexIndex = 0; indexIndex < indexCount; indexIndex++) {
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

@end

@implementation OFIndexPath (Private)

- (id)_initWithParent:(OFIndexPath *)parent index:(NSUInteger)anIndex length:(NSUInteger)aLength;
{
    _parent = [parent retain];
    _index = anIndex;
    _length = aLength;
    return self;
}

@end
