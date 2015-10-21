// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSSegmentedEncryption.h>

#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CoreFoundation/CoreFoundation.h>
#import <OmniFoundation/NSRange-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFByteProviderProtocol.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFileStore/OFSDocumentKey.h>
#import <OmniFileStore/Errors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <dispatch/dispatch.h>
#import <libkern/OSAtomic.h>

#if (defined(MAC_OS_X_VERSION_10_10) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000)
#import <CommonCrypto/CommonRandom.h>
#endif

RCS_ID("$Id$");

OB_REQUIRE_ARC

#define FMT_V0_6_MAGIC_LEN 35
static const char magic_ver0_6[FMT_V0_6_MAGIC_LEN] = "OmniFileStore encryption\x00STRAWMAN-6";

#define SEGMENTED_IV_LEN 12           /* The length of the IV stored in front of each encrypted segment */
#define SEGMENTED_MAC_LEN 20          /* The length of the HMAC value stored with each encrypted segment */
#define SEGMENTED_MAC_KEY_LEN 16      /* The length of the HMAC key, stored in the file-key blob along with the AES key */
#define SEGMENTED_PAGE_SIZE 65536     /* Size of one encrypted segment */
#define SEGMENTED_INNER_LENGTH ( kCCKeySizeAES128 + SEGMENTED_MAC_KEY_LEN )  /* Size of the wrapped data for inner FMT_V0_6 blob */
#define SEGMENTED_INNER_LENGTH_PADDED (((SEGMENTED_INNER_LENGTH + 15) / 16) * 16)
#define SEGMENTED_FILE_MAC_VERSION_BYTE "\x01"
#define SEGMENTED_FILE_MAC_LEN 32     /* Length of the whole-file MAC */

#define SEGMENT_HEADER_LEN (SEGMENTED_IV_LEN + SEGMENTED_MAC_LEN)
#define SEGMENT_ENCRYPTED_PAGE_SIZE (SEGMENT_HEADER_LEN + SEGMENTED_PAGE_SIZE)

/* We could use the derived key to simply wrap the bulk encryption keys themselves instead of having an intermediate document key, but that would make it difficult for the user to change their password without re-writing every encrypted file in the wrapper. This way we can simply wrap the same document key with a new password-derived key. It also leaves open the possibility of using keys on smartcards, phone TPMs, or whatever, to decrypt the document key, possibly with asymmetric crypto for least-authority background operation, and all that fun stuff. */

/* Utility functions */
static NSError *wrapCCError(CCCryptorStatus cerr, NSString *op, NSString *extra, NSObject *val) __attribute__((cold)); /* CommonCrypto errors fit in the OSStatus error domain */
#define wrapSecError(e,o,k,v) wrapCCError(e,o,k,v) /* Security.framework errors are also OSStatus error codes */
static NSError *unsupportedError_(int lineno, NSString *detail) __attribute__((cold));
static BOOL randomBytes(uint8_t *buffer, size_t bufferLength, NSError **outError);
static CCCryptorRef createCryptor(const uint8_t segmentIV[kCCBlockSizeAES128], const uint8_t key[kCCKeySizeAES128], NSError **outError);
static BOOL resetCryptor(CCCryptorRef cryptor, const uint8_t segmentIV[kCCBlockSizeAES128], NSError **outError);
static void cryptOrCrash(CCCryptorRef cryptor, const void *dataIn, size_t dataLength, void *dataOut, int lineno);
static void hmacSegmentHeader(CCHmacContext *hashContext, const uint8_t *segmentIV, uint32_t order);
static uint8_t finishAndVerifyHMAC256(CCHmacContext *hashContext, const uint8_t *expectedValue, unsigned hashLength) __attribute__((noinline));
static BOOL verifySegment(const uint8_t *hmacKey, NSUInteger segmentNumber, const uint8_t *hdr, const uint8_t *ciphertext, size_t ciphertextLength);

static dispatch_once_t testRADARsOnce;
static BOOL canResetCTRIV = NO;
static void testRADAR18222014(void *dummy) __attribute__((cold));

#define unsupportedError(e, t) do{ if(e) { *(e) = unsupportedError_(__LINE__, t); } }while(0)

static inline CCCryptorRef createOrResetCryptor(CCCryptorRef cryptor, const uint8_t segmentIV[kCCBlockSizeAES128], const uint8_t key[kCCKeySizeAES128], NSError **outError)
{
    if (cryptor) {
        if (canResetCTRIV) {
            if (!resetCryptor(cryptor, segmentIV, outError)) {
                CCCryptorRelease(cryptor);
                return NULL;
            } else {
                return cryptor;
            }
        } else {
            CCCryptorRelease(cryptor);
        }
    }
    
    return createCryptor(segmentIV, key, outError);
}

/*

 A file consists of a header, followed by a sequence of independently-encrypted segments.
 
   See EncryptionFormat.md for more detailed description of the format.
 
   The header has this format:
 
   Magic bytes  (to identify an OFSEncryptingFileManager file)
   Key information length (2 bytes) - includes the diversification field and the wrapped blob
   Key diversification field (2 bytes)
   Wrapped key information: the following fields, wrapped using RFC3394 wrapping using the specified document key:
      AES key ( kCCKeySizeAES128 = 16 bytes)
      HMAC key ( SEGMENTED_MAC_KEY_LEN = 16 bytes )
   Zero padding to a 16-byte boundary
   The encrypted file segments
   The file HMAC (SEGMENTED_FILE_MAC_LEN = 32 bytes)
 
   Each segment contains:
 
   Segment IV  (12 bytes)  ( = block size minus 32 bits)
   Segment MAC (20 bytes)  ( a common size, but also IV+MAC length adds to a 16-byte boundary)
   Segment data (SEGMENTED_PAGE_SIZE = 64k bytes, except possibly for the last segment)
 
   The segment MAC is the truncated HMAC-SHA256 of ( IV || segment number || encrypted data ), where ( IV || segment number ) is 16 bytes.
   The data is AES-CTR encrypted with initial IV of ( IV || zeroes )
   (The IV is constructed from some random bytes and a per-AES-key counter to eliminate the possibility of nonce reuse, but that's an implementation detail)
 
   Document key management is handled by the OFSDocumentKey class, which wraps and unwraps the key information and maintains expired keys as needed for key rollover.
*/

@implementation OFSSegmentDecryptingByteProvider
{
    id <NSObject,OFByteProvider> _backingStore;
    NSCache *_pages;
    NSMutableIndexSet *_verifiedPages;
    
    uint8_t _keyMaterial[kCCKeySizeAES128 + SEGMENTED_MAC_KEY_LEN];
#define _bulkKey &(_keyMaterial[0])
#define _hmacKey &(_keyMaterial[kCCKeySizeAES128])
    
    size_t _offset;       /* The offset of the beginning of the encrypted data segments (after the file MAC) */
    size_t _segmentsLength;  /* The amount of backing store occupied by encrypted data segments */
    size_t _length;       /* The length we present to our callers */
}

+ (NSInteger)version
{
    return 6;
}

/* We assume our caller has already verified the file magic. */
- initWithByteProvider:(id <NSObject,OFByteProvider>)underlying
                 range:(NSRange)segmentsAndFileMAC
                 error:(NSError **)outError;
{
    if (!(self = [super init])) {
        if (outError)
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        return nil;
    }
    
    if (segmentsAndFileMAC.length < (SEGMENTED_FILE_MAC_LEN + SEGMENT_HEADER_LEN)) {
        unsupportedError(outError, @"File is too short");
        return nil;
    }
    
    size_t offsetOfFirstSegment = segmentsAndFileMAC.location;
    size_t segmentsLength = segmentsAndFileMAC.length - SEGMENTED_FILE_MAC_LEN;
    size_t completeSegmentCount = segmentsLength / SEGMENT_ENCRYPTED_PAGE_SIZE;
    size_t remainder = segmentsLength - ( completeSegmentCount * SEGMENT_ENCRYPTED_PAGE_SIZE );
    
    _length = completeSegmentCount * SEGMENTED_PAGE_SIZE;
    if (remainder > SEGMENT_HEADER_LEN) {
        _length += remainder - SEGMENT_HEADER_LEN;
    } else if (remainder > 0) {
        // We have a bit of data on the end, too small to be a fractional segment.
        unsupportedError(outError, @"Trailing data at end of file");
        return nil;
    }
    
    dispatch_once_f(&testRADARsOnce, NULL, testRADAR18222014);
        
    _backingStore = underlying;
    _pages = [[NSCache alloc] init];
    _pages.name = NSStringFromClass([self class]);
    _pages.countLimit = 5;
    _verifiedPages = [[NSMutableIndexSet alloc] init];
    _offset = offsetOfFirstSegment;
    _segmentsLength = segmentsLength;
    
    return self;
}

- (BOOL)unwrapKey:(NSRange)wrappedBlob using:(OFSDocumentKey *)unwrapper error:(NSError **)outError;
{
    return withBackingRange(_backingStore, wrappedBlob, ^(const uint8_t *buffer){
        ssize_t len = [unwrapper unwrapFileKey:buffer length:wrappedBlob.length into:_keyMaterial length:sizeof(_keyMaterial) error:outError];
        if (len < 0)
            return NO;
        else if (len == sizeof(_keyMaterial)) {
            return YES;
        } else {
            unsupportedError(outError, @"Incorrect inner key version");
            return NO;
        }
    });
}

- (NSUInteger)length;
{
    return _length;
}

static BOOL withBackingRange(id <OFByteProvider, NSObject> backingStore, NSRange backingRange, BOOL (^doWork)(const uint8_t *buffer))
{
    BOOL rv;
    
    if ([backingStore respondsToSelector:@selector(getBuffer:range:)]) {
        NSRange retrievedRange = backingRange;
        const uint8_t *backingBuffer = NULL;
        OFByteProviderBufferRelease releaser = [backingStore getBuffer:(const void **)&backingBuffer range:&retrievedRange];
        if (releaser && OFRangeContainsRange(retrievedRange, backingRange)) {
            const uint8_t *retrievedSegmentBuffer = backingBuffer + (backingRange.location - retrievedRange.location);
            
            rv = doWork(retrievedSegmentBuffer);
            
            if (releaser)
                releaser();
            
            return rv;
        }
        
        if (releaser)
            releaser();
    }
    
    /* Can't use -getBuffer:range:, so fall back on getBytes:range: */
    void *buffer = malloc(backingRange.length);
    [backingStore getBytes:buffer range:backingRange];
    rv = doWork(buffer);
    free(buffer);
    
    return rv;
}

- (BOOL)verifyFileMAC;
{
    CCHmacContext ctxt, *ctxt_ptr;
    uint8_t expected[SEGMENTED_FILE_MAC_LEN];
    _Static_assert(CC_SHA256_DIGEST_LENGTH == SEGMENTED_FILE_MAC_LEN, "");
    
    ctxt_ptr = &ctxt;
    CCHmacInit(&ctxt, kCCHmacAlgSHA256, _hmacKey, SEGMENTED_MAC_KEY_LEN);
    CCHmacUpdate(&ctxt, SEGMENTED_FILE_MAC_VERSION_BYTE, 1);
    
    [_backingStore getBytes:expected range:(NSRange){ _offset + _segmentsLength, SEGMENTED_FILE_MAC_LEN }];
    
    uint32_t pageIndex = 0;
    size_t position = 0;
    while(position < _length) {
        size_t underpos = _offset + ( pageIndex * (size_t)SEGMENT_ENCRYPTED_PAGE_SIZE );
        withBackingRange(_backingStore, (NSRange){ underpos + SEGMENTED_IV_LEN, SEGMENTED_MAC_LEN }, ^(const uint8_t *buffer){
            CCHmacUpdate(ctxt_ptr, buffer, SEGMENTED_MAC_LEN);
            return YES;
        });
        position += SEGMENT_ENCRYPTED_PAGE_SIZE;
        pageIndex ++;
    }
    
    if (finishAndVerifyHMAC256(&ctxt, expected, SEGMENTED_FILE_MAC_LEN) != 0)
        return NO;
    
    return YES;
}

/* Retrieve a segment from the backing store, verifying it if we haven't seen it before, and decrypting it into the provided buffer. thisPageSize will normally be equal to SEGMENTED_PAGE_SIZE unless this is the last segment in the file. */
- (void)_faultPage:(NSUInteger)pageNumber size:(size_t)thisPageSize toBuffer:(uint8_t *)plaintextBuffer
{
    withBackingRange(_backingStore,
                     (NSRange){ _offset + ( pageNumber * (size_t)SEGMENT_ENCRYPTED_PAGE_SIZE ), SEGMENT_HEADER_LEN + thisPageSize },
                     ^(const uint8_t *retrievedSegmentBuffer){
        BOOL verified = [_verifiedPages containsIndex:pageNumber];
        
        if (!verified) {
            verified = verifySegment(_hmacKey, pageNumber, retrievedSegmentBuffer, retrievedSegmentBuffer + SEGMENT_HEADER_LEN, thisPageSize);
            
            if (verified) {
                [_verifiedPages addIndex:pageNumber];
            }
        }
        
        if (!verified)
            return NO;
        
        /* If Apple ever fixes the CTR reset bug, it'll be worth caching the decryptor */
        CCCryptorRef ctrDecryptor;
        {
            uint8_t segmentIV[ kCCBlockSizeAES128 ];
            memcpy(segmentIV, retrievedSegmentBuffer, SEGMENTED_IV_LEN);
            memset(segmentIV + SEGMENTED_IV_LEN, 0, kCCBlockSizeAES128 - SEGMENTED_IV_LEN);
            ctrDecryptor = createCryptor(segmentIV, _bulkKey, NULL);
        }
        
        cryptOrCrash(ctrDecryptor, retrievedSegmentBuffer + SEGMENT_HEADER_LEN, thisPageSize, plaintextBuffer, __LINE__);
                         
        CCCryptorRelease(ctrDecryptor);
        
        return YES;
    });
}

- (void)getBytes:(void *)buffer range:(NSRange)range;
{
    if (range.location > _length || NSMaxRange(range) > _length) {
        OBRejectInvalidCall(self, _cmd, @"Requested range %@ is invalid (length is %zu)", NSStringFromRange(range), _length);
    }
    
    while (range.length > 0) {
        NSUInteger pageNumber = range.location / SEGMENTED_PAGE_SIZE;
        unsigned pageOffset = range.location % SEGMENTED_PAGE_SIZE;
        NSNumber *pageKey = [NSNumber numberWithUnsignedInteger:pageNumber];
        NSData *cachedPage = [_pages objectForKey:pageKey];
        NSUInteger bytesCopiedOut;
        size_t thisPageSize;
        
        if ( (pageNumber+1)*SEGMENTED_PAGE_SIZE > _length ) {
            thisPageSize = _length - pageNumber*SEGMENTED_PAGE_SIZE;
        } else {
            thisPageSize = SEGMENTED_PAGE_SIZE;
        }
        
        if (pageOffset == 0 && range.length >= thisPageSize && !cachedPage) {
            [self _faultPage:pageNumber size:thisPageSize toBuffer:buffer];
            bytesCopiedOut = thisPageSize;
        } else {
            if (!cachedPage) {
                void *page = malloc(thisPageSize);
                [self _faultPage:pageNumber size:thisPageSize toBuffer:page];
                cachedPage = (NSData *)dispatch_data_create(page, thisPageSize, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
                [_pages setObject:cachedPage forKey:pageKey];
            }

            OBINVARIANT(cachedPage.length == thisPageSize);
            
            NSRange part;
            part.location = pageOffset;
            part.length = MIN( (cachedPage.length - pageOffset), range.length );
            bytesCopiedOut = part.length;
            [cachedPage getBytes:buffer range:part];
        }
        
        buffer += bytesCopiedOut;
        range.location += bytesCopiedOut;
        range.length -= bytesCopiedOut;
    }
}

@end

struct pendingPage {
    uint32_t pageIndex;         /* page index in the file */
    unsigned size;              /* Number of bytes in this page:  0 <= validToIndex <= size <= SEGMENTED_PAGE_SIZE */
 // unsigned validToIndex;      /* bytes to this index are valid; any past this index would need to be retrieved from backing store and re-encrypted */
 // BOOL     needsWrite;
    uint8_t  *buffer;           /* plaintext; buffer is always of length SEGMENTED_PAGE_SIZE */
};

static CFStringRef describePage(const void *value) CF_RETURNS_RETAINED ;
static CFStringRef describePage(const void *value)
{
    const struct pendingPage *pg = value;
    
    return CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("<page %" PRIu32 ", size=0x%x @ %p>"),
                                    pg->pageIndex, pg->size, pg->buffer);
}

static const CFArrayCallBacks pageCacheArrayCallbacks = {
    .version = 0,
    .retain = NULL,
    .release = NULL,
    .copyDescription = describePage,
    .equal = NULL
};

@implementation OFSSegmentEncryptingByteAcceptor
{
    id <NSObject,OFByteAcceptor> _backingStore;
    OFSSegmentEncryptWorker     *_encryptor;
    CFMutableArrayRef            _pageCache;
    size_t                       _offset;     /* The offset of the beginning of the first segment */
    size_t                       _length;     /* The length we present to our callers */
    size_t                       _cachedUnderlyingLength;
}

- (instancetype)initWithByteAcceptor:(id <NSObject,OFByteProvider,OFByteAcceptor>)underlying cryptor:(OFSSegmentEncryptWorker *)cr offset:(size_t)segmentsBegin;
{
    if (!(self = [super init])) {
        return nil;
    }
    
    _backingStore = underlying;
    _encryptor = cr;
    _pageCache = CFArrayCreateMutable(kCFAllocatorDefault, 0, &pageCacheArrayCallbacks);
    _offset = segmentsBegin;
    _length = 0;
    
    return self;
}

- (void)dealloc
{
    CFIndex pageCount = CFArrayGetCount(_pageCache);
    while (pageCount) {
        struct pendingPage *lastPage = (struct pendingPage *)CFArrayGetValueAtIndex(_pageCache, pageCount-1);
        CFArrayRemoveValueAtIndex(_pageCache, pageCount-1);
        free(lastPage->buffer);
        free(lastPage);
        pageCount --;
    }
    CFRelease(_pageCache);
    _pageCache = NULL;
}

- (void)setLength:(NSUInteger)length;
{
#ifndef __clang_analyzer__  /* RADAR 19406485 - clang-analyze's CFArrayGetValueAtIndex() checker doesn't understand mutable arrays? */
    CFIndex pageCount = CFArrayGetCount(_pageCache);
    CFIndex desiredPageCount = (length + SEGMENTED_PAGE_SIZE - 1) / SEGMENTED_PAGE_SIZE;
    
    if (desiredPageCount < 0 || desiredPageCount > (CFIndex)UINT32_MAX) {
        OBRejectInvalidCall(self, _cmd, @"Offset exceeds maximum length (page count would be 0x%" PRIxCFIndex ")", desiredPageCount);
    }
    
    CFIndex originalPageCount = pageCount;
    
    /* Add pages as needed */
    while (pageCount < desiredPageCount) {
        struct pendingPage *p = malloc(sizeof(*p));
        p->pageIndex = (uint32_t)pageCount;
        p->size = 0;
        p->buffer = calloc(SEGMENTED_PAGE_SIZE, 1);
        CFArrayAppendValue(_pageCache, p);
        pageCount ++;
    }
    /* Remove pages as needed */
    while (pageCount > desiredPageCount) {
        struct pendingPage *lastPage = (struct pendingPage *)CFArrayGetValueAtIndex(_pageCache, pageCount-1);
        CFArrayRemoveValueAtIndex(_pageCache, pageCount-1);
        free(lastPage->buffer);
        free(lastPage);
        pageCount --;
    }
    
    OBASSERT(pageCount == desiredPageCount);
    OBINVARIANT(pageCount == CFArrayGetCount(_pageCache));
    
    /* Any non-end pages must be completely used */
    for (CFIndex pageIndex = originalPageCount? originalPageCount-1 : 0; pageIndex < desiredPageCount-1; pageIndex ++) {
        struct pendingPage *page = (struct pendingPage *)CFArrayGetValueAtIndex(_pageCache, pageIndex);
        page->size = SEGMENTED_PAGE_SIZE;
    }
    
    /* And the end page's length should be set to whatever fraction of a page makes the total length correct */
    unsigned lastPageSize = (unsigned)(length - (pageCount-1)*SEGMENTED_PAGE_SIZE);
    struct pendingPage *lastPage = (struct pendingPage *)CFArrayGetValueAtIndex(_pageCache, pageCount-1);
    if (lastPage->size != lastPageSize) {
        unsigned zeroFrom = MIN(lastPage->size, lastPageSize);
        memset(lastPage->buffer + zeroFrom, 0, SEGMENTED_PAGE_SIZE - zeroFrom);
        lastPage->size = lastPageSize;
    }
#endif
    
    _length = length;
}

- (void)flushByteAcceptor;
{
    CFIndex pageCount = CFArrayGetCount(_pageCache);
    dispatch_queue_t writeQueue = dispatch_queue_create("OFSEncryptingByteAcceptor.write", DISPATCH_QUEUE_SERIAL);
    uint8_t *macs = malloc(SEGMENTED_MAC_LEN * pageCount);
    
    size_t pagesSize;
    if (pageCount == 0)
        pagesSize = 0;
    else {
        struct pendingPage *lastPage = (struct pendingPage *)CFArrayGetValueAtIndex(_pageCache, pageCount-1);
        pagesSize = ( SEGMENT_ENCRYPTED_PAGE_SIZE * (pageCount-1) ) + SEGMENT_HEADER_LEN + lastPage->size;
    }

    dispatch_async(writeQueue, ^{
        [_backingStore setLength: _offset + SEGMENTED_FILE_MAC_LEN + pagesSize ];
    });
    
    dispatch_apply(pageCount, dispatch_get_global_queue(QOS_CLASS_UNSPECIFIED, 0), ^(size_t pageIndex){
        struct pendingPage *page = (struct pendingPage *)CFArrayGetValueAtIndex(_pageCache, pageIndex);
        uint8_t *segBuffer = malloc(SEGMENT_HEADER_LEN + SEGMENTED_PAGE_SIZE);
        OBINVARIANT(pageIndex == page->pageIndex);
        
        [_encryptor encryptBuffer:page->buffer length:page->size index:(uint32_t)pageIndex into:segBuffer + SEGMENT_HEADER_LEN header:segBuffer error:NULL];
        
        memcpy(macs + SEGMENTED_MAC_LEN*pageIndex, segBuffer+SEGMENTED_IV_LEN, SEGMENTED_MAC_LEN);

        dispatch_async(writeQueue, ^{
            [_backingStore replaceBytesInRange:(NSRange){ _offset + (SEGMENT_ENCRYPTED_PAGE_SIZE*pageIndex), SEGMENT_HEADER_LEN + page->size }
                                     withBytes:segBuffer];
            free(segBuffer);
        });
    });
    
    CCHmacContext fileMAC;
    [_encryptor fileMACContext:&fileMAC];
    CCHmacUpdate(&fileMAC, macs, SEGMENTED_MAC_LEN * pageCount);
    uint8_t output[CC_SHA256_DIGEST_LENGTH];
    _Static_assert(sizeof(output) >= SEGMENTED_FILE_MAC_LEN, "");
    uint8_t *output_p = output;
    CCHmacFinal(&fileMAC, output);
    free(macs);
    
    dispatch_sync(writeQueue, ^{
        [_backingStore replaceBytesInRange:(NSRange){ _offset + pagesSize, SEGMENTED_FILE_MAC_LEN }
                                 withBytes:output_p];
        
        if ([_backingStore respondsToSelector:@selector(flushByteAcceptor)]) {
            [_backingStore flushByteAcceptor];
        }
    });
}

- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes;
{
    if (range.location+range.length > _length)
        OBRejectInvalidCall(self, _cmd, @"Written range (ends 0x%" PRIxNS ") exceeds current length (0x%zx)",
                            range.location+range.length, _length);
    
    while (range.length > 0) {
        uint32_t pageNumber = (uint32_t)( range.location / SEGMENTED_PAGE_SIZE );
        unsigned pageOffset = range.location % SEGMENTED_PAGE_SIZE;
        unsigned bytesOnPage;
        
        if (range.length + pageOffset <= SEGMENTED_PAGE_SIZE) {
            bytesOnPage = (unsigned)(range.length);
        } else {
            bytesOnPage = SEGMENTED_PAGE_SIZE - pageOffset;
        }
        
        struct pendingPage *page = (struct pendingPage *)CFArrayGetValueAtIndex(_pageCache, pageNumber);
        OBINVARIANT(page->pageIndex == pageNumber);
        
        OBASSERT(pageOffset+bytesOnPage <= page->size);
        memcpy(page->buffer + pageOffset, bytes, bytesOnPage);
        
        bytes += bytesOnPage;
        range.location += bytesOnPage;
        range.length   -= bytesOnPage;
    }
}

@end

@implementation OFSSegmentEncryptWorker
{
    CCCryptorRef _cachedCryptor;
    int32_t      _nonceCounter;
    uint8_t      _keydata[ kCCKeySizeAES128 + SEGMENTED_MAC_KEY_LEN + SEGMENTED_IV_LEN ];
#define EW_KEYDATA_KEY_OFFSET 0
#define EW_KEYDATA_MAC_OFFSET ( EW_KEYDATA_KEY_OFFSET + kCCKeySizeAES128 )
#define EW_KEYDATA_IV_OFFSET  ( EW_KEYDATA_MAC_OFFSET + SEGMENTED_MAC_KEY_LEN )
    BOOL         _forEncryption;
}

- (instancetype)init;
{
    if (!(self = [super init]))
        return nil;
    
    dispatch_once_f(&testRADARsOnce, NULL, testRADAR18222014);
    
    if (!randomBytes(_keydata, sizeof(_keydata), NULL)) {
        return nil;
    }
    
    _forEncryption = YES;
    
    return self;
}

- (NSData *)wrappedKeyWithDocumentKey:(OFSDocumentKey *)docKey error:(NSError **)outError
{
    /* The IV isn't part of the wrapped key--- each segment's IV is stored with that segment. */
    _Static_assert( EW_KEYDATA_IV_OFFSET == SEGMENTED_INNER_LENGTH, "" );
    uint8_t buf[SEGMENTED_INNER_LENGTH_PADDED];
    memcpy(buf, _keydata, kCCKeySizeAES128 + SEGMENTED_MAC_KEY_LEN);
    memset(buf + kCCKeySizeAES128 + SEGMENTED_MAC_KEY_LEN, 0, sizeof(buf) - (kCCKeySizeAES128 + SEGMENTED_MAC_KEY_LEN));
    NSData *res = [docKey wrapFileKey:buf length:sizeof(buf) error:outError];
    memset(buf, 0, sizeof(buf));
    return res;
}

- (void)fileMACContext:(CCHmacContext *)ctxt;
{
    CCHmacInit(ctxt, kCCHmacAlgSHA256, _keydata + EW_KEYDATA_MAC_OFFSET, SEGMENTED_MAC_KEY_LEN);
    CCHmacUpdate(ctxt, SEGMENTED_FILE_MAC_VERSION_BYTE, 1);
}

#if 0

/* This is/was needed for the version of OFSSegmentEncryptingByteAcceptor which would eject pages to its backing store on the fly--- if the caller went back and wrote into a previously-written page (which OUZip does do) it would have to read in the already-encrypted page, decrypt it, and put it back in the page cache (to eventually be re-written with a new IV). That turned out to be a PITA to implement cleanly, so we don't do that yet, and we don't need this method yet. We will eventually want it, though, I think. */

- (BOOL)decryptBuffer:(const uint8_t *)ciphertext range:(NSRange)r index:(uint32_t)order into:(uint8_t *)plaintext header:(const uint8_t *)hdr error:(NSError **)outError;
{
    CCCryptorRef cryptor;
    
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
        
        if (!(cryptor = createOrResetCryptor(cryptor, segmentIV, _keydata + EW_KEYDATA_KEY_OFFSET, outError)))
            return NO;
    }
    
    /* Actually process the data */
    if (initialBlockCounter*kCCBlockSizeAES128 != r.location) {
        unsigned discard = (uint32_t)r.location - initialBlockCounter*kCCBlockSizeAES128;
        uint8_t partialBlock[ kCCBlockSizeAES128 ];
        cryptOrCrash(cryptor, ciphertext + initialBlockCounter*kCCBlockSizeAES128, kCCBlockSizeAES128, partialBlock, __LINE__);
        size_t copylen = MIN(r.length, kCCBlockSizeAES128 - discard);
        memcpy(plaintext, partialBlock + discard, copylen);
        r.location += copylen;
        r.length -= copylen;
        plaintext += copylen;
    }
    if (r.length >= kCCBlockSizeAES128) {
        size_t fullBlocks = (r.length / kCCBlockSizeAES128) + kCCBlockSizeAES128;
        cryptOrCrash(cryptor, ciphertext, fullBlocks, plaintext, __LINE__);
        r.location += fullBlocks;
        r.length -= fullBlocks;
        ciphertext += fullBlocks;
        plaintext += fullBlocks;
    }
    if (r.length) {
        assert(r.length < kCCBlockSizeAES128);
        uint8_t partialBlock[ kCCBlockSizeAES128 ];
        cryptOrCrash(cryptor, ciphertext, kCCBlockSizeAES128, partialBlock, __LINE__);
        memcpy(plaintext, partialBlock, r.length);
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
#endif

- (BOOL)encryptBuffer:(const uint8_t *)plaintext length:(size_t)len index:(uint32_t)order into:(uint8_t *)ciphertext header:(uint8_t *)hdr error:(NSError **)outError;
{
    CCCryptorRef cryptor;
    uint8_t segmentIV[ kCCBlockSizeAES128 ];
    int32_t nonceCounter;
    dispatch_semaphore_t hashSem;
    CCHmacContext ctxt;
    const size_t strideLength = 4096;
    
    /* Fetch the already-set-up cryptor instance, if we have one */
    @synchronized(self) {
        cryptor = _cachedCryptor;
        _cachedCryptor = nil;
        nonceCounter = OSAtomicIncrement32(&_nonceCounter);
    }
    
    /* Construct the initial CTR state for this segment: our random IV, our counter, and four bytes of zeroes for the block counter */
    memcpy(segmentIV, _keydata + EW_KEYDATA_IV_OFFSET, SEGMENTED_IV_LEN - 4);
    OSWriteBigInt32(segmentIV, SEGMENTED_IV_LEN - 4, nonceCounter);
    memset(segmentIV + SEGMENTED_IV_LEN, 0, kCCBlockSizeAES128 - SEGMENTED_IV_LEN);
    
    if (!(cryptor = createOrResetCryptor(cryptor, segmentIV, _keydata + EW_KEYDATA_KEY_OFFSET, outError)))
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

+ (NSData *)encryptData:(NSData *)plaintext withKey:(OFSDocumentKey *)kek error:(NSError * __autoreleasing *)outError;
{
    if (!plaintext)
        return nil;
    
    size_t segmentCount = ( [plaintext length] + SEGMENTED_PAGE_SIZE - 1 ) / SEGMENTED_PAGE_SIZE;
    
    if (segmentCount >= UINT_MAX) {
        return nil;
    }
    
    OFSSegmentEncryptWorker *worker = [kek encryptionWorker];
    
    NSData *keyInfo = [worker wrappedKeyWithDocumentKey:kek error:outError];
    if (!keyInfo)
        return nil;
    
    // Ugly.
    const void **segments = calloc(MAX((size_t)1, segmentCount), sizeof(void *));
    
    dispatch_apply(segmentCount, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t segmentIndex){
        size_t plaintextLength = [plaintext length];
        size_t segmentBegins = segmentIndex * SEGMENTED_PAGE_SIZE;
        size_t segmentLength = MIN((size_t)SEGMENTED_PAGE_SIZE, plaintextLength - segmentBegins);
        void *buffer = malloc(SEGMENT_HEADER_LEN + segmentLength);
        NSError *localError = nil;
        
        BOOL ok = [worker encryptBuffer:[plaintext bytes] + segmentBegins length:segmentLength
                                  index:(uint32_t)segmentIndex
                                   into:buffer + SEGMENT_HEADER_LEN header:buffer error:&localError];
        
        if (ok) {
            segments[segmentIndex] = CFBridgingRetain(dispatch_data_create(buffer, SEGMENT_HEADER_LEN + segmentLength, NULL, DISPATCH_DATA_DESTRUCTOR_FREE));
        } else {
            free(buffer);
#ifndef DEBUG
#error do not commit this, wim
            abort();
#endif
        }
    });
    
    /* Header is: magic || infolength || info || padding */
    size_t keyInfoLength = [keyInfo length];
    size_t headerLength = FMT_V0_6_MAGIC_LEN + 2 + keyInfoLength;
    headerLength = 16 * ((headerLength + 15)/16);
    void *header = calloc(1, headerLength);
    memcpy(header, magic_ver0_6, FMT_V0_6_MAGIC_LEN);
    OSWriteBigInt16(header, FMT_V0_6_MAGIC_LEN, (uint16_t)keyInfoLength);
    [keyInfo getBytes:header + (FMT_V0_6_MAGIC_LEN + 2) length:keyInfoLength];
    dispatch_data_t result_data = dispatch_data_create(header, headerLength, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
    
    /* Concat the segments, and compute the file MAC */
    
    CCHmacContext fileMAC;
    [worker fileMACContext:&fileMAC];
    
    for(size_t segmentIndex = 0; segmentIndex < segmentCount; segmentIndex ++) {
        dispatch_data_t seg = CFBridgingRelease(segments[segmentIndex]);
        segments[segmentIndex] = NULL;
        CCHmacUpdate(&fileMAC, [(NSData *)seg bytes] + 12, 20);
        result_data = dispatch_data_create_concat(result_data, seg);
    }
    
    free(segments);
    
    /* Trailer is just the file MAC */
    
    char finalMAC[SEGMENTED_FILE_MAC_LEN];
    CCHmacFinal(&fileMAC, finalMAC);
    
    dispatch_data_t final_block = dispatch_data_create(finalMAC, SEGMENTED_FILE_MAC_LEN, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    
    dispatch_data_t final_result = dispatch_data_create_concat(result_data, final_block);
    
    return (NSData *)final_result;
}

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
    
    return [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:uinfo];
}

static uint16_t checkHeaderMagic(NSData * __nonnull ciphertext, size_t ciphertextLength, NSError **outError)
{
    char buffer[FMT_V0_6_MAGIC_LEN + 2];
    
    /* Look at the fixed-length portions of the header */
    if (ciphertextLength < (FMT_V0_6_MAGIC_LEN + 2)) {
        if (outError) *outError = headerError("file too short");
        return 0;
    }
    
    [ciphertext getBytes:buffer length:FMT_V0_6_MAGIC_LEN + 2];
    
    /* Check the file magic */
    if (memcmp(buffer, magic_ver0_6, FMT_V0_6_MAGIC_LEN) != 0) {
        if (outError) *outError = headerError("invalid encryption header");
        return 0;
    }
    
    /* Find the length of the header */
    return OSReadBigInt16(buffer, FMT_V0_6_MAGIC_LEN);
}

static BOOL unwrappedKeyFromHeader(NSData *ciphertext, OFSDocumentKey *kek, size_t *headerLength, uint8_t unwrappedKey[SEGMENTED_INNER_LENGTH_PADDED], NSError **outError)
{
    if (!ciphertext) {
        if (outError) *outError = headerError("missing ciphertext");
        return NO;
    }
    size_t ciphertextLength = [ciphertext length];
    
    size_t const wrappedKeyBlobLocation = FMT_V0_6_MAGIC_LEN + 2;
    uint16_t wrappedKeyBlobSize = checkHeaderMagic(ciphertext, ciphertextLength, outError);
    if (!wrappedKeyBlobSize)
        return NO;
    
    /* Read the variable-length portion of the header, which consists of the wrapped key blob, followed by zero-padding to a 16-byte boundary */
    
    size_t paddedLength = ((wrappedKeyBlobLocation + wrappedKeyBlobSize + 15) / 16) * 16;
    
    if (ciphertextLength < (paddedLength + SEGMENTED_FILE_MAC_LEN)) {
        if (outError) *outError = headerError("file too short");
        return NO;
    }
    
    *headerLength = paddedLength;
    
    /* Safe alloca, since wrappedKeyBlobSize < 2^16 */
    uint8_t *blobbuffer = alloca(paddedLength - wrappedKeyBlobLocation);
    [ciphertext getBytes:blobbuffer range:(NSRange){wrappedKeyBlobLocation, paddedLength - wrappedKeyBlobLocation}];
    // NSLog(@"Variable-length header: %@", [ciphertext subdataWithRange:(NSRange){wrappedKeyBlobLocation, paddedLength - wrappedKeyBlobLocation}]);
    
    /* Check the padding - we haven't touched our key yet, so no information leaks here */
    for(size_t i = wrappedKeyBlobSize; i < (paddedLength - wrappedKeyBlobLocation); i++) {
        if (blobbuffer[i] != 0) {
            if (outError) *outError = headerError("invalid encryption header");
            return NO;
        }
    }
    
    /* Finally, ask our document key manager to unwrap the file key */
    ssize_t resultSize = [kek unwrapFileKey:blobbuffer length:wrappedKeyBlobSize into:unwrappedKey length:SEGMENTED_INNER_LENGTH_PADDED error:outError];
    if (resultSize < 0)
        return NO;
    if (resultSize != SEGMENTED_INNER_LENGTH_PADDED) {
        if (outError) *outError = headerError("invalid encryption header");
        return NO;
    }
    
    return YES;
}

+ (NSData *)decryptData:(NSData *)ciphertext withKey:(OFSDocumentKey *)kek error:(NSError * __autoreleasing *)outError;
{
    size_t segmentsBegin;
    uint8_t fileKey[SEGMENTED_INNER_LENGTH_PADDED];
    
    if (!unwrappedKeyFromHeader(ciphertext, kek, &segmentsBegin, fileKey, outError))
        return nil;
    
    size_t segmentsLength = [ciphertext length] - segmentsBegin - SEGMENTED_FILE_MAC_LEN;
    size_t segmentCount = ( segmentsLength + SEGMENT_ENCRYPTED_PAGE_SIZE - 1 ) / SEGMENT_ENCRYPTED_PAGE_SIZE;
    size_t plaintextLength = segmentsLength - (SEGMENT_HEADER_LEN * segmentCount);
    size_t lastSegmentLength = segmentsLength - (SEGMENT_ENCRYPTED_PAGE_SIZE * (segmentCount-1));
    
    if (lastSegmentLength < SEGMENT_HEADER_LEN) {
        // Impossible file length
        if (outError) *outError = headerError("file too short");
        return nil;
    }
    
    NSMutableData *plaintext = [NSMutableData dataWithLength:plaintextLength];

    const uint8_t * const fileKeyBytes = fileKey;
    char *plaintextBuffer = [plaintext mutableBytes];
    __block uint32_t errorBits = 0;
    
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

        if (!verifySegment(fileKeyBytes + kCCKeySizeAES128, segmentIndex, segmentBegins, segmentBegins + SEGMENT_HEADER_LEN, segmentLength - SEGMENT_HEADER_LEN)) {
            OSAtomicOr32(0x01, &errorBits);
            return;
        }
        
        CCCryptorRef ctrDecryptor;
        {
            uint8_t segmentIV[ kCCBlockSizeAES128 ];
            memcpy(segmentIV, segmentBegins, SEGMENTED_IV_LEN);
            memset(segmentIV + SEGMENTED_IV_LEN, 0, kCCBlockSizeAES128 - SEGMENTED_IV_LEN);
            _Static_assert(kCCBlockSizeAES128 == SEGMENTED_IV_LEN + sizeof(uint32_t), "");
            ctrDecryptor = createCryptor(segmentIV, (const uint8_t *)fileKeyBytes, NULL);
        }
        
        cryptOrCrash(ctrDecryptor, segmentBegins + SEGMENT_HEADER_LEN, segmentLength - SEGMENT_HEADER_LEN, plaintextBuffer + (segmentIndex * SEGMENTED_PAGE_SIZE), __LINE__);
        
        CCCryptorRelease(ctrDecryptor);
    });
    
    if (errorBits != 0) {
        if (outError) *outError = headerError("encrypted file is corrupt");
        return nil;
    }
    
    /* Check the file MAC */
    CCHmacContext fileMACContext;
    CCHmacInit(&fileMACContext, kCCHmacAlgSHA256, fileKeyBytes + kCCKeySizeAES128, SEGMENTED_MAC_KEY_LEN);
    CCHmacUpdate(&fileMACContext, SEGMENTED_FILE_MAC_VERSION_BYTE, 1);
    for (size_t segmentIndex = 0; segmentIndex < segmentCount; segmentIndex ++) {
        char segmentMAC[SEGMENTED_MAC_LEN];
        [ciphertext getBytes:segmentMAC range:(NSRange){ segmentsBegin + (segmentIndex * SEGMENT_ENCRYPTED_PAGE_SIZE) + SEGMENTED_IV_LEN, SEGMENTED_MAC_LEN}];
        CCHmacUpdate(&fileMACContext, segmentMAC, SEGMENTED_MAC_LEN);
    }

    uint8_t foundFileMAC[SEGMENTED_FILE_MAC_LEN];
    [ciphertext getBytes:foundFileMAC range:(NSRange){ segmentsBegin + segmentsLength, SEGMENTED_FILE_MAC_LEN}];
    if (finishAndVerifyHMAC256(&fileMACContext, foundFileMAC, SEGMENTED_FILE_MAC_LEN) != 0) {
        if (outError) *outError = headerError("encrypted file is corrupt");
        return nil;
    }
    
    return plaintext;
}

@end

#pragma mark Utility functions

/* Format and hash in the IV and block number parts of the hashed data */
static void hmacSegmentHeader(CCHmacContext *hashContext, const uint8_t *segmentIV, uint32_t order)
{
    uint8_t hashPrefix[ kCCBlockSizeAES128 ];
    memset(hashPrefix, 0, kCCBlockSizeAES128);
    memcpy(hashPrefix, segmentIV, SEGMENTED_IV_LEN);
    OSWriteBigInt32(hashPrefix, kCCBlockSizeAES128 - 4, order);
    CCHmacUpdate(hashContext, hashPrefix, kCCBlockSizeAES128);
}

static uint8_t finishAndVerifyHMAC256(CCHmacContext *hashContext, const uint8_t *expectedValue, unsigned hashLength)
{
    uint8_t mismatches = 0;
    
    uint8_t computedMac[CC_SHA256_DIGEST_LENGTH];
    CCHmacFinal(hashContext, computedMac);
    
    memset(hashContext, 0, sizeof(*hashContext));
    
    /* Constant-time compare (this is why this function is marked noinline--- we can't control compiler settings, especially if we start distributing as bitcode, so this hopefully keeps the comparison hidden from the optimizer) */
    for(unsigned i = 0; i < hashLength; i++)
        mismatches |= (computedMac[i] ^ expectedValue[i]);
    
    return mismatches;
}

/* Verify the HMAC on an encrypted segment */
static BOOL verifySegment(const uint8_t *hmacKey, NSUInteger segmentNumber, const uint8_t *hdr, const uint8_t *ciphertext, size_t ciphertextLength)
{
    if (segmentNumber > UINT32_MAX)
        return NO;
    
    CCHmacContext hashContext;
    CCHmacInit(&hashContext, kCCHmacAlgSHA256, hmacKey, SEGMENTED_MAC_KEY_LEN);
    hmacSegmentHeader(&hashContext, hdr, (uint32_t)segmentNumber);
    CCHmacUpdate(&hashContext, ciphertext, ciphertextLength);
    
    return (finishAndVerifyHMAC256(&hashContext, hdr + SEGMENTED_IV_LEN, SEGMENTED_MAC_LEN) == 0)? YES : NO;
}

static NSError *wrapCCError(CCCryptorStatus cerr, NSString *func, NSString *extra, NSObject *val)
{
    NSString *ks[2] = { @"function", extra };
    NSObject *vs[2] = { func, val };
    
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjects:vs forKeys:ks count:extra? 2 : 1];
    
    /* CCCryptorStatus is actually in the Carbon OSStatus error domain. However, many CommonCrypto functions just return -1 on failure, instead of the error codes they are documented to return; perhaps we should check for that here and substitute a better error code? */
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:cerr userInfo:userInfo];
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

static BOOL randomBytes(uint8_t *buffer, size_t bufferLength, NSError **outError)
{
#if (defined(MAC_OS_X_VERSION_10_10) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_10) || (TARGET_OS_IPHONE && __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000)
    CCRNGStatus randomErr = CCRandomGenerateBytes(buffer, bufferLength);
    if (randomErr) {
        if (outError)
            *outError = wrapCCError(randomErr, @"CCRandomGenerateBytes", @"length", [NSNumber numberWithUnsignedInteger:bufferLength]);
        return NO;
    }
#else
    if (SecRandomCopyBytes(kSecRandomDefault, bufferLength, buffer) != 0) {
        /* Documentation says "check errno to find out the real error" but a look at the published source code shows that's not going to be very reliable */
        if (outError)
            *outError = wrapSecError(kCCRNGFailure, @"SecRandomCopyBytes", @"length", [NSNumber numberWithUnsignedInteger:bufferLength]);
        return NO;
    }
#endif
    
    return YES;
}

static CCCryptorRef createCryptor(const uint8_t segmentIV[kCCBlockSizeAES128], const uint8_t key[kCCKeySizeAES128], NSError **outError)
{
    CCCryptorRef cryptor = NULL;
    CCCryptorStatus cerr;
    cerr = CCCryptorCreateWithMode(kCCEncrypt, kCCModeCTR, kCCAlgorithmAES, 0,
                                   segmentIV, key, kCCKeySizeAES128,
                                   NULL, 0, 0,
                                   /* This mode option is "deprecated" and "not in use", but if you don't supply it, the call fails with kCCUnimplemented (at least on 10.9.4) */
                                   kCCModeOptionCTR_BE,
                                   &cryptor);
    if (cerr != kCCSuccess) {
        if (outError)
            *outError = wrapCCError(cerr, @"CCCryptorCreate", @"mode", @"AES128-CTR");
        return NULL;
    }
    return cryptor;
}

static BOOL resetCryptor(CCCryptorRef cryptor, const uint8_t segmentIV[kCCBlockSizeAES128], NSError **outError)
{
    /* Note that this function does not work correctly in released versions of iOS (see RADARs 18222014 and 12680772). We test the functionality and don't call this function if it does not appear to work. */
    /* (This means that this code path has never actually been tested for real, unfortunately.) */
    OBASSERT(canResetCTRIV);
    CCCryptorStatus cerr = CCCryptorReset(cryptor, segmentIV);
    if (cerr != kCCSuccess) {
        if (outError)
            *outError = wrapCCError(cerr, @"CCCryptorReset", nil, nil);
        return NO;
    }
    return YES;
}

/* There's no plausible reason for our bulk data encryption to fail--- there's no mallocing or anything variable happening in there. So just crash if any error is returned. */
static void cryptOrCrash(CCCryptorRef cryptor, const void *dataIn, size_t dataLength, void *dataOut, int lineno)
{
    
    /* The documentation says that the input and output buffers can be the same, but according to a March 2015 thread on the apple-cdsa list, the documentation is wrong. */
    OBASSERT(dataIn != dataOut);
    
    size_t actualAmountEncrypted = 0;
    CCCryptorStatus cerr = CCCryptorUpdate(cryptor,
                                           dataIn, dataLength,
                                           dataOut, dataLength,
                                           &actualAmountEncrypted);
    if (cerr != kCCSuccess) {
        NSLog(@"Unexpected CCCryptorUpdate failure: code=%" PRId32 ", line %d", cerr, lineno);
        abort();
    }
    if (actualAmountEncrypted != dataLength) {
        NSLog(@"Unexpected CCCryptorUpdate failure: line %d, expected %zu bytes moved, got %zu", lineno, dataLength, actualAmountEncrypted);
        abort();
    }
}

#pragma mark RADAR workarounds

/* RADAR 18222014 (which has been closed as a dup of 12680772) is that CCCryptorReset() just plain does nothing for a CTR-mode cryptor. */
static void testRADAR18222014(void *dummy)
{
    _Static_assert(kCCKeySizeAES128 == kCCBlockSizeAES128, "");
    static const uint8_t v[kCCKeySizeAES128] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    static const uint8_t expected[12] = { 148, 88, 198, 83, 234, 90, 2, 99, 236, 148, 102, 24 };
    uint8_t buf[4 * kCCBlockSizeAES128];
    uint8_t zbuf[2 * kCCBlockSizeAES128];
    
    CCCryptorRef c = createCryptor(v, v, NULL);
    if (!c) {
        /* ???? */
        return;
    }
    
    memset(buf, 0, sizeof(buf));
    memset(zbuf, 0, sizeof(zbuf));
    cryptOrCrash(c, zbuf, 2 * kCCBlockSizeAES128, buf, __LINE__);
    
    if (memcmp(buf+10, expected, 12) != 0) {
        NSLog(@"AES self-test failure");
        abort();
    }
    
    CCCryptorStatus cerr = CCCryptorReset(c, v);
    if (cerr != kCCSuccess) {
        /* Shouldn't be possible for this to fail */
        NSLog(@"CCCryptorReset() returns %ld", (long)cerr);
        CCCryptorRelease(c);
        canResetCTRIV = NO;
        return;
    }
    
    cryptOrCrash(c, zbuf, 2 * kCCBlockSizeAES128, buf + 2 * kCCBlockSizeAES128, __LINE__);
    CCCryptorRelease(c);
    
    if (!memcmp(buf, buf + 2 * kCCBlockSizeAES128, 2 * kCCBlockSizeAES128)) {
        /* Everything looks good! */
        canResetCTRIV = YES;
    } else {
        NSLog(@"Working around RADAR 12680772 and 18222014 - performance may suffer");
        canResetCTRIV = NO;
    }
}

