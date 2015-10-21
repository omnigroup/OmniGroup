// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>
#import "OFTestCase.h"
#import <XCTest/XCTest.h>

#import <OmniFileStore/OFSDocumentKey.h>
#import <OmniFileStore/OFSSegmentedEncryption.h>
#import <OmniFileStore/OFSFileByteAcceptor.h>

RCS_ID("$Id$");

@interface OFSEncryptionTests : XCTestCase

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
    [docKey reset];
    
    NSMutableData *backing = [NSMutableData data];
    size_t prefixLen;
    NSData *blob;
    
    {
        OFSSegmentEncryptWorker *cryptWorker = [docKey encryptionWorker];
        
        OBShouldNotError(blob = [cryptWorker wrappedKeyWithDocumentKey:docKey error:&error]);
        
        [backing appendData:blob];
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
    [docKey reset];
    
    
    NSString *fpath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"OFSEncryptionTests-test2"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    size_t prefixLen;
    NSData *blob;
    
    {
        int fd = open([fm fileSystemRepresentationWithPath:fpath], O_RDWR|O_CREAT, 0666);
        OFSFileByteAcceptor *backing = [[OFSFileByteAcceptor alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
        
        OFSSegmentEncryptWorker *cryptWorker = [docKey encryptionWorker];
        
        OBShouldNotError(blob = [cryptWorker wrappedKeyWithDocumentKey:docKey error:&error]);
        
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
    [docKey reset];
    
    
    NSString *fpath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"OFSEncryptionTests-test2Large"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    size_t prefixLen;
    NSData *blob;
    
    {
        int fd = open([fm fileSystemRepresentationWithPath:fpath], O_RDWR|O_CREAT, 0666);
        OFSFileByteAcceptor *backing = [[OFSFileByteAcceptor alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
        
        OFSSegmentEncryptWorker *cryptWorker = [docKey encryptionWorker];
        
        OBShouldNotError(blob = [cryptWorker wrappedKeyWithDocumentKey:docKey error:&error]);
        
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
    [docKey reset];
    
    
    NSString *fpath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"OFSEncryptionTests-test3Large"];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    size_t prefixLen;
    NSData *blob;
    
    {
        int fd = open([fm fileSystemRepresentationWithPath:fpath], O_RDWR|O_CREAT, 0666);
        OFSFileByteAcceptor *backing = [[OFSFileByteAcceptor alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
        
        OFSSegmentEncryptWorker *cryptWorker = [docKey encryptionWorker];
        
        OBShouldNotError(blob = [cryptWorker wrappedKeyWithDocumentKey:docKey error:&error]);
        
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
    
    OBShouldNotError(docKey = [[OFSDocumentKey alloc] initWithData:nil error:&error]);
    [docKey reset];
    
    OBShouldNotError(otherDocKey = [[OFSDocumentKey alloc] initWithData:nil error:&error]);
    [otherDocKey reset];
    
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
        
        OBShouldNotError(ciphertext = [OFSSegmentEncryptWorker encryptData:plaintext withKey:docKey error:&error]);
        
        // Assert that encryption grew the ciphertext by a reasonable amount. We have two 128-bit session keys, a 96-bit IV, a 160-bit segment MAC, and a 256-bit file MAC: 96 bytes. There's also the magic number, key diversification, and padding overhead.
        XCTAssertGreaterThanOrEqual([ciphertext length], [plaintext length] + 96);
        
        // We should be able to decrypt the ciphertext.
        OBShouldNotError(decrypted = [OFSSegmentEncryptWorker decryptData:ciphertext withKey:docKey error:&error]);
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
            
            error = nil;
            decrypted = [OFSSegmentEncryptWorker decryptData:damagedCiphertext withKey:docKey error:&error];
            XCTAssertNil(decrypted, @"Decryption should fail: damage at index %zu undetected", ix);
        }
        
        // Also verify failure when decrypting with a different document key
        decrypted = [OFSSegmentEncryptWorker decryptData:ciphertext withKey:otherDocKey error:&error];
        XCTAssertNil(decrypted, @"Decryption should fail: wrong key");
    }
}



- (void)testOneShotMed
{
    /* This test is similar to -testOneShotSmall, but makes sure we have correct behavior near the edges of segment boundaries. */
#define SEGMENTED_PAGE_SIZE 65536     /* From OFSSegmentedEncryption - Size of one encrypted segment */

    NSError * __autoreleasing error = nil;
    
    OFSDocumentKey *docKey;
    
    OBShouldNotError(docKey = [[OFSDocumentKey alloc] initWithData:nil error:&error]);
    [docKey reset];
    

    for (unsigned  npages = 1; npages < 4; npages ++) {
        size_t previousCiphertextLength = 0;
        int sizeJumps = 0;
        for (int delta = -2; delta < 3; delta ++) {
            size_t plaintextLength = ( SEGMENTED_PAGE_SIZE * npages ) + delta;
            
            NSData *plaintext = OFRandomCreateDataOfLength(plaintextLength);
            NSData *ciphertext, *decrypted;

            OBShouldNotError(ciphertext = [OFSSegmentEncryptWorker encryptData:plaintext withKey:docKey error:&error]);
            XCTAssertGreaterThanOrEqual([ciphertext length], [plaintext length] + 96);
            
            if (previousCiphertextLength != 0) {
                NSInteger growth = [ciphertext length] - previousCiphertextLength;
                XCTAssertGreaterThanOrEqual(growth, 1);
                if (growth > 1)
                    sizeJumps ++;
            }
            
            // We should be able to decrypt the ciphertext.
            OBShouldNotError(decrypted = [OFSSegmentEncryptWorker decryptData:ciphertext withKey:docKey error:&error]);
            XCTAssertEqualObjects(plaintext, decrypted);
            
            previousCiphertextLength = [ciphertext length];
        }
        XCTAssertEqual(sizeJumps, 1);
    }
}


@end
