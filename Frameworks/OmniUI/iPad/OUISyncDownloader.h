// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@class NSFileWrapper;
@class OFSFileInfo;

extern NSString * const OUISyncDownloadFinishedNotification;
extern NSString * const OUISyncDownloadURL;
extern NSString * const OUISyncDownloadCanceledNotification;

// Base class for sync downloaders. Should not be used directly. Please subclass as needed.
@interface OUISyncDownloader : UIViewController
{
@private
    // IBOutlets
    UIProgressView *_progressView;
    UIButton *_cancelButton;
}

@property (nonatomic, retain) IBOutlet UIProgressView *progressView;
@property (nonatomic, retain) IBOutlet UIButton *cancelButton;

// All following methods should be overridden in Subclasses.
- (void)download:(OFSFileInfo *)aFile;
- (IBAction)cancelDownload:(id)sender;
- (void)uploadFileWrapper:(NSFileWrapper *)fileWrapper toURL:(NSURL *)targetURL;
// End Subclass Overriding.

- (void)uploadData:(NSData *)data toURL:(NSURL *)targetURL;

- (NSString *)unarchiveFileAtPath:(NSString *)filePathWithArchiveExtension error:(NSError **)error;

@end
