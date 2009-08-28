// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFHeap.h>

RCS_ID("$Id$")

// In this case, the userInfo is the selector
static NSComparisonResult OFHeapCompareBySelector(OFHeap *heap, __strong void *userInfo, id object1, id object2)
{
    return (NSComparisonResult)objc_msgSend(object1, (SEL)userInfo, object2);
}
                                                  
@implementation OFHeap

- initWithCapacity:(NSUInteger)newCapacity compareFunction:(OFHeapComparisonFunction)comparisonFunction userInfo:(__strong void *)userInfo;
{
    if (!(self == [super init]))
        return nil;

    _capacity = newCapacity ? newCapacity : 4;
    _count = 0;
    _objects = (__strong id *)NSAllocateCollectable(sizeof(_objects) * _capacity, NSScannedOption);
    
    _comparisonFunction = comparisonFunction;
    _userInfo = userInfo;
    
    return self;
}

- initWithCapacity:(NSUInteger)newCapacity compareSelector:(SEL) comparisonSelector;
{
    return [self initWithCapacity:newCapacity compareFunction:OFHeapCompareBySelector userInfo:comparisonSelector];
}

- (void) dealloc;
{
    [self removeAllObjects];
    if (_objects)
        free(_objects);
    [super dealloc];
}

- (NSUInteger) count;
{
    return _count;
}

#define LESSTHAN(a, b)  (_comparisonFunction(self, _userInfo, _objects[a], _objects[b]) == NSOrderedAscending)

#define PARENT(a)     ((a - 1) >> 1)
#define LEFTCHILD(a)  ((a << 1) + 1)
#define RIGHTCHILD(a) ((a << 1) + 2)

- (void)addObject:(id)anObject;
{
    NSUInteger upFrom, upTo;

    if (_count == _capacity) {
        _capacity <<= 1;
        _objects = (__strong id *)NSReallocateCollectable(_objects, sizeof(*_objects) * _capacity, NSScannedOption);
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
    if (_comparisonFunction(self, _userInfo, _objects[0], object) == NSOrderedAscending)
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
