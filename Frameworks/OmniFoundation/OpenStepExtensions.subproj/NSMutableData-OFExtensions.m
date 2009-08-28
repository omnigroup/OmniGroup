// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSMutableData-OFExtensions.h>

RCS_ID("$Id$")

@implementation NSMutableData (OFExtensions)

- (void)appendString:(NSString *)aString encoding:(NSStringEncoding)anEncoding;
{
    CFStringRef cfString = (CFStringRef)aString;
    CFStringEncoding cfEncoding = CFStringConvertNSStringEncodingToEncoding(anEncoding);
    
    const char *encoded = CFStringGetCStringPtr(cfString, cfEncoding);
    if (encoded) {
        // Thanks to Adam R. Maxwell for pointing this out: the only reliable way to determine the length of the buffer returned by CFStringGetCStringPtr() is to call CFStringGetBytes() (with a NULL buffer). Hopefully this is still fast in the cases that CFStringGetCStringPtr() is fast.
        CFIndex length = CFStringGetLength(cfString);
        CFIndex bufLen;
        bufLen = kCFNotFound;
        CFIndex convertedLength = CFStringGetBytes(cfString, CFRangeMake(0, length), cfEncoding, 0, FALSE, NULL, UINT_MAX, &bufLen);
        if (convertedLength == length && bufLen != kCFNotFound) {
            [self appendBytes:encoded length:bufLen];
            return;
        }
    }
    
    CFDataRef block = CFStringCreateExternalRepresentation(kCFAllocatorDefault, cfString, cfEncoding, 0);
    if (block) {
        [self appendData:(NSData *)block];
        CFRelease(block);
        return;
    }
    
    [NSException raise:NSInvalidArgumentException format:@"Cannot convert string to bytes in %@ encoding", [NSString localizedNameOfStringEncoding:anEncoding]];
}

@end
