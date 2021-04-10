// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIResponder.h>

#import <MessageUI/MFMailComposeViewController.h>
#import <OmniUI/OUIFeatures.h>
#import <OmniUI/OUIWebViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class UIBarButtonItem;
@class OUIMenuOption;

// IMPORTANT note about the error/alert presentation macros.
//
// Avoid using the _IN_ACTIVE_SCENE variants. These will attempt to look up an active scene, but all the scenes that are currently on screen (side-by-side, or in slideover) are in the active state, so it will pick one subject to the semantics of `+windowForScene:options:` when passed a nil scene and allowing cascading lookup.
//
// Prefer to specify a non-nil scene, or a view controller to present from.

#define OUI_PRESENT_ERROR_IN_SCENE(error, scene) [[[OUIAppController controller] class] presentError:(error) inScene:scene file:__FILE__ line:__LINE__]
#define OUI_PRESENT_ERROR_IN_ACTIVE_SCENE(error) [[[OUIAppController controller] class] presentError:(error) inScene:nil file:__FILE__ line:__LINE__]
#define OUI_PRESENT_ERROR_FROM(error, viewController) [[[OUIAppController controller] class] presentError:(error) fromViewController:(viewController) file:__FILE__ line:__LINE__]

#define OUI_PRESENT_ALERT_IN_SCENE(error, scene) [[[OUIAppController controller] class] presentAlert:(error) inScene:scene file:__FILE__ line:__LINE__]
#define OUI_PRESENT_ALERT_IN_ACTIVE_SCENE(error) [[[OUIAppController controller] class] presentAlert:(error) inScene:nil file:__FILE__ line:__LINE__]
#define OUI_PRESENT_ALERT_FROM(error, viewController) [[[OUIAppController controller] class] presentAlert:(error) fromViewController:(viewController) file:__FILE__ line:__LINE__]

#define OUI_PRESENT_ERROR_DEPRECATED(error) [[[OUIAppController controller] class] presentError:(error) fromViewController:[OUIAppController controller].window.rootViewController file:__FILE__ line:__LINE__]
#define OUI_PRESENT_ALERT_DEPRECATED(error) [[[OUIAppController controller] class] presentAlert:(error) fromViewController:[OUIAppController controller].window.rootViewController file:__FILE__ line:__LINE__]

/// An error with a @(NO) for this user info key will not get an error reporting option.
extern NSErrorUserInfoKey const OUIShouldOfferToReportErrorUserInfoKey;

/// Posted when attention is sought or no longer sought. Notifications user info will have key for the sort of attention, mapping to a boolean value which is YES if attention is sought or NO if attention is no longer sought.
extern NSNotificationName const OUIAttentionSeekingNotification;
/// The key for when attention is sought for new "News" from Omni.
extern NSString * const OUIAttentionSeekingForNewsKey;

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

typedef NS_OPTIONS(NSUInteger, OUIApplicationEditionOptions) {
    OUIApplicationEditionOptionsNone                        = 0,
    OUIApplicationEditionOptionsIncludeApplicationName      = 1 << 0,
    OUIApplicationEditionOptionsIncludeMajorVersionNumber   = 1 << 1,
    OUIApplicationEditionOptionsVerbose                     = (OUIApplicationEditionOptionsIncludeApplicationName | OUIApplicationEditionOptionsIncludeMajorVersionNumber),
};

typedef NS_OPTIONS(NSUInteger, OUIWindowForSceneOptions) {
    OUIWindowForSceneOptionsNone                            = 0,
    OUIWindowForSceneOptionsAllowCascadingLookup            = 1 << 0,
    OUIWindowForSceneOptionsRequireForegroundActiveScene    = 1 << 1,
    OUIWindowForSceneOptionsRequireForegroundScene          = 1 << 2,
};

@property (class, nonatomic, nullable, readonly) NSString *applicationEdition;
+ (nullable NSString *)applicationEditionWithOptions:(OUIApplicationEditionOptions)options;

@property (class, nonatomic, nullable, readonly) NSString *majorVersionNumberString;

extern NSString *const OUIHelpBookNameKey; // @"OUIHelpBookName" is the Info.plist key which tells the app where to find its built-in help

@property (class, nonatomic, nullable, readonly) NSString *helpEdition;
@property (class, nonatomic, nullable, readonly) NSString *helpTitle;

@property (class, nonatomic, readonly, getter=inSandboxStore) BOOL sandboxStore;

+ (BOOL)canHandleURLScheme:(NSString *)urlScheme;
+ (void)openURL:(NSURL*)url options:(NSDictionary<NSString *, id> *)options completionHandler:(void (^ __nullable)(BOOL success))completion NS_EXTENSION_UNAVAILABLE_IOS("") NS_DEPRECATED_IOS(13_0, 13_0, "The singleton app controller cannot know the correct presentation source in a multi-scene context.");

+ (BOOL)shouldOfferToReportError:(NSError *)error;
+ (void)presentError:(NSError *)error NS_EXTENSION_UNAVAILABLE_IOS("Use +presentError:fromViewController: or another variant instead.");
+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController;
+ (void)presentError:(NSError *)error inScene:(nullable UIScene *)scene file:(const char * _Nullable)file line:(int)line NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based approach.");
+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char * _Nullable)file line:(int)line;
+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char * _Nullable)file line:(int)line optionalActionTitle:(nullable NSString *)optionalActionTitle optionalAction:(void (^ __nullable)(UIAlertAction *action))optionalAction;
+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController cancelButtonTitle:(NSString *)cancelButtonTitle optionalActionTitle:(nullable NSString *)optionalActionTitle optionalAction:(void (^ __nullable)(UIAlertAction *action))optionalAction;

+ (void)presentAlert:(NSError *)error inScene:(nullable UIScene *)scene file:(const char * _Nullable)file line:(int)line NS_EXTENSION_UNAVAILABLE_IOS("Use +presentAlert:fromViewController:file:line: instead.");  // 'OK' instead of 'Cancel' for the button title
+ (void)presentAlert:(NSError *)error file:(const char * _Nullable)file line:(int)line NS_EXTENSION_UNAVAILABLE_IOS("Use +presentAlert:fromViewController:file:line: instead.") NS_DEPRECATED_IOS(13_0, 13_0, "The singleton app controller cannot know the correct presentation source in a multi-scene context. Use +presentAlert:fromViewController:file:line: instead.");  // 'OK' instead of 'Cancel' for the button title

+ (void)presentAlert:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char * _Nullable)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title

- (NSOperationQueue *)backgroundPromptQueue;

@property (nonatomic, nullable, strong) IBOutlet UIWindow *window NS_DEPRECATED_IOS(5_0, 13_0, "Use view controller and scene based alternatives.");

/// When passing a nil scene and OUIWindowForSceneOptionsAllowCascadingLookup, this method will attempt to find a scene which mathces the other options passed.
///
/// However, when doing this search, all the scenes that are currently on screen (side-by-side, or in slideover) are in the active state. The resolved window will be the main window for the scene associated with the key window, but failing that, a random scene out of the active ones will be picked, which is likely not what you want.
+ (nullable UIWindow *)windowForScene:(nullable UIScene *)scene options:(OUIWindowForSceneOptions)options NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based approach.");

// Can be set by early startup code and queried by later startup code to determine whether to launch into a plain state (no inbox item opened, no last document opened, etc). This can be used by applications integrating crash reporting software when they detect a crash from a previous launch and want to report it w/o other launch-time activities.
@property(nonatomic,assign) BOOL shouldPostponeLaunchActions;
- (void)addLaunchAction:(void (^)(void))launchAction;

@property (nonatomic, nullable, readonly) NSURL *helpForwardURL; // Used to rewrite URLs to point at our website as needed
@property (nonatomic, nullable, readonly) NSURL *onlineHelpURL; // URL pointing at our help (could be embedded in the app)
@property (nonatomic, readonly) BOOL hasOnlineHelp;

// UIApplicationDelegate methods that we implement
- (void)applicationWillTerminate:(UIApplication *)application;
- (void)applicationDidEnterBackground:(UIApplication *)application;
- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application;

// A UIResponder to make first responder if the app delegate is asked to become first responder.
@property(nonatomic,readonly) UIResponder *defaultFirstResponder NS_EXTENSION_UNAVAILABLE_IOS("Not available in extensions.");

// Just stores a default that other parts of the app can use to set/get what keyboard to use.
@property(nonatomic,assign) UIKeyboardAppearance defaultKeyboardAppearance;

// Subclass responsibility
- (void)resetKeychain;

- (BOOL)isRunningRetailDemo;
- (BOOL)showFeatureDisabledForRetailDemoAlertFromViewController:(UIViewController *)presentingViewController; // Runs an alert and returns YES if running a retail demo.

@property(nonatomic,readonly) NSString *fullReleaseString;

// App menu support
@property (nonatomic, strong, nullable) NSString *newsURLStringToShowWhenReady;

@property (nonatomic, readonly) BOOL hasUnreadNews;
@property (nonatomic, readonly) BOOL hasAnyNews;
- (BOOL)haveShownReleaseNotes:(NSString *)urlString;
- (void)didShowReleaseNotes:(NSString *)urlString;

/// The most recent news URL, which could be an unread one or just the most recently shown one. Will be nil if there is no unread news and no already-read news stored in preferences.
- (NSString *)mostRecentNewsURLString;

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
- (NSString *)currentSKU;
- (NSString *)purchaseDateString;
- (NSString *)appSpecificDebugInfo;

@property (nonatomic, readonly) BOOL newsWantsAttention;

- (NSArray *)additionalAppMenuOptionsAtPosition:(OUIAppMenuOptionPosition)position; // override to supplement super's return value with additional OUIMenuOptions
- (nullable OUIMenuOption *)specialFirstAppMenuOption; // Override to place an option at the top of the list, separate from the rest
- (void)sendFeedbackWithSubject:(NSString * _Nullable)subject body:(NSString * _Nullable)body inScene:(nullable UIScene *)scene NS_EXTENSION_UNAVAILABLE_IOS("Feedback cannot be sent from extensions.");
- (void)signUpForOmniNewsletterFromViewController:(UIViewController *)viewController NS_EXTENSION_UNAVAILABLE_IOS("Extensions cannot sign up for the Omni newsletter");
- (MFMailComposeViewController * _Nullable)mailComposeController;
- (void)sendMailTo:(NSArray<NSString *> *)recipients withComposeController:(MFMailComposeViewController *)mailComposeController inScene:(nullable UIScene *)scene;

@property(nonatomic,readonly) UIImage *appMenuImage;
@property(nonatomic,readonly) UIImage *aboutMenuImage;
@property(nonatomic,readonly) UIImage *helpMenuImage;
@property(nonatomic,readonly) UIImage *sendFeedbackMenuImage;
@property(nonatomic,readonly) UIImage *newsletterMenuImage;
@property(nonatomic,readonly) UIImage *announcementMenuImage;
@property(nonatomic,readonly) UIImage *announcementBadgedMenuImage;
@property(nonatomic,readonly) UIImage *releaseNotesMenuImage;
@property(nonatomic,readonly) UIImage *settingsMenuImage;
@property(nonatomic,readonly) UIImage *inAppPurchasesMenuImage;
@property(nonatomic,readonly) UIImage *quickStartMenuImage;
@property(nonatomic,readonly) UIImage *trialModeMenuImage;
@property(nonatomic,readonly) UIImage *introVideoMenuImage;
@property(nonatomic,readonly) UIImage *registerMenuImage;
@property(nonatomic,readonly) UIImage *specialLicensingImage;

@property(nonatomic,readonly) BOOL useCompactBarButtonItemsIfApplicable; // will allow for possible compact versions of navbar items

- (UIImage *)exportBarButtonItemImageInViewController:(UIViewController *)viewController;

- (void)willWaitForSnapshots;
- (void)didFinishWaitingForSnapshots;
- (void)startNewSnapshotTimer;
- (void)destroyCurrentSnapshotTimer;
extern NSNotificationName const OUISystemIsSnapshottingNotification;

@property (readonly) BOOL canCreateNewDocument;
@property (readonly) BOOL shouldEnableCreateNewDocument;
- (void)unlockCreateNewDocumentWithCompletion:(void (^ __nonnull)(BOOL isUnlocked))completionBlock;

- (void)checkTemporaryLicensingStateWithCompletionHandler:(void (^ __nullable)(void))completionHandler;

@end

extern BOOL OUIShouldLogPerformanceMetrics;
extern NSTimeInterval OUIElapsedTimeSinceProcessCreation(void); // For timing startup work before main() is entered
extern NSTimeInterval OUIElapsedTimeSinceApplicationStarted(void); // Time since the beginning of -[OUIApplication initialize]

@interface UIViewController (OUIDisabledDemoFeatureAlerter) <OUIDisabledDemoFeatureAlerter>
- (NSString *)featureDisabledForDemoAlertTitle;
@end

#define OUILogPerformanceMetric(format, ...) if (OUIShouldLogPerformanceMetrics) NSLog((format), ## __VA_ARGS__)

NS_ASSUME_NONNULL_END
