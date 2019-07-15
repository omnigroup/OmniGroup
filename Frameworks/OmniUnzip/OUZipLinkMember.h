// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUZipMember.h>

NS_ASSUME_NONNULL_BEGIN

@interface OUZipLinkMember : OUZipMember

- initWithName:(NSString *)name date:(NSDate *)date destination:(NSString *)destination;

@property(nonatomic,readonly) NSString *destination;

@end

NS_ASSUME_NONNULL_END
