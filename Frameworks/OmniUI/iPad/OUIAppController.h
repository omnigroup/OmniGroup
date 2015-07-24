// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
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

@class UIBarButtonItem;

#define OUI_PRESENT_ERROR(error) [[[OUIAppController controller] class] presentError:(error) file:__FILE__ line:__LINE__]
#define OUI_PRESENT_ALERT(error) [[[OUIAppController controller] class] presentAlert:(error) file:__FILE__ line:__LINE__]

@interface OUIAppController : UIResponder <UIApplicationDelegate, MFMailComposeViewControllerDelegate>

+ (instancetype)controller;

+ (NSString *)applicationName;

+ (BOOL)canHandleURLScheme:(NSString *)urlScheme;

+ (void)presentError:(NSError *)error;
+ (void)presentError:(NSError *)error file:(const char *)file line:(int)line;
+ (void)presentAlert:(NSError *)error file:(const char *)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title

// Can be set by early startup code and queried by later startup code to determine whether to launch into a plain state (no inbox item opened, no last document opened, etc). This can be used by applications integrating crash reporting software when they detect a crash from a previous launch and want to report it w/o other launch-time activities.
@property(nonatomic,assign) BOOL shouldPostponeLaunchActions;
- (void)addLaunchAction:(void (^)(void))launchAction;

- (void)showAboutScreenInNavigationController:(UINavigationController *)navigationController;
- (void)showOnlineHelp:(id)sender;

// Popover Helpers
// Present all popovers via this API to help avoid popovers having to know about one another to avoid multiple popovers on screen.
@property(nonatomic,readonly) BOOL hasVisiblePopover;
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation; // Called by OUIMainViewController
- (BOOL)presentPopover:(UIPopoverController *)popover fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
- (BOOL)presentPopover:(UIPopoverController *)popover fromBarButtonItem:(UIBarButtonItem *)item permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
- (BOOL)dismissPopover:(UIPopoverController *)popover animated:(BOOL)animated; // If the popover in question is not visible, does nothing. DOES send the 'did' delegate method, unlike the plain UIPopoverController method (see the implementation for reasoning). Returns YES if the popover was visible.
- (void)dismissPopoverAnimated:(BOOL)animated; // Calls -dismissPopover:animated: with whatever popover is visible

- (void)forgetPossiblyVisiblePopoverIfAlreadyHidden;

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
- (BOOL)showFeatureDisabledForRetailDemoAlert; // Runs an alert and returns YES if running a retail demo.

@property(nonatomic,readonly) NSString *fullReleaseString;

// App menu support
- (void)dismissAppMenuIfVisible:(UINavigationController *)navigationController;

typedef NS_ENUM(NSInteger, OUIAppMenuOptionPosition) {
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
- (UIBarButtonItem *)newAppMenuBarButtonItem; // insert this into your view controllers; see -additionalAppMenuOptionsAtPosition: for customization
- (NSArray *)additionalAppMenuOptionsAtPosition:(OUIAppMenuOptionPosition)position; // override to supplement super's return value with additional OUIMenuOptions
- (void)sendFeedbackWithSubject:(NSString *)subject body:(NSString *)body;

@property(nonatomic,readonly) UIImage *settingsMenuImage;
@property(nonatomic,readonly) UIImage *inAppPurchasesMenuImage;

@end

extern BOOL OUIShouldLogPerformanceMetrics;
extern NSTimeInterval OUIElapsedTimeSinceProcessCreation(void); // For timing startup work before main() is entered
extern NSTimeInterval OUIElapsedTimeSinceApplicationStarted(void); // Time since the beginning of -[OUIApplication initialize]

#define OUILogPerformanceMetric(format, ...) if (OUIShouldLogPerformanceMetrics) NSLog((format), ## __VA_ARGS__)
