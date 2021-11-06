// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIResponder.h>

#import <MessageUI/MFMailComposeViewController.h>
#import <OmniUI/OUIFeatures.h>
#import <OmniUI/OUIWebViewController.h>
#import <OmniUI/OUIEnqueueableAlertController.h>

NS_ASSUME_NONNULL_BEGIN

@class UIBarButtonItem;
@class OUIMenuOption;

#define OUI_PRESENT_ERROR_IN_SCENE(error, scene) [[[OUIAppController controller] class] presentError:(error) inScene:scene file:__FILE__ line:__LINE__]
#define OUI_PRESENT_ERROR_FROM(error, viewController) [[[OUIAppController controller] class] presentError:(error) fromViewController:(viewController) file:__FILE__ line:__LINE__]

#define OUI_PRESENT_ALERT_IN_SCENE(error, scene) [[[OUIAppController controller] class] presentAlert:(error) inScene:scene file:__FILE__ line:__LINE__]
#define OUI_PRESENT_ALERT_FROM(error, viewController) [[[OUIAppController controller] class] presentAlert:(error) fromViewController:(viewController) file:__FILE__ line:__LINE__]

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

typedef NS_OPTIONS(NSUInteger, OUIWindowForSceneOptions) {
    OUIWindowForSceneOptionsNone                            = 0,
    OUIWindowForSceneOptionsAllowFallbackLookup             = 1 << 0,
    OUIWindowForSceneOptionsRequireForegroundActiveScene    = 1 << 1, // Requirement is only applied in the fallback lookup path
    OUIWindowForSceneOptionsRequireForegroundScene          = 1 << 2, // Requirement is only applied in the fallback lookup path
};

@property (class, nonatomic, nullable, readonly) NSString *applicationEdition;
@property (class, nonatomic, nullable, readonly) NSString *majorVersionNumberString;
@property (class, nonatomic, readonly) NSString *appStoreApplicationId;
@property (class, nonatomic, readonly) NSString *appStoreReviewLink;

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
+ (void)presentError:(NSError *)error fromViewController:(nullable UIViewController *)viewController file:(const char * _Nullable)file line:(int)line;
+ (void)presentError:(NSError *)error fromViewController:(nullable UIViewController *)viewController file:(const char * _Nullable)file line:(int)line optionalActionTitle:(nullable NSString *)optionalActionTitle optionalAction:(void (^ __nullable)(OUIExtendedAlertAction *action))optionalAction;
+ (void)presentError:(NSError *)error fromViewController:(nullable UIViewController *)viewController cancelButtonTitle:(nullable NSString *)cancelButtonTitle optionalActionTitle:(nullable NSString *)optionalActionTitle optionalAction:(void (^ __nullable)(OUIExtendedAlertAction *action))optionalAction;
+ (void)presentError:(NSError *)error fromViewController:(nullable UIViewController *)viewController cancelButtonTitle:(nullable NSString *)cancelButtonTitle optionalActionTitle:(nullable NSString *)optionalActionTitle isDestructive:(BOOL)isDestructive optionalAction:(void (^ __nullable)(OUIExtendedAlertAction *action))optionalAction;
+ (void)presentError:(NSError *)error fromViewController:(nullable UIViewController *)viewController cancelButtonTitle:(nullable NSString *)cancelButtonTitle optionalActionTitle:(nullable NSString *)optionalActionTitle isDestructive:(BOOL)isDestructive optionalAction:(void (^ __nullable)(OUIExtendedAlertAction *action))optionalAction completionHandler:(void (^ _Nullable)(void))handler;
+ (void)presentError:(NSError *)error fromViewController:(nullable UIViewController *)viewController cancelButtonTitle:(nullable NSString *)cancelButtonTitle optionalActionTitle:(nullable NSString *)optionalActionTitle optionalAction:(void (^ __nullable)(OUIExtendedAlertAction *action))optionalAction completionHandler:(void (^ _Nullable)(void))handler;
+ (void)presentError:(NSError *)error fromViewController:(nullable UIViewController *)viewController file:(const char * _Nullable)file line:(int)line cancelButtonTitle:(nullable NSString *)cancelButtonTitle optionalActions:(nullable NSArray <OUIExtendedAlertAction *> *)optionalActions completionHandler:(void (^ _Nullable)(void))handler;

+ (void)presentAlert:(NSError *)error inScene:(nullable UIScene *)scene file:(const char * _Nullable)file line:(int)line NS_EXTENSION_UNAVAILABLE_IOS("Use +presentAlert:fromViewController:file:line: instead.");  // 'OK' instead of 'Cancel' for the button title
+ (void)presentAlert:(NSError *)error file:(const char * _Nullable)file line:(int)line NS_EXTENSION_UNAVAILABLE_IOS("Use +presentAlert:fromViewController:file:line: instead.") NS_DEPRECATED_IOS(13_0, 13_0, "The singleton app controller cannot know the correct presentation source in a multi-scene context. Use +presentAlert:fromViewController:file:line: instead.");  // 'OK' instead of 'Cancel' for the button title

+ (void)presentAlert:(NSError *)error fromViewController:(nullable UIViewController *)viewController file:(const char * _Nullable)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title

// Sometimes, extended alert actions trigger errors that we need to present to the user. Some error presentations need to spawn their own extended interaction (if we offer to report that error, the user will receive an email sheet)
+ (void)presentError:(NSError *)error fromViewController:(nonnull UIViewController *)viewController completingExtendedAction:(OUIExtendedAlertAction *)action;

- (NSOperationQueue *)backgroundPromptQueue;

@property (nonatomic, nullable, strong) IBOutlet UIWindow *window NS_DEPRECATED_IOS(5_0, 13_0, "Use view controller and scene based alternatives.");

// If there is more than one scene active, this returns the scene that had key focus.
@property (nonatomic, nullable, readonly) UIScene *mostRecentlyActiveScene;
@property (nonatomic, readonly) NSArray<UIScene *> *allConnectedScenes;
- (nullable UIScene *)mostRecentlyActiveSceneSatisfyingCondition:(BOOL (^)(UIScene *))condition;
- (NSArray<UIScene *> *)allConnectedScenesSatisfyingCondition:(BOOL (^)(UIScene *))condition;

/// When passing a nil scene and OUIWindowForSceneOptionsAllowFallbackLookup, this method will attempt to find a scene which mathces the other options passed.
///
/// However, when doing this search, all the scenes that are currently on screen (side-by-side, or in slideover) are in the active state. The resolved window will be the main window for the scene associated with the key window, but failing that, a random scene out of the active ones will be picked, which is likely not what you want.
+ (nullable UIWindow *)windowForScene:(nullable UIScene *)scene options:(OUIWindowForSceneOptions)options NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based approach.");

// If some scene is foreground and active, the controller will be presented immediately on that scene. If there is no foreground active scene, the controller will be displayed upon the next scene that enters the foreground.
+ (void)enqueueInteractionControllerPresentationForAnyForegroundScene:(UIViewController<ExtendedInteractionDefining> *)controller NS_SWIFT_NAME(enqueueInteractionControllerPresentationForAnyForegroundScene(_:));
+ (void)enqueueInteractionControllerPresentationForAnyForegroundScene:(UIViewController<ExtendedInteractionDefining> *)controller presentationCompletionHandler:(void (^ __nullable)(void))presentationCompletionHandler NS_SWIFT_NAME(enqueueInteractionControllerPresentationForAnyForegroundScene(_:presentationCompletionHandler:));

/* If the specified scene is foregrounded and active, then the controller is presented immediately. If the scene is not foreground active but some other scene is, then we will immediately present an alert on that active scene with the following format:
 
    "<activityContextTitle> is open in another window"
    [ activityContinuationButtonTitle ][ postponeActivityButtonTitle ]
 
    The activityContinuationButton will jump the user to the desired scene, where we will then present the enqueued alert. The postponeActivityButton will keep the user in the current workspace, and keep the alert enqueued. Subsequent scene activations will follow the same rules: if the desired scene is active then the controller is dequeued and presented; if some other scene is presented the user will see the above alert again.
 
    If no scene is foreground active, then the controller will be enqueued. If the desired scene is foregrounded, then the controller will be presented. If some other scene is foregrounded, we will present the alert detailed above, prompting the user to switch to the desired scene.
 
    Enqueuing your controller in this manner will prompt the user each time they open a non-desired scene, so be sure to use this method carefully. Only prompt for app-critical functionality, like OmniFocus syncing, or Omni Account setup. If you have a more local interaction, like showing a photo picker availability error or something else that doesn't need immediate consideration, instead just present that error on the backgrounded scene, leaving the user to find it when they foreground that scene again.
 */
+ (void)enqueueInteractionController:(UIViewController<ExtendedInteractionDefining> *)controller forPresentationInScene:(UIScene *)scene withActivityContextTitle:(NSString *)activityContextTitle activityContinuationButtonTitle:(NSString *)activityContinuationButtonTitle postponeActivityButtonTitle:(NSString *)postponeActivityButtonTitle;
+ (void)enqueueInteractionController:(UIViewController<ExtendedInteractionDefining> *)controller forPresentationInScene:(UIScene *)scene withActivityContextTitle:(NSString *)activityContextTitle activityContinuationButtonTitle:(NSString *)activityContinuationButtonTitle postponeActivityButtonTitle:(NSString *)postponeActivityButtonTitle presentationCompletionHandler:(void (^ __nullable)(void))presentationCompletionHandler;

@property (readonly, class) BOOL hasEnqueuedInteractionControllers;

// Can be set by early startup code and queried by later startup code to determine whether to launch into a plain state (no inbox item opened, no last document opened, etc). This can be used by applications integrating crash reporting software when they detect a crash from a previous launch and want to report it w/o other launch-time activities.
@property(nonatomic,assign) BOOL shouldPostponeLaunchActions;
- (void)addLaunchAction:(void (^)(void))launchAction;

@property (nonatomic, nullable, readonly) NSURL *helpForwardURL; // Used to rewrite URLs to point at our website as needed
@property (nonatomic, nullable, readonly) NSURL *onlineHelpURL; // URL pointing at our help (could be embedded in the app)
@property (nonatomic, readonly) BOOL hasOnlineHelp;

// UIApplication lifecycle subclassing points
@property (nonatomic, readonly, getter=isApplicationInForeground) BOOL applicationInForeground;
- (void)applicationDidBecomeActive NS_REQUIRES_SUPER;
- (void)applicationWillResignActive NS_REQUIRES_SUPER;
- (void)applicationWillEnterForeground NS_REQUIRES_SUPER;
- (void)applicationDidEnterBackground NS_REQUIRES_SUPER;

// UIApplicationDelegate methods that we implement
- (void)applicationWillTerminate:(UIApplication *)application;
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
@property (nonatomic, nullable, readonly) NSString *mostRecentNewsURLString;

typedef NS_ENUM(NSInteger, OUIAppMenuOptionPosition) {
    OUIAppMenuOptionPositionBeforeReleaseNotes,
    OUIAppMenuOptionPositionAfterReleaseNotes,
    OUIAppMenuOptionPositionAtEnd
};

// override to customize the about screen
- (NSString *)omniAccountMenuTitle;
- (NSString *)aboutMenuTitle;
- (NSString *)aboutScreenTitle;
- (NSURL *)aboutScreenURL;
- (NSDictionary *)aboutScreenBindingsDictionary;

extern NSString *const OUIAboutScreenBindingsDictionaryVersionStringKey; // @"versionString"
extern NSString *const OUIAboutScreenBindingsDictionaryCopyrightStringKey; // @"copyrightString"
extern NSString *const OUIAboutScreenBindingsDictionaryFeedbackAddressKey; // @"feedbackAddress"

- (NSString *)feedbackMenuTitle;
- (nullable NSString *)currentSKU;
- (NSString *)purchaseDateString;
- (NSString *)appSpecificDebugInfo;
- (void)addFilesToAppDebugInfoWithHandler:(void (^ _Nonnull)(NSURL * _Nonnull))handler;

@property (nonatomic, readonly) BOOL newsWantsAttention;

- (NSArray *)additionalAppMenuOptionsAtPosition:(OUIAppMenuOptionPosition)position; // override to supplement super's return value with additional OUIMenuOptions
- (nullable OUIMenuOption *)specialFirstAppMenuOption; // Override to place an option at the top of the list, separate from the rest
- (void)sendFeedbackWithSubject:(NSString * _Nullable)subject body:(NSString * _Nullable)body inScene:(nullable UIScene *)scene completion:(void (^ _Nullable)(void))mailInteractionCompletionHandler NS_EXTENSION_UNAVAILABLE_IOS("Feedback cannot be sent from extensions.");
- (void)signUpForOmniNewsletterFromViewController:(UIViewController *)viewController NS_EXTENSION_UNAVAILABLE_IOS("Extensions cannot sign up for the Omni newsletter");
- (MFMailComposeViewController * _Nullable)newMailComposeController;
- (void)sendMailTo:(NSArray<NSString *> *)recipients withComposeController:(MFMailComposeViewController *)mailComposeController inScene:(nullable UIScene *)scene;
- (void)showSettingsFromViewController:(UIViewController *)viewController prefPaneToPush:(UIViewController *) paneToPush potentialDismissViewHandler:(void (^)(void))dismissHandler;

@property(nonatomic,readonly) UIImage *appMenuImage;
@property(nonatomic,readonly) UIImage *aboutMenuImage;
@property(nonatomic,readonly) UIImage *helpMenuImage;
@property(nonatomic,readonly) UIImage *sendFeedbackMenuImage;
@property(nonatomic,readonly) UIImage *newsletterMenuImage;
@property(nonatomic,readonly) UIImage *announcementMenuImage;
@property(nonatomic,readonly) UIImage *announcementBadgedMenuImage;
@property(nonatomic,readonly) UIImage *releaseNotesMenuImage;
@property(nonatomic,readonly) UIImage *configureOmniPresenceMenuImage;
@property(nonatomic,readonly) UIImage *settingsMenuImage;
@property(nonatomic,readonly) UIImage *omniAccountsMenuImage;
@property(nonatomic,readonly) UIImage *inAppPurchasesMenuImage;
@property(nonatomic,readonly) UIImage *quickStartMenuImage;
@property(nonatomic,readonly) UIImage *trialModeMenuImage;
@property(nonatomic,readonly) UIImage *introVideoMenuImage;
@property(nonatomic,readonly) UIImage *registerMenuImage;
@property(nonatomic,readonly) UIImage *specialLicensingImage;

@property(nonatomic,readonly) BOOL useCompactBarButtonItemsIfApplicable; // will allow for possible compact versions of navbar items

- (UIImage *)exportBarButtonItemImageInViewController:(UIViewController *)viewController;

@property (readonly) BOOL canCreateNewDocument;
@property (readonly) BOOL shouldEnableCreateNewDocument;
- (void)unlockCreateNewDocumentInViewController:(UIViewController *)viewController withCompletionHandler:(void (^ __nonnull)(BOOL isUnlocked))completionBlock;

- (void)checkTemporaryLicensingStateInViewController:(UIViewController *)viewController withCompletionHandler:(void (^ __nullable)(void))completionHandler;
- (void)handleLicensingAuthenticationURL:(NSURL *)url presentationSource:(UIViewController *)presentationSource;

// Defaults to YES, can be overridden by apps to allow only one crash report, and subsequent scenes will show an alert pointing the user to the lone crash report scene.
@property (nonatomic, readonly) BOOL canHaveMultipleCrashReportScenes;

// Defaults to YES. Setting this to NO will prevent interactions enqueued via enqueueInteractionControllerPresentationForAnyForegroundScene and it's scene-specific counterpart from being dequeued. Setting this from NO back to YES will immediately dequeue and present any queued interaction if some scene is in the foreground.
@property (nonatomic) BOOL canDequeueQueuedInteractions;

// Defaults to NO, override in the app subclass if the watch is supported.
@property (nonatomic, readonly) BOOL supportsAppleWatch;

@end

extern BOOL OUIShouldLogPerformanceMetrics;
extern NSTimeInterval OUIElapsedTimeSinceProcessCreation(void); // For timing startup work before main() is entered
extern NSTimeInterval OUIElapsedTimeSinceApplicationStarted(void); // Time since the beginning of -[OUIApplication initialize]

@interface UIViewController (OUIDisabledDemoFeatureAlerter) <OUIDisabledDemoFeatureAlerter>
- (NSString *)featureDisabledForDemoAlertTitle;
@end

#define OUILogPerformanceMetric(format, ...) if (OUIShouldLogPerformanceMetrics) NSLog((format), ## __VA_ARGS__)

NS_ASSUME_NONNULL_END
