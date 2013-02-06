// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import <OmniFileStore/OFSAsynchronousOperation.h>

@class OFSFileManager;

@interface OFSFileOperation : NSObject <OFSAsynchronousOperation>

- initWithFileManager:(OFSFileManager *)fileManager readingURL:(NSURL *)url;
- initWithFileManager:(OFSFileManager *)fileManager writingData:(NSData *)data atomically:(BOOL)atomically toURL:(NSURL *)url;

@end
