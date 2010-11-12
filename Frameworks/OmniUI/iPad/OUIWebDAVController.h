// Copyright 2010 The Omni Group.  All rights reserved.
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

@interface OUIWebDAVController : UITableViewController <OUIReplaceDocumentAlertDelegate>
{
@private 
    OUISyncType _syncType;
    NSURL *_address;
    UIView *_connectingView;
    UIActivityIndicatorView *_connectingProgress;
    
    NSArray *_files;
    BOOL _isDownloading;
    BOOL _isExporting;
    NSData *_exportingData;
    NSString *_exportingFilename;
    
    /* these are used when the download is delayed in order to scroll the view to the visible */ 
    NSURL *_exportURL; 
    NSIndexPath *_exportIndexPath; 
    
    OUIReplaceDocumentAlert *_replaceDocumentAlert;
}

- (void)signOut:(id)sender;

@property (nonatomic, assign) OUISyncType syncType;
@property (readwrite, retain) NSURL *address;

@property (nonatomic, retain) IBOutlet UIView *connectingView;
@property (nonatomic, retain) IBOutlet UIActivityIndicatorView *connectingProgress;

@property (nonatomic, retain) NSArray *files;
@property (nonatomic, assign) BOOL isExporting;
@property (readwrite, retain) NSData *exportingData;
@property (readwrite, retain) NSString *exportingFilename;

@end
