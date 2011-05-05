// Copyright 2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <CommonCrypto/CommonDigest.h>

@class NSData, NSError;

@protocol OFBufferEater
- (BOOL)processBuffer:(const uint8_t *)buffer length:(size_t)length error:(NSError **)outError;
@end

/* OFDigestionContext protocol
 
 The caller should call methods either in the seqience verifyInit/processBuffer/verifyFinal or generateInit/processBuffer/generateFinal.
 
 (For the simple message-digest classes in this file there isn't much of a difference; verify simply generates a digest and compares it to the supplied digest. For some algorithms there is a difference.)
 
 An incorrect digest is treated as an error by verify and results in a false return value and an error of OFXMLSignatureValidationFailure.
*/
@protocol OFDigestionContext <OFBufferEater>
- (BOOL)verifyInit:(NSError **)outError;
- (BOOL)verifyFinal:(NSData *)digest error:(NSError **)outError;

- (BOOL)generateInit:(NSError **)outError;
- (NSData *)generateFinal:(NSError **)outError;
@end

/*
 A set of classes implementing OFDigestionContext for a few of the message digests supported by the CommonDigest.h.
*/
@interface OFCCDigestContext : NSObject <OFDigestionContext>
{
    NSData *result;
}

- (BOOL)verifyInit:(NSError **)outError;
- (BOOL)verifyFinal:(NSData *)digest error:(NSError **)outError; /* Digest may be nil */

- (BOOL)generateInit:(NSError **)outError;
- (NSData *)generateFinal:(NSError **)outError;

- (BOOL)processBuffer:(const uint8_t *)buffer length:(size_t)length error:(NSError **)outError;

@property (readonly, nonatomic) NSData *result;

@end

@interface OFMD5DigestContext : OFCCDigestContext
{
    CC_MD5_CTX ctx;
}

@end

@interface OFSHA1DigestContext : OFCCDigestContext
{
    CC_SHA1_CTX ctx;
}

@end

@interface OFSHA256DigestContext : OFCCDigestContext
{
    CC_SHA256_CTX ctx;
}

@end

@interface OFSHA512DigestContext : OFCCDigestContext
{
    CC_SHA512_CTX ctx;
}

@end

