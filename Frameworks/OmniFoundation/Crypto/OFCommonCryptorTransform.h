// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDataTransform.h>
#import <CommonCrypto/CommonCryptor.h>

NS_ASSUME_NONNULL_BEGIN

@interface OFCommonCryptorTransform : OFDataTransform

- (instancetype)initWithCryptor:(CCCryptorRef /* CONSUMED */)cr;

@end

NS_ASSUME_NONNULL_END
