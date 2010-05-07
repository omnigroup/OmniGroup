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

@class UIBarButtonItem;
@class OUIOmniMenuController, OUIDocumentPicker;

#define OUI_PRESENT_ERROR(error) [[[OUIAppController controller] class] presentError:(error) file:__FILE__ line:__LINE__]

@interface OUIAppController : OFObject <UIApplicationDelegate, MFMailComposeViewControllerDelegate, OUIDocumentPickerDelegate>
{
@private
    OUIDocumentPicker *_documentPicker;
    UIBarButtonItem *_omniMenuBarItem;
    OUIOmniMenuController *_omniMenuController;
    
    UIActivityIndicatorView *_activityIndicator;
    UIView *_eventBlockingView;
}

+ (id)controller;
+ (BOOL)canHandleURLScheme:(NSString *)urlScheme;

+ (void)presentError:(NSError *)error;
+ (void)presentError:(NSError *)error file:(const char *)file line:(int)line;

@property(readonly) UIBarButtonItem *omniMenuBarItem;
- (void)dismissOmniMenu;

@property(nonatomic,retain) IBOutlet OUIDocumentPicker *documentPicker;

@property(readonly) BOOL activityIndicatorVisible;
- (void)showActivityIndicatorInView:(UIView *)view;
- (void)hideActivityIndicator;

// NSObject (OUIOmniMenuTarget)
- (void)sendFeedback:(id)sender;
- (void)showOmniMenu:(id)sender;

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
