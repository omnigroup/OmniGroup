// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSData, NSError;
@class OFSFileManager;
@protocol OFSAsynchronousOperation;

@protocol OFSFileManagerAsynchronousOperationTarget <NSObject>

- (void)fileManager:(OFSFileManager *)fileManager operationDidFinish:(id <OFSAsynchronousOperation>)operation withError:(NSError *)error;

// For write operations, the 'didProcessBytes' will be called. For read operations, the 'didReceiveData' will be called if present, otherwise the didProcessBytes.
@optional
- (void)fileManager:(OFSFileManager *)fileManager operation:(id <OFSAsynchronousOperation>)operation didReceiveData:(NSData *)data;
- (void)fileManager:(OFSFileManager *)fileManager operation:(id <OFSAsynchronousOperation>)operation didProcessBytes:(long long)processedBytes;

@end
