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

- (void)testGilloglyGrieu
{
    /* Some test vectors produced by Jim Gillogly and Francois Grieu */
    /* See: http://www.chiark.greenend.org.uk/pipermail/ukcrypto/1999-February/003538.html */
    /* We can only test bitstrings of lengths which are multiples of 8, not bitstrings of arbitrary length */

    shouldBeEqual([tripletsAndSuffix(6, 149, 1, 1) sha1Signature],
                  [NSData dataWithHexString:@"A3D2982427AE39C8920CA5F499D6C2BD71EBF03C"]);

    shouldBeEqual([tripletsAndSuffix(6, 170, 3, 2) sha1Signature],
                  [NSData dataWithHexString:@"9E92C5542237B957BA2244E8141FDB66DEC730A5"]);

    shouldBeEqual([tripletsAndSuffix(3, 490, 1, 2) sha1Signature],
                  [NSData dataWithHexString:@"75FACE1802B9F84F326368AB06E73E0502E9EA34"]);

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
                  [NSData dataWithHexString:@"d5e09777a94f1ea9240874c48d9fecb6b634256b"]);

    [pool release];
    pool = [[NSAutoreleasePool alloc] init];

    shouldBeEqual([tripletsAndSuffix(3, 1431655765, 0, 1) sha1Signature],
                  [NSData dataWithHexString:@"A3D7438C589B0B932AA91CC2446F06DF9ABC73F0"]);

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

@end

