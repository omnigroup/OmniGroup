// Copyright 2006-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAController.h>

@class NSTextField, NSTextView, NSWindow;


@interface OSUTAController : OAController
{
    IBOutlet NSWindow *window;
    IBOutlet NSTextField *bundleIdentifierField;
    IBOutlet NSPopUpButton *licenseStatePopUp;
    IBOutlet NSTextField *marketingVersionField;
    IBOutlet NSTextField *buildVersionField;
    IBOutlet NSTextField *systemVersionField;
    IBOutlet NSTextField *applicationTrackField;
    IBOutlet NSTextView *visibleTracksTextView;
    IBOutlet NSTextField *requestedTrackField;
    
    IBOutlet NSTextField *urlPromptField;
}

- (IBAction)forceInstall:sender;
- (IBAction)acceptURL:sender;
- (IBAction)changeLicenseState:sender;
- (IBAction)fakeTimedCheck:sender;

@end

