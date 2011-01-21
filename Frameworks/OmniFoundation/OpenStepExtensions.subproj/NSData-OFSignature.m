// Copyright 1998-2005,2007,2008, 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFSignature.h>

#import <OmniFoundation/CFData-OFExtensions.h>

RCS_ID("$Id$")

@implementation NSData (OFSignature)

- (NSData *)copySHA1Signature;
{
    CFDataRef signature = OFDataCreateSHA1Digest(kCFAllocatorDefault, (CFDataRef)self);
    return NSMakeCollectable(signature);
}

- (NSData *)sha1Signature;
{
    return [[self copySHA1Signature] autorelease];
}

- (NSData *)sha256Signature;
{
    CFDataRef signature = OFDataCreateSHA256Digest(kCFAllocatorDefault, (CFDataRef)self);
    return [NSMakeCollectable(signature) autorelease];
}

- (NSData *)md5Signature;
{
    CFDataRef signature = OFDataCreateMD5Digest(kCFAllocatorDefault, (CFDataRef)self);
    return [NSMakeCollectable(signature) autorelease];
}

- (NSData *)signatureWithAlgorithm:(NSString *)algName;
{
    switch ([algName caseInsensitiveCompare:@"sha1"]) {
        case NSOrderedSame:
            return [self sha1Signature];
        case NSOrderedAscending:
            switch ([algName caseInsensitiveCompare:@"md5"]) {
                case NSOrderedSame:
                    return [self md5Signature];
                default:
                    break;
            }
            break;
        case NSOrderedDescending:
            switch ([algName caseInsensitiveCompare:@"sha256"]) {
                case NSOrderedSame:
                    return [self sha256Signature];
                default:
                    break;
            }
            break;
        default:
            break;
    }
    
    return nil;
}

@end
