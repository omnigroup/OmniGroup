// Copyright 2003-2005, 2007-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniBase/rcsid.h>

#import <CoreFoundation/CoreFoundation.h>

#ifndef OF_USE_NEW_CF_PLIST_API
/* The old-style APIs return strings which we want to wrap in NSErrors; we'll want an error code to do that with */
#if !(defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE)
#import <MacErrors.h> // For coreFoundationUnknownErr
#define stringErrorCode coreFoundationUnknownErr
#else
/* Hilariously, coreFoundationUnknownErr exists in the *simulator* SDKs but not the *device* SDKs. Let's just copy the value out here. This whole chunk of code is only compiled if we're targeting an old (pre-4.0) version of iOS anyway. */
#define stringErrorCode -4960
#endif
#endif

RCS_ID("$Id$")


#ifdef OF_USE_NEW_CF_PLIST_API

/* OFCreateDataFromPropertyList() and OFCreatePropertyListFromData() are inlines on 10.6+ since there are now CF functions with nearly identical behavior */

static inline CFPropertyListRef _OFCreatePropertyListWithStream(CFAllocatorRef allocator, CFReadStreamRef stream, CFOptionFlags options, CFErrorRef *error) CF_RETURNS_RETAINED;
static inline CFPropertyListRef _OFCreatePropertyListWithStream(CFAllocatorRef allocator, CFReadStreamRef stream, CFOptionFlags options, CFErrorRef *error)
{
    return CFPropertyListCreateWithStream(allocator, stream, 0, options, NULL, error);
}

#else

/* Pre-10.6 (or pre-iOS 4.0), we need to use the stream APIs directly */

static int _OFSetErrorFromString(CFErrorRef *error, CFStringRef functionName, CFStringRef errorText)
{
    if (error) {
        const void *keys[1], *values[1];
        keys[0] = kCFErrorDescriptionKey;
        values[0] = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@: %@"), functionName, errorText);
        *error = CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, kCFErrorDomainOSStatus, stringErrorCode, keys, values, 1);
        CFRelease(values[0]);
    }
    
    /* We don't have any useful return value, but clang insists that we must: "warning: Function accepting CFErrorRef* should have a non-void return value to indicate whether or not an error occurred" */
    return 0;
}

static CFPropertyListRef _OFCreatePropertyListWithStream(CFAllocatorRef allocator, CFReadStreamRef stream, CFPropertyListMutabilityOptions options, CFErrorRef *outError) CF_RETURNS_RETAINED;
static CFPropertyListRef _OFCreatePropertyListWithStream(CFAllocatorRef allocator, CFReadStreamRef stream, CFPropertyListMutabilityOptions options, CFErrorRef *outError)
{
    CFStringRef errorString = NULL;
    CFPropertyListRef result = CFPropertyListCreateFromStream(allocator, stream, 0, options, NULL, &errorString);
    
    /* Note that the documentation for CFPropertyListCreateFromStream says that the error indication is based on whether errorString is NULL, not on whether the return value is NULL. WTF. */ 
    if (errorString != NULL) {
        OBASSERT_NULL(result);
        _OFSetErrorFromString(outError, CFSTR("CFPropertyListCreateFromStream"), errorString);
        return NULL;
    }
    
    return result;
}

CFDataRef OFCreateDataFromPropertyList(CFAllocatorRef allocator, CFPropertyListRef plist, CFPropertyListFormat format, CFErrorRef *outError)
{
    CFWriteStreamRef stream;
    CFStringRef error;
    CFDataRef buf;

    stream = CFWriteStreamCreateWithAllocatedBuffers(kCFAllocatorDefault, allocator);
    CFWriteStreamOpen(stream);

    error = NULL;
    CFPropertyListWriteToStream(plist, stream, format, &error);

    if (error != NULL) {
        _OFSetErrorFromString(outError, CFSTR("CFPropertyListWriteToStream"), error);
        CFWriteStreamClose(stream);
        CFRelease(stream);
        return NULL;
    }
    
    buf = CFWriteStreamCopyProperty(stream, kCFStreamPropertyDataWritten);
    CFWriteStreamClose(stream);
    CFRelease(stream);

    return buf;
}

#if 0  /* Not currently used anywhere */
CFPropertyListRef OFCreatePropertyListFromBytes(CFAllocatorRef allocator, bytes, length, CFPropertyListMutabilityOptions options, CFErrorRef *outError)
{
    CFReadStreamRef stream = CFReadStreamCreateWithBytesNoCopy(kCFAllocatorDefault, bytes, length, kCFAllocatorNull);
    CFPropertyListRef result = _OFCreatePropertyListWithStream(allocator, stream, options, outError);
    CFReadStreamClose(stream);
    CFRelease(stream);
    return result;
}
#endif

#endif

CFPropertyListRef OFCreatePropertyListFromFile(CFStringRef filePath, CFPropertyListMutabilityOptions options, CFErrorRef *outError)
{
    CFReadStreamRef stream;
    
    CFURLRef fileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, filePath, kCFURLPOSIXPathStyle, FALSE);
    if (!fileURL || !(stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, fileURL))) {
        if (outError) {
            const void *keys[1], *values[1];
            keys[0] = NSFilePathErrorKey;
            values[0] = filePath;
            *outError = CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, (CFStringRef)NSCocoaErrorDomain, NSFileReadUnknownError, keys, values, 1);
        }
        if (fileURL) 
            CFRelease(fileURL);

        return NULL;
    }
    CFRelease(fileURL);
    CFReadStreamOpen(stream);
    {
        CFErrorRef openError = CFReadStreamCopyError(stream);
        if (openError) {
            if (outError)
                *outError = openError;
            else
                CFRelease(openError);
            CFRelease(stream);
            return NULL;
        }
    }
    
    CFPropertyListRef result = _OFCreatePropertyListWithStream(kCFAllocatorDefault, stream, options, outError);
    CFReadStreamClose(stream);
    CFRelease(stream);
    
    return result;
}
