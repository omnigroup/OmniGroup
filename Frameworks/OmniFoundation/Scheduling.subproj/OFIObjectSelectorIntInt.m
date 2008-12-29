// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFIObjectSelectorIntInt.h>

#import <objc/objc-class.h>

RCS_ID("$Id$")

@implementation OFIObjectSelectorIntInt;

static Class myClass;

+ (void)initialize;
{
    OBINITIALIZE;
    myClass = self;
}

- initForObject:(id)anObject selector:(SEL)aSelector withInt:(int)anInt withInt:(int)anotherInt;
{
    OBPRECONDITION([anObject respondsToSelector:aSelector]);

    [super initForObject:anObject selector:aSelector];

    theInt = anInt;
    otherInt = anotherInt;

    return self;
}

- (void)invoke;
{
    Class cls = object_getClass(object);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method)
        [NSException raise:NSInvalidArgumentException format:@"%s(%p) does not respond to the selector %@", class_getName(cls), object, NSStringFromSelector(selector)];

    method_getImplementation(method)(object, selector, theInt, otherInt);
}

- (NSUInteger)hash;
{
    uintptr_t hashv = (uintptr_t)object + (uintptr_t)(void *)selector;
    return OFHashUIntptr(hashv) + (NSUInteger)theInt + (NSUInteger)otherInt;
}


- (BOOL)isEqual:(id)anObject;
{
    OFIObjectSelectorIntInt *otherObject = anObject;
    if (object_getClass(otherObject) != myClass)
	return NO;
    return object == otherObject->object && selector == otherObject->selector && theInt == otherObject->theInt && otherInt == otherObject->otherInt;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (object)
	[debugDictionary setObject:object forKey:@"object"];
    [debugDictionary setObject:NSStringFromSelector(selector) forKey:@"selector"];
    [debugDictionary setObject:[NSNumber numberWithInt:theInt] forKey:@"theInt"];
    [debugDictionary setObject:[NSNumber numberWithInt:otherInt] forKey:@"otherInt"];

    return debugDictionary;
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"-[%@ %@(%d,%d)]", OBShortObjectDescription(object), NSStringFromSelector(selector), theInt, otherInt];
}

@end
