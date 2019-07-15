// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <Foundation/NSData.h>

@class NSIndexSet;
@class OFSSegmentEncryptWorker;

/* The format of the wrapped data is a sequence of key slots. Each slot contains:
 - key type (1 byte)
 - key length in quads (1 byte)
 - key index (2 bytes)
 - key data (keylength*4 bytes)
 
 Any unused trailing space is filled with 0s; key type 0 is reserved to avoid ambiguity.
 
 All slots come in pairs, an active slot (odd) and a retired version of the same key type (the next even number).
 "Retired" keys act the same as active keys, except that they're only used for decryption, not encryption; and XMLSyncManager (or other higher level code) will remove them when unused, according to OFSEncryptingFileManager's -unusedKeySlotsOfSet:amongFiles: method.
 
 Note that these numbers are part of the file format: don't change them! Also, don't reuse old numbers. (Unless you assign a new file magic number.)
 */
enum OFSDocumentKeySlotType : uint8_t {
    SlotTypeNone                 = 0,    // Trailing padding
    
    /* Note that AESWRAP keys are no longer generated (the direct CTR+HMAC method is better). We have them around for compatibility right now, but next time we rev the file magic number we can drop them. */
    SlotTypeActiveAESWRAP        = 1,    // Currently-active AES key
    SlotTypeRetiredAESWRAP       = 2,    // Old AES key used after rollover

    SlotTypeActiveAES_CTR_HMAC   = 3,    // Currently-active CTR+HMAC key
    SlotTypeRetiredAES_CTR_HMAC  = 4,    // Retired CTR+HMAC key
    
    SlotTypePlaintextMask        = 5,    // Indicates filename patterns which should not be encrypted
    SlotTypeRetiredPlaintextMask = 6,    // Indicates filename patterns which may be read unencrypted, but must be written encrypted
};

#define OFSDocKeyFlagAllowUnencryptedRead    0x0001
#define OFSDocKeyFlagAlwaysUnencryptedRead   0x0002
#define OFSDocKeyFlagAlwaysUnencryptedWrite  0x0004

enum OFSEncryptingFileManagerDisposition {
    OFSEncryptingFileManagerDispositionPassthrough = 1,
    OFSEncryptingFileManagerDispositionTemporarilyReadPlaintext = 2,
};

NS_ASSUME_NONNULL_BEGIN

/* An OFSDocumentKey represents a set of subkeys protected by a user-relevant mechanism like a passphrase. */
@interface OFSKeySlots : NSObject <NSCopying,NSMutableCopying>

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithData:(NSData *)unwrappedKeyTable error:(NSError **)outError NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithData:(NSData *)wrappedKeyTable wrappedWithKey:(const uint8_t *)keyBytes length:(size_t)keyLength error:(NSError **)outError;

@property (readonly,nonatomic) NSIndexSet *retiredKeySlots, *keySlots;
- (enum OFSDocumentKeySlotType)typeOfKeySlot:(NSUInteger)slot; // Returns SlotTypeNone if not found / invalid

/* Returns some flags for a filename, based on whether it matches any rules added by -setDisposition:forSuffix:. */
- (unsigned)flagsForFilename:(NSString *)filename fromSlot:(int * __nullable)outSlot;

- (NSString * __nullable)suffixForSlot:(NSUInteger)slotnum;  // Only used by the unit tests
- (NSDictionary *)descriptionDictionary;   // For the UI. See keys below.

/* Return an encryption worker for the current active key slot. */
- (nullable OFSSegmentEncryptWorker *)encryptionWorker:(NSError **)outError;

// These methods are called by OFSSegmentEncryptWorker
- (NSData * __nullable)wrapFileKey:(const uint8_t *)fileKeyInfo length:(size_t)len error:(NSError **)outError;
- (ssize_t)unwrapFileKey:(NSData *)wrappedFileKeyInfo into:(uint8_t *)buffer length:(size_t)unwrappedKeyBufferLength error:(NSError **)outError;

@end

@interface OFSMutableKeySlots : OFSKeySlots

- (instancetype)init;

@property (readonly,nonatomic) NSInteger changeCount;  // For detecting (semantically significant) changes to -data. Starts at 0 and increases. Not (currently) KVOable.

/* Key rollover: this updates the receiver to garbage-collect any slots not mentioned in keepThese, and if retireCurrent=YES, mark any active keys as inactive (and generate new active keys as needed). If keepThese is nil, no keys are discarded (if you want to discard everything, pass a non-nil index set containing no indices). */
- (void)discardKeysExceptSlots:(NSIndexSet * __nullable)keepThese retireCurrent:(BOOL)retire generate:(enum OFSDocumentKeySlotType)tp;

- (void)setDisposition:(enum OFSEncryptingFileManagerDisposition)disposition forSuffix:(NSString *)ext;

- (NSData *)data;
- (NSData *)wrapWithKey:(const uint8_t *)keyBytes length:(size_t)keyLength;

@end

// Keys in the dictionary returned by -descriptionDictionary
#define OFSDocKeyDescription_AccessMethod  @"method"   // User-displayable name of unlock method, e.g. "Password (PBKDF2; aes128-wrap)"
#define OFSDocKeyDescription_PlaintextSuffixes @"plaintext"
#define OFSDocKeyDescription_TemporaryPlaintextSuffixes @"temporary plaintext"

#define OFSDocKeyDescription_KeyList       @"keys"
#define OFSDocKeyDescription_Key_TypeName  @"type"
#define OFSDocKeyDescription_Key_Active    @"active"
#define OFSDocKeyDescription_Key_Identifier @"slot"

// Error userInfo keys
extern NSString * const OFSKeySlotUserInfoKey;

NS_ASSUME_NONNULL_END

