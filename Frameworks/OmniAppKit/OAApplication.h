// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OAApplication.h 104581 2008-09-06 21:18:23Z kc $

#import <AppKit/NSApplication.h>
#import <Foundation/NSDate.h> // For NSTimeInterval
#import <Foundation/NSPathUtilities.h> // For NSSearchPathDomainMask
#import <AppKit/NSNibDeclarations.h> // For IBAction
#import <OmniAppKit/FrameworkDefines.h>

@class NSDate, NSException, NSMutableArray, NSMutableDictionary;
@class NSPanel;

@interface OAApplication : NSApplication
{
    NSDate *exceptionCheckpointDate;
    unsigned int exceptionCount;
    NSTimeInterval lastEventTimeInterval;
    unsigned int mouseButtonState;
    NSMutableDictionary *windowsForSheets;
    NSMutableArray *sheetQueue;
    NSPanel *currentRunExceptionPanel;
}

- (void)handleInitException:(NSException *)anException;
- (void)handleRunException:(NSException *)anException;
- (NSPanel *)currentRunExceptionPanel;

- (NSWindow *)frontWindowForMouseLocation;

- (NSTimeInterval)lastEventTimeInterval;
- (BOOL)mouseButtonIsDownAtIndex:(unsigned int)mouseButtonIndex;
- (BOOL)scrollWheelButtonIsDown;
- (unsigned int)currentModifierFlags;
- (BOOL)checkForModifierFlags:(unsigned int)flags;
- (unsigned int)launchModifierFlags;

- (void)scheduleModalPanelForTarget:(id)modalController selector:(SEL)modalSelector userInfo:(id)userInfo;
    // This method ensures that a modal panel is never presented while another modal panel is already being shown.  It accomplishes this by ensuring that modalSelector is never called on modalController while the runloop mode is NSModalPanelRunLoopMode.
    // You cannot rely on -scheduleModalPanelForTarget:selector: to block; if there is already a modal panel on screen, then a timer is scheduled on the runloop for NSDefaultRunLoopMode and this method returns immediately.
    // modalController is the controller object which will present the modal panel.
    // modalSelector is the selector which presents said panel.
    // userInfo is an optional object which can be passed to modalController's modalSelector method.
    
// Show a specific Help page in an appropriate viewer.
- (void)showHelpURL:(NSString *)helpURL;
    // - If invoked in OmniWeb, opens the URL in OmniWeb. helpURL should be a path relative to omniweb:/Help/.
    // - If invoked in an application that has Apple Help content (determined by the presence of the CFBundleHelpBookName key in the app's Info.plist), the URL will display in  Help Viewer. helpURL should be a path relative to the help book folder.
    // - Otherwise, we hand the URL off to NSWorkspace. This should generally be avoided.

// Actions
- (IBAction)closeAllMainWindows:(id)sender;
- (IBAction)cycleToNextMainWindow:(id)sender;
- (IBAction)cycleToPreviousMainWindow:(id)sender;
- (IBAction)showPreferencesPanel:(id)sender;

- (void)miniaturizeWindows:(NSArray *)windows;

// Application Support directory
- (NSString *)applicationSupportDirectoryName; // Calls the delegate, falls back to the process name. Does not cache.
- (NSArray *)supportDirectoriesInDomain:(NSSearchPathDomainMask)domains;
- (NSArray *)readableSupportDirectoriesInDomain:(NSSearchPathDomainMask)domains withComponents:(NSString *)subdir, ...;
- (NSString *)writableSupportDirectoryInDomain:(NSSearchPathDomainMask)domains withComponents:(NSString *)subdir, ...;

@end

@interface NSObject (OAApplicationDelegate)
- (NSString *)applicationSupportDirectoryName;
@end

@interface NSResponder (OAApplicationEvents)
- (void)controlMouseDown:(NSEvent *)event;
@end


OmniAppKit_EXTERN NSString *OAFlagsChangedNotification; // Posted when we send a modfier-flags-changed event; notification object is the event
OmniAppKit_EXTERN NSString *OAFlagsChangedQueuedNotification; // Same as OAFlagsChangedNotification, but queued with NSPostWhenIdle
