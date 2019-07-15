// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAAppearance.h>

extern NSString * const OAAppearanceErrorDomain;
typedef NS_ENUM(NSUInteger, OAAppearanceErrorCode) {
    OAAppearanceErrorCodeKeyNotFound,
    OAAppearanceErrorCodeUnexpectedValueType,
    OAAppearanceErrorCodeInvalidValueInPropertyList,
};


@interface OAAppearance (Internal)
+ (BOOL)isReifyingClass:(Class)cls;
@end
