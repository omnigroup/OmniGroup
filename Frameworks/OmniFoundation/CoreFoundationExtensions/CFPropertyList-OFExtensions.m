// Copyright 2003-2005, 2007-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniBase/rcsid.h>

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/NSPropertyList.h>

RCS_ID("$Id$")

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
    
    CFPropertyListRef result = CFPropertyListCreateWithStream(kCFAllocatorDefault, stream, 0/*read to end of stream*/, options, NULL, outError);
    CFReadStreamClose(stream);
    CFRelease(stream);
    
    return result;
}

id OFReadNSPropertyListFromURL(NSURL *fileURL, NSError **outError)
{
    NSData *data = [[NSData alloc] initWithContentsOfURL:fileURL options:NSDataReadingUncached error:outError];
    if (!data)
        return nil;
    
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:outError];
    [data release];
    return plist;
}

BOOL OFWriteNSPropertyListToURL(id plist, NSURL *fileURL, NSError **outError)
{
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:outError];
    if (!data)
        return NO;
    
    return [data writeToURL:fileURL options:0 error:outError];
}

