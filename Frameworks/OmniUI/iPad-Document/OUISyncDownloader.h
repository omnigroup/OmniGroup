// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIViewController.h>

@class NSFileWrapper;
@class ODAVFileInfo;

extern NSString * const OUISyncDownloadFinishedNotification;
extern NSString * const OUISyncDownloadURL;
extern NSString * const OUISyncDownloadCanceledNotification;

// Base class for sync downloaders. Should not be used directly. Please subclass as needed.
@interface OUISyncDownloader : UIViewController

@property (nonatomic, strong) IBOutlet UIProgressView *progressView;
@property (nonatomic, strong) IBOutlet UIButton *cancelButton;

- (void)uploadData:(NSData *)data toURL:(NSURL *)targetURL;

- (NSString *)unarchiveFileAtPath:(NSString *)filePathWithArchiveExtension error:(NSError **)error;

@end

@protocol OUIConcreteSyncDownloader <NSObject>
- (void)download:(ODAVFileInfo *)aFile;
- (IBAction)cancelDownload:(id)sender;
- (void)uploadFileWrapper:(NSFileWrapper *)fileWrapper toURL:(NSURL *)targetURL;
@end

// Declare these are implemented though the main class doesn't -- subclasses must
@interface OUISyncDownloader (OUIConcreteSyncDownloader) <OUIConcreteSyncDownloader>
@end
