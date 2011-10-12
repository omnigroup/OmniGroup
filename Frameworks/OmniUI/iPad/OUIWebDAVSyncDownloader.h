// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OUISyncDownloader.h"
#import <OmniFileStore/OFSFileManagerAsynchronousOperationTarget.h>

@protocol OFSAsynchronousOperation;

@class NSFileWrapper;
@class OFSFIleInfo;

@interface OUIWebDAVSyncDownloader : OUISyncDownloader <OFSFileManagerAsynchronousOperationTarget>
{
@private
    id <OFSAsynchronousOperation> _downloadOperation;
    NSOutputStream *_downloadStream;
    NSMutableArray *_uploadOperations;
    
    OFSFileInfo *_file;
    NSURL *_baseURL;
    NSMutableArray *_fileQueue;
    
    off_t _totalDataLength;
    off_t _totalUploadedBytes;
    
    NSURL *_uploadTemporaryURL, *_uploadFinalURL;
}

- (void)download:(OFSFileInfo *)aFile;
- (IBAction)cancelDownload:(id)sender;
- (void)uploadFileWrapper:(NSFileWrapper *)fileWrapper toURL:(NSURL *)targetURL;

@end
