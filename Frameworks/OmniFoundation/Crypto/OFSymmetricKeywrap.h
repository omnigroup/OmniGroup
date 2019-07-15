// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

/*!
 OFSymmetricKeyUnwrap wraps the functionality of CCSymmetricKeyUnwrap, adjusting the returned error code to make it more sensible. Specifically, it works around rdar://29280638 ("10.12.2 beta regression: CCSymmetricKeyUnwrap erroneously returns kCCParamError on unwrap failure") by mapping the return codes -1 and -4300 (kCCParamError) to kCCDecodeError.
 
 For a complete discussion of the arguments and return value, see the comment above CCSymmetricKeyUnwrap in <CommonCrypto/CommonSymmetricKeywrap.h>. (Note that CCSymmetricKeyUnwrap is not documented to ever return kCCDecodeError.)
 */
int OFSymmetricKeyUnwrap( CCWrappingAlgorithm algorithm,
                         const uint8_t *iv, const size_t ivLen,
                         const uint8_t *kek, size_t kekLen,
                         const uint8_t *wrappedKey, size_t wrappedKeyLen,
                         uint8_t *rawKey, size_t *rawKeyLen);

/*!
 A specialized version of OFSymmetricKeyUnwrap for the case where all the key material is in NSDatas. Note that the only algorithm that CCSymmetricKeyWrap supports is RFC3394-AESWRAP, so we just hardcode that.
*/
NSData *OFSymmetricKeyUnwrapDataRFC3394(NSData *kek, NSData *wrappedKey, NSError **outError);

