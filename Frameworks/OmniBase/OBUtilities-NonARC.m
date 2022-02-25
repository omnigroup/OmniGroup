// Copyright 1997-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBUtilities.h>

#import <OmniBase/rcsid.h>
#import <malloc/malloc.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

void OBObjectGetUnsafeObjectIvar(id _Nullable object, const char *ivarName, __unsafe_unretained id _Nullable * _Nullable outValue)
{
    __unsafe_unretained id value = nil;
    object_getInstanceVariable(object, ivarName, (void **)&value);
    if (outValue)
        *outValue = value;
}

__unsafe_unretained id _Nullable * _Nullable OBCastMemoryBufferToUnsafeObjectArray(void * _Nullable buffer)
{
    return (__unsafe_unretained id *)buffer;
}

id OBAllocateObject(Class cls, NSUInteger extraBytes)
{
    return NSAllocateObject(cls, extraBytes, NULL);
}

void *OBGetIndexedIvars(id object)
{
    return object_getIndexedIvars(object);
}

#ifdef DEBUG
NSUInteger OBRetainCount(id object)
{
    return [object retainCount];
}
#endif

// KVO debugging helpers
#if 0 && defined(DEBUG)
static void (*original_addObserver)(id self, SEL _cmd, NSObject *observer, NSString *keyPath, NSKeyValueObservingOptions options, void * _Nullable context);
static void (*original_removeObserver)(id self, SEL _cmd, NSObject *observer, NSString *keyPath, void * _Nullable context);

static void replacement_addObserver(id self, SEL _cmd, NSObject *observer, NSString *keyPath, NSKeyValueObservingOptions options, void * _Nullable context)
{
    malloc_statistics_t stats;
    malloc_zone_statistics(NULL, &stats);

    fprintf(stderr, "🟪 ADD %s %p.%s -> %s %p %p %u\n", class_getName([self class]), self, [keyPath UTF8String], class_getName([observer class]), observer, context, stats.blocks_in_use);
    original_addObserver(self, _cmd, observer, keyPath, options, context);
}

static void replacement_removeObserver(id self, SEL _cmd, NSObject *observer, NSString *keyPath, void * _Nullable context)
{
    malloc_statistics_t stats;
    malloc_zone_statistics(NULL, &stats);

    fprintf(stderr, "🟪 DEL %s %p.%s -> %s %p %p %u\n", class_getName([self class]), self, [keyPath UTF8String], class_getName([observer class]), observer, context, stats.blocks_in_use);
    original_removeObserver(self, _cmd, observer, keyPath, context);
}

static void Initialize(void) __attribute__((constructor));
static void Initialize(void)
{
    Class cls = [NSObject class];
    original_addObserver = (typeof(original_addObserver))OBReplaceMethodImplementation(cls, @selector(addObserver:forKeyPath:options:context:), (IMP)replacement_addObserver);
    original_removeObserver = (typeof(original_removeObserver))OBReplaceMethodImplementation(cls, @selector(removeObserver:forKeyPath:context:), (IMP)replacement_removeObserver);
}
#endif

NS_ASSUME_NONNULL_END

