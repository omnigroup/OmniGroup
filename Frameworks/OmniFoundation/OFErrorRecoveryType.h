// Copyright 2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSError.h>

// This allows platform-specific interfaces to style buttons based on the recovery type.

typedef NS_ENUM(NSInteger, OFErrorRecoveryType) {
    OFErrorRecoveryTypeDefault = 0,
    OFErrorRecoveryTypeCancel,
    OFErrorRecoveryTypeDestructive
};

// This should be placed in the userInfo of an NSError, containing an NSArray<NSNumber *> of OFErrorRecoveryType.
extern NSErrorUserInfoKey const OFErrorRecoveryTypesErrorKey;
