// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>
#import "OFTestCase.h"
#import "ODAVTestServer.h"
#import <XCTest/XCTest.h>

#import <OmniFileStore/OFSDocumentKey.h>
#import <OmniFileStore/OFSSegmentedEncryptionWorker.h>
#import <OmniFileStore/OFSSegmentedEncryptionProviderAcceptor.h>
#import <OmniFileStore/OFSFileByteAcceptor.h>
#import <OmniFileStore/OFSEncryptionConstants.h>
#import <OmniFileStore/Errors.h>

#import <OmniFileStore/OFSFileManager.h>
#import <OmniFileStore/OFSEncryptingFileManager.h>
#import <OmniDAV/ODAVFileInfo.h>


RCS_ID("$Id$");

#define ENCRYPTION_FILE @"encrypted"

@interface OFSEncryptionTests : XCTestCase
@end

@interface OFSEncryptedDAVTests : XCTestCase <OFSFileManagerDelegate>
@end

@implementation OFSEncryptionTests

#if 0
- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}
#endif

static const char *thing1 = "Thing one.\n";
static const char *thing2 = "Thing two...\n";
static const char *thing3 = "Thing three\n";

- (void)writeThings:(NSObject <OFByteAcceptor> *)writer;
{
    [writer setLength:strlen(thing1) + strlen(thing2) + strlen(thing3)];
    [writer replaceBytesInRange:(NSRange){0, strlen(thing1)} withBytes:thing1];
    [writer replaceBytesInRange:(NSRange){strlen(thing1) + strlen(thing2), strlen(thing3)} withBytes:thing3];
    [writer replaceBytesInRange:(NSRange){strlen(thing1), strlen(thing2)} withBytes:thing2];
    
    if ([writer respondsToSelector:@selector(error)]) {
        XCTAssertNotNil([writer error]);
    }
}

- (void)readThings:(NSObject <OFByteProvider> *)reader;
{
    char buf[1024];

    XCTAssertEqual([reader length], strlen(thing1) + strlen(thing2) + strlen(thing3));
    
    NSMutableData *expected = [NSMutableData dataWithBytes:thing1 length:strlen(thing1)];
    memset(buf, '*', sizeof(buf));
    [reader getBytes:buf range:(NSRange){ 0, strlen(thing1) }];
    XCTAssertEqualObjects([NSData dataWithBytes:buf length:strlen(thing1)], expected);
    
    expected = [NSMutableData dataWithBytes:thing2 length:strlen(thing2)];
    [expected appendBytes:thing3 length:strlen(thing3)];
    
    memset(buf, '*', sizeof(buf));
    [reader getBytes:buf range:(NSRange){ strlen(thing1), strlen(thing2)+strlen(thing3) }];
    XCTAssertEqualObjects([NSData dataWithBytes:buf length:strlen(thing2)+strlen(thing3)], expected);
}

/* Test the encryptor against a simple NSMutableData. This only writes a small amount of data and reads it back. */
- (void)test1
{
    NSError * __autoreleasing error;
    
    OFSDocumentKey *docKey;
    
    OBShouldNotError(docKey = [[OFSDocumentKey alloc] initWithData:nil error:&error]);
    [docKey discardKeysExceptSlots:nil retireCurrent:YES generate:SlotTypeActiveAES_CTR_HMAC];
    
    NSMutableData *backing = [NSMutableData data];
    size_t prefixLen;
    
    {
        OFSSegmentEncryptWorker *cryptWorker = [docKey encryptionWorker];
        
        XCTAssertNotNil(cryptWorker.wrappedKey);
        
        [backing appendData:cryptWorker.wrappedKey];
        prefixLen = [backing length];
        
        OFSSegmentEncryptingByteAcceptor *writer = [[OFSSegmentEncryptingByteAcceptor alloc] initWithByteAcceptor:backing cryptor:cryptWorker offset:prefixLen];
        [self writeThings:writer];
        [writer flushByteAcceptor];
        
//        XCTAssertNotNil([writer error]);
    }
    
   // NSLog(@"Encrypted data is %@", backing);
    
    {
        OFSSegmentDecryptingByteProvider *reader;
        
        OBShouldNotError(reader = [[OFSSegmentDecryptingByteProvider alloc] initWithByteProvider:backing range:((NSRange){ prefixLen, [backing length] - prefixLen }) error:&error]);
        OBShouldNotError([reader unwrapKey:((NSRange){0, prefixLen}) using:docKey error:&error]);
        XCTAssertTrue([reader verifyFileMAC]);
        [self readThings:reader];
    }
}

/* Same as -test1, but uses a file as the backing store */
- (void)test2
{
    NSError * __autoreleasing error;
    
    OFSDocumentKey *docKey;
    
    OBShouldNotError(docKey = [[OFSDocumentKey alloc] initWithData:nil error:&error]);
    [docKey discardKeysExceptSlots:nil retireCurrent:YES generate:SlotTypeActiveAESWRAP];
    
    
    NSString *fpath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"OFSEncryptionTests-test2"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    size_t prefixLen;
    
    {
        int fd = open([fm fileSystemRepresentationWithPath:fpath], O_RDWR|O_CREAT, 0666);
        OFSFileByteAcceptor *backing = [[OFSFileByteAcceptor alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
        
        OFSSegmentEncryptWorker *cryptWorker = [docKey encryptionWorker];
        NSData *blob = cryptWorker.wrappedKey;
        XCTAssertNotNil(blob);
        
        [backing setLength:[blob length]];
        [backing replaceBytesInRange:(NSRange){0, [blob length]} withBytes:[blob bytes]];

        prefixLen = [backing length];
        XCTAssertEqual(prefixLen, [blob length]);
        
        OFSSegmentEncryptingByteAcceptor *writer = [[OFSSegmentEncryptingByteAcceptor alloc] initWithByteAcceptor:backing cryptor:cryptWorker offset:prefixLen];
        [self writeThings:writer];
        [writer flushByteAcceptor];
        
        [backing flushByteAcceptor];
        
        //        XCTAssertNotNil([writer error]);
    }
    
    // NSLog(@"Encrypted data is %@", backing);
    
    {
        OFSSegmentDecryptingByteProvider *reader;

        int fd = open([fm fileSystemRepresentationWithPath:fpath], O_RDONLY);
        OFSFileByteAcceptor *backing = [[OFSFileByteAcceptor alloc] initWithFileDescriptor:fd closeOnDealloc:YES];

        OBShouldNotError(reader = [[OFSSegmentDecryptingByteProvider alloc] initWithByteProvider:backing range:((NSRange){ prefixLen, [backing length] - prefixLen }) error:&error]);
        OBShouldNotError([reader unwrapKey:((NSRange){0, prefixLen}) using:docKey error:&error]);
        
        XCTAssertTrue([reader verifyFileMAC]);
        
        [self readThings:reader];
    }
}

static char *generateLongBlob(const char *ident, NSRange r)
{
    OBASSERT(r.length % 2 == 0);
    char *buffer = malloc(r.length);
    unsigned char mdbuffer[ CC_SHA256_DIGEST_LENGTH ];
    
    size_t sl = strlen(ident);
    
    CC_SHA256(ident, (CC_LONG)strlen(ident), mdbuffer);
    static const char hex[16]={48,49,50,51,52,53,54,55,56,57,97,98,99,100,101,102};
    for (size_t i = 0, j = 0; i < r.length; i+=2) {
        unsigned char c = mdbuffer[j];
        buffer[i+0] = hex[ (c & 0xF0) >> 4 ];
        buffer[i+1] = hex[ (c & 0x0F)      ];
        j = ( j + 1 ) % CC_SHA256_DIGEST_LENGTH;
    }
    
    memcpy(buffer, ident, sl);
    buffer[sl] = '>';
    memcpy(buffer + r.length - sl, ident, sl);
    buffer[r.length - sl - 1] = '<';
    
    return buffer;
}

static void writeLongBlob(NSObject <OFByteAcceptor> *writer, const char *ident, NSRange r)
{
    char *buffer = generateLongBlob(ident, r);
    [writer replaceBytesInRange:r withBytes:buffer];
    free(buffer);
}


static BOOL checkLongBlob(const char *ident, NSRange blobR, const char *found, NSRange bufR)
{
    char *expected = generateLongBlob(ident, blobR);
    size_t expectedOffset, foundOffset, overlap;
    
    if (blobR.location < bufR.location) {
        expectedOffset = bufR.location - blobR.location;
        foundOffset = 0;
        overlap = MIN(bufR.length, blobR.length - expectedOffset);
    } else {
        expectedOffset = 0;
        foundOffset = blobR.location - bufR.location;
        overlap = MIN(bufR.length - foundOffset, blobR.length);
    }

    BOOL ok = ( memcmp(expected + expectedOffset, found + foundOffset, overlap) == 0 );
    
    free(expected);
    
    return ok;
}

- (void)test2Large
{
    NSError * __autoreleasing error;
    
    OFSDocumentKey *docKey;
    
    OBShouldNotError(docKey = [[OFSDocumentKey alloc] initWithData:nil error:&error]);
    [docKey discardKeysExceptSlots:nil retireCurrent:YES generate:SlotTypeActiveAES_CTR_HMAC];
    
    
    NSString *fpath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"OFSEncryptionTests-test2Large"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    size_t prefixLen;
    
    {
        int fd = open([fm fileSystemRepresentationWithPath:fpath], O_RDWR|O_CREAT, 0666);
        OFSFileByteAcceptor *backing = [[OFSFileByteAcceptor alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
        
        OFSSegmentEncryptWorker *cryptWorker = [docKey encryptionWorker];
        NSData *blob = cryptWorker.wrappedKey;
        
        prefixLen = [blob length];
        [backing setLength:prefixLen];
        [backing replaceBytesInRange:(NSRange){0, prefixLen} withBytes:[blob bytes]];
        
        OFSSegmentEncryptingByteAcceptor *writer = [[OFSSegmentEncryptingByteAcceptor alloc] initWithByteAcceptor:backing cryptor:cryptWorker offset:prefixLen];
        [writer setLength:64*1024];
        writeLongBlob(writer, "ONE",   (NSRange){0,        64*1024});
        [writer setLength:200*1024];
        writeLongBlob(writer, "TWO",   (NSRange){60*1024, 140*1024});
        writeLongBlob(writer, "THREE", (NSRange){100*1024, 28*1024});
        
        [writer flushByteAcceptor];
        
        [backing flushByteAcceptor];
        
        // XCTAssertNotNil([writer error]);
    }
    
    NSLog(@"Wrote to: %@", fpath);
    
    {
        OFSSegmentDecryptingByteProvider *reader;
        
        int fd = open([fm fileSystemRepresentationWithPath:fpath], O_RDONLY);
        OFSFileByteAcceptor *backing = [[OFSFileByteAcceptor alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
        
        OBShouldNotError(reader = [[OFSSegmentDecryptingByteProvider alloc] initWithByteProvider:backing range:((NSRange){ prefixLen, [backing length] - prefixLen }) error:&error]);
        OBShouldNotError([reader unwrapKey:((NSRange){0, prefixLen}) using:docKey error:&error]);

        XCTAssertTrue([reader verifyFileMAC]);
        
        char *rbuffer = malloc(160*1024);
        memset(rbuffer, '*', 160*1024);
        [reader getBytes:rbuffer range:(NSRange){0, 1024}];
        XCTAssert(checkLongBlob("ONE", (NSRange){0, 64*1024}, rbuffer, (NSRange){0, 1024}));
        memset(rbuffer, '*', 160*1024);
        [reader getBytes:rbuffer range:(NSRange){1024, 129*1024}];
        XCTAssert(checkLongBlob("ONE", (NSRange){0, 64*1024}, rbuffer, (NSRange){1024, 59*1024}));
        XCTAssert(checkLongBlob("THREE", (NSRange){100*1024, 28*1024}, rbuffer, (NSRange){1024, 129*1024}));
        XCTAssert(checkLongBlob("TWO", (NSRange){60*1024, 140*1024}, rbuffer, (NSRange){1024, 99*1024}));
        memset(rbuffer, '*', 160*1024);
        [reader getBytes:rbuffer range:(NSRange){40*1024, 160*1024}];
        XCTAssert(checkLongBlob("THREE", (NSRange){100*1024, 28*1024}, rbuffer, (NSRange){40*1024, 160*1024}));
        XCTAssert(checkLongBlob("TWO", (NSRange){60*1024, 140*1024}, rbuffer + (128-40)*1024, (NSRange){128*1024, 72*1024}));
        free(rbuffer);
    }
    
}

static void wrXY(char *into, int x, int y)
{
    sprintf(into, "%d.%d", x, y);
    memset(into + strlen(into), ' ', 10 - strlen(into));
    into[9] = '\n';
}

- (void)test3Large
{
    NSError * __autoreleasing error;
    
    OFSDocumentKey *docKey;
    
    OBShouldNotError(docKey = [[OFSDocumentKey alloc] initWithData:nil error:&error]);
    [docKey discardKeysExceptSlots:nil retireCurrent:YES generate:SlotTypeActiveAES_CTR_HMAC];
    
    
    NSString *fpath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"OFSEncryptionTests-test3Large"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    size_t prefixLen;
    ;
    
    {
        int fd = open([fm fileSystemRepresentationWithPath:fpath], O_RDWR|O_CREAT, 0666);
        OFSFileByteAcceptor *backing = [[OFSFileByteAcceptor alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
        
        OFSSegmentEncryptWorker *cryptWorker = [docKey encryptionWorker];
        NSData *blob = cryptWorker.wrappedKey;
        
        prefixLen = [blob length];
        [backing setLength:prefixLen];
        [backing replaceBytesInRange:(NSRange){0, prefixLen} withBytes:[blob bytes]];
        
        OFSSegmentEncryptingByteAcceptor *writer = [[OFSSegmentEncryptingByteAcceptor alloc] initWithByteAcceptor:backing cryptor:cryptWorker offset:prefixLen];
        
        char *buf = malloc(5000);
        for(int i = 0; i < 5000; i++) {
            [writer setLength:(i+1) * 5000];
            for (int j = 0; j < 500; j++) {
                wrXY(buf + j*10, i, j);
            }
            [writer replaceBytesInRange:(NSRange){i*5000, 5000} withBytes:buf];
        }
        free(buf);
        
        [writer flushByteAcceptor];
        [backing flushByteAcceptor];
        
        // XCTAssertNotNil([writer error]);
    }
    
    NSLog(@"Wrote to: %@", fpath);
    
    {
        OFSSegmentDecryptingByteProvider *reader;
        
        int fd = open([fm fileSystemRepresentationWithPath:fpath], O_RDONLY);
        OFSFileByteAcceptor *backing = [[OFSFileByteAcceptor alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
        
        OBShouldNotError(reader = [[OFSSegmentDecryptingByteProvider alloc] initWithByteProvider:backing range:((NSRange){ prefixLen, [backing length] - prefixLen }) error:&error]);
        OBShouldNotError([reader unwrapKey:((NSRange){0, prefixLen}) using:docKey error:&error]);

        XCTAssertTrue([reader verifyFileMAC]);
        
        char *rbuffer = malloc(10000);
        OFRandomState *rnd = OFRandomStateCreate();
        
        for(int i = 0; i < 20000; i++) {
            int p = OFRandomNextStateN(rnd, (5000*5000)-10000);
            [reader getBytes:rbuffer range:(NSRange){ p, 10000 }];
            char buf[10];
            int pmod = p % 10;
            for(int o = p / 10; o <= (p+10000)/10; o++) {
                wrXY(buf, o / 500, o % 500);
                int offs = (o * 10) - p;
                if (offs < 0) {
                    XCTAssert(-offs == pmod);
                    XCTAssert(!memcmp(rbuffer, buf-offs, 10+offs));
                } else if (offs+10 > 10000) {
                    XCTAssert(!memcmp(rbuffer + offs, buf, 10000-offs));
                } else {
                    XCTAssert(!memcmp(rbuffer + offs, buf, 10));
                }
            }
        }
        
        OFRandomStateDestroy(rnd);
        free(rbuffer);
    }
    
}

- (void)testOneShotSmall
{
    NSError * __autoreleasing error = nil;
    
    OFSDocumentKey *docKey, *otherDocKey;
    OFSSegmentDecryptWorker *decryptor;
    size_t offset = 0;
    
    OBShouldNotError(docKey = [[OFSDocumentKey alloc] initWithData:nil error:&error]);
    [docKey discardKeysExceptSlots:nil retireCurrent:NO generate:SlotTypeActiveAESWRAP];
    
    OBShouldNotError(otherDocKey = [[OFSDocumentKey alloc] initWithData:nil error:&error]);
    [otherDocKey discardKeysExceptSlots:nil retireCurrent:NO generate:SlotTypeActiveAESWRAP];
    
    for (int whichCiphertext = 0; whichCiphertext < 3; whichCiphertext ++) {
        NSData *plaintext, *ciphertext, *decrypted;
        
        switch (whichCiphertext) {
            case 0:
                plaintext = [NSData data];
                break;
            case 1:
                plaintext = [@"This is my super secret message! Remember to drink your squeamish ossifrage, kids! And stay in school!" dataUsingEncoding:NSASCIIStringEncoding];
                break;
            case 2:
                plaintext = [NSData dataWithBytes:"?" length:1];
                break;
        }
        
        OBShouldNotError(ciphertext = [docKey.encryptionWorker encryptData:plaintext error:&error]);
        
        // Assert that encryption grew the ciphertext by a reasonable amount. We have two 128-bit session keys, a 96-bit IV, a 160-bit segment MAC, and a 256-bit file MAC: 96 bytes. There's also the magic number, key diversification, and padding overhead.
        XCTAssertGreaterThanOrEqual([ciphertext length], [plaintext length] + 96);
        
        // We should be able to decrypt the ciphertext.
        offset = 0;
        OBShouldNotError(decryptor = [OFSSegmentDecryptWorker decryptorForData:ciphertext key:docKey dataOffset:&offset error:&error]);
        OBShouldNotError(decrypted = [decryptor decryptData:ciphertext dataOffset:offset error:&error]);
        XCTAssertEqualObjects(plaintext, decrypted);
        
        // No byte should be changeable and still allow decryption to succeed.
        for (size_t ix = 0; ix <= [ciphertext length]; ix ++) {
            NSMutableData *damagedCiphertext = [ciphertext mutableCopy];
            if (ix < [ciphertext length]) {
                uint8_t *p = [damagedCiphertext mutableBytes];
                p[ix] ^= 0x02;
            } else {
                [damagedCiphertext appendBytes:"\x00" length:1];
            }
            
            offset = 0;
            error = nil;
            decryptor = [OFSSegmentDecryptWorker decryptorForData:damagedCiphertext key:docKey dataOffset:&offset error:&error];
            decrypted = decryptor? [decryptor decryptData:damagedCiphertext dataOffset:offset error:&error] : nil;
            XCTAssertNil(decrypted, @"Decryption should fail: damage at index %zu undetected", ix);
            decryptor = nil;
        }
        
        // Also verify failure when decrypting with a different document key
        offset = 0;
        decryptor = [OFSSegmentDecryptWorker decryptorForData:ciphertext key:otherDocKey dataOffset:&offset error:&error];
        decrypted = decryptor? [decryptor decryptData:ciphertext dataOffset:offset error:&error] : nil;
        XCTAssertNil(decrypted, @"Decryption should fail: wrong key");
    }
}



- (void)testOneShotMed
{
    /* This test is similar to -testOneShotSmall, but makes sure we have correct behavior near the edges of segment boundaries. */
    NSError * __autoreleasing error = nil;
    
    OFSDocumentKey *docKey;
    
    OBShouldNotError(docKey = [[OFSDocumentKey alloc] initWithData:nil error:&error]);
    [docKey discardKeysExceptSlots:nil retireCurrent:YES generate:SlotTypeActiveAESWRAP];
    

    for (unsigned  npages = 1; npages < 4; npages ++) {
        size_t previousCiphertextLength = 0;
        int sizeJumps = 0;
        for (int delta = -2; delta < 3; delta ++) {
            size_t plaintextLength = ( SEGMENTED_PAGE_SIZE * npages ) + delta;
            
            NSData *plaintext = OFRandomCreateDataOfLength(plaintextLength);
            NSData *ciphertext, *decrypted;

            OBShouldNotError(ciphertext = [docKey.encryptionWorker encryptData:plaintext error:&error]);
            XCTAssertGreaterThanOrEqual([ciphertext length], [plaintext length] + 96);
            
            if (previousCiphertextLength != 0) {
                NSInteger growth = [ciphertext length] - previousCiphertextLength;
                XCTAssertGreaterThanOrEqual(growth, 1);
                if (growth > 1)
                    sizeJumps ++;
            }
            
            // We should be able to decrypt the ciphertext.
            OFSSegmentDecryptWorker *decryptor;
            size_t offset = 0;
            OBShouldNotError(decryptor = [OFSSegmentDecryptWorker decryptorForData:ciphertext key:docKey dataOffset:&offset error:&error]);
            OBShouldNotError(decrypted = [decryptor decryptData:ciphertext dataOffset:offset error:&error]);
            XCTAssertEqualObjects(plaintext, decrypted);
            
            previousCiphertextLength = [ciphertext length];
        }
        
        XCTAssertEqual(sizeJumps, 1);  /* Make sure we did actually cross a segment-number boundary */
    }
}

- (void)testRollover
{
    OFSDocumentKey *docKey, *intermediateDocKey, *otherDocKey, *futureDocKey;
    NSData *intermediateData = nil;
    NSIndexSet *intermediateIndices;
    NSError * __autoreleasing error = nil;
    NSString *passwd = @"pass blah";
    const char *sekrit = "DOOMDOOMDOOMDOOM";
    
    OBShouldNotError(docKey = [[OFSDocumentKey alloc] initWithData:nil error:&error]);
    [docKey discardKeysExceptSlots:nil retireCurrent:YES generate:SlotTypeActiveAESWRAP];

    OBShouldNotError([docKey setPassword:passwd error:&error]);
    
    /* Generate a bunch of wrapped keys, keeping track of the slot numbers they have */
    NSMutableArray *keyblobs = [NSMutableArray array];
    NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];
    NSInteger docKeyChangecount = [docKey changeCount];
    for(int i = 0; i < 25; i ++) {
        for(int j = 0; j < 2; j++) {
            NSData *kb;
            OBShouldNotError(kb = [docKey wrapFileKey:(const void *)sekrit length:16 error:&error]);
            [keyblobs addObject:kb];
            uint16_t theIndex = OSReadBigInt16([kb bytes], 0);
            if (j == 0) {
                XCTAssertFalse([indices containsIndex:theIndex]);
                [indices addIndex:theIndex];
            } else {
                XCTAssertTrue([indices containsIndex:theIndex]);
            }
        }
        
        if (i == 10) {
            intermediateData = [docKey data];
            intermediateIndices = [indices copy];
        }
        
        XCTAssertEqual(docKeyChangecount, [docKey changeCount]);
        [docKey discardKeysExceptSlots:indices retireCurrent:YES generate:SlotTypeActiveAESWRAP];
        XCTAssertNotEqual(docKeyChangecount, [docKey changeCount]);
        docKeyChangecount = [docKey changeCount];
    }
    
    XCTAssertNotNil(intermediateData);
    
    /* Verify that the wrapped keys can all be unwrapped by a doc key restored from saved state, but that a doc key restored from an earlier state can only unwrap the keys it should be able to unwrap */
    OBShouldNotError(otherDocKey = [[OFSDocumentKey alloc] initWithData:[docKey data] error:&error]);
    OBShouldNotError([otherDocKey deriveWithPassword:passwd error:&error]);
    OBShouldNotError(intermediateDocKey = [[OFSDocumentKey alloc] initWithData:intermediateData error:&error]);
    OBShouldNotError([intermediateDocKey deriveWithPassword:passwd error:&error]);
    for(NSData *kb in keyblobs) {
        uint16_t thisBlobIndex = OSReadBigInt16([kb bytes], 0);
        uint8_t obuf[32];
        ssize_t unw;
        
        /* Should succeed */
        memset(obuf, '*', 32);
        error = nil;
        unw = [otherDocKey unwrapFileKey:[kb bytes] length:[kb length] into:obuf length:sizeof(obuf) error:&error];
        XCTAssertTrue(unw == 16, @"outError = %@", error);
        if (unw != 16)
            break;
        XCTAssertTrue(memcmp(obuf, sekrit, 16) == 0);
        
        /* Should succeed */
        memset(obuf, '*', 32);
        error = nil;
        unw = [docKey unwrapFileKey:[kb bytes] length:[kb length] into:obuf length:sizeof(obuf) error:&error];
        XCTAssertTrue(unw == 16, @"outError = %@", error);
        if (unw != 16)
            break;
        XCTAssertTrue(memcmp(obuf, sekrit, 16) == 0);

        /* May succeed or fail */
        memset(obuf, '*', 32);
        error = nil;
        unw = [intermediateDocKey unwrapFileKey:[kb bytes] length:[kb length] into:obuf length:sizeof(obuf) error:&error];
        if ([intermediateIndices containsIndex:thisBlobIndex]) {
            XCTAssertTrue(unw == 16, @"outError = %@", error);
            if (unw != 16)
                break;
            XCTAssertTrue(memcmp(obuf, sekrit, 16) == 0);
        } else {
            XCTAssertTrue(unw < 0);
            if (unw < 0) {
                XCTAssertTrue([[error domain] isEqualToString:OFSErrorDomain] && [error code] == OFSEncryptionNeedAuth,
                              @"outError = %@", error);
            }
        }
    }
    
    /* And generate a doc key in The Future sometime with some garbage-collected keys */
    NSMutableIndexSet *keptSlots = [NSMutableIndexSet indexSet];
    [indices enumerateIndexesUsingBlock:^(NSUInteger keyslot, BOOL *stop){
        if (OFRandomNext32() % 3 == 0) {
            [keptSlots addIndex:keyslot];
        }
    }];
    
    /* Check that behavior */
    XCTAssertEqual(docKeyChangecount, [docKey changeCount]);
    [docKey discardKeysExceptSlots:keptSlots retireCurrent:NO generate:SlotTypeNone];
    XCTAssertNotEqual(docKeyChangecount, [docKey changeCount]);
    docKeyChangecount = [docKey changeCount];
    
    OBShouldNotError(futureDocKey = [[OFSDocumentKey alloc] initWithData:[docKey data] error:&error]);
    OBShouldNotError([futureDocKey deriveWithPassword:passwd error:&error]);
    XCTAssertEqual(0, [futureDocKey changeCount]);
    for(NSData *kb in keyblobs) {
        uint16_t thisBlobIndex = OSReadBigInt16([kb bytes], 0);
        uint8_t obuf[32];
        ssize_t unw;
        
        memset(obuf, '*', 32);
        error = nil;
        unw = [docKey unwrapFileKey:[kb bytes] length:[kb length] into:obuf length:sizeof(obuf) error:&error];
        if ([keptSlots containsIndex:thisBlobIndex]) {
            /* Should succeed */
            XCTAssertTrue(unw == 16, @"outError = %@", error);
            if (unw != 16)
                break;
            XCTAssertTrue(memcmp(obuf, sekrit, 16) == 0);
        } else {
            /* Should fail */
            XCTAssertTrue(unw < 0);
            if (unw < 0) {
                XCTAssertTrue([[error domain] isEqualToString:OFSErrorDomain] && [error code] == OFSEncryptionNeedAuth,
                              @"outError = %@", error);
            }
        }
        
        memset(obuf, '*', 32);
        error = nil;
        unw = [futureDocKey unwrapFileKey:[kb bytes] length:[kb length] into:obuf length:sizeof(obuf) error:&error];
        if ([keptSlots containsIndex:thisBlobIndex]) {
            /* Should succeed */
            XCTAssertTrue(unw == 16, @"outError = %@", error);
            if (unw != 16)
                break;
            XCTAssertTrue(memcmp(obuf, sekrit, 16) == 0);
        } else {
            /* Should fail */
            XCTAssertTrue(unw < 0);
            if (unw < 0) {
                XCTAssertTrue([[error domain] isEqualToString:OFSErrorDomain] && [error code] == OFSEncryptionNeedAuth,
                              @"outError = %@", error);
            }
        }
    }
}

@end

@implementation OFSEncryptedDAVTests

static ODAVTestServer *srv;

+ (void)setUp;
{
    if (srv && !(srv.process.running)) {
        [srv stop];
        srv = nil;
    }
    
    if (!srv) {
        srv = [[ODAVTestServer alloc] init];
        NSMutableString *configfile = [NSMutableString stringWithContentsOfURL:[[NSBundle bundleForClass:[OFSEncryptedDAVTests class]] URLForResource:@"template-simpledav" withExtension:@"conf"] encoding:NSUTF8StringEncoding error:NULL];
        
        [srv startWithConfiguration:[configfile stringByReplacingKeysInDictionary:[srv substitutions]
                                                                startingDelimiter:@"$("
                                                                  endingDelimiter:@")"]];
    }
}

+ (void)tearDown;
{
    [srv stop];
    srv = nil;
}

- (NSString *)password
{
    return @"password";
}

- (OFSFileManager *)emptyTestDirectory;
{
    NSError * __autoreleasing error;
    NSURL *baseURL = srv.baseURL;
    OFSFileManager *baseFm = [[OFSFileManager alloc] initWithBaseURL:baseURL delegate:self error:&error];
    if (!baseFm) {
        XCTFail(@"Could not create file manager for base url: %@ error: %@", baseURL, error);
        return nil;
    }
    
    NSURL *testBaseURL = [baseURL URLByAppendingPathComponent:NSStringFromSelector(self.invocation.selector)];
    
    ODAVFileInfo *dirstat = [baseFm fileInfoAtURL:testBaseURL error:&error];
    if (!dirstat) {
        XCTFail(@"Could not check for pre-existence of url %@: error=%@", testBaseURL, error);
    } else if (dirstat.exists) {
        NSLog(@"Removing old item at %@", testBaseURL);
        BOOL did = [baseFm deleteURL:dirstat.originalURL error:&error];
        if (!did) {
            NSLog(@"Warning: could not remove old item: %@", error);
        }
    }
    
    NSURL *made = [baseFm createDirectoryAtURL:testBaseURL attributes:nil error:&error];
    if (!made) {
        XCTFail(@"Could not create directory: %@ error: %@", baseURL, error);
        return nil;
    }
    
    OFSFileManager *fm = [[OFSFileManager alloc] initWithBaseURL:made delegate:self error:&error];
    if (!fm) {
        XCTFail(@"Could not create file manager for test directory url: %@ error: %@", made, error);
    }
    
    return fm;
}

- (OFSEncryptingFileManager *)initializedWrapper:(OFSFileManager *)fm
{
    OFSDocumentKey *keys = [[OFSDocumentKey alloc] initWithData:nil error:NULL];
    [keys discardKeysExceptSlots:nil retireCurrent:NO generate:SlotTypeActiveAES_CTR_HMAC];
    if (![keys setPassword:self.password error:NULL]) {
        XCTFail(@"Could not generate document key");
        return nil;
    }
    
    NSError * __autoreleasing error;
    
    if (![fm writeData:[keys data] toURL:[fm.baseURL URLByAppendingPathComponent:ENCRYPTION_FILE] atomically:NO error:&error]) {
        XCTFail(@"Could not store initial keyblob");
    }
    
    OFSEncryptingFileManager *efm = [[OFSEncryptingFileManager alloc] initWithFileManager:fm keyStore:keys error:&error];
    if (!efm) {
        XCTFail(@"Could not create OFSEncryptingFileManager: %@", error);
        return nil;
    }
    
    return efm;
}

- (OFSEncryptingFileManager *)openedWrapper:(OFSFileManager *)fm
{
    NSError * __autoreleasing error;
    NSURL *blobURL = [fm.baseURL URLByAppendingPathComponent:ENCRYPTION_FILE];
    NSData *kmblob = [fm dataWithContentsOfURL:blobURL error:&error];
    if (!kmblob) {
        XCTFail(@"Could not read key management info from %@", blobURL);
        return nil;
    }
    
    OFSDocumentKey *keys = [[OFSDocumentKey alloc] initWithData:kmblob error:&error];
    if (!keys) {
        XCTFail(@"Could not parse key management info: %@", error);
        return nil;
    }
    
    if (![keys deriveWithPassword:[self password] error:&error]) {
        XCTFail(@"Could not decrypt key management info: %@", error);
        return nil;
    }
    
    OFSEncryptingFileManager *efm = [[OFSEncryptingFileManager alloc] initWithFileManager:fm keyStore:keys error:&error];
    if (!efm) {
        XCTFail(@"Could not create OFSEncryptingFileManager: %@", error);
        return nil;
    }

    return efm;
}

- (void)testSimple;
{
    OFSFileManager *fm = [self emptyTestDirectory];
    if (!fm)
        return;
    
    OFSEncryptingFileManager *efm = [self initializedWrapper:fm];
    if (!efm)
        return;
    
    NSError * __autoreleasing error;
    NSArray <ODAVFileInfo *> *infos;
    NSData *testData1 = [@"Some test text." dataUsingEncoding:NSUTF8StringEncoding];
    NSData *roundtrip;
    
    OBShouldNotError(infos = [efm directoryContentsAtURL:efm.baseURL collectingRedirects:nil error:&error]);
    XCTAssertEqual([infos count], (NSUInteger)1);
    
    OBShouldNotError([efm writeData:testData1 toURL:[efm.baseURL URLByAppendingPathComponent:@"test1"] atomically:NO error:&error]);
    
    OBShouldNotError(roundtrip = [efm dataWithContentsOfURL:[efm.baseURL URLByAppendingPathComponent:@"test1"] error:&error]);
    XCTAssertEqualObjects(testData1, roundtrip);
    
    OFSEncryptingFileManager *rfm = [self openedWrapper:fm];
    XCTAssertEqualObjects(efm.keyStore.keySlots, rfm.keyStore.keySlots);
    
    OBShouldNotError(roundtrip = [rfm dataWithContentsOfURL:[efm.baseURL URLByAppendingPathComponent:@"test1"] error:&error]);
    XCTAssertEqualObjects(testData1, roundtrip);
    
    OBShouldNotError(infos = [rfm directoryContentsAtURL:rfm.baseURL collectingRedirects:nil error:&error]);
    XCTAssertEqual([infos count], (NSUInteger)2 /* One test file and the key-metadata file */);
    XCTAssertTrue([infos[0].name isEqualToString:@"test1"] || [infos[1].name isEqualToString:@"test1"]);
}

- (void)testTaste;
{
    OFSFileManager *fm = [self emptyTestDirectory];
    if (!fm)
        return;
    
    OFSEncryptingFileManager *efm = [self initializedWrapper:fm];
    if (!efm)
        return;
    
    NSError * __autoreleasing error;
    NSData *testData1 = [@"Some test text." dataUsingEncoding:NSUTF8StringEncoding];
    NSData *testData2 = [@"Some more test text — this is a little longer, right?\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *roundtrip;
    
    OBShouldNotError([efm writeData:testData1 toURL:[efm.baseURL URLByAppendingPathComponent:@"test1"] atomically:NO error:&error]);
    OBShouldNotError([efm writeData:testData2 toURL:[efm.baseURL URLByAppendingPathComponent:@"test2"] atomically:YES error:&error]);
    
    OBShouldNotError(roundtrip = [efm dataWithContentsOfURL:[efm.baseURL URLByAppendingPathComponent:@"test1"] error:&error]);
    XCTAssertEqualObjects(testData1, roundtrip);
    
    OBShouldNotError(roundtrip = [efm dataWithContentsOfURL:[efm.baseURL URLByAppendingPathComponent:@"test2"] error:&error]);
    XCTAssertEqualObjects(testData2, roundtrip);
    
    OFSEncryptingFileManager *rfm = [self openedWrapper:fm];
    NSIndexSet *activeKeys = efm.keyStore.keySlots;
    XCTAssertEqualObjects(activeKeys, rfm.keyStore.keySlots);
    XCTAssertEqual(activeKeys.count, (NSUInteger)1);
    NSInteger expectedKeySlot = [activeKeys firstIndex];
    
    OBShouldNotError(roundtrip = [rfm dataWithContentsOfURL:[efm.baseURL URLByAppendingPathComponent:@"test1"] error:&error]);
    XCTAssertEqualObjects(testData1, roundtrip);
    
    OBShouldNotError(roundtrip = [rfm dataWithContentsOfURL:[efm.baseURL URLByAppendingPathComponent:@"test2"] error:&error]);
    XCTAssertEqualObjects(testData2, roundtrip);
    
    NSArray *infos;
    OBShouldNotError(infos = [rfm directoryContentsAtURL:rfm.baseURL collectingRedirects:nil error:&error]);
    
    XCTAssertEqual([infos count], (NSUInteger)3 /* Two test files and the key-metadata file */);
    NSMutableArray *ops = [NSMutableArray array];
    for(ODAVFileInfo *inf in infos) {
        if ([inf.name isEqualToString:ENCRYPTION_FILE])
            continue;
        
        [ops addObject:[rfm asynchronouslyTasteKeySlot:inf]];
        [ops addObject:[efm asynchronouslyTasteKeySlot:inf]];
    }
    
    NSOperationQueue *opq = [[NSOperationQueue alloc] init];
    [opq addOperations:ops waitUntilFinished:NO];
    
    for (OFSEncryptingFileManagerTasteOperation *op in ops) {
        [op waitUntilFinished];
        NSLog(@" op %@: ks=%@ err=%@",
              [op shortDescription],
              [op valueForKey:@"keySlot"],
              [op valueForKey:@"error"]);
        XCTAssertNil(op.error);
        if (!op.error) {
            XCTAssertEqual(op.keySlot, expectedKeySlot);
        }
    }
}

- (void)testTastingLarge;
{
    OFSFileManager *fm = [self emptyTestDirectory];
    if (!fm)
        return;
    
    OFSEncryptingFileManager *efm = [self initializedWrapper:fm];
    if (!efm)
        return;
    
    NSError * __autoreleasing error;
    NSMutableData *testData1 = [NSMutableData dataWithCapacity:100000];
    for(int i = 0; i < 10000; i++) {
        [testData1 appendData:[[NSString stringWithFormat:@"%u: Some test text.\n", i] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    NSData *roundtrip;
    
    OBShouldNotError([efm writeData:testData1 toURL:[efm.baseURL URLByAppendingPathComponent:@"test1"] atomically:NO error:&error]);
    
    OBShouldNotError(roundtrip = [efm dataWithContentsOfURL:[efm.baseURL URLByAppendingPathComponent:@"test1"] error:&error]);
    XCTAssertEqualObjects(testData1, roundtrip);
    
    OFSEncryptingFileManager *rfm = [self openedWrapper:fm];
    NSIndexSet *activeKeys = efm.keyStore.keySlots;
    XCTAssertEqualObjects(activeKeys, rfm.keyStore.keySlots);
    NSArray *infos;
    OBShouldNotError(infos = [rfm directoryContentsAtURL:rfm.baseURL collectingRedirects:nil error:&error]);

    XCTAssertEqual(activeKeys.count, (NSUInteger)1);
    NSInteger expectedKeySlot = [activeKeys firstIndex];

    XCTAssertEqual([infos count], (NSUInteger)2 /* One test file and the key-metadata file */);
    NSMutableArray *ops = [NSMutableArray array];
    for(ODAVFileInfo *inf in infos) {
        if ([inf.name isEqualToString:ENCRYPTION_FILE])
            continue;
        
        [ops addObject:[rfm asynchronouslyTasteKeySlot:inf]];
        [ops addObject:[efm asynchronouslyTasteKeySlot:inf]];
    }
    
    NSOperationQueue *opq = [[NSOperationQueue alloc] init];
    [opq addOperations:ops waitUntilFinished:YES];
    
    for (OFSEncryptingFileManagerTasteOperation *op in ops) {
        NSLog(@" op %@: ks=%@ err=%@",
              [op shortDescription],
              [op valueForKey:@"keySlot"],
              [op valueForKey:@"error"]);
        XCTAssertNil(op.error);
        if (!op.error) {
            XCTAssertEqual(op.keySlot, expectedKeySlot);
        }
    }
}

@end


