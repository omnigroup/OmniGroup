// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <MessageUI/MFMailComposeViewController.h>
#import <OmniUI/OUIDocumentPickerDelegate.h>
#import <OmniUI/OUIFeatures.h>

@class UIBarButtonItem;
@class OUIAppMenuController, OUIDocumentPicker, OUISyncMenuController;

#if OUI_SOFTWARE_UPDATE_CHECK
@class OUISoftwareUpdateController;
#endif

#define OUI_PRESENT_ERROR(error) [[[OUIAppController controller] class] presentError:(error) file:__FILE__ line:__LINE__]
#define OUI_PRESENT_ALERT(error) [[[OUIAppController controller] class] presentAlert:(error) file:__FILE__ line:__LINE__]

@interface OUIAppController : OFObject <UIApplicationDelegate, MFMailComposeViewControllerDelegate, OUIDocumentPickerDelegate>
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
}

+ (id)controller;
+ (BOOL)canHandleURLScheme:(NSString *)urlScheme;

+ (void)presentError:(NSError *)error;
+ (void)presentError:(NSError *)error file:(const char *)file line:(int)line;
+ (void)presentAlert:(NSError *)error file:(const char *)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title

@property(readonly) UIBarButtonItem *appMenuBarItem;
- (void)dismissAppMenu;

@property(nonatomic,retain) IBOutlet OUIDocumentPicker *documentPicker;

@property(readonly) BOOL activityIndicatorVisible;
- (void)showActivityIndicatorInView:(UIView *)view;
- (void)hideActivityIndicator;

// NSObject (OUIAppMenuTarget)
- (NSString *)feedbackMenuTitle;
- (void)sendFeedback:(id)sender;
- (void)showAppMenu:(id)sender;
- (void)showSyncMenu:(id)sender;

// Special URL handling
- (BOOL)isSpecialURL:(NSURL *)url;
- (BOOL)handleSpecialURL:(NSURL *)url;

// UIApplicationDelegate methods that we implement
- (void)applicationWillTerminate:(UIApplication *)application;

// Subclass responsibility
@property(readonly) UIViewController *topViewController;

@end

extern BOOL OUIShouldLogPerformanceMetrics;

#define OUILogPerformanceMetric(format, ...) if (OUIShouldLogPerformanceMetrics) NSLog((format), ## __VA_ARGS__)
