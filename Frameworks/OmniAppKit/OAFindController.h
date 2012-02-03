// Copyright 1997-2005, 2008, 2010, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

// OAFindController controls a simple find panel.

// To use, add an OAFindController object to your main nib, and hook up the appropriate menu items to its -showFindPanel:, -findNext:, -findPrevious:, and -enterSelection: actions.  (Hook up Scroll To Selection to First Responder's -jumpToSelection: action, which you'll need to add.)
// The find panel will search the OAFindControllerTarget indicated by the main window's delegate's -omniFindControllerTarget method:
// - (id <OAFindControllerTarget>)omniFindControllerTarget;

#import <OmniFoundation/OFObject.h>

@class NSButton, NSForm, NSWindow, NSMatrix, NSPopUpButton, NSTextField, NSBox, NSView;

#import <OmniAppKit/OAFindControllerTargetProtocol.h>

@interface OAFindController : OFObject
{
    NSWindow *_findPanel;
    NSForm *_searchTextForm;
    NSForm *_replaceTextForm;
    NSButton *_ignoreCaseButton;
    NSButton *_wholeWordButton;
    NSButton *_findNextButton;
    NSButton *_findPreviousButton;
    NSButton *_replaceAllButton;
    NSButton *_replaceButton;
    NSButton *_replaceAndFindButton;
    NSMatrix *_findTypeMatrix;
    NSPopUpButton *_subexpressionPopUp;
    NSButton *_replaceInSelectionCheckbox;
    NSBox *_additionalControlsBox;
    NSView *_stringControlsView;
    NSView *_regularExpressionControlsView;
    
    id <OAFindPattern> _currentPattern;
}

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
