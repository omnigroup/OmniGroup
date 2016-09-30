// Copyright 2016 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSFileWrapper.h>

@class NSError, NSURL;

NS_ASSUME_NONNULL_BEGIN

@interface NSFileWrapper (OmniUnzipExtensions)

- (NSFileWrapper * __nullable )zippedFileWrapper:(NSError **)outError;
- (NSFileWrapper * __nullable )unzippedFileWrapperFromURL:(NSURL * __nullable )url error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
