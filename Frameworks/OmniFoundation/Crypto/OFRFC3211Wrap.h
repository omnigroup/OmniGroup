// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#include <OmniFoundation/OFCMS.h>
#include <CommonCrypto/CommonCrypto.h>

NS_ASSUME_NONNULL_BEGIN

/* Old-style PBE key wrapping. We include this if we want to run unit tests against published test vectors, or do interoperability tests against implementations that don't handle AESWRAP. */
#if WITH_RFC3211_KEY_WRAP

NSData * __nullable OFRFC3211Wrap(NSData *CEK, NSData *KEK, NSData *iv, CCAlgorithm innerAlgorithm, size_t blockSize) OB_HIDDEN;
NSData * __nullable OFRFC3211Unwrap(NSData *input, NSData *KEK, NSData *iv, CCAlgorithm innerAlgorithm, size_t blockSize) OB_HIDDEN;

#endif

NS_ASSUME_NONNULL_END
