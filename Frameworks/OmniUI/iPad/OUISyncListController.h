// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UITableViewController.h>

#import "OUIListController.h"
#import <OmniUI/OUIReplaceDocumentAlert.h>

#import "OUISyncMenuController.h"

@class NSFileWrapper;
@class OFSFileInfo;
@class OUISyncDownloader;

@interface OUISyncListController : OUIListController <OUIReplaceDocumentAlertDelegate> {
@protected
    UIView *_connectingView;
    UIActivityIndicatorView *_connectingProgress;
    UILabel *_connectingLabel;
    
    BOOL _isDownloading;
    
@private
    OUISyncType _syncType;
    NSURL *_address;
    
    BOOL _isExporting;
    NSFileWrapper *_exportFileWrapper;
    
    /* these are used when the download is delayed in order to scroll the view to the visible */ 
    NSURL *_exportURL; 
    NSIndexPath *_exportIndexPath; 
    
    OUIReplaceDocumentAlert *_replaceDocumentAlert;
    
    OUISyncDownloader *_downloader;
}

@property (nonatomic, retain) UIView *connectingView;
@property (nonatomic, retain) UIActivityIndicatorView *connectingProgress;
@property (nonatomic, retain) UILabel *connectingLabel;

@property (nonatomic, assign) OUISyncType syncType;
@property (readwrite, retain) NSURL *address;

@property (nonatomic, assign) BOOL isExporting;
@property (readwrite, retain) NSFileWrapper *exportFileWrapper;

@property (nonatomic, retain) OUISyncDownloader *downloader;

// Public
- (void)signOut:(id)sender;
- (void)addDownloaderWithURL:(NSURL *)exportURL toCell:(UITableViewCell *)cell;
- (void)downloadFinished:(NSNotification *)notification;

// Private
- (void)_loadFiles;
- (void)_stopConnectingIndicator;
- (void)_exportToURL:(NSURL *)exportURL;
- (void)_displayDuplicateFileAlertForFile:(NSURL *)fileURL;
- (void)_exportToNewPathGeneratedFromURL:(NSURL *)documentURL;

@end
