// Copyright 2016-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSFileWrapper.h>

@class NSError, NSURL;

NS_ASSUME_NONNULL_BEGIN

@interface NSFileWrapper (OmniUnzipExtensions)

- (nullable NSFileWrapper *)zippedFileWrapper:(NSError **)outError;
- (nullable NSFileWrapper *)unzippedFileWrapperWithError:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
