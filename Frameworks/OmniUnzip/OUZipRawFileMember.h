// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUZipMember.h>

@class OUUnzipEntry, OUUnzipArchive;

NS_ASSUME_NONNULL_BEGIN

@interface OUZipRawFileMember : OUZipMember

- (instancetype)initWithName:(NSString *)name entry:(OUUnzipEntry *)entry archive:(OUUnzipArchive *)archive;
- (instancetype)initWithEntry:(OUUnzipEntry *)entry archive:(OUUnzipArchive *)archive;

@property(nonatomic,readonly) OUUnzipArchive *archive;
@property(nonatomic,readonly) OUUnzipEntry *entry;

/// Returns the raw (compressed) data backing this zip member, reading it from the underlying archive if necessary.
- (nullable NSData *)readRawData:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
