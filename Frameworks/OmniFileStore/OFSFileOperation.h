// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

#import <OmniDAV/ODAVAsynchronousOperation.h>

@class OFSFileManager;

@interface OFSFileOperation : NSObject <ODAVAsynchronousOperation>

- initWithFileManager:(OFSFileManager *)fileManager readingURL:(NSURL *)url;
- initWithFileManager:(OFSFileManager *)fileManager writingData:(NSData *)data atomically:(BOOL)atomically toURL:(NSURL *)url;
- initWithFileManager:(OFSFileManager *)fileManager deletingURL:(NSURL *)url;

@end
