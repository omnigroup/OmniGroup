// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFHashTests : OFTestCase
{
}

@end

@implementation OFHashTests

- (void)testFIPS180_1
{
    NSMutableData *oneMillionAs;
    NSArray *expectedResults;

    expectedResults = [@"( <A9993E36 4706816A BA3E2571 7850C26C 9CD0D89D>, <84983E44 1C3BD26E BAAE4AA1 F95129E5 E54670F1>, <34AA973C D4C4DAA4 F61EEB2B DBAD2731 6534016F> )" propertyList];
    should([expectedResults count] == 3);

    shouldBeEqual([[@"abc" dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO] sha1Signature], [expectedResults objectAtIndex:0]);
    shouldBeEqual([[@"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq" dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO] sha1Signature], [expectedResults objectAtIndex:1]);

    oneMillionAs = [[NSMutableData alloc] initWithLength:1000000];
    memset([oneMillionAs mutableBytes], 'a', [oneMillionAs length]);
    shouldBeEqual([oneMillionAs sha1Signature], [expectedResults objectAtIndex:2]);
    [oneMillionAs release];
}

static NSData *tripletsAndSuffix(unsigned char triplet, unsigned int count, unsigned int suffix, unsigned int suffixLength)
{
    uint32_t buf;
    int bufFill;
    unsigned int repetition;
    NSMutableData *result;

    result = [[NSMutableData alloc] initWithCapacity: (3 * count + suffixLength) / 8];
    [result autorelease];

    buf = 0;
    bufFill = 0;
    for (repetition = 0; repetition < count; repetition ++) {
        buf = ( buf << 3 ) | triplet;
        bufFill += 3;

        if (bufFill >= 8) {
            uint8_t spill;

            spill = ( buf >> (bufFill - 8) ) & 0xFFU;
            bufFill -= 8;
            [result appendBytes:&spill length:1];
        }
    }

    buf = ( buf << suffixLength ) | suffix;
    bufFill += suffixLength;
    while (bufFill >= 8) {
        uint8_t spill;

        spill = ( buf >> (bufFill - 8) ) & 0xFFU;
        bufFill -= 8;
        [result appendBytes:&spill length:1];
    }
    

    OBASSERT(bufFill == 0);  // Assert that we got an even number of bytes.
    
    return result;
}

static NSData *repeatedBytes(int bytevalue, unsigned int count)
{
    char *buf = malloc(count);
    memset(buf, bytevalue, count);
    NSData *result = [[NSData alloc] initWithBytesNoCopy:buf length:count freeWhenDone:YES];
    return [result autorelease];
}

- (void)testGilloglyGrieu
{
    /* Some test vectors produced by Jim Gillogly and Francois Grieu */
    /* See: http://www.chiark.greenend.org.uk/pipermail/ukcrypto/1999-February/003538.html */
    /* We can only test bitstrings of lengths which are multiples of 8, not bitstrings of arbitrary length */

    shouldBeEqual([tripletsAndSuffix(6, 149, 1, 1) sha1Signature],
                  [NSData dataWithHexString:@"A3D2982427AE39C8920CA5F499D6C2BD71EBF03C" error:NULL]);

    shouldBeEqual([tripletsAndSuffix(6, 170, 3, 2) sha1Signature],
                  [NSData dataWithHexString:@"9E92C5542237B957BA2244E8141FDB66DEC730A5" error:NULL]);

    shouldBeEqual([tripletsAndSuffix(3, 490, 1, 2) sha1Signature],
                  [NSData dataWithHexString:@"75FACE1802B9F84F326368AB06E73E0502E9EA34" error:NULL]);

}

/* These next two vectors are 2^29 bytes (512MB) apiece; give them their own autorelease pools */
/* The reason a 2^29-byte vector is significant is that SHA1 contains a 32-bit bit counter, which will roll over at 2^32 bits = 2^29 bytes */
- (void)testGilloglyGrieu_Huge
{
    if (![[self class] shouldRunSlowUnitTests]) {
        NSLog(@"*** SKIPPING slow test [%@ %s]", [self class], _cmd);
        return;
    }
    
    NSAutoreleasePool *pool;

    pool = [[NSAutoreleasePool alloc] init];

    shouldBeEqual([tripletsAndSuffix(6, 1431655765, 1, 1) sha1Signature],
                  [NSData dataWithHexString:@"d5e09777a94f1ea9240874c48d9fecb6b634256b" error:NULL]);

    [pool release];
    pool = [[NSAutoreleasePool alloc] init];

    shouldBeEqual([tripletsAndSuffix(3, 1431655765, 0, 1) sha1Signature],
                  [NSData dataWithHexString:@"A3D7438C589B0B932AA91CC2446F06DF9ABC73F0" error:NULL]);

    [pool release];
}

NSString *md5string(NSString *input)
{
    return [[[input dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO] md5Signature] unadornedLowercaseHexString];
}

- (void)testRFC1321
{
    shouldBeEqual([[[NSData data] md5Signature] unadornedLowercaseHexString],
                  @"d41d8cd98f00b204e9800998ecf8427e");

    shouldBeEqual(md5string(@"a"),
                  @"0cc175b9c0f1b6a831c399e269772661");

    shouldBeEqual(md5string(@"abc"),
                  @"900150983cd24fb0d6963f7d28e17f72");

    shouldBeEqual(md5string(@"message digest"),
                  @"f96b697d7cb7938d525a2f31aaf161d0");

    shouldBeEqual(md5string(@"abcdefghijklmnopqrstuvwxyz"),
                  @"c3fcd3d76192e4007dfb496cca67e13b");

    shouldBeEqual(md5string(@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"),
                  @"d174ab98d277d9f5a5611c2c9f419d9f");

    shouldBeEqual(md5string(@"12345678901234567890123456789012345678901234567890123456789012345678901234567890"),
                  @"57edf4a22be3c955ac49da2e2107b67a");
}

- (void)testSHA256
{
    shouldBeEqual([[NSData data] sha256Signature],
                  [NSData dataWithHexString:@"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" error:NULL]);
        
    NSMutableData *oneMillionBytes = [[NSMutableData alloc] initWithLength:1000000];
    memset([oneMillionBytes mutableBytes], 'a', [oneMillionBytes length]);
    
    shouldBeEqual([oneMillionBytes sha256Signature],
                  [NSData dataWithHexString:@"cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0" error:NULL]);
    
    /* This one is from the NIST test vectors, moved it here so we can reuse the buffer */
    
    memset([oneMillionBytes mutableBytes], 0, [oneMillionBytes length]);
    shouldBeEqual([oneMillionBytes sha256Signature],
                  [NSData dataWithHexString:@"d29751f2649b32ff572b5e0a9f541ea660a50f94ff0beedfb0b692b924cc8025" error:NULL]);
    
    [oneMillionBytes release];
    
    shouldBeEqual([[NSData dataWithBytes:"message digest" length:14] sha256Signature],
                  [NSData dataWithHexString:@"f7846f55cf23e14eebeab5b4e1550cad5b509e3348fbc4efa3a1413d393cb650" error:NULL]);
}

- (void)testSHA256_NIST
{
    /* These are from http://csrc.nist.gov/groups/ST/toolkit/documents/Examples/SHA256.pdf */
        
    shouldBeEqual([[NSData dataWithBytes:"abc" length:3] sha256Signature],
                  [NSData dataWithHexString:@"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" error:NULL]);
    
    shouldBeEqual([[@"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq" dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:NO] sha256Signature],
                  [NSData dataWithHexString:@"248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1" error:NULL]);
    
    /* These are from http://csrc.nist.gov/groups/ST/toolkit/documents/Examples/SHA2_Additional.pdf */
    
    shouldBeEqual([[NSData dataWithBytes:"\xBD" length:1] sha256Signature],
                  [NSData dataWithHexString:@"68325720aabd7c82f30f554b313d0570c95accbb7dc4b5aae11204c08ffe732b" error:NULL]);
    
    shouldBeEqual([[NSData dataWithBytes:"\xC9\x8C\x8E\x55" length:4] sha256Signature],
                  [NSData dataWithHexString:@"7abc22c0ae5af26ce93dbb94433a0e0b2e119d014f8e7f65bd56c61ccccd9504" error:NULL]);

    shouldBeEqual([repeatedBytes(0, 55) sha256Signature],
                  [NSData dataWithHexString:@"02779466cdec163811d078815c633f21901413081449002f24aa3e80f0b88ef7" error:NULL]);

    shouldBeEqual([repeatedBytes(0, 56) sha256Signature],
                  [NSData dataWithHexString:@"d4817aa5497628e7c77e6b606107042bbba3130888c5f47a375e6179be789fbb" error:NULL]);

    shouldBeEqual([repeatedBytes(0, 57) sha256Signature],
                  [NSData dataWithHexString:@"65a16cb7861335d5ace3c60718b5052e44660726da4cd13bb745381b235a1785" error:NULL]);

    shouldBeEqual([repeatedBytes(0, 64) sha256Signature],
                  [NSData dataWithHexString:@"f5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b" error:NULL]);

    shouldBeEqual([repeatedBytes(0, 1000) sha256Signature],
                  [NSData dataWithHexString:@"541b3e9daa09b20bf85fa273e5cbd3e80185aa4ec298e765db87742b70138a53" error:NULL]);

    shouldBeEqual([repeatedBytes('A', 1000) sha256Signature],
                  [NSData dataWithHexString:@"c2e686823489ced2017f6059b8b239318b6364f6dcd835d0a519105a1eadd6e4" error:NULL]);

    shouldBeEqual([repeatedBytes('U', 1005) sha256Signature],
                  [NSData dataWithHexString:@"f4d62ddec0f3dd90ea1380fa16a5ff8dc4c54b21740650f24afc4120903552b0" error:NULL]);

}

/* A 2^29-byte test vector, for the same reason as testGilloglyGrieu_Huge */
- (void)testSHA256_Huge
{
    if (![[self class] shouldRunSlowUnitTests]) {
        NSLog(@"*** SKIPPING slow test [%@ %s]", [self class], _cmd);
        return;
    }
    
    NSMutableData *fourGigabits = [[NSMutableData alloc] initWithLength: ( 0x100000000ULL / 8)];
    
    /* A long buffer of 'a' (random value found on the net, test vector used by some open source implementations) */
    memset([fourGigabits mutableBytes], 'a', [fourGigabits length]);
    shouldBeEqual([fourGigabits sha256Signature],
                  [NSData dataWithHexString:@"b9045a713caed5dff3d3b783e98d1ce5778d8bc331ee4119d707072312af06a7" error:NULL]);
    
/* The NIST test vector:
     #11) 0x20000000 (536870912) bytes of 0x5a ‘Z’ 
     15a1868c 12cc5395 1e182344 277447cd 0979536b adcc512a d24c67e9 b2d4f3dd
*/
    memset([fourGigabits mutableBytes], 'Z', [fourGigabits length]);
    shouldBeEqual([fourGigabits sha256Signature],
                  [NSData dataWithHexString:@"15a1868c12cc53951e182344277447cd0979536badcc512ad24c67e9b2d4f3dd" error:NULL]);
    
/* NIST also provides test vectors for buffers of length 0x41000000 and 0x6000003e, but that's really pushing the amount of memory we have available here
       #12) 0x41000000 (1090519040) bytes of zeros 
         461c19a9 3bd4344f 9215f5ec 64357090 342bc66b 15a14831 7d276e31 cbc20b53 
       #13) 0x6000003e (1610612798) bytes of 0x42 ‘B’ 
         c23ce8a7 895f4b21 ec0daf37 920ac0a2 62a22004 5a03eb2d fed48ef9 b05aabea 
*/
    
    [fourGigabits release];
}

// Simple test of -signatureWithAlgorithm:
- (void)testByName
{
    NSData *abc = [NSData dataWithBytes:"abc" length:3];
    
    shouldBeEqual([abc signatureWithAlgorithm:@"md5"], [NSData dataWithHexString:@"900150983cd24fb0d6963f7d28e17f72" error:NULL]);
    shouldBeEqual([abc signatureWithAlgorithm:@"MD5"], [NSData dataWithHexString:@"900150983cd24fb0d6963f7d28e17f72" error:NULL]);
    shouldBeEqual([abc signatureWithAlgorithm:@"sha1"], [NSData dataWithHexString:@"A9993E364706816ABA3E25717850C26C9CD0D89D" error:NULL]);
    shouldBeEqual([abc signatureWithAlgorithm:@"SHA1"], [NSData dataWithHexString:@"A9993E364706816ABA3E25717850C26C9CD0D89D" error:NULL]);
    shouldBeEqual([abc signatureWithAlgorithm:@"sha-1"], nil);
    shouldBeEqual([abc signatureWithAlgorithm:@"sha256"], [NSData dataWithHexString:@"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" error:NULL]);
    shouldBeEqual([abc signatureWithAlgorithm:@"Sha256"], [NSData dataWithHexString:@"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" error:NULL]);
}

@end

