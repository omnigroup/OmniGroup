// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSBundle.h>
#import <OmniBase/macros.h>
#import <os/trace.h> // For __dso_handle

extern NSBundle *_OBBundleForDataPointer(const void *ptr, const void *dso_handle);

#define OMNI_BUNDLE ((NSBundle *)({ \
    static dispatch_once_t _OBBundle_once; \
    static NSBundle *_OBBundle_bundle = nil; \
    dispatch_once(&_OBBundle_once, ^{ \
        _OBBundle_bundle = OB_RETAIN(_OBBundleForDataPointer(&_OBBundle_bundle, &__dso_handle)); \
    }); \
    _OBBundle_bundle; \
}))
