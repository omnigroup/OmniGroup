// Copyright 1997-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBBundle.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>
#import <OmniBase/OBUtilities.h>

RCS_ID("$Id$");

#import <dlfcn.h>

static BOOL _OBBundleHasExecutablePath(NSBundle *bundle, NSString *path)
{
    // On the Mac, it is insufficient to just compare, since the actual path will be fully resolved (.../Foo.framework/Versions/A/Foo) while the bundle executable path won't (.../Foo.framework/Foo)
    // It may be better to just stat the path and compare the filesystem identifier and file identifier.
    NSString *bundleExecutable = [[bundle executablePath] stringByResolvingSymlinksInPath];
    path = [path stringByResolvingSymlinksInPath];

    return [bundleExecutable isEqual:path];
}

static NSBundle *_OBLoadedBundleWithExecutablePath(NSString *path)
{
    for (NSBundle *bundle in [NSBundle allBundles]) {
        if (![bundle isLoaded]) {
            continue; // Can't be running code from a bundle that isn't loaded.
        }
        if (_OBBundleHasExecutablePath(bundle, path)) {
            //NSLog(@"ptr %p maps to bundle %@", ptr, bundle);
            return bundle;
        }
    }

    for (NSBundle *bundle in [NSBundle allFrameworks]) {
        if (![bundle isLoaded]) {
            continue; // Can't be running code from a bundle that isn't loaded.
        }
        if (_OBBundleHasExecutablePath(bundle, path)) {
            //NSLog(@"ptr %p maps to bundle %@", ptr, bundle);
            return bundle;
        }
    }

    OBASSERT_NOT_REACHED("No bundle found for path %@", path);
    return nil;
}

// May want to move OFCFCallbacks.[hm] to OmniBase...

static CFStringRef OBPointerCopyDescription(const void *ptr)
{
    return CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("<%p>"), ptr);
}

static const CFDictionaryKeyCallBacks OBNonOwnedPointerDictionaryKeyCallbacks = {
    0,    // version
    NULL, // retain
    NULL, // release
    OBPointerCopyDescription,
    NULL, // equal
    NULL, // hash
};

static const void * OBNSObjectRetain(CFAllocatorRef allocator, const void *value)
{
    OBStrongRetain((OB_BRIDGE id)value);
    return value;
}

static void OBNSObjectRelease(CFAllocatorRef allocator, const void *value)
{
    OBStrongRelease((OB_BRIDGE id)value);
}

static Boolean OBNSObjectIsEqual(const void *value1, const void *value2)
{
    return [(OB_BRIDGE id)value1 isEqual: (OB_BRIDGE id)value2];
}

static CFStringRef OBNSObjectCopyDescription(const void *value)
{
    CFStringRef str = (OB_BRIDGE CFStringRef)[(OB_BRIDGE id)value description];
    if (str)
        CFRetain(str);
    return str;
}

static const CFDictionaryValueCallBacks OBNSObjectDictionaryValueCallbacks = {
    0,    // version
    OBNSObjectRetain,
    OBNSObjectRelease,
    OBNSObjectCopyDescription,
    OBNSObjectIsEqual,
};

NSBundle *_OBBundleForDataPointer(const void *ptr, const void *dso_handle)
{
    // NSMapTable.h says "We recommend the C function API for "void *" access.", but the C API isn't present on iOS, or at least not public. So, we'll use a CF dictionary instead.
    static dispatch_queue_t Queue;
    static CFMutableDictionaryRef DSOToBundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Queue = dispatch_queue_create("com.omnigroup.framework.OmniBase.OBBundle", DISPATCH_QUEUE_CONCURRENT);
        DSOToBundle = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OBNonOwnedPointerDictionaryKeyCallbacks, &OBNSObjectDictionaryValueCallbacks);
    });

    __block NSBundle *bundle = nil;
    dispatch_sync(Queue, ^{
        bundle = (NSBundle *)CFDictionaryGetValue(DSOToBundle, dso_handle);
    });

    if (!bundle) {
        Dl_info info;
        if (dladdr(ptr, &info) == 0) {
            NSLog(@"No image found for pointer %p", ptr);
            return nil;
        }
        OBASSERT(info.dli_fbase == dso_handle);

        //NSLog(@"ptr %p maps to image %s, for dso %p", ptr, info.dli_fname, dso_handle);
        NSString *executablePath = [NSString stringWithUTF8String:info.dli_fname];

        // Not currently caching misses, but we assert in _OBLoadedBundleWithExecutablePath.
        bundle = _OBLoadedBundleWithExecutablePath(executablePath);
        if (bundle) {
            dispatch_barrier_async(Queue, ^{
                // Can't use CFDictionaryAddValue since we might be racing to fill the cache from multiple queues.
                CFDictionarySetValue(DSOToBundle, dso_handle, (OB_BRIDGE void *)bundle);
            });
        }
    }

    return bundle;

}
