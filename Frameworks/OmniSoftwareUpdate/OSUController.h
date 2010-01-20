// Copyright 2003-2005, 2007-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <AppKit/NSNibDeclarations.h>

@class NSDictionary;
@class NSButton, NSImageView, NSPanel, NSTextField, NSTextView, NSWindow;
@class OSUDownloadController, OSUItem, OSUCheckOperation;

typedef enum _OSUPrivacyNoticeResult {
    OSUPrivacyNoticeResultOK,
    OSUPrivacyNoticeResultShowPreferences,
} OSUPrivacyNoticeResult;

extern NSString *OSUReleaseDisplayVersionKey;
extern NSString *OSUReleaseDownloadPageKey;
extern NSString *OSUReleaseEarliestCompatibleLicenseKey;
extern NSString *OSUReleaseRequiredOSVersionKey;
extern NSString *OSUReleaseVersionKey;
extern NSString *OSUReleaseSpecialNotesKey;
extern NSString *OSUReleaseMajorSummaryKey;
extern NSString *OSUReleaseMinorSummaryKey;
extern NSString *OSUReleaseApplicationSummaryKey;

@interface OSUController : NSObject
{
    // Unused currently
    //IBOutlet NSPanel *panel;
    //IBOutlet NSImageView *appIconView;
    //IBOutlet NSTextField *mainMessageField;
    //IBOutlet NSTextField *moreMessageField;
    //IBOutlet NSTextView *releaseNotesView;
    //IBOutlet NSTextField *warningField;
    //IBOutlet NSImageView *warningIconView;

    IBOutlet NSPanel     *privacyNoticePanel;
    IBOutlet NSImageView *privacyNoticeAppIconImageView;
    IBOutlet NSTextField *privacyNoticeTitleTextField;
    IBOutlet NSTextField *privacyNoticeMessageTextField;
    IBOutlet NSButton    *enableHardwareCollectionButton;
    
    OSUDownloadController *_currentDownloadController;
}

// API
+ (OSUController *)sharedController;
+ (void)checkSynchronouslyWithUIAttachedToWindow:(NSWindow *)aWindow;
+ (void)newVersionsAvailable:(NSArray *)versionInfos fromCheck:(OSUCheckOperation *)op;
+ (void)startingCheckForUpdates;

- (OSUPrivacyNoticeResult)runPrivacyNoticePanelHavingSeenPreviousVersion:(BOOL)hasSeenPreviousVersion;

- (BOOL)beginDownloadAndInstallFromPackageAtURL:(NSURL *)packageURL item:(OSUItem *)item error:(NSError **)outError;

// Actions
//- (IBAction)downloadNow:(id)sender;
//- (IBAction)showMoreInfo:(id)sender;
//- (IBAction)cancel:(id)sender;

- (IBAction)privacyNoticePanelOK:(id)sender;
- (IBAction)privacyNoticePanelShowPreferences:(id)sender;

@end
