// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$


#import <Foundation/NSObject.h>
#import <CommonCrypto/CommonHMAC.h>
#include <stdint.h>

@class OFSDocumentKey;
@class NSData, NSError;

NS_ASSUME_NONNULL_BEGIN

@interface OFSSegmentDecryptWorker : NSObject

+ (size_t)maximumSlotOffset;

// We don't actually do anything with the wrappedKey or keySlot value; it's just convenient to keep it associated it with us
@property (readwrite,copy,atomic,nullable) NSData *wrappedKey;
@property (readwrite,assign,atomic) int keySlot;

- (BOOL)verifySegment:(NSUInteger)segmentIndex data:(NSData *)ciphertext;
- (BOOL)decryptBuffer:(const uint8_t *)ciphertext range:(NSRange)r index:(uint32_t)order into:(uint8_t *)plaintext header:(const uint8_t *)hdr error:(NSError **)outError;
- (void)fileMACContext:(CCHmacContext *)ctxt;

@end

@interface OFSSegmentDecryptWorker (OneShot)

// Temporary non-incremental encrypt and decrypt methods
+ (int)slotForData:(NSData *)filePrefix error:(NSError **)outError;
+ (OFSSegmentDecryptWorker *)decryptorForData:(NSData *)ciphertext key:(OFSDocumentKey *)kek dataOffset:(size_t *)outHeaderLength error:(NSError * __autoreleasing *)outError;
- (NSData *)decryptData:(NSData *)ciphertext dataOffset:(size_t)headerLength error:(NSError * __autoreleasing *)outError;

@end

@interface OFSSegmentEncryptWorker : OFSSegmentDecryptWorker

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithBytes:(const uint8_t *)bytes length:(NSUInteger)length NS_DESIGNATED_INITIALIZER;

- (BOOL)encryptBuffer:(const uint8_t *)plaintext length:(size_t)len index:(uint32_t)order into:(uint8_t *)ciphertext header:(uint8_t *)hdr error:(NSError **)outError;
- (NSData *)encryptData:(NSData *)plaintext error:(NSError * __autoreleasing *)outError;

@end


NS_ASSUME_NONNULL_END
