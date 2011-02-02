// Copyright 1997-2005, 2007, 2009, 2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFHeap.h>

RCS_ID("$Id$")

@implementation OFHeap

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
    [self removeAllObjects];
    [_comparator release];
    if (_objects)
        free(_objects);
    [super dealloc];
}

- (NSUInteger) count;
{
    return _count;
}

#define LESSTHAN(a, b)  (_comparator(_objects[a], _objects[b]) == NSOrderedAscending)

#define PARENT(a)     ((a - 1) >> 1)
#define LEFTCHILD(a)  ((a << 1) + 1)
#define RIGHTCHILD(a) ((a << 1) + 2)

- (void)addObject:(id)anObject;
{
    NSUInteger upFrom, upTo;

    if (_count == _capacity) {
        _capacity = 2 * (_capacity + 1); // might be zero
        _objects = NSReallocateCollectable(_objects, sizeof(*_objects) * _capacity, NSScannedOption);
    }

    _objects[_count] = [anObject retain];

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
    id result;

    if (!_count)
	return nil;

    result = _objects[0];
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

    return [result autorelease];
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
    while (_count--)
        [_objects[_count] release];

    // Don't leave this at -1
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
    [objectDescriptions release];
    
    return dict;
}

@end
