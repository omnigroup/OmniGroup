// Copyright 2003-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFPropertyList-OFExtensions.h>

#import <CoreFoundation/CFStream.h>
#import <CoreFoundation/CFString.h>

RCS_ID("$Id$")

CFDataRef OFCreateDataFromPropertyList(CFAllocatorRef allocator, CFPropertyListRef plist, CFPropertyListFormat format)
{
    CFWriteStreamRef stream;
    CFStringRef error;
    CFDataRef buf;

    stream = CFWriteStreamCreateWithAllocatedBuffers(kCFAllocatorDefault, allocator);
    CFWriteStreamOpen(stream);

    error = NULL;
    CFPropertyListWriteToStream(plist, stream, format, &error);

    if (error != NULL) {
        CFWriteStreamClose(stream);
        CFRelease(stream);
        [NSException raise:NSGenericException format:@"CFPropertyListWriteToStream: %@", error];
    }
    
    buf = CFWriteStreamCopyProperty(stream, kCFStreamPropertyDataWritten);
    CFWriteStreamClose(stream);
    CFRelease(stream);

    return buf;
}

