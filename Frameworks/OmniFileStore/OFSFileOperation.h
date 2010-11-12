// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OmniFileStore/OFSAsynchronousOperation.h>
#import <OmniFileStore/OFSFileManagerAsynchronousOperationTarget.h>

@class OFSFileManager;

@interface OFSFileOperation : OFObject <OFSAsynchronousOperation>
{
@private
    OFSFileManager *_nonretained_fileManager;
    NSURL *_url;
    BOOL _read;
    BOOL _atomically; // for writing
    NSData *_data;
    id <OFSFileManagerAsynchronousOperationTarget> _target;
    long long _processedLength;
}

- initWithFileManager:(OFSFileManager *)fileManager readingURL:(NSURL *)url target:(id <OFSFileManagerAsynchronousOperationTarget>)target;
- initWithFileManager:(OFSFileManager *)fileManager writingData:(NSData *)data atomically:(BOOL)atomically toURL:(NSURL *)url target:(id <OFSFileManagerAsynchronousOperationTarget>)target;

@end
