// Copyright 2011-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class NSData, NSError;

@protocol OFBufferEater
- (BOOL)processBuffer:(const uint8_t *)buffer length:(size_t)length error:(NSError **)outError;
@end

/* OFDigestionContext protocol
 
 The caller should call methods either in the sequence verifyInit/processBuffer/verifyFinal or generateInit/processBuffer/generateFinal.
 
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

- (BOOL)verifyInit:(NSError **)outError;
- (BOOL)verifyFinal:(NSData *)digest error:(NSError **)outError; /* Digest may be nil */

- (BOOL)generateInit:(NSError **)outError;
- (NSData *)generateFinal:(NSError **)outError;

- (BOOL)processBuffer:(const uint8_t *)buffer length:(size_t)length error:(NSError **)outError;

@property (readonly, nonatomic) NSData *result;
@property (readwrite, nonatomic) unsigned int outputLength;
+ (unsigned int)outputLength;

@end

@interface OFMD5DigestContext : OFCCDigestContext
@end

@interface OFSHA1DigestContext : OFCCDigestContext
@end

@interface OFSHA256DigestContext : OFCCDigestContext
@end

@interface OFSHA512DigestContext : OFCCDigestContext
@end

/* There are two common representations for discrete-logarithm schemes like DSA and ECDSA: most APIs use an ASN.1 SEQUENCE of two INTEGERs encoded using DER, but the DSIG specification uses the (very slightly more compact) representation of two fixed-length integers concatenated with no headers. These functions help convert. */
NSData *OFDigestConvertDLSigToPacked(NSData *der, int integerWidthBits, NSError **outError);
NSData *OFDigestConvertDLSigToDER(NSData *packed, int integerWidthBits, NSError **outError);

