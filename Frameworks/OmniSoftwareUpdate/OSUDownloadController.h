// Copyright 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniSoftwareUpdate/OSUDownloadController.h 95171 2007-11-27 10:35:14Z bungi $

#import <AppKit/NSWindowController.h>

@class OSUFlippedView, OSUItem;

@interface OSUDownloadController : NSWindowController
{
    IBOutlet OSUFlippedView *_bottomView;
    
    IBOutlet NSView *_plainStatusView;
    IBOutlet NSView *_credentialsView;
    IBOutlet NSView *_progressView;
    IBOutlet NSView *_installView;
    
    NSURL *_packageURL;
    NSURLRequest *_request;
    NSURLDownload *_download;
    NSURLAuthenticationChallenge *_challenge;
    BOOL _didFinishOrFail;
    
    // KVC
    NSString *_status;

    NSString *_userName;
    NSString *_password;
    BOOL _rememberInKeychain;
    
    off_t _currentBytesDownloaded, _totalSize;
    
    NSString *_suggestedDestinationFile;
    NSString *_destinationFile;
}

+ (OSUDownloadController *)currentDownloadController;

- initWithPackageURL:(NSURL *)packageURL item:(OSUItem *)item error:(NSError **)outError;

// Actions
- (IBAction)cancelAndClose:(id)sender;

- (IBAction)continueDownloadWithCredentials:(id)sender;

- (IBAction)installAndRelaunch:(id)sender;
- (IBAction)revealDownloadInFinder:(id)sender;

@end
