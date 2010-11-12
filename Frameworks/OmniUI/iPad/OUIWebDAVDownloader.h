// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>
#import <OmniFileStore/OFSFileManagerAsynchronousOperationTarget.h>

@protocol OFSAsynchronousOperation;
@class OFSFileInfo;

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
    id <OFSAsynchronousOperation> _uploadOperation;
    
    off_t _totalDataLength;
}

- (IBAction)cancelDownload:(id)sender;
- (void)download:(OFSFileInfo *)aFile;
- (void)upload:(NSData *)data toURL:(NSURL *)fileURL;

@end
