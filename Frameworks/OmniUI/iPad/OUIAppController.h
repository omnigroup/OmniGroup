// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <MessageUI/MFMailComposeViewController.h>
#import <OmniUI/OUISpecialURLActionSheet.h>
#import <OmniUI/OUIDocumentStoreDelegate.h>
#import <OmniUI/OUIFeatures.h>
#import <OmniUI/OUIActionSheet.h>

@class UIBarButtonItem;
@class OUIAppMenuController, OUIDocumentPicker, OUISyncMenuController;

#if OUI_SOFTWARE_UPDATE_CHECK
@class OUISoftwareUpdateController;
#endif

#define OUI_PRESENT_ERROR(error) [[[OUIAppController controller] class] presentError:(error) file:__FILE__ line:__LINE__]
#define OUI_PRESENT_ALERT(error) [[[OUIAppController controller] class] presentAlert:(error) file:__FILE__ line:__LINE__]

@interface OUIAppController : OFObject <UIApplicationDelegate, MFMailComposeViewControllerDelegate, OUIDocumentStoreDelegate>
{
@private
    OUIDocumentPicker *_documentPicker;
    UIBarButtonItem *_appMenuBarItem;
    OUIAppMenuController *_appMenuController;
    OUISyncMenuController *_syncMenuController;
    
    UIActivityIndicatorView *_activityIndicator;
    UIView *_eventBlockingView;
    
#if OUI_SOFTWARE_UPDATE_CHECK
    OUISoftwareUpdateController *_softwareUpdateController;
#endif
    
    dispatch_once_t _roleByFileTypeOnce;
    NSDictionary *_roleByFileType;
    
    NSArray *_editableFileTypes;
}

+ (id)controller;

+ (BOOL)canHandleURLScheme:(NSString *)urlScheme;

- (NSArray *)editableFileTypes;
- (BOOL)canViewFileTypeWithIdentifier:(NSString *)uti;

+ (void)presentError:(NSError *)error;
+ (void)presentError:(NSError *)error file:(const char *)file line:(int)line;
+ (void)presentAlert:(NSError *)error file:(const char *)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title

@property(readonly) UIBarButtonItem *appMenuBarItem;

@property(nonatomic,retain) IBOutlet OUIDocumentPicker *documentPicker;

@property(readonly) BOOL activityIndicatorVisible;
- (void)showActivityIndicatorInView:(UIView *)view;
- (void)hideActivityIndicator;

// NSObject (OUIAppMenuTarget)
- (NSString *)aboutMenuTitle;
- (NSString *)feedbackMenuTitle;
- (NSString *)aboutMenuTitle;
- (void)sendFeedback:(id)sender;
- (void)showAppMenu:(id)sender;
- (void)showSyncMenu:(id)sender;

// Popover Helpers
// Present all popovers via this API to help avoid popovers having to know about one another to avoid multiple popovers on screen.
- (BOOL)presentPopover:(UIPopoverController *)popover fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
- (BOOL)presentPopover:(UIPopoverController *)popover fromBarButtonItem:(UIBarButtonItem *)item permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
- (void)dismissPopover:(UIPopoverController *)popover animated:(BOOL)animated; // If the popover in question is not visible, does nothing. DOES send the 'did' delegate method, unlike the plain UIPopoverController method (see the implementation for reasoning)
- (void)dismissPopoverAnimated:(BOOL)animated; // Calls -dismissPopover:animated: with whatever popover is visible

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

// Optional OUIDocumentStoreDelegate that we implement
- (NSArray *)documentStoreEditableDocumentTypes:(OUIDocumentStore *)store;

// Subclass responsibility
@property(readonly) UIViewController *topViewController;
@property(readonly) NSString *applicationName;

- (void)resetKeychain;
@end

extern BOOL OUIShouldLogPerformanceMetrics;
extern NSTimeInterval OUIElapsedTimeSinceProcessCreation(void); // For timing startup work before main() is entered

#define OUILogPerformanceMetric(format, ...) if (OUIShouldLogPerformanceMetrics) NSLog((format), ## __VA_ARGS__)
