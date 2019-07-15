// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <Foundation/NSData.h>
#import <OmniFileStore/OFSKeySlots.h>

@class NSIndexSet;

NS_ASSUME_NONNULL_BEGIN

@interface OFSDocumentKeyDerivationParameters : NSObject <NSCopying>

- initWithAlgorithm:(NSString *)algorithm rounds:(unsigned)rounds salt:(NSData *)salt pseudoRandomAlgorithm:(NSString *)pseudoRandomAlgorithm;

@property(nonatomic,readonly) NSString *algorithm;
@property(nonatomic,readonly) unsigned rounds;
@property(nonatomic,readonly) NSData *salt;
@property(nonatomic,readonly) NSString *pseudoRandomAlgorithm;

@end

/* An OFSDocumentKey represents a set of subkeys protected by a user-relevant mechanism like a passphrase. */
@interface OFSDocumentKey : NSObject <NSCopying,NSMutableCopying>

- (instancetype)init NS_UNAVAILABLE;
- (instancetype __nullable)initWithData:(NSData * __nullable)finfo error:(NSError **)outError NS_DESIGNATED_INITIALIZER;          // For reading a stored keyblob
- (NSData *)data;

@property (readonly,nonatomic) NSInteger changeCount;  // For detecting (semantically significant) changes to -data. Starts at 0 and increases. Not (currently) KVOable.

@property (readonly,nonatomic) BOOL valid;  // =YES if we have successfully derived our unwrapping key and have access to the key slots

/* Password-based encryption */
@property (readonly,nonatomic) BOOL hasPassword;
- (nullable OFSDocumentKeyDerivationParameters *)passwordDerivationParameters:(NSError **)outError;
- (BOOL)deriveWithPassword:(NSString *)password error:(NSError **)outError;
- (BOOL)deriveWithWrappingKey:(NSData *)wrappingKey error:(NSError **)outError;
+ (nullable NSData *)wrappingKeyFromPassword:(NSString *)password parameters:(OFSDocumentKeyDerivationParameters *)parameters error:(NSError **)outError;

- (BOOL)borrowUnwrappingFrom:(OFSDocumentKey *)otherKey;

@property (readonly,atomic) OFSKeySlots *keySlots;
/* Returns some flags for a filename, based on whether it matches any rules added by -setDisposition:forSuffix:. */
- (unsigned)flagsForFilename:(NSString *)filename;

/* Return an encryption worker for the current active key slot. */
- (nullable OFSSegmentEncryptWorker *)encryptionWorker:(NSError **)outError;

- (NSDictionary *)descriptionDictionary;   // For the UI. See keys below.

@end

@interface OFSMutableDocumentKey : OFSDocumentKey

- (instancetype)init;
- (instancetype __nullable)initWithAuthenticator:(OFSDocumentKey *)source error:(NSError **)outError;   // For creating a new keyblob sharing another one's password

- (BOOL)setPassword:(NSString *)password error:(NSError **)outError;

// Users of the document key can modify this key slot object. The owning document key's changeCount will reflect changes made to its key slot object.
@property (readonly,atomic) OFSMutableKeySlots *mutableKeySlots;

@end

// Keys in the dictionary returned by -descriptionDictionary
// See also the keys defined in OFSKeySlots.h; our -descriptionDictionary is merged with the one returned by OFSKeySlots.
#define OFSDocKeyDescription_AccessMethod  @"method"   // User-displayable name of unlock method, e.g. "Password (PBKDF2; aes128-wrap)"

NS_ASSUME_NONNULL_END

