// Copyright 1999-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

static int status;

void doTest(NSData *input, NSData *expectedHash)
{
    NSData *hash = [input md5Signature];
    NSString *comment;

    if (expectedHash) {
        if ([expectedHash isEqual:hash])
            comment = @"(ok)";
        else {
            comment = @"(***BAD***)";
            status ++;
        }
    } else
        comment = @"";

    NSLog(@"MD5(\"%@\") = %@ %@",
          [[[NSString alloc] initWithData:input encoding:NSASCIIStringEncoding] autorelease],
          [hash unadornedLowercaseHexString],
          comment);
}

#define TEST_VECTOR_COUNT 7
struct {
    char *testData;
    unsigned char expectedHash[16];
} rfc1321TestVectors[TEST_VECTOR_COUNT] = {
    { "",
      { 0xd4, 0x1d, 0x8c, 0xd9, 0x8f, 0x00, 0xb2, 0x04,
        0xe9, 0x80, 0x09, 0x98, 0xec, 0xf8, 0x42, 0x7e } },
    { "a",
      { 0x0c, 0xc1, 0x75, 0xb9, 0xc0, 0xf1, 0xb6, 0xa8,
        0x31, 0xc3, 0x99, 0xe2, 0x69, 0x77, 0x26, 0x61 } },
    { "abc",
      { 0x90, 0x01, 0x50, 0x98, 0x3c, 0xd2, 0x4f, 0xb0,
        0xd6, 0x96, 0x3f, 0x7d, 0x28, 0xe1, 0x7f, 0x72 } },
    { "message digest",
      { 0xf9, 0x6b, 0x69, 0x7d, 0x7c, 0xb7, 0x93, 0x8d,
        0x52, 0x5a, 0x2f, 0x31, 0xaa, 0xf1, 0x61, 0xd0 } },
    { "abcdefghijklmnopqrstuvwxyz",
      { 0xc3, 0xfc, 0xd3, 0xd7, 0x61, 0x92, 0xe4, 0x00,
        0x7d, 0xfb, 0x49, 0x6c, 0xca, 0x67, 0xe1, 0x3b } },
    { "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789",
      { 0xd1, 0x74, 0xab, 0x98, 0xd2, 0x77, 0xd9, 0xf5,
        0xa5, 0x61, 0x1c, 0x2c, 0x9f, 0x41, 0x9d, 0x9f } },
    { "12345678901234567890123456789012345678901234567890123456789012345678901234567890",
      { 0x57, 0xed, 0xf4, 0xa2, 0x2b, 0xe3, 0xc9, 0x55,
        0xac, 0x49, 0xda, 0x2e, 0x21, 0x07, 0xb6, 0x7a } }
};
    

void doRFC1321Tests()
{
    int vectorIndex;
    NSData *input, *output;

    for(vectorIndex = 0; vectorIndex < TEST_VECTOR_COUNT; vectorIndex++) {
        input = [[NSData alloc] initWithBytes:rfc1321TestVectors[vectorIndex].testData length:strlen(rfc1321TestVectors[vectorIndex].testData)];
        output = [[NSData alloc] initWithBytes:rfc1321TestVectors[vectorIndex].expectedHash length:16];
        doTest(input, output);
        [input release];
        [output release];
    }
}

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    status = 0; // successful so far
    
    if (argc == 1)
        doRFC1321Tests();
    else if (argc == 2) {
        NSData *testData = [[NSData alloc] initWithContentsOfFile:[NSString stringWithCString:argv[1]]];
        if (!testData) {
            perror(argv[1]);
            return 1;
        }
        doTest(testData, nil);
        [testData release];
    }

    [pool release];
    return 0;
}
