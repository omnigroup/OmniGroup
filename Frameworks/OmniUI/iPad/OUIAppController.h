// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import <MessageUI/MFMailComposeViewController.h>
#import <OmniUI/OUISpecialURLActionSheet.h>
#import <OmniUI/OUIFeatures.h>
#import <OmniUI/OUIActionSheet.h>

@class UIBarButtonItem;

#if OUI_SOFTWARE_UPDATE_CHECK
@class OUISoftwareUpdateController;
#endif

#define OUI_PRESENT_ERROR(error) [[[OUIAppController controller] class] presentError:(error) file:__FILE__ line:__LINE__]
#define OUI_PRESENT_ALERT(error) [[[OUIAppController controller] class] presentAlert:(error) file:__FILE__ line:__LINE__]

@interface OUIAppController : NSObject <UIApplicationDelegate, MFMailComposeViewControllerDelegate>

+ (instancetype)controller;

+ (BOOL)canHandleURLScheme:(NSString *)urlScheme;

+ (void)presentError:(NSError *)error;
+ (void)presentError:(NSError *)error file:(const char *)file line:(int)line;
+ (void)presentAlert:(NSError *)error file:(const char *)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title

// Popover Helpers
// Present all popovers via this API to help avoid popovers having to know about one another to avoid multiple popovers on screen.
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation; // Called by OUIMainViewController
- (BOOL)presentPopover:(UIPopoverController *)popover fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
- (BOOL)presentPopover:(UIPopoverController *)popover fromBarButtonItem:(UIBarButtonItem *)item permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
- (BOOL)dismissPopover:(UIPopoverController *)popover animated:(BOOL)animated; // If the popover in question is not visible, does nothing. DOES send the 'did' delegate method, unlike the plain UIPopoverController method (see the implementation for reasoning). Returns YES if the popover was visible.
- (void)dismissPopoverAnimated:(BOOL)animated; // Calls -dismissPopover:animated: with whatever popover is visible

- (void)forgetPossiblyVisiblePopoverIfAlreadyHidden;

// Action Sheet Helpers
- (void)showActionSheet:(OUIActionSheet *)actionSheet fromSender:(id)sender animated:(BOOL)animated;

- (void)dismissActionSheetAndPopover:(BOOL)animated;

// Special URL handling
- (BOOL)isSpecialURL:(NSURL *)url;
- (BOOL)handleSpecialURL:(NSURL *)url;
- (OUISpecialURLHandler)debugURLHandler;
    // subclass should override to provide handler for app-specific debug URLs

// UIApplicationDelegate methods that we implement
- (void)applicationWillTerminate:(UIApplication *)application;
- (void)applicationDidEnterBackground:(UIApplication *)application;
- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application;

// Subclass responsibility
@property(readonly) UIViewController *topViewController;
@property(readonly) NSString *applicationName;

- (void)resetKeychain;

- (BOOL)isRunningRetailDemo;
- (BOOL)showFeatureDisabledForRetailDemoAlert; // Runs an alert and returns YES if running a retail demo.

@property(nonatomic,readonly) NSString *fullReleaseString;

- (void)sendFeedbackWithSubject:(NSString *)subject body:(NSString *)body;


@end

extern BOOL OUIShouldLogPerformanceMetrics;
extern NSTimeInterval OUIElapsedTimeSinceProcessCreation(void); // For timing startup work before main() is entered

#define OUILogPerformanceMetric(format, ...) if (OUIShouldLogPerformanceMetrics) NSLog((format), ## __VA_ARGS__)
