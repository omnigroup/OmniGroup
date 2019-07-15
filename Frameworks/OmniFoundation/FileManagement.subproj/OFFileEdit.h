// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

// A snapshot of the edit information about an on-disk file. We assume that all documents we deal with are written with replacing safe saves which swaps out the whole file wrapper instead of updating its contents (so the modification date and inode will change).
@interface OFFileEdit : NSObject <NSCopying>

// This accesses the filesystem, possibly using a NSFileCoordinator, and must only be called on a background queue.
- (nullable instancetype)initWithFileURL:(NSURL *)fileURL error:(NSError **)outError;

// Here we assume that the inputs were previously read under file coordination and so are consistent.
- (instancetype)initWithFileURL:(NSURL *)fileURL fileModificationDate:(NSDate *)fileModificationDate inode:(NSUInteger)inode isDirectory:(BOOL)isDirectory;

@property(nonatomic,readonly) NSURL *originalFileURL; // Might have moved or been deleted
@property(nonatomic,readonly) NSDate *fileModificationDate;
@property(nonatomic,readonly) NSUInteger inode;
@property(nonatomic,readonly,getter=isDirectory) BOOL directory;

@property(nonatomic,readonly) NSString *uniqueEditIdentifier;

@end

NS_ASSUME_NONNULL_END
