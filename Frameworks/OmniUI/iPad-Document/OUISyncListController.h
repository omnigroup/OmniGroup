// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIFileListViewController.h"

@class NSFileWrapper;
@class ODAVFileInfo, OFXServerAccount;
@class OUISyncDownloader;

@interface OUISyncListController : OUIFileListViewController
{
@protected
    UIView *_connectingView;
    UIActivityIndicatorView *_connectingProgress;
    UILabel *_connectingLabel;
    
    BOOL _isDownloading;
}

- initWithServerAccount:(OFXServerAccount *)serverAccount exporting:(BOOL)exporting error:(NSError **)outError;

- (IBAction)cancel:(id)sender;

@property(nonatomic,readonly) OFXServerAccount *serverAccount;
@property(nonatomic,readonly) BOOL isExporting;

@property(nonatomic,strong) UIView *connectingView;
@property(nonatomic,strong) UIActivityIndicatorView *connectingProgress;
@property(nonatomic,strong) UILabel *connectingLabel;

@property(nonatomic,strong) NSURL *address;

@property(nonatomic,strong) NSFileWrapper *exportFileWrapper;

@property(nonatomic,strong) OUISyncDownloader *downloader;

// Public
- (void)addDownloaderWithURL:(NSURL *)exportURL toCell:(UITableViewCell *)cell;
- (void)downloadFinished:(NSNotification *)notification;
- (void)downloadCanceled:(NSNotification *)notification;

// Private
- (void)_loadFiles;
- (void)_stopConnectingIndicator;
- (void)_exportToURL:(NSURL *)exportURL;
- (void)_displayDuplicateFileAlertForFile:(NSURL *)fileURL;
- (void)_exportToNewPathGeneratedFromURL:(NSURL *)documentURL;

@end
