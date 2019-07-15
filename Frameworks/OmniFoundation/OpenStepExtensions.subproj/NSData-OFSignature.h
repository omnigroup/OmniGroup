// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSData.h>

#if defined(DEBUG)
#import <Foundation/NSOperation.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface NSData (OFSignature)

- (NSData *)copySHA1Signature;

/// Uses the SHA-1 algorithm to compute a signature for the receiver.
- (NSData *)sha1Signature;

/// Uses the SHA-256 algorithm to compute a signature for the receiver.
- (NSData *)sha256Signature;

/// Computes an MD5 digest of the receiver and returns it. (Derived from the RSA Data Security, Inc. MD5 Message-Digest Algorithm.)
- (NSData *)md5Signature OB_DEPRECATED_ATTRIBUTE;

- (nullable NSData *)signatureWithAlgorithm:(NSString *)algName;

@end

#if defined(DEBUG)

@interface OFSignatureTimingOperation : NSOperation

- (id)init NS_UNAVAILABLE;
- (id)initWithDataSize:(size_t)dataSize algorithm:(NSString *)algorithmName NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) size_t dataSize;
@property (nonatomic, readonly) NSString *algorithmName;

@property (nonatomic, readonly) NSUInteger iterations;
@property (nonatomic, readonly) NSTimeInterval averageTime;
@property (nonatomic, readonly) double standardDeviation;

@end

#endif

NS_ASSUME_NONNULL_END
