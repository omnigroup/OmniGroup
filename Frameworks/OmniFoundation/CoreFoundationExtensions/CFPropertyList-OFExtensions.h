// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <CoreFoundation/CFData.h>
#import <CoreFoundation/CFPropertyList.h>
#import <OmniBase/objc.h>
#import <OmniBase/macros.h>
#import <Foundation/NSError.h>

CFPropertyListRef OFCreatePropertyListFromFile(CFStringRef filePath, CFPropertyListMutabilityOptions options, CFErrorRef *outError) CF_RETURNS_RETAINED;

/* Toll-free briding casts and (non-Core-) Foundation memory management */
static inline NSData *OFCreateNSDataFromPropertyList(id plist, CFPropertyListFormat format, NSError **outError) NS_RETURNS_RETAINED;
static inline NSData *OFCreateNSDataFromPropertyList(id plist, CFPropertyListFormat format, NSError **outError)
{
    CFErrorRef cfError = NULL;
    CFDataRef data = CFPropertyListCreateData(kCFAllocatorDefault, (OB_BRIDGE CFPropertyListRef)plist, format, 0/*options*/, &cfError);
    if (data)
        return (OB_BRIDGE_TRANSFER NSData *)data;

    if (outError) {
        *outError = OB_AUTORELEASE((OB_BRIDGE NSError *)cfError);
    } else {
        CFRelease(cfError);
    }
    return nil;
}

static inline id OFCreatePropertyListFromNSData(NSData *data, NSError **outError) NS_RETURNS_RETAINED;
static inline id OFCreatePropertyListFromNSData(NSData *data, NSError **outError)
{
    CFErrorRef cfError = nil;
    CFPropertyListRef propList = CFPropertyListCreateWithData(NULL, (__bridge CFDataRef)data, 0, NULL, &cfError);
    if (propList == NULL) {
        OB_CFERROR_TO_NS(outError, cfError);
        return nil;
    }
    
    return (OB_BRIDGE_TRANSFER id)propList;
}


extern id OFReadNSPropertyListFromURL(NSURL *fileURL, NSError **outError);
extern BOOL OFWriteNSPropertyListToURL(id plist, NSURL *fileURL, NSError **outError);

#ifdef DEBUG
extern void OFReportDuplicatePropertyListEntries(id plist);
extern void OFReportPointerCountInPropertyList(id plist);
#endif
