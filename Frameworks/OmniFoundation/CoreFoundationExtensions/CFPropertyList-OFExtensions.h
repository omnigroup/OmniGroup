// Copyright 2003-2005, 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#include <CoreFoundation/CFData.h>
#include <CoreFoundation/CFPropertyList.h>
#import <OmniBase/objc.h>

/*
 Figure out whether we can use the new (CFError) APIs or the old (CFString) APIs.
 On the Mac, we can use the new APIs starting with 10.6.
 On iOS, we can use the new APIs starting with 4.0.
 Unfortunately, even earlier versions of iOS SDKs (e.g. 3.2) claim to be MacOSX 10.6! So we need to detect iOS first and ignore the (bogus) OSX version information in that case.
*/

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    /* We're targeting iOS (iPhone/iPad). The new APIs showed up in iOS 4.0. We could optionally check for them at runtime on 3.2, but won't for now. */
    #if defined(__IPHONE_4_0) && __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
        #define OF_USE_NEW_CF_PLIST_API
    #endif
#elif defined(MAC_OS_X_VERSION_MAX_ALLOWED)
    /* We're presumably running on MacOSX, or at least something whose MAC_OS_X_VERSION_foo macros correspond to the Mac version numbers. The new APIs showed up in Mac OS X 10.6. */
    #if (defined(MAC_OS_X_VERSION_10_6) && (MAC_OS_X_VERSION_10_6 <= MAC_OS_X_VERSION_MAX_ALLOWED))
        #define OF_USE_NEW_CF_PLIST_API
    #endif
#endif


#ifdef OF_USE_NEW_CF_PLIST_API

static inline CFDataRef OFCreateDataFromPropertyList(CFAllocatorRef allocator, CFPropertyListRef plist, CFPropertyListFormat format, CFErrorRef *outError) CF_RETURNS_RETAINED;
static inline CFDataRef OFCreateDataFromPropertyList(CFAllocatorRef allocator, CFPropertyListRef plist, CFPropertyListFormat format, CFErrorRef *outError) 
{
    return CFPropertyListCreateData(allocator, plist, format, 0, outError);
}

#if 0 // Currently unused
static inline CFPropertyListRef CF_RETURNS_RETAINED OFCreatePropertyListFromData(CFAllocatorRef allocator, CFDataRef data, CFPropertyListMutabilityOptions options, CFErrorRef *outError) 
{
    return CFPropertyListCreateWithData(allocator, data, options, NULL, outError);
}
#endif

#else /* not OF_USE_NEW_CF_PLIST_API */

/* This simply creates a CFStream, writes the property list using CFPropertyListWriteToStream(), and returns the resulting bytes. if an error occurs, an exception is raised. */
CFDataRef OFCreateDataFromPropertyList(CFAllocatorRef allocator, CFPropertyListRef plist, CFPropertyListFormat format, CFErrorRef *outError) CF_RETURNS_RETAINED;

// CFPropertyListRef OFCreatePropertyListFromData(CFAllocatorRef allocator, CFDataRef data, CFPropertyListMutabilityOptions options, CFErrorRef *outError) CF_RETURNS_RETAINED;

#endif

CFPropertyListRef OFCreatePropertyListFromFile(CFStringRef filePath, CFPropertyListMutabilityOptions options, CFErrorRef *outError) CF_RETURNS_RETAINED;


/* Regardless of which version of the function we're using, provide a wrapper to perform the toll-free-bridging casts and (non-Core-) Foundation memory management */
static inline NSData *OFCreateNSDataFromPropertyList(id plist, CFPropertyListFormat format, NSError **outError)
{
    CFDataRef data = OFCreateDataFromPropertyList(kCFAllocatorDefault, (CFPropertyListRef)plist, format, (CFErrorRef *)outError);
    if (data)
        return NSMakeCollectable(data);
    else {
        *outError = [(id)CFMakeCollectable(*(CFErrorRef *)outError) autorelease];
        return nil;
    }
}

