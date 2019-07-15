// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBijection.h>

NS_ASSUME_NONNULL_BEGIN

@interface OFMutableBijection<__covariant KeyType, __covariant ObjectType> : OFBijection

- (void)setObject:(nullable ObjectType)anObject forKey:(KeyType)aKey;
- (void)setKey:(nullable KeyType)aKey forObject:(ObjectType)anObject;

- (void)setObject:(nullable ObjectType)anObject forKeyedSubscript:(KeyType)aKey;

- (void)invert;

@end

NS_ASSUME_NONNULL_END
