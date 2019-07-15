// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCharacterScanner.h>

NS_ASSUME_NONNULL_BEGIN

@interface OFStringScanner : OFCharacterScanner

/// Scan the specified string. Retains string, rather than copying it, for efficiency, so don't change it.
- (id)initWithString:(NSString *)aString;

@property(nonatomic, readonly) NSString *string;

@property(nonatomic, readonly) NSRange remainingRange;
@property(nonatomic, readonly) NSString *remainingString;

@end

NS_ASSUME_NONNULL_END
