// Copyright 1998-2005,2007,2008, 2010-2011, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFSignature.h>

#import <OmniFoundation/CFData-OFExtensions.h>
#import <OmniBase/macros.h>

RCS_ID("$Id$")

@implementation NSData (OFSignature)

- (NSData *)copySHA1Signature;
{
    return (OB_BRIDGE NSData *)OFDataCreateSHA1Digest(kCFAllocatorDefault, (CFDataRef)self);
}

- (NSData *)sha1Signature;
{
    return [[self copySHA1Signature] autorelease];
}

- (NSData *)sha256Signature;
{
    return CFBridgingRelease(OFDataCreateSHA256Digest(kCFAllocatorDefault, (CFDataRef)self));
}

- (NSData *)md5Signature;
{
    return CFBridgingRelease(OFDataCreateMD5Digest(kCFAllocatorDefault, (CFDataRef)self));
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
