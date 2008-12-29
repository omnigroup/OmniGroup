// Copyright 2003-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFIObjectSelectorObjectInt.h>

#import <objc/objc-class.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>

RCS_ID("$Id$")

@implementation OFIObjectSelectorObjectInt

- initForObject:(id)targetObject selector:(SEL)aSelector withObject:(id)anObject withInt:(int)anInt;
{
    OBPRECONDITION([targetObject respondsToSelector:aSelector]);

    [super initForObject:targetObject selector:aSelector];

    withObject = [anObject retain];
    theInt = anInt;

    return self;
}

- (void)dealloc;
{
    [withObject release];
    [super dealloc];
}

- (void)invoke;
{
    Class cls = object_getClass(object);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method)
        [NSException raise:NSInvalidArgumentException format:@"%s(%p) does not respond to the selector %@", class_getName(cls), object, NSStringFromSelector(selector)];

    method_getImplementation(method)(object, selector, withObject, theInt);
}

- (NSUInteger)hash;
{
    uintptr_t hashv = (uintptr_t)object + (uintptr_t)(void *)selector + (uintptr_t)withObject;
    return OFHashUIntptr(hashv) + (NSUInteger)theInt;
}

- (BOOL)isEqual:(id)anObject;
{
    OFIObjectSelectorObjectInt *otherObject;

    otherObject = anObject;
    if (object_getClass(otherObject) != isa)
        return NO;
    return object == otherObject->object && selector == otherObject->selector && withObject == otherObject->withObject && theInt == otherObject->theInt;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (object)
        [debugDictionary setObject:object forKey:@"object"];
    [debugDictionary setObject:NSStringFromSelector(selector) forKey:@"selector"];
    if (withObject)
        [debugDictionary setObject:withObject forKey:@"withObject"];
    [debugDictionary setIntValue:theInt forKey:@"theInt"];

    return debugDictionary;
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"-[%@ %@(%@,%d)]", OBShortObjectDescription(object), NSStringFromSelector(selector), OBShortObjectDescription(withObject), theInt];
}

@end
