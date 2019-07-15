// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

// OAFindController controls a simple find panel.

// To use, add an OAFindController object to your main nib, and hook up the appropriate menu items to its -showFindPanel:, -findNext:, -findPrevious:, and -enterSelection: actions.  (Hook up Scroll To Selection to First Responder's -jumpToSelection: action, which you'll need to add.)
// The find panel will search the OAFindControllerTarget indicated by the main window's delegate's -omniFindControllerTarget method:
// - (id <OAFindControllerTarget>)omniFindControllerTarget;

#import <AppKit/NSWindowController.h>

#import <OmniAppKit/OAFindControllerTargetProtocol.h>

@interface OAFindController : NSWindowController


@property (nonatomic) BOOL supportsRegularExpressions;

// Menu actions

- (IBAction)showFindPanel:(id)sender;
- (IBAction)findNext:(id)sender;
- (IBAction)findPrevious:(id)sender;
- (IBAction)enterSelection:(id)sender;

// Panel actions

- (IBAction)panelFindNext:(id)sender;
    // This action is sent by findNextButton
- (IBAction)panelFindPrevious:(id)sender;
    // This action is sent by findPreviousButton
- (IBAction)panelFindNextAndClosePanel:(id)sender;
    // This action is called when you hit return in searchTextForm
- (IBAction)replaceAll:(id)sender;
- (IBAction)replace:(id)sender;
- (IBAction)replaceAndFind:(id)sender;
- (IBAction)findTypeChanged:(id)sender;

// Utility methods
- (void)enterSelectionWithString:(NSString *)selectionString;
- (void)saveFindText:(NSString *)string;
- (NSString *)restoreFindText;
- (id <OAFindControllerTarget>)target;
- (NSString *)enterSelectionString;
- (NSUInteger)enterSelectionStringLength;

@end
