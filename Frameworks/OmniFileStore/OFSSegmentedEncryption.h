// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$


#import <OmniFoundation/OFByteProviderProtocol.h>
#import <Foundation/NSObject.h>
#import <CommonCrypto/CommonHMAC.h>
#include <stdint.h>

@class OFSDocumentKey;
@class NSData, NSError;

@interface OFSSegmentEncryptWorker : NSObject

- (NSData *)wrappedKeyWithDocumentKey:(OFSDocumentKey *)dk error:(NSError **)outError;
- (BOOL)encryptBuffer:(const uint8_t *)plaintext length:(size_t)len index:(uint32_t)order into:(uint8_t *)ciphertext header:(uint8_t *)hdr error:(NSError **)outError;
//- (BOOL)decryptBuffer:(const uint8_t *)ciphertext range:(NSRange)r index:(uint32_t)order into:(uint8_t *)plaintext header:(const uint8_t *)hdr error:(NSError **)outError;  // Not currently used
- (void)fileMACContext:(CCHmacContext *)ctxt;


// Temporary non-incremental encrypt and decrypt methods
+ (NSData *)encryptData:(NSData *)plaintext withKey:(OFSDocumentKey *)kek error:(NSError * __autoreleasing *)outError;
+ (NSData *)decryptData:(NSData *)ciphertext withKey:(OFSDocumentKey *)kek error:(NSError * __autoreleasing *)outError;

@end

@interface OFSSegmentDecryptingByteProvider : NSObject <OFByteProvider>

- (instancetype)initWithByteProvider:(id <NSObject,OFByteProvider>)underlying
                               range:(NSRange)segmentsAndFileMAC
                               error:(NSError **)outError;
- (BOOL)unwrapKey:(NSRange)wrappedBlob using:(OFSDocumentKey *)unwrapper error:(NSError **)outError;
- (BOOL)verifyFileMAC;

@end

@interface OFSSegmentEncryptingByteAcceptor : NSObject <OFByteAcceptor>

- (instancetype)initWithByteAcceptor:(id <NSObject,OFByteProvider,OFByteAcceptor>)underlying
                             cryptor:(OFSSegmentEncryptWorker *)cr
                              offset:(size_t)segmentsBegin;

@end

