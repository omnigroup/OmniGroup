// Copyright 1997-2005, 2007, 2009, 2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFHeap.h>
#import <OmniBase/OBUtilities.h>

RCS_ID("$Id$")

@implementation OFHeap
{
    // In ARC, stores into a '__strong id *' will release the old value and retain the new one. But, -dealloc doesn't know how to clean up the array. We could write nils to all the slots to do the releases, which would save us the effort of doing retains/releases elsewhere, but would mean we had to do writes in -dealloc. Unclear that it matters too much.
    // If we do use __strong, then growing the array is harder. We can't use realloc naively since the new space in the array could be non-nil.
    // For now, we'll manage references ourselves since we do a lot of swap operations storing into the array, which would cause spurious retain/releases.
    __unsafe_unretained id *_objects;
    
    NSUInteger _count, _capacity;
    NSComparator _comparator;
}

- init;
{
    return [self initWithComparator:^(id objectA, id objectB) {
        return [objectA compare:objectB];
    }];
}

- initWithComparator:(NSComparator)comparator;
{
    if (!(self = [super init]))
        return nil;

    _comparator = [comparator copy];
    
    return self;
}

- (void) dealloc;
{
    for (NSUInteger objectIndex = 0; objectIndex < _count; objectIndex++)
        OBStrongRelease(_objects[objectIndex]);
    if (_objects)
        free(_objects);
}

- (NSUInteger)count;
{
    return _count;
}

#define LESSTHAN(a, b) (_comparator(_objects[a], _objects[b]) == NSOrderedAscending)

#define PARENT(a)     ((a - 1) >> 1)
#define LEFTCHILD(a)  ((a << 1) + 1)
#define RIGHTCHILD(a) ((a << 1) + 2)

- (void)addObject:(id)anObject;
{
    NSUInteger upFrom, upTo;

    if (_count == _capacity) {
        _capacity = 2 * (_capacity + 1); // might be zero
        _objects = (__unsafe_unretained id *)realloc(_objects, sizeof(*_objects) * _capacity);
    }

    OBStrongRetain(anObject);
    _objects[_count] = anObject;

    upFrom = _count;

    while (upFrom) {
	// move the new value up the tree as far as it should go
	upTo = PARENT(upFrom);
	if (LESSTHAN(upFrom, upTo)) {
	    SWAP(_objects[upFrom], _objects[upTo]);
	} else
	    break;
	upFrom = upTo;
    }

    _count++;
}

- (id)removeObject;
{
    NSUInteger root, left, right, swapWith;

    if (!_count)
	return nil;

    id result = _objects[0]; // ARC should give it a reference here and autorelease it below
    OBStrongRelease(result); // Account for the one still in _objects[0]
    
    _objects[0] = _objects[--_count];
    root = 0;
    while (YES) {
	swapWith = root;
        if ((right = RIGHTCHILD(root)) < _count && LESSTHAN(right, root))
	    swapWith = right;
        if ((left = LEFTCHILD(root)) < _count && LESSTHAN(left, swapWith))
	    swapWith = left;
	if (swapWith == root)
	    break;
	SWAP(_objects[root], _objects[swapWith]);
	root = swapWith;
    }

    return result;
}

- (id)removeObjectLessThanObject:(id)object;
{
    if (_comparator(_objects[0], object) == NSOrderedAscending)
	return [self removeObject];
    else
	return nil;
}

- (void)removeAllObjects;
{
    for (NSUInteger objectIndex = 0; objectIndex < _count; objectIndex++)
        OBStrongRelease(_objects[objectIndex]);
    _count = 0;
}

- (id)peekObject;
{
    if (_count)
        return _objects[0];
    return nil;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    NSMutableArray *objectDescriptions = [[NSMutableArray alloc] init];

    for (NSUInteger i = 0; i < _count; i++)
        [objectDescriptions addObject: [_objects[i] debugDictionary]];
    [dict setObject: objectDescriptions forKey: @"objects"];
    
    return dict;
}

@end
