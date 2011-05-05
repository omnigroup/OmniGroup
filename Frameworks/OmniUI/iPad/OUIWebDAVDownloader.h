// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>
#import <OmniFileStore/OFSFileManagerAsynchronousOperationTarget.h>

@class OFFileWrapper;
@class OFSFileInfo;
@protocol OFSAsynchronousOperation;

extern NSString * const OUIWebDAVDownloadFinishedNotification;
extern NSString * const OUIWebDAVDownloadURL;
extern NSString * const OUIWebDAVDownloadCanceledNotification;

@interface OUIWebDAVDownloader : UIViewController <OFSFileManagerAsynchronousOperationTarget>
{
@private
    IBOutlet UIProgressView *progressView;
    IBOutlet UIButton *cancelButton;
    
    NSOutputStream *_downloadStream;
    OFSFileInfo *_file;
    NSURL *_baseURL;
    NSMutableArray *_fileQueue;
    
    id <OFSAsynchronousOperation> _downloadOperation;
    NSMutableArray *_uploadOperations;
    NSURL *_uploadTemporaryURL, *_uploadFinalURL;
    
    off_t _totalDataLength;
    off_t _totalUploadedBytes;
}

- (IBAction)cancelDownload:(id)sender;
- (void)download:(OFSFileInfo *)aFile;
- (void)uploadFileWrapper:(OFFileWrapper *)fileWrapper toURL:(NSURL *)targetURL;
- (void)uploadData:(NSData *)data toURL:(NSURL *)targetURL;

@end
