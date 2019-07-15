// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <Foundation/NSObject.h>

#import <OmniFoundation/OFByteProviderProtocol.h>
#import <stdint.h>

@class OFSDocumentKey, OFSSegmentEncryptWorker;
@class NSData, NSError;

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

// Redeclared from OFByteAcceptor to make it non-@optional
- (void)flushByteAcceptor;

@end

