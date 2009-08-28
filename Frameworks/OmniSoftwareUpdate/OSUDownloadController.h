// Copyright 2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSWindowController.h>

@class OSUItem;

@interface OSUDownloadController : NSWindowController
{
    // Book-keeping information for swapping views in and out of the panel.
    IBOutlet NSView *_bottomView;
    NSSize originalBottomViewSize;
    NSSize originalWindowSize;
    NSSize originalWarningViewSize;
    CGFloat originalWarningTextHeight;
    CGFloat warningTextTopMargin;
    
    // These are the toplevel views we might display in the panel.
    IBOutlet NSView *_plainStatusView;
    IBOutlet NSView *_credentialsView;
    IBOutlet NSView *_progressView;
    IBOutlet NSView *_installBasicView;         // Very basic, nonthreatening dialog text.
    IBOutlet NSView *_installOptionsView;       // Installation options.
    IBOutlet NSView *_installOptionsNoteView;   // View with small note text displayed instead of options view.
    IBOutlet NSView *_installWarningView;       // Warning message and icon.
    IBOutlet NSView *_installButtonsView;       // Box containing the action buttons.
    
    IBOutlet NSTextField *_installViewMessageText;
    IBOutlet NSTextField *_installViewCautionText;
    IBOutlet NSButton *_installViewInstallButton;
    
    NSURL *_packageURL;
    OSUItem *_item;
    NSURLRequest *_request;
    NSURLDownload *_download;
    NSURLAuthenticationChallenge *_challenge;
    BOOL _didFinishOrFail;
    BOOL _showCautionText;  // Usually describing a verification failure
    BOOL _displayingInstallView;
    
    // KVC
    NSString *_status;

    NSString *_userName;
    NSString *_password;
    BOOL _rememberInKeychain;
    
    off_t _currentBytesDownloaded, _totalSize;
    
    // Where we're downloading the package to
    NSString *_suggestedDestinationFile;
    NSString *_destinationFile;
    
    // Where we think we'll install the new application
    NSString *_installationDirectory;
    NSAttributedString *_installationDirectoryNote;
}

+ (OSUDownloadController *)currentDownloadController;

- initWithPackageURL:(NSURL *)packageURL item:(OSUItem *)item error:(NSError **)outError;

@property (readwrite, copy) NSString *installationDirectory;
@property (readonly       ) NSAttributedString *installationDirectoryNote;

// Actions
- (IBAction)cancelAndClose:(id)sender;

- (IBAction)continueDownloadWithCredentials:(id)sender;

- (IBAction)installAndRelaunch:(id)sender;
- (IBAction)revealDownloadInFinder:(id)sender;
- (IBAction)chooseDirectory:(id)sender;

@end
