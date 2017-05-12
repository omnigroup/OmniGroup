// Copyright 2016 The Omni Group. All rights reserved.
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
static inline BOOL _OFValidateUnwrapParameters(const uint8_t *kek, const uint8_t *wrappedKey, uint8_t *rawKey) {
    return (kek != NULL && wrappedKey != NULL && rawKey != NULL);
}

int OFSymmetricKeyUnwrap(CCWrappingAlgorithm algorithm, const uint8_t *iv, const size_t ivLen, const uint8_t *kek, size_t kekLen, const uint8_t *wrappedKey, size_t wrappedKeyLen, uint8_t *rawKey, size_t *rawKeyLen) {
    
    OBPRECONDITION(_OFValidateUnwrapParameters(kek, wrappedKey, rawKey));
    
    int result = CCSymmetricKeyUnwrap(algorithm, iv, ivLen, kek, kekLen, wrappedKey, wrappedKeyLen, rawKey, rawKeyLen);
    
    if (result == -1) {
        // -1 occurred on older systems that did not exhibit rdar://29280638 but which did exhibit rdar://27463510. Rewrite it to kCCDecodeError unconditionally.
        OBASSERT(![OFVersionNumber isOperatingSystemWithRadar29280638OrLater]);
        result = kCCDecodeError;
    } else if (result == kCCParamError) {
        // We could theoretically get a parameter error for actual bad parameters. Do our own validation, and if it passes, assert we're subject to the radar and rewrite the result.
        if (_OFValidateUnwrapParameters(kek, wrappedKey, rawKey)) {
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
