// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFSignature.h>

#import <CommonCrypto/CommonDigest.h>

RCS_ID("$Id$")

#define CONTEXT  ((CC_SHA1_CTX *)_private)

@implementation OFSignature

+ (void) initialize
{
    OBINITIALIZE;

    // Verify that the renaming of this define is valid
    OBASSERT(OF_SIGNATURE_LENGTH == CC_SHA1_DIGEST_LENGTH);
}

- init;
{
    return [self initWithBytes:nil length:0];
}

- (void) dealloc;
{
    NSZoneFree(NULL, _private);
    [_signatureData release];
    [super dealloc];
}

- initWithData: (NSData *) data;
{
    return [self initWithBytes: [data bytes] length: [data length]];
}

- initWithBytes: (const void *) bytes length: (NSUInteger) length;
{
    if ([super init] == nil)
        return nil;

    _private = NSZoneMalloc(NULL, sizeof(*CONTEXT));
    CC_SHA1_Init(CONTEXT);

    [self addBytes: bytes length: length];
    return self;
}

- (void) addData: (NSData *) data;
{
    [self addBytes: [data bytes] length: [data length]];
}

- (void) addBytes: (const void *) bytes length: (NSUInteger) length;
{
    OBPRECONDITION(!_signatureData);
    
    while (length) {
        CC_LONG currentLengthToProcess = MIN((CC_LONG)length, 16384u);
        CC_SHA1_Update(CONTEXT, bytes, currentLengthToProcess);
        length -= currentLengthToProcess;
        bytes += currentLengthToProcess;
    }
}

- (NSData *) signatureData;
{
    if (!_signatureData) {
        unsigned char signature[CC_SHA1_DIGEST_LENGTH];

        CC_SHA1_Final(signature, CONTEXT);
        _signatureData = [[NSData alloc] initWithBytes: signature length:CC_SHA1_DIGEST_LENGTH];
       
    }

    return _signatureData;
}


@end
