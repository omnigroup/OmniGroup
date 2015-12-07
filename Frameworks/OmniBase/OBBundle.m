// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBBundle.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

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

NSBundle *_OBBundleForDataPointer(const void *ptr)
{
    Dl_info info;
    if (dladdr(ptr, &info) == 0) {
        NSLog(@"No image found for pointer %p", ptr);
        return nil;
    }

    //NSLog(@"ptr %p maps to image %s", ptr, info.dli_fname);

    NSString *executablePath = [NSString stringWithUTF8String:info.dli_fname];

    for (NSBundle *bundle in [NSBundle allBundles]) {
        if (_OBBundleHasExecutablePath(bundle, executablePath)) {
            //NSLog(@"ptr %p maps to bundle %@", ptr, bundle);
            return bundle;
        }
    }

    for (NSBundle *bundle in [NSBundle allFrameworks]) {
        if (_OBBundleHasExecutablePath(bundle, executablePath)) {
            //NSLog(@"ptr %p maps to bundle %@", ptr, bundle);
            return bundle;
        }
    }

    OBASSERT_NOT_REACHED("No bundle found for pointer %p", ptr);
    return nil;
}
