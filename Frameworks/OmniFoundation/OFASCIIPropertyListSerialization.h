// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

// This is much like NSPropertyListSerialization, but writes the old NSPropertyListOpenStepFormat.

@class NSData, NSError, NSString;

NS_ASSUME_NONNULL_BEGIN

@interface OFASCIIPropertyListSerialization : NSObject
+ (nullable NSData *)dataFromPropertyList:(id)plist error:(out NSError **)outError;
+ (nullable NSString *)stringFromPropertyList:(id)plist error:(out NSError **)outError;
@end

NS_ASSUME_NONNULL_END
