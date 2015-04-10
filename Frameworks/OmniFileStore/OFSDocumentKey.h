// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>

@class OFSSegmentEncryptWorker;

@interface OFSDocumentKey : NSObject
{
    NSMutableDictionary *derivations;
    OFSSegmentEncryptWorker *reusableEncryptionWorker;
 
    BOOL valid;
    
    uint8_t _key[16 /* kCCKeySizeAES128 */];
}

- initWithData:(NSData *)finfo error:(NSError **)outError;

@property (readonly,nonatomic) BOOL hasPassword;
@property (readonly,nonatomic) BOOL hasKeychainItem;
@property (readonly,nonatomic) BOOL valid;

- (BOOL)deriveWithOptions:(unsigned)opts password:(NSString *)password error:(NSError **)outError;

- (NSData *)data;

- (void)reset; // Sets the document key to a new, randomly generated value. This is only a useful operation when you're creating a new document--- any existing items will become inaccessible.

- (BOOL)setPassword:(NSString *)password error:(NSError **)outError;
- (BOOL)storeInKeychainWithAttributes:(NSDictionary *)attrs error:(NSError **)outError;

- (OFSSegmentEncryptWorker *)encryptionWorker;
- (NSData *)wrapFileKey:(const uint8_t *)fileKeyInfo length:(size_t)len error:(NSError **)outError;
- (NSData *)unwrapFileKey:(const uint8_t *)fileKeyInfo length:(size_t)len error:(NSError **)outError;

@end


