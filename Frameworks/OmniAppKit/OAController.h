// Copyright 2004-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFController.h>

@class OAAboutPanelController;

#import <AppKit/NSApplication.h> // For NSApplicationDelegate
#import <AppKit/NSNibDeclarations.h> // For IBAction and IBOutlet

NS_ASSUME_NONNULL_BEGIN

@interface OAController : OFController <NSApplicationDelegate>

+ (BOOL)handleChangePreferenceURL:(NSURL *)url error:(NSError **)outError;

- (OAAboutPanelController *)aboutPanelController;

- (IBAction)showAboutPanel:(nullable id)sender;
- (IBAction)hideAboutPanel:(nullable id)sender;
- (IBAction)sendFeedback:(nullable id)sender;
- (IBAction)showMessageOfTheDay:(nullable id)sender;
- (IBAction)openApplicationScriptsFolder:(nullable id)sender;

/// returns the the display name of the application without file extension.
- (NSString *)appName NS_DEPRECATED_MAC(10_0, 10_13, "Use the applicationName property instead.");
@property (nonatomic, readonly) NSString *applicationName;
@property (nonatomic, readonly) NSString *fullReleaseString;

- (void)getFeedbackAddress:(NSString * _Nullable * _Nonnull)feedbackAddress andSubject:(NSString * _Nullable * _Nonnull)subjectLine;
- (void)sendFeedbackEmailTo:(nullable NSString *)feedbackAddress subject:(nullable NSString *)subjectLine body:(nullable NSString *)body;
- (void)sendFeedbackEmailWithBody:(nullable NSString *)body;

- (BOOL)openURL:(NSURL *)url; // Passes this off to -[NSWorkspace openURL:] if the local app doesn't intercept the URL

- (void)checkMessageOfTheDay; // This will display the message of the day if it has changed since the last time it was displayed.

- (NSOperationQueue *)backgroundPromptQueue;

// OAController has concrete implementations of the following NSApplicationDelegate methods. They're responsible for driving the OFController behavior at appropriate times during the app's lifecycle. If you override these methods, be sure to call super's implementation.
- (void)applicationWillFinishLaunching:(NSNotification *)notification NS_REQUIRES_SUPER;
- (void)applicationDidFinishLaunching:(NSNotification *)notification NS_REQUIRES_SUPER;
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender NS_REQUIRES_SUPER;
- (void)applicationWillTerminate:(NSNotification *)notification NS_REQUIRES_SUPER;

@end

NS_ASSUME_NONNULL_END
