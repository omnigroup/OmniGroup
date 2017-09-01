// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIResponder.h>

#import <MessageUI/MFMailComposeViewController.h>
#import <OmniUI/OUIFeatures.h>
#import <OmniUI/OUIWebViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class UIBarButtonItem;

#define OUI_PRESENT_ERROR(error) [[[OUIAppController controller] class] presentError:(error) fromViewController:[[[[UIApplication sharedApplication] delegate] window] rootViewController] file:__FILE__ line:__LINE__]
#define OUI_PRESENT_ERROR_FROM(error, viewController) [[[OUIAppController controller] class] presentError:(error) fromViewController:(viewController) file:__FILE__ line:__LINE__]

#define OUI_PRESENT_ALERT(error) [[[OUIAppController controller] class] presentAlert:(error) fromViewController:[[[[UIApplication sharedApplication] delegate] window] rootViewController] file:__FILE__ line:__LINE__]
#define OUI_PRESENT_ALERT_FROM(error, viewController) [[[OUIAppController controller] class] presentAlert:(error) fromViewController:(viewController) file:__FILE__ line:__LINE__]

/// Posted when attention is sought or no longer sought. Notifications user info will have key for the sort of attention, mapping to a boolean value which is YES if attention is sought or NO if attention is no longer sought.
extern NSString *OUIAttentionSeekingNotification;
/// The key for when attention is sought for new "News" from Omni.
extern NSString *OUIAttentionSeekingForNewsKey;

@protocol OUIDisabledDemoFeatureAlerter
- (NSString *)featureDisabledForDemoAlertTitle;
@optional
- (NSString *)featureDisabledForDemoAlertMessage;
@end

@interface OUIAppController : UIResponder <UIApplicationDelegate, MFMailComposeViewControllerDelegate, OUIWebViewControllerDelegate>

+ (nonnull instancetype)controller NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");

// +sharedController is a synonym for +controller.
// The Swift bridge allows us to use +sharedController, but generates a compile error on +controller, suggesting we use a constructor instead.
+ (nonnull instancetype)sharedController NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");

+ (NSString *)applicationName;
+ (nullable NSString *)applicationEdition;
+ (BOOL)inSandboxStore;

+ (BOOL)canHandleURLScheme:(NSString *)urlScheme;

+ (void)presentError:(NSError *)error NS_EXTENSION_UNAVAILABLE_IOS("Use +presentError:fromViewController: or another variant instead.");
+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController;
+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char * _Nullable)file line:(int)line;
+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char * _Nullable)file line:(int)line optionalActionTitle:(NSString *)optionalActionTitle optionalAction:(void (^ __nullable)(UIAlertAction *action))optionalAction;
+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController cancelButtonTitle:(NSString *)cancelButtonTitle optionalActionTitle:(NSString *)optionalActionTitle optionalAction:(void (^ __nullable)(UIAlertAction *action))optionalAction;

+ (void)presentAlert:(NSError *)error file:(const char * _Nullable)file line:(int)line NS_EXTENSION_UNAVAILABLE_IOS("Use +presentAlert:fromViewController:file:line: instead.");  // 'OK' instead of 'Cancel' for the button title

+ (void)presentAlert:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char * _Nullable)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title

- (NSOperationQueue *)backgroundPromptQueue;

// Can be set by early startup code and queried by later startup code to determine whether to launch into a plain state (no inbox item opened, no last document opened, etc). This can be used by applications integrating crash reporting software when they detect a crash from a previous launch and want to report it w/o other launch-time activities.
@property(nonatomic,assign) BOOL shouldPostponeLaunchActions;
- (void)addLaunchAction:(void (^)(void))launchAction;

- (void)showAboutScreenInNavigationController:(UINavigationController * _Nullable)navigationController NS_EXTENSION_UNAVAILABLE_IOS("");
@property(nonatomic,readonly) BOOL hasOnlineHelp;
- (void)showOnlineHelp:(nullable id)sender NS_EXTENSION_UNAVAILABLE_IOS("");

// UIApplicationDelegate methods that we implement
- (void)applicationWillTerminate:(UIApplication *)application;
- (void)applicationDidEnterBackground:(UIApplication *)application;
- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application;

// A UIResponder to make first responder if the app delegate is asked to become first responder.
@property(nonatomic,readonly) UIResponder *defaultFirstResponder;

// Just stores a default that other parts of the app can use to set/get what keyboard to use.
@property(nonatomic,assign) UIKeyboardAppearance defaultKeyboardAppearance;

// Subclass responsibility
- (void)resetKeychain;

- (BOOL)isRunningRetailDemo;
- (BOOL)showFeatureDisabledForRetailDemoAlertFromViewController:(UIViewController *)presentingViewController; // Runs an alert and returns YES if running a retail demo.

@property(nonatomic,readonly) NSString *fullReleaseString;

// App menu support
@property (nonatomic, strong, nullable) NSString *newsURLStringToShowWhenReady;
@property (nonatomic, strong, nullable) NSString *newsURLCurrentlyShowing;
@property (nonatomic, weak) OUIWebViewController *newsViewController NS_EXTENSION_UNAVAILABLE_IOS("OUIWebViewController not available in app extensions.");
- (void)dismissAppMenuIfVisible:(UINavigationController *)navigationController;

@property (nonatomic, readonly) BOOL hasUnreadNews;
@property (nonatomic, readonly) BOOL hasAnyNews;

/// The most recent news URL, which could be an unread one or just the most recently shown one. Will be nil if there is no unread news and no already-read news stored in preferences.
- (NSString *)mostRecentNewsURLString;

- (OUIWebViewController * _Nullable)showNewsURLString:(NSString *)urlString evenIfShownAlready:(BOOL)showNoMatterWhat NS_EXTENSION_UNAVAILABLE_IOS("OUIWebViewController not available in app extensions.");

typedef NS_ENUM(NSInteger, OUIAppMenuOptionPosition) {
    OUIAppMenuOptionPositionBeforeReleaseNotes,
    OUIAppMenuOptionPositionAfterReleaseNotes,
    OUIAppMenuOptionPositionAtEnd
};

// override to customize the about screen
- (NSString *)aboutMenuTitle;
- (NSString *)aboutScreenTitle;
- (NSURL *)aboutScreenURL;
- (NSDictionary *)aboutScreenBindingsDictionary;

extern NSString *const OUIAboutScreenBindingsDictionaryVersionStringKey; // @"versionString"
extern NSString *const OUIAboutScreenBindingsDictionaryCopyrightStringKey; // @"copyrightString"
extern NSString *const OUIAboutScreenBindingsDictionaryFeedbackAddressKey; // @"feedbackAddress"

- (NSString *)feedbackMenuTitle;
- (NSString *)appSpecificDebugInfo;
- (UIBarButtonItem *)newAppMenuBarButtonItem; // insert this into your view controllers; see -additionalAppMenuOptionsAtPosition: for customization
- (NSArray *)additionalAppMenuOptionsAtPosition:(OUIAppMenuOptionPosition)position; // override to supplement super's return value with additional OUIMenuOptions
- (void)sendFeedbackWithSubject:(NSString * _Nullable)subject body:(NSString * _Nullable)body NS_EXTENSION_UNAVAILABLE_IOS("Feedback cannot be sent from extensions.");
- (IBAction)sendFeedback:(id)sender NS_EXTENSION_UNAVAILABLE_IOS("");
- (MFMailComposeViewController * _Nullable)mailComposeController;
- (void)sendMailTo:(NSArray<NSString *> *)recipients withComposeController:(MFMailComposeViewController *)mailComposeController;

/// Presents a view controller displaying the contents of the given URL in an in-app web view. The view controller is wrapped in a UINavigationController instance; if non-nil, the given title is shown in the navigation bar of this controller. Returns the web view controller being used to show the URL's content.
- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title NS_EXTENSION_UNAVAILABLE_IOS("OUIWebViewController not available in app extensions.");
- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title modalPresentationStyle:(UIModalPresentationStyle)presentationStyle modalTransitionStyle:(UIModalTransitionStyle)transitionStyle animated:(BOOL)animated NS_EXTENSION_UNAVAILABLE_IOS("OUIWebViewController not available in app extensions.");
- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title modalPresentationStyle:(UIModalPresentationStyle)presentationStyle modalTransitionStyle:(UIModalTransitionStyle)transitionStyle  animated:(BOOL)animated navigationController:(UINavigationController * _Nullable)navigationController NS_EXTENSION_UNAVAILABLE_IOS("OUIWebViewController not available in app extensions.");

@property(nonatomic,readonly) UIImage *settingsMenuImage;
@property(nonatomic,readonly) UIImage *inAppPurchasesMenuImage;
@property(nonatomic,readonly) UIImage *quickStartMenuImage;
@property(nonatomic,readonly) UIImage *trialModeMenuImage;
@property(nonatomic,readonly) UIImage *introVideoMenuImage;

@property(nonatomic,readonly) BOOL useCompactBarButtonItemsIfApplicable; // will allow for possible compact versions of navbar items

- (UIImage *)exportBarButtonItemImageInHostViewController:(UIViewController *)hostViewController;

- (void)willWaitForSnapshots;
- (void)didFinishWaitingForSnapshots;
- (void)startNewSnapshotTimer;
- (void)destroyCurrentSnapshotTimer;
extern NSString * const OUISystemIsSnapshottingNotification;

@property (readonly) BOOL canCreateNewDocument;

@end

extern BOOL OUIShouldLogPerformanceMetrics;
extern NSTimeInterval OUIElapsedTimeSinceProcessCreation(void); // For timing startup work before main() is entered
extern NSTimeInterval OUIElapsedTimeSinceApplicationStarted(void); // Time since the beginning of -[OUIApplication initialize]

@interface UIViewController (OUIDisabledDemoFeatureAlerter) <OUIDisabledDemoFeatureAlerter>
- (NSString *)featureDisabledForDemoAlertTitle;
@end

#define OUILogPerformanceMetric(format, ...) if (OUIShouldLogPerformanceMetrics) NSLog((format), ## __VA_ARGS__)

NS_ASSUME_NONNULL_END
