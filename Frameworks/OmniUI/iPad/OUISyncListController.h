// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UITableViewController.h>

#import "OUISyncMenuController.h"
#import <OmniUI/OUIReplaceDocumentAlert.h>

@class OFFileWrapper;
@class OFSFileInfo;
@class OUISyncDownloader;

@interface OUISyncListController : UITableViewController <OUIReplaceDocumentAlertDelegate> {
@protected
    BOOL _isDownloading;
    
@private 
    OUISyncType _syncType;
    NSURL *_address;
    UIView *_connectingView;
    UIActivityIndicatorView *_connectingProgress;
    UILabel *_connectingLabel;
    
    NSArray *_files;
    BOOL _isExporting;
    OFFileWrapper *_exportFileWrapper;
    
    /* these are used when the download is delayed in order to scroll the view to the visible */ 
    NSURL *_exportURL; 
    NSIndexPath *_exportIndexPath; 
    
    OUIReplaceDocumentAlert *_replaceDocumentAlert;
    
    OUISyncDownloader *_downloader;
}

@property (nonatomic, assign) OUISyncType syncType;
@property (readwrite, retain) NSURL *address;

@property (nonatomic, retain) IBOutlet UIView *connectingView;
@property (nonatomic, retain) IBOutlet UIActivityIndicatorView *connectingProgress;
@property (nonatomic, retain) IBOutlet UILabel *connectingLabel;

@property (nonatomic, retain) NSArray *files;
@property (nonatomic, assign) BOOL isExporting;
@property (readwrite, retain) OFFileWrapper *exportFileWrapper;

@property (nonatomic, retain) OUISyncDownloader *downloader;

// Public
- (void)signOut:(id)sender;
- (void)addDownloaderWithURL:(NSURL *)exportURL toCell:(UITableViewCell *)cell;
- (void)downloadFinished:(NSNotification *)notification;

// Private
- (BOOL)_canOpenFile:(OFSFileInfo *)fileInfo;
- (void)_loadFiles;
- (void)_stopConnectingIndicator;
- (void)_exportToURL:(NSURL *)exportURL;
- (void)_displayDuplicateFileAlertForFile:(NSURL *)fileURL;
- (void)_exportToNewPathGeneratedFromURL:(NSURL *)documentURL;

@end
