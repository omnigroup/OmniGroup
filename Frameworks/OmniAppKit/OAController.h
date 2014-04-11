// Copyright 2004-2008, 2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFController.h>

@class OAAboutPanelController;

#import <AppKit/NSApplication.h> // For NSApplicationDelegate
#import <AppKit/NSNibDeclarations.h> // For IBAction and IBOutlet

@interface OAController : OFController <NSApplicationDelegate>
{
@private
    OAAboutPanelController *aboutPanelController;
}

- (OAAboutPanelController *)aboutPanelController;

- (IBAction)showAboutPanel:(id)sender;
- (IBAction)hideAboutPanel:(id)sender;
- (IBAction)sendFeedback:(id)sender;
- (IBAction)showMessageOfTheDay:(id)sender;
- (IBAction)openApplicationScriptsFolder:(id)sender;

- (NSString *)appName;
- (void)getFeedbackAddress:(NSString **)feedbackAddress andSubject:(NSString **)subjectLine;
- (void)sendFeedbackEmailTo:(NSString *)feedbackAddress subject:(NSString *)subjectLine body:(NSString *)body;
- (void)sendFeedbackEmailWithBody:(NSString *)body;

// OAController has concrete implementations of the following NSApplicationDelegate methods. They're responsible for driving the OFController behavior at appropriate times during the app's lifecycle. If you override these methods, be sure to call super's implementation.
- (void)applicationWillFinishLaunching:(NSNotification *)notification;
- (void)applicationDidFinishLaunching:(NSNotification *)notification;
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender;
- (void)applicationWillTerminate:(NSNotification *)notification;

- (void)checkMessageOfTheDay; // This will display the message of the day if it has changed since the last time it was displayed.

@end
