// Copyright 2014-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSSegmentedEncryptionWorker.h>

#import <CommonCrypto/CommonCrypto.h>
#import <CoreFoundation/CoreFoundation.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSRange-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFByteProviderProtocol.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFileStore/OFSKeySlots.h>
#import <OmniFileStore/OFSEncryptionConstants.h>
#import <OmniBase/OmniBase.h>
#import "OFSEncryption-Internal.h"
#import <OmniFileStore/Errors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <dispatch/dispatch.h>
#import <stdatomic.h>
#import <libkern/OSAtomic.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

static NSRange checkHeaderMagic(NSData * __nonnull ciphertext, size_t ciphertextLength, NSError **outError);
static NSError *headerError(const char *detail) __attribute__((cold));
static NSError *badMagic(const char *detail) __attribute__((cold));
static NSError *unsupportedError_(int lineno, NSString *detail) __attribute__((cold,unused));
#define unsupportedError(e, t) do{ if(e) { *(e) = unsupportedError_(__LINE__, t); } }while(0)

@implementation OFSSegmentDecryptWorker
{
@protected
    CCCryptorRef _cachedCryptor;
    NSData      *_wrappedKey;
    int          _keySlot;
    uint8_t      _keydata[ kCCKeySizeAES128 + SEGMENTED_MAC_KEY_LEN ];
#define EW_KEYDATA_KEY_OFFSET 0
#define EW_KEYDATA_MAC_OFFSET ( EW_KEYDATA_KEY_OFFSET + kCCKeySizeAES128 )
}

+ (size_t)maximumSlotOffset;
{
    /* This returns the maximum file prefix length we need in order to discover the key slot of a file. It's used when "tasting" for expired keys. */
    return MAX(FMT_V0_6_MAGIC_LEN, FMT_V1_0_MAGIC_LEN) /* Magic number */ + 2 /* Key info length */ + 16 /* Only need 2 bytes for slot number; being generous */;
}

- (instancetype)init;
{
    if (!(self = [super init]))
        return nil;
    
    dispatch_once_f(&testRADARsOnce, NULL, testRADAR18222014);
    
    return self;
}

@synthesize wrappedKey;
@synthesize keySlot;

- (void)fileMACContext:(CCHmacContext *)ctxt;
{
    CCHmacInit(ctxt, kCCHmacAlgSHA256, _keydata + EW_KEYDATA_MAC_OFFSET, SEGMENTED_MAC_KEY_LEN);
    CCHmacUpdate(ctxt, SEGMENTED_FILE_MAC_VERSION_BYTE, 1);
}

- (BOOL)verifySegment:(NSUInteger)segmentIndex data:(NSData *)ciphertext;
{
    if (segmentIndex > UINT32_MAX)
        return NO;
    const uint8_t *segmentBegins = [ciphertext bytes];
    size_t segmentLength = [ciphertext length];
    if (segmentLength < SEGMENT_HEADER_LEN)
        return NO;
    return verifySegment(_keydata + EW_KEYDATA_MAC_OFFSET, segmentIndex, segmentBegins, segmentBegins + SEGMENT_HEADER_LEN, segmentLength - SEGMENT_HEADER_LEN);
}

/* This decrypts r.length bytes from `ciphertext` to `plaintext`. The range is the range within the encrypted segment, which determines the CTR values used; regardless of r.location the data is read from the beginning of `ciphertext` and written to the beginning of `plaintext`. */
- (BOOL)decryptBuffer:(const uint8_t *)ciphertext range:(NSRange)r index:(uint32_t)order into:(uint8_t *)plaintext header:(const uint8_t *)hdr error:(NSError **)outError;
{
    CCCryptorRef cryptor;
    
    if (r.length == 0) {
        return YES;
    }
    
    if (r.location > UINT32_MAX) {
        OBRejectInvalidCall(self, _cmd, @"Excessively long block");
    }
    
    /* Fetch the already-set-up cryptor instance, if we have one and can use it */
    if (canResetCTRIV) {
        @synchronized(self) {
            cryptor = _cachedCryptor;
            _cachedCryptor = nil;
        }
    } else {
        cryptor = NULL;
        _cachedCryptor = NULL;
    }
    
    uint32_t initialBlockCounter = ((uint32_t)r.location) / kCCBlockSizeAES128;
    
    /* Set up our encryptor state */
    {
        uint8_t segmentIV[ kCCBlockSizeAES128 ];

        /* Construct the initial CTR state for this segment: the stored IV, and four bytes of zeroes for the block counter */
        memcpy(segmentIV, hdr, SEGMENTED_IV_LEN);
        OSWriteBigInt32(segmentIV, SEGMENTED_IV_LEN, initialBlockCounter);
        _Static_assert(SEGMENTED_IV_LEN + sizeof(initialBlockCounter) == sizeof(segmentIV), "");
        
        if (!(cryptor = createOrResetCryptor(cryptor, segmentIV, _keydata + EW_KEYDATA_KEY_OFFSET, kCCKeySizeAES128, outError)))
            return NO;
    }
    
    /* Actually process the data */
    
    /* Handle the situation where we're not starting on a block boundary */
    if (initialBlockCounter*kCCBlockSizeAES128 != r.location) {
        unsigned discard = (uint32_t)r.location - initialBlockCounter*kCCBlockSizeAES128;
        size_t copylen = MIN(r.length, kCCBlockSizeAES128 - discard);
        uint8_t partialBlockIn[ kCCBlockSizeAES128 ];
        uint8_t partialBlockOut[ kCCBlockSizeAES128 ];
        memset(partialBlockIn, 0, kCCBlockSizeAES128);
        memcpy(partialBlockIn + discard, ciphertext, copylen);
        cryptOrCrash(cryptor, partialBlockIn, kCCBlockSizeAES128, partialBlockOut, __LINE__);
        memcpy(plaintext, partialBlockOut + discard, copylen);
        r.location += copylen;
        r.length -= copylen;
        ciphertext += copylen;
        plaintext += copylen;
    }
    
    /* Process any complete blocks (often this will be the only branch taken) */
    if (r.length >= kCCBlockSizeAES128) {
        size_t fullBlocks = (r.length / kCCBlockSizeAES128) * kCCBlockSizeAES128;
        cryptOrCrash(cryptor, ciphertext, fullBlocks, plaintext, __LINE__);
        r.location += fullBlocks;
        r.length -= fullBlocks;
        ciphertext += fullBlocks;
        plaintext += fullBlocks;
    }
    
    /* Process any fractional block at the end of the buffers */
    if (r.length) {
        assert(r.length < kCCBlockSizeAES128);
        uint8_t partialBlockIn[ kCCBlockSizeAES128 ];
        uint8_t partialBlockOut[ kCCBlockSizeAES128 ];
        memset(partialBlockIn, 0, kCCBlockSizeAES128);
        memcpy(partialBlockIn, ciphertext, r.length);
        cryptOrCrash(cryptor, partialBlockIn, kCCBlockSizeAES128, partialBlockOut, __LINE__);
        memcpy(plaintext, partialBlockOut, r.length);
    }
    
    /* Stash the cryptor for later re-use (key-schedule setup is relatively expensive) */
    if (canResetCTRIV) {
        @synchronized(self) {
            if (!_cachedCryptor) {
                _cachedCryptor = cryptor;
                cryptor = NULL;
            }
        }
    }
    
    if (cryptor) {
        CCCryptorRelease(cryptor);
    }
    
    return YES;
}

@end

@implementation OFSSegmentEncryptWorker
{
    atomic_int_fast32_t      _nonceCounter;
    uint8_t                 _iv[ SEGMENTED_IV_LEN-4 ];
}

- (instancetype)initWithBytes:(const uint8_t *)bytes length:(NSUInteger)length;
{
    if (!(self = [super init]))
        return nil;
    
    _Static_assert(sizeof(_keydata) == SEGMENTED_INNER_LENGTH, "");
    if (length != SEGMENTED_INNER_LENGTH) {
        OBRejectInvalidCall(self, _cmd, @"Invalid length");
    }
    
    memcpy(_keydata, bytes, sizeof(_keydata));
    
    /* The IV isn't part of the wrapped key--- each segment's IV is stored with that segment. */
    if (!randomBytes(_iv, sizeof(_iv), NULL)) {
        return nil;
    }
    
    return self;
}

- (BOOL)encryptBuffer:(const uint8_t *)plaintext length:(size_t)len index:(uint32_t)order into:(uint8_t *)ciphertext header:(uint8_t *)hdr error:(NSError **)outError;
{
    CCCryptorRef cryptor;
    uint8_t segmentIV[ kCCBlockSizeAES128 ];
    atomic_int_fast32_t nonceCounter;
    dispatch_semaphore_t hashSem;
    CCHmacContext ctxt;
    const size_t strideLength = 4096;
    
    /* Fetch the already-set-up cryptor instance, if we have one */
    @synchronized(self) {
        cryptor = _cachedCryptor;
        _cachedCryptor = nil;
        nonceCounter = atomic_fetch_add(&_nonceCounter, 1);
    }
    
    /* Construct the initial CTR state for this segment: our random IV, our counter, and four bytes of zeroes for the block counter */
    memcpy(segmentIV, _iv, SEGMENTED_IV_LEN - 4);
    OSWriteBigInt32(segmentIV, SEGMENTED_IV_LEN - 4, nonceCounter);
    memset(segmentIV + SEGMENTED_IV_LEN, 0, kCCBlockSizeAES128 - SEGMENTED_IV_LEN);
    _Static_assert(sizeof(_iv) + 4 + 4 == sizeof(segmentIV), "");
    
    if (!(cryptor = createOrResetCryptor(cryptor, segmentIV, _keydata + EW_KEYDATA_KEY_OFFSET, kCCKeySizeAES128, outError)))
        return NO;
    
    /* In a concurrent thread, encrypt the data buffer, using the hashSem semaphore to indicate when each stride's worth of ciphertext has been written to the output buffer */
    hashSem = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UNSPECIFIED, 0), ^{
       
        size_t stridePosition = 0;
        while (stridePosition < len) {
            size_t thisStrideLength = MIN(strideLength, len - stridePosition);
            cryptOrCrash(cryptor, plaintext + stridePosition, thisStrideLength, ciphertext + stridePosition, __LINE__);
            stridePosition += thisStrideLength;
            dispatch_semaphore_signal(hashSem);
        }
        
    });
    
    /* In this thread, compute the segment's HMAC in parallel with the encryption happening in the other thread */
    CCHmacInit(&ctxt, kCCHmacAlgSHA256, _keydata + EW_KEYDATA_MAC_OFFSET, SEGMENTED_MAC_KEY_LEN);
    
    /* Construct and hash in the header, which (most critically) contains the segment number */
    hmacSegmentHeader(&ctxt, segmentIV, order);
    
    /* Ready to start hashing in the ciphertext */
    size_t stridePosition = 0;
    while (stridePosition < len) {
        dispatch_semaphore_wait(hashSem, DISPATCH_TIME_FOREVER);
        size_t thisStrideLength = MIN(strideLength, len - stridePosition);
        CCHmacUpdate(&ctxt, ciphertext + stridePosition, thisStrideLength);
        stridePosition += thisStrideLength;
    }
    
    /* At this point, we know that the other thread is done using the cryptor, because we've waited on its last semaphore signal. */
    
    /* Stash the cryptor for later re-use (key-schedule setup is relatively expensive) */
    if (canResetCTRIV) {
        @synchronized(self) {
            if (!_cachedCryptor) {
                _cachedCryptor = cryptor;
                cryptor = NULL;
            }
        }
    }
    
    /* Finish computing the HMAC */
    {
        uint8_t hmacBuffer[ CC_SHA256_DIGEST_LENGTH ];
        CCHmacFinal(&ctxt, hmacBuffer);
        
        /* And construct the segment header */
        memcpy(hdr, segmentIV, SEGMENTED_IV_LEN);
        memcpy(hdr + SEGMENTED_IV_LEN, hmacBuffer, SEGMENTED_MAC_LEN);
    }
    
    if (cryptor) {
        CCCryptorRelease(cryptor);
    }
    
    return YES;
}


#pragma mark Encryption and decryption methods

// These are here temporarily until we implement streaming or random-access encode/decode. There are two situations where we want to be able to encrypt or decrypt without pulling the entire thing into core:
//   1. Reading and writing .zip files on the local disk, to support encrypted local databases. For this, we want the OFByteAcceptor/OFByteProvider protocol, which allows OUUnzip to perform random reads and writes. This
//   2. Transferring a file to/from an encrypted remote database to a file on disk. For this, we want something more like a stream filter. Unfortunately, NSStream and CFStream are unusably buggy, and they're the only way to interact with NSURLSession. We'll need to figure out how to do that, but not today. (Perhaps we'll end up having to just buffer the encrypted data on disk.)


- (nullable NSData *)encryptData:(NSData *)plaintext error:(NSError * __autoreleasing *)outError;
{
    if (!plaintext)
        return nil;
    
    size_t segmentCount = ( [plaintext length] + SEGMENTED_PAGE_SIZE - 1 ) / SEGMENTED_PAGE_SIZE;
    
    if (segmentCount >= UINT_MAX) {
        return nil;
    }
    
    NSData *keyInfo = [self wrappedKey];
    if (!keyInfo) {
        [NSException raise:NSInternalInconsistencyException format:@"%@.wrappedKey is nil", self];
        return nil;
    }
    
    // Ugly.
    const void **segments = calloc(MAX((size_t)1, segmentCount), sizeof(void *));
    
    dispatch_apply(segmentCount, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t segmentIndex){
        size_t plaintextLength = [plaintext length];
        size_t segmentBegins = segmentIndex * SEGMENTED_PAGE_SIZE;
        size_t segmentLength = MIN((size_t)SEGMENTED_PAGE_SIZE, plaintextLength - segmentBegins);
        void *buffer = malloc(SEGMENT_HEADER_LEN + segmentLength);
        NSError * __autoreleasing localError = nil;
        
        BOOL ok = [self encryptBuffer:[plaintext bytes] + segmentBegins length:segmentLength
                                index:(uint32_t)segmentIndex
                                 into:buffer + SEGMENT_HEADER_LEN header:buffer error:&localError];
        
        if (ok) {
            segments[segmentIndex] = CFBridgingRetain(dispatch_data_create(buffer, SEGMENT_HEADER_LEN + segmentLength, NULL, DISPATCH_DATA_DESTRUCTOR_FREE));
        } else {
            free(buffer);
            NSLog(@"Segment %zu failed: %@", segmentIndex, localError);
        }
    });
    
    /* Header is: magic || infolength || info || padding */
    size_t keyInfoLength = [keyInfo length];
    size_t headerLength = FMT_V1_0_MAGIC_LEN + 2 + keyInfoLength;
    headerLength = 16 * ((headerLength + 15)/16);
    void *header = calloc(1, headerLength);
    memcpy(header, magic_ver1_0, FMT_V1_0_MAGIC_LEN);
    OSWriteBigInt16(header, FMT_V1_0_MAGIC_LEN, (uint16_t)keyInfoLength);
    [keyInfo getBytes:header + (FMT_V1_0_MAGIC_LEN + 2) length:keyInfoLength];
    dispatch_data_t result_data = dispatch_data_create(header, headerLength, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
    
    /* Concat the segments, and compute the file MAC */
    
    CCHmacContext fileMAC;
    [self fileMACContext:&fileMAC];
    
    BOOL failed = NO;
    for(size_t segmentIndex = 0; segmentIndex < segmentCount; segmentIndex ++) {
        dispatch_data_t seg = CFBridgingRelease(segments[segmentIndex]);
        segments[segmentIndex] = NULL;
        if (!seg) {
            failed = YES;
            continue;
        }
        CCHmacUpdate(&fileMAC, [(NSData *)seg bytes] + SEGMENTED_IV_LEN, SEGMENTED_MAC_LEN);
        result_data = dispatch_data_create_concat(result_data, seg);
    }
    
    free(segments);
    
    if (failed) {
        /* This is completely unexpected - there's almost nothing that can generate an error in that loop. */
        if (outError) {
            *outError = nil;
            _OBError(outError, NSOSStatusErrorDomain, errSecInternalComponent, __FILE__, __LINE__, nil);
        }
        return nil;
    }
    
    /* Trailer is just the file MAC */
    
    char finalMAC[SEGMENTED_FILE_MAC_LEN];
    _Static_assert(sizeof(finalMAC) == CC_SHA256_DIGEST_LENGTH, "");
    CCHmacFinal(&fileMAC, finalMAC);
    
    dispatch_data_t final_block = dispatch_data_create(finalMAC, SEGMENTED_FILE_MAC_LEN, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    
    dispatch_data_t final_result = dispatch_data_create_concat(result_data, final_block);
    
    return (NSData *)final_result;
}

@end

@implementation OFSSegmentDecryptWorker (OneShot)

static uint16_t checkOneHeaderMagic(size_t magicLength, const char *magicBytes, NSData * __nonnull ciphertext, size_t ciphertextLength)
{
    char buffer[magicLength + 2];
    
    /* Look at the fixed-length portions of the header: the magic number, and the info blob length field which immediately follows it */
    if (ciphertextLength < (magicLength + 2)) {
        return 0;
    }
    
    [ciphertext getBytes:buffer length:magicLength + 2];
    
    /* Check the file magic */
    if (memcmp(buffer, magicBytes, magicLength) != 0) {
        return 0;
    }
    
    /* Find the length of the info blob */
    uint16_t infoBlobLength = OSReadBigInt16(buffer, magicLength);
    
    /* A zero-length info blob is invalid (which is why we also use 0 as our error return value here). */
    if (infoBlobLength == 0) {
        return 0;
    }
    
    return infoBlobLength;
}

static BOOL checkForeignHeaderMagic(NSData * __nonnull ciphertext, size_t ciphertextLength)
{
    if (ciphertextLength >= 16u && [ciphertext indexOfBytes:"crypt" length:5 range:(NSRange){0, MIN(ciphertextLength, 32u)}])
        return YES;
    
    return NO;
}

static NSRange checkHeaderMagic(NSData * __nonnull ciphertext, size_t ciphertextLength, NSError **outError)
{
    uint16_t infoBlobLength;
    
    /* STRAWMAN-6 and version 1.0 are identical. Accept both for now. In the future we might also want to check for version 1.1 or something and return an indication of which sub-version we found (if nothing else, we'll need to be sure to adjust SEGMENTED_FILE_MAC_VERSION_BYTE for any format changes) */
    
    infoBlobLength = checkOneHeaderMagic(FMT_V1_0_MAGIC_LEN, magic_ver1_0, ciphertext, ciphertextLength);
    if (infoBlobLength) {
        return (NSRange){ FMT_V1_0_MAGIC_LEN /* magic */ + 2 /* info blob length field */, infoBlobLength };
    }
    
    infoBlobLength = checkOneHeaderMagic(FMT_V0_6_MAGIC_LEN, magic_ver0_6, ciphertext, ciphertextLength);
    if (infoBlobLength) {
        return (NSRange){ FMT_V0_6_MAGIC_LEN /* magic */ + 2 /* info blob length field */, infoBlobLength };
    }
    
    if (outError) {
        if (checkForeignHeaderMagic(ciphertext, ciphertextLength)) {
            *outError = badMagic("Invalid encryption header.");
        } else {
            *outError = headerError("Invalid encryption header.");
        }
    }
    
    return (NSRange){ 0, 0 };
}

/* Check the magic number of this encrypted file. Return YES (and optionally return the keyinfo blob and the offset of the start of the ciphertext) if it's a file we can handle, otherwise return NO and set *outError.
 
 If mayBeTruncated is YES, then we're given a "ciphertext" data that is just a prefix of a file. We return YES if we can positively identify the magic number and the offsets of the other stuff in the file, but we don't fail if some of those offsets are past the end of the data we have. This is used for checking what keyslot a file uses without reading the entire file.
*/
+ (BOOL)parseHeader:(NSData *)ciphertext truncated:(BOOL)mayBeTruncated wrappedInfo:(NSRange *)outBlobLocation dataOffset:(size_t *)outHeaderLength error:(NSError * __autoreleasing *)outError;
{
    if (!ciphertext) {
        if (outError) *outError = headerError("Missing ciphertext.");
        return NO;
    }
    size_t ciphertextLength = [ciphertext length];
    
    NSRange wrappedKeyBlobRange = checkHeaderMagic(ciphertext, ciphertextLength, outError);
    if (!wrappedKeyBlobRange.location)
        return NO;
    
    /* Read the variable-length portion of the header, which consists of the wrapped key blob, followed by zero-padding to a 16-byte boundary */
    
    size_t paddedLength = ((NSMaxRange(wrappedKeyBlobRange) + 15) / 16) * 16;
    
    if (!mayBeTruncated && ciphertextLength < (paddedLength + SEGMENTED_FILE_MAC_LEN)) {
        if (outError) *outError = headerError("File too short.");
        return NO;
    }
    
    /* Check the padding - we haven't touched our key yet, so no information leaks here */
    size_t paddingLength = paddedLength - NSMaxRange(wrappedKeyBlobRange);
    if (paddingLength && (!mayBeTruncated || ciphertextLength >= paddedLength)) {
        char buf[16];
        [ciphertext getBytes:buf range:(NSRange){NSMaxRange(wrappedKeyBlobRange), paddingLength}];
        for(size_t i = 0; i < paddingLength; i++) {
            if (buf[i] != 0) {
                if (outError) *outError = headerError("Invalid encryption header.");
                return NO;
            }
        }
    }
    
    if (outHeaderLength)
        *outHeaderLength = paddedLength;
    
    if (outBlobLocation) {
        *outBlobLocation = wrappedKeyBlobRange;
    }
    
    return YES;
}

+ (nullable OFSSegmentDecryptWorker *)decryptorForWrappedKey:(NSData *)keyblob documentKey:(OFSKeySlots *)kek error:(NSError * __autoreleasing *)outError;
{
    OFSSegmentDecryptWorker *result = [[OFSSegmentDecryptWorker alloc] init];
    
    /* Finally, ask our document key manager to unwrap the file key */
    _Static_assert(sizeof(result->_keydata) == SEGMENTED_INNER_LENGTH_PADDED, "");
    ssize_t resultSize = [kek unwrapFileKey:keyblob into:result->_keydata length:SEGMENTED_INNER_LENGTH_PADDED error:outError];
    if (resultSize < 0)
        return nil;
    if (resultSize != SEGMENTED_INNER_LENGTH_PADDED) {
        if (outError) *outError = headerError("Invalid encryption header.");
        return nil;
    }
    
    return result;
}

- (nullable NSData *)decryptData:(NSData *)ciphertext dataOffset:(size_t)segmentsBegin error:(NSError * __autoreleasing *)outError;
{
    // Some amusing facts:
    //   - Calling -subdataWithRange: on a mutable data will (often/always?) call -copy on the receiver in order to get an immutable subrange, instead of copying out just the relevant bytes.
    //   - That copy will apparently be autoreleased, even if you're in ARC, because of course your ARC code is several stack frames away from the copy.
    //   - dispatch_apply() is not autorelease-pool aware.
    // So, if our passed-in data is mutable, our decryption loop below will end up creating a large number of inaccessible autoreleased immutable copies of it, which easily exhausts the address space of a 32-bit machine. Instead, we do one copy up-front, here.
    // (If the passed-in data is already immutable, this effectively a no-op of course.)
    ciphertext = [ciphertext copy];
    
    size_t totalCiphertextLength = [ciphertext length];
    
    if (totalCiphertextLength < (segmentsBegin + SEGMENTED_FILE_MAC_LEN)) {
        // Impossible file length
        // We may have no segments, but even in that case, we'll have the header (before segmentsBegin) and the end-of-ciphertext MAC
        if (outError) *outError = headerError("File too short.");
        return nil;
    }
    
    size_t segmentsLength = totalCiphertextLength - segmentsBegin - SEGMENTED_FILE_MAC_LEN;
    size_t segmentCount = ( segmentsLength + SEGMENT_ENCRYPTED_PAGE_SIZE - 1 ) / SEGMENT_ENCRYPTED_PAGE_SIZE;
    size_t plaintextLength = segmentsLength - (SEGMENT_HEADER_LEN * segmentCount);
    
    size_t lastSegmentLength;
    if (segmentCount > 0) {
        lastSegmentLength = segmentsLength - (SEGMENT_ENCRYPTED_PAGE_SIZE * (segmentCount-1));
        
        if (lastSegmentLength < SEGMENT_HEADER_LEN) {
            // Impossible file length
            // (some ciphertext lengths do not correspond to any plaintext length)
            if (outError) *outError = headerError("File too short.");
            return nil;
        }
    } else {
        // Initialize just in case, but we don't expect this value to be used – its only reference below should be in dispatch_apply(0, ^{…}), which won't invoke its block.
        lastSegmentLength = 0;
    }
    
    NSMutableData *plaintext = [NSMutableData dataWithLength:plaintextLength];

    char *plaintextBuffer = [plaintext mutableBytes];
    __block atomic_uint_fast32_t errorBits = 0;
    
    if (plaintextBuffer == NULL) {
        NSLog(@"Failed to get mutableBytes from an %@ of length %zu! A crash is likely to occur soon.", NSStringFromClass([plaintext class]), plaintextLength);
    }
    
    /* Check all the segment MACs, and decrypt */
    dispatch_apply(segmentCount, dispatch_get_global_queue(QOS_CLASS_UNSPECIFIED, 0), ^(size_t segmentIndex){
        if (errorBits != 0) {
            // Early-out if a segment MAC fails.
        }
        
        size_t segmentLength = SEGMENT_ENCRYPTED_PAGE_SIZE;
        if (segmentIndex == segmentCount - 1)
            segmentLength = lastSegmentLength;
        NSData *subrange NS_VALID_UNTIL_END_OF_SCOPE = [ciphertext subdataWithRange:(NSRange){ segmentsBegin + (segmentIndex * SEGMENT_ENCRYPTED_PAGE_SIZE), segmentLength }];
        const uint8_t *segmentBegins = [subrange bytes];

        if (![self verifySegment:segmentIndex data:subrange]) {
            atomic_fetch_or(&errorBits, 0x01);
            return;
        }
        
        if (![self decryptBuffer:segmentBegins + SEGMENT_HEADER_LEN range:(NSRange){0, segmentLength - SEGMENT_HEADER_LEN} index:(uint32_t)segmentIndex
                            into:(uint8_t *)plaintextBuffer + (segmentIndex * SEGMENTED_PAGE_SIZE)
                          header:segmentBegins
                           error:NULL]) {
            atomic_fetch_or(&errorBits, 0x02);
            return;
        }
    });
    
    if (errorBits != 0) {
        if (outError) *outError = headerError("Encrypted file is corrupt.");
        return nil;
    }
    
    /* Check the file MAC */
    CCHmacContext fileMACContext;
    [self fileMACContext:&fileMACContext];
    for (size_t segmentIndex = 0; segmentIndex < segmentCount; segmentIndex ++) {
        char segmentMAC[SEGMENTED_MAC_LEN];
        [ciphertext getBytes:segmentMAC range:(NSRange){ segmentsBegin + (segmentIndex * SEGMENT_ENCRYPTED_PAGE_SIZE) + SEGMENTED_IV_LEN, SEGMENTED_MAC_LEN}];
        CCHmacUpdate(&fileMACContext, segmentMAC, SEGMENTED_MAC_LEN);
    }

    uint8_t foundFileMAC[SEGMENTED_FILE_MAC_LEN];
    [ciphertext getBytes:foundFileMAC range:(NSRange){ segmentsBegin + segmentsLength, SEGMENTED_FILE_MAC_LEN}];
    if (finishAndVerifyHMAC256(&fileMACContext, foundFileMAC, SEGMENTED_FILE_MAC_LEN) != 0) {
        if (outError) *outError = headerError("Encrypted file is corrupt.");
        return nil;
    }
    
    return plaintext;
}

@end

#pragma mark Utility functions

static NSError *headerError(const char *msg)
{
    /* This error path is for errors which don't depend on knowing the file key: unknown magic, gross format errors, etc. */
    
    /* The user should not normally see these messages: they'll be wrapped in some higher level error message. */
    NSDictionary *uinfo;
    if (msg) {
        uinfo = @{ NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:msg] };
    } else {
        uinfo = nil;
    }
    
    return [NSError errorWithDomain:OFSErrorDomain code:OFSEncryptionBadFormat userInfo:uinfo];
}

static NSError *badMagic(const char *msg)
{
    /* The user should not normally see these messages: they'll be wrapped in some higher level error message. */
    NSDictionary *uinfo = @{
                            NSLocalizedFailureReasonErrorKey: [NSString stringWithUTF8String:msg],
                            OFSEncryptionBadFormatNotEncryptedKey: @(YES)
                            };
    return [NSError errorWithDomain:OFSErrorDomain code:OFSEncryptionBadFormat userInfo:uinfo];
}

static NSError *unsupportedError_(int lineno, NSString *detail)
{
    NSDictionary *userInfo = @{
                               NSLocalizedDescriptionKey: @"Could not decrypt file",
                               NSLocalizedRecoverySuggestionErrorKey: detail,
                               };
    
    return [NSError errorWithDomain:OFSErrorDomain
                               code:OFSEncryptionBadFormat
                           userInfo:userInfo];
}

