// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBUtilities.h>
#import <OmniBase/assertions.h>

NS_ASSUME_NONNULL_BEGIN

// Support for working with Swift calling into C APIs where you need to store a pointer to an object as a raw 'void *'

static inline void *OBCastObjectToPointer(id object)
{
    OBPRECONDITION(object != NULL); // Our signature exposed to Swift is non-optional
    return (__bridge void *)object;
}

static inline __kindof id OBCastPointerToObject(void *ptr)
{
    OBPRECONDITION(ptr != NULL); // Our signature exposed to Swift is non-optional
    return (__bridge id)ptr;
}

static inline __kindof id OBCastClassToObject(Class cls)
{
    OBPRECONDITION(cls != NULL); // Our signature exposed to Swift is non-optional
    return (id)cls;
}

static inline Class OBCastObjectToClass(id object)
{
    OBPRECONDITION(object != NULL); // Our signature exposed to Swift is non-optional
    OBPRECONDITION(OBObjectIsClass(object));
    return (Class)object;
}

// CFHashCode is unsigned and Int is signed. Swift will signal an error if the conversion of an unsigned to signed will overflow into the sign bit.
static inline NSInteger OBIntegerFromHash(CFHashCode code)
{
    return code;
}

// Useful in the debugger when trying to `po` some hex address.
static inline id OBObjectFromInteger(uintptr_t value) {
    return OBCastPointerToObject((void *)value);
}

// Does a checked cast for the (rare) cases where you want to do 'obj as? Self' in Swift.
@interface NSObject (OBAsSelf)
+ (nullable instancetype)asSelf:(id)object;
@end

NS_ASSUME_NONNULL_END
