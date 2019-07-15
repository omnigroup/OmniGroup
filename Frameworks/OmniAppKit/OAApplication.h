// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSApplication.h>
#import <Foundation/NSDate.h> // For NSTimeInterval
#import <Foundation/NSPathUtilities.h> // For NSSearchPathDomainMask
#import <AppKit/NSNibDeclarations.h> // For IBAction

@class NSDate;
@class NSPanel;
@class OFVersionNumber;
@class OADocument;

@interface OAApplication : NSApplication

+ (instancetype)sharedApplication;

@property(nonatomic,readonly) OFVersionNumber *buildVersionNumber;

- (NSWindow *)frontWindowForMouseLocation;

- (NSTimeInterval)lastEventTimeInterval;
- (BOOL)mouseButtonIsDownAtIndex:(unsigned int)mouseButtonIndex;
- (BOOL)scrollWheelButtonIsDown;
@property(nonatomic,readonly) NSEventModifierFlags launchModifierFlags;
    
// Show a specific Help page in an appropriate viewer.
- (void)showHelpURL:(NSString *)helpURL;
    // - If invoked in OmniWeb, opens the URL in OmniWeb. helpURL should be a path relative to omniweb:/Help/.
    // - If invoked in an application that has built-in HTML help (Omni-style, determined by the presence of the OAHelpFolder key in the app's Info.plist), the (mapped) URL will be displayed in the built-in help viewer.
    // - If invoked in an application that has Apple Help content (determined by the presence of the CFBundleHelpBookName key in the app's Info.plist), the URL will display in Help Viewer. helpURL should be a path relative to the help book folder.
    // - Otherwise, we hand the URL off to NSWorkspace. This should generally be avoided.

@property (nonatomic, readonly) NSString *helpIndexFilename; // name the file minus the file extension.
@property (nonatomic, readonly) NSString *anchorsPlistFilename;
- (NSURL *)builtInHelpURLForHelpURLString:(NSString *)helpURLString;
    // If the application has built-in help content (as determined by the presence of the OAHelpFolder key in the app's Info.plist), returns the URL that should be opened in the built-in help viewer, otherwise returns nil.
    // This is typically only used internally by -showHelpURL:, but may be used by a subclass which has need to override -showHelpURL: to spawn custom viewers for certain help documents.

// Application Support directory
- (NSString *)applicationSupportDirectoryName; // Calls the delegate, falls back to the process name. Does not cache.
- (NSArray *)supportDirectoriesInDomain:(NSSearchPathDomainMask)domains;
- (NSArray *)readableSupportDirectoriesInDomain:(NSSearchPathDomainMask)domains withComponents:(NSString *)subdir, ... NS_REQUIRES_NIL_TERMINATION;
- (NSString *)writableSupportDirectoryInDomain:(NSSearchPathDomainMask)domains withComponents:(NSString *)subdir, ... NS_REQUIRES_NIL_TERMINATION;

// Actions
- (IBAction)closeAllMainWindows:(id)sender;
- (IBAction)cycleToNextMainWindow:(id)sender;
- (IBAction)cycleToPreviousMainWindow:(id)sender;
- (IBAction)showPreferencesPanel:(id)sender;

- (void)miniaturizeWindows:(NSArray *)windows;

// AppleScript
- (id)valueInOrderedDocumentsWithUniqueID:(NSString *)identifier ignoringDocument:(OADocument *)ignoringDocument;
- (id)valueInOrderedDocumentsWithUniqueID:(NSString *)identifier;
- (id)valueInOrderedDocumentsWithName:(NSString *)name;

@end

@protocol OAApplicationDelegate <NSApplicationDelegate>
@optional
- (NSString *)applicationSupportDirectoryName:(OAApplication *)application;
- (void)openAddressWithString:(NSString *)urlString;
- (void)downloadAddressWithString:(NSString *)urlString;
@end

@interface NSResponder (OAApplicationEvents)
- (void)controlMouseDown:(NSEvent *)event;
@end

extern NSString * const OAFlagsChangedNotification; // Posted when we send a modfier-flags-changed event; notification object is the event
extern NSString * const OAFlagsChangedQueuedNotification; // Same as OAFlagsChangedNotification, but queued with NSPostWhenIdle

// OAApplications's enhanced target selection support is off by default for now.  Set the "OATargetSelection" user default to YES to use it.
// Return NO to stop the applier, YES to continue
typedef BOOL (^OAResponderChainApplier)(id target);

extern BOOL OATargetSelectionEnabled(void);

@interface NSObject (OATargetSelection)
// Return NO to stop the traversal, YES to continue
- (BOOL)applyToResponderChain:(OAResponderChainApplier)applier;
- (id)responsibleTargetForAction:(SEL)action sender:(id)sender;
@end
