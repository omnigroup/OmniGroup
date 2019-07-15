// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUZipMember.h>

NS_ASSUME_NONNULL_BEGIN

@interface OUZipFileMember : OUZipMember

- (instancetype)initWithName:(NSString *)name date:(NSDate *)date contents:(NSData *)contents;
- (instancetype)initWithName:(NSString *)name date:(NSDate *)date mappedFilePath:(NSString *)filePath;

- (nullable NSData *)contents;
- (nullable NSData *)contents:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
