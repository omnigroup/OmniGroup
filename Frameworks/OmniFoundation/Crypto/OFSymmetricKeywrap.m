// Copyright 2016-2017 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFSymmetricKeywrap.h>

#import <OmniBase/macros.h>
#import <OmniBase/rcsid.h>
#import <OmniFoundation/OFVersionNumber.h>

RCS_ID("$Id$");

@interface OFVersionNumber (Radar29280638)
+ (BOOL)isOperatingSystemWithRadar29280638OrLater;
@end

@implementation OFVersionNumber (Radar29280638)

+ (BOOL)isOperatingSystemWithRadar29280638OrLater;
{
    static BOOL isLater;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
        OFVersionNumber *version = [[OFVersionNumber alloc] initWithVersionString:@"10.2"];
#else
        OFVersionNumber *version = [[OFVersionNumber alloc] initWithVersionString:@"10.12.2"];
#endif
        isLater = [[OFVersionNumber userVisibleOperatingSystemVersionNumber] isAtLeast:version];
        [version release];
    });
    return isLater;
}

@end

#pragma mark -

/*
 CommonSymmetricKeywrap.h says: 
 
     kCCParamError can result from bad values for the kek, rawKey, and
     wrappedKey key pointers.
 
 Validate these three pointers in one place here. The wrapper implementation below relies on this function both as precondition and to check whether a parameter error (on systems that exhibit rdar://29280638) should be rewritten as a decode error or left alone.
 */
static inline BOOL _OFValidateUnwrapParametersAESWRAP(const uint8_t *kek, size_t kekLen, const uint8_t *wrappedKey, size_t wrappedKeyLength, uint8_t *rawKey) {
    if (kek == NULL || wrappedKey == NULL || rawKey == NULL)
        return NO;
    
    /* CCSymmetricKeyWrap() does RFC3394 key-wrap, not RFC5649 key-wrap, which means we can only wrap things which are multiples of half the block size. A wrapped key is at least three half-blocks long. */
    if (wrappedKeyLength < (3 * (kCCBlockSizeAES128/2)))
        return NO;
    if ((wrappedKeyLength % (kCCBlockSizeAES128/2)) != 0)
        return NO;
    
    /* AES keys are only allowed to be specific sizes */
    if (kekLen != kCCKeySizeAES128 && kekLen != kCCKeySizeAES192 && kekLen != kCCKeySizeAES256)
        return NO;
    
    return YES;
}

int OFSymmetricKeyUnwrap(CCWrappingAlgorithm algorithm, const uint8_t *iv, const size_t ivLen, const uint8_t *kek, size_t kekLen, const uint8_t *wrappedKey, size_t wrappedKeyLen, uint8_t *rawKey, size_t *rawKeyLen) {
    
    OBPRECONDITION(algorithm == kCCWRAPAES);
    OBPRECONDITION(_OFValidateUnwrapParametersAESWRAP(kek, kekLen, wrappedKey, wrappedKeyLen, rawKey));
    
    int result = CCSymmetricKeyUnwrap(algorithm, iv, ivLen, kek, kekLen, wrappedKey, wrappedKeyLen, rawKey, rawKeyLen);
    
    if (result == -1) {
        // -1 occurred on older systems that did not exhibit rdar://29280638 but which did exhibit rdar://27463510. Rewrite it to kCCDecodeError unconditionally.
        OBASSERT(![OFVersionNumber isOperatingSystemWithRadar29280638OrLater]);
        result = kCCDecodeError;
    } else if (result == kCCParamError) {
        // We could theoretically get a parameter error for actual bad parameters. Do our own validation, and if it passes, assert we're subject to the radar and rewrite the result.
        if (_OFValidateUnwrapParametersAESWRAP(kek, kekLen, wrappedKey, wrappedKeyLen, rawKey)) {
            OBASSERT([OFVersionNumber isOperatingSystemWithRadar29280638OrLater]);
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                NSLog(@"CCSymmetricKeyUnwrap returned kCCParamError for valid parameters. Working around rdar://29280638. Logging once only.");
            });
            result = kCCDecodeError;
        }
    }
    
    return result;
}

NSData *OFSymmetricKeyUnwrapDataRFC3394(NSData *KEK, NSData *wrappedKey, NSError **outError)
{
    size_t wrappedKeyLength = wrappedKey.length;
    size_t unwrappedKeyLength = CCSymmetricUnwrappedSize(kCCWRAPAES, wrappedKeyLength);
    
    void *buffer = malloc(unwrappedKeyLength);
    size_t unwrappedLenTmp = unwrappedKeyLength; /* RADAR 18206798 aka 15949620 */
    int unwrapError = OFSymmetricKeyUnwrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen, [KEK bytes], [KEK length], wrappedKey.bytes, wrappedKeyLength, buffer, &unwrappedLenTmp);
    if (unwrapError) {
        free(buffer);
        // Note that CCSymmetricKeyUnwrap() is documented to return various kCCFoo error codes, but it actually only ever returns -1 (RADAR 27463510) or kCCParamError (RADAR 29280638), depending on the OS revision.
        // Other than programming errors, the only error we should see here is if the AESWRAP IV didn't verify, which is an indication that the user entered the wrong password.
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unwrapError userInfo:@{ @"function": @"CCSymmetricKeyUnwrap" }];
        return nil;
    }
    
    return [NSData dataWithBytesNoCopy:buffer length:unwrappedKeyLength freeWhenDone:YES];
}
