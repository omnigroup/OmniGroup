// Copyright 2014-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSSegmentedEncryptionProviderAcceptor.h>

#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CoreFoundation/CoreFoundation.h>
#import <OmniFoundation/NSRange-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFByteProviderProtocol.h>
#import <OmniFileStore/OFSDocumentKey.h>
#import <OmniFileStore/OFSSegmentedEncryptionWorker.h>
#import <OmniFileStore/OFSEncryptionConstants.h>
#import "OFSEncryption-Internal.h"
#import <OmniFileStore/Errors.h>
#import <libkern/OSAtomic.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

static NSError *unsupportedError_(int lineno, NSString *detail) __attribute__((cold,unused));
#define unsupportedError(e, t) do{ if(e) { *(e) = unsupportedError_(__LINE__, t); } }while(0)

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
    __block NSError *strongError = nil;
    BOOL success = withBackingRange(_backingStore, wrappedBlob, ^(const uint8_t *buffer){
        NSData *wrappedKey = [NSData dataWithBytes:buffer length:wrappedBlob.length];
        __autoreleasing NSError *error = nil;
        ssize_t len = [unwrapper.keySlots unwrapFileKey:wrappedKey into:_keyMaterial length:sizeof(_keyMaterial) error:&error];
        if (len < 0) {
            strongError = error;
            return NO;
        }
        else if (len == sizeof(_keyMaterial)) {
            return YES;
        } else {
            unsupportedError(&error, @"Incorrect inner key version");
            strongError = error;
            return NO;
        }
    });

    if (!success && outError) {
        *outError = strongError;
    }
    return success;
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
            ctrDecryptor = createOrResetCryptor(NULL, segmentIV, _bulkKey, kCCKeySizeAES128, NULL);
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

- (NSUInteger)length;
{
    return _length;
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


