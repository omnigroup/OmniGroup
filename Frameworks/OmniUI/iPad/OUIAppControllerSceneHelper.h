// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class UIButton, UIBarButtonItem, UINavigationController;
@class OUIWebViewController;

NS_EXTENSION_UNAVAILABLE_IOS("OUIAppControllerSceneHelper not available in app extensions.")
@interface OUIAppControllerSceneHelper : UIResponder

@property (nonatomic, nullable, strong) UIWindow *window;

// App menu support
- (UIBarButtonItem *)newAppMenuBarButtonItem; // insert this into your view controllers; see -additionalAppMenuOptionsAtPosition: for customization

// Implicitly includes Done as the right bar button
- (void)showAboutScreenInNavigationController:(nullable UINavigationController *)navigationController;
- (void)showAboutScreenInNavigationController:(nullable UINavigationController *)navigationController withDoneButton:(BOOL)withDoneButton;
- (void)showReleaseNotes:(nullable id)sender;
- (void)showOnlineHelp:(nullable id)sender;
- (nullable OUIWebViewController *)showNewsURLString:(NSString *)urlString evenIfShownAlready:(BOOL)showNoMatterWhat;

/// Presents a view controller displaying the contents of the given URL in an in-app web view. The view controller is wrapped in a UINavigationController instance; if non-nil, the given title is shown in the navigation bar of this controller. Returns the web view controller being used to show the URL's content.
- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title;
- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title modalPresentationStyle:(UIModalPresentationStyle)presentationStyle modalTransitionStyle:(UIModalTransitionStyle)transitionStyle animated:(BOOL)animated;
- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title modalPresentationStyle:(UIModalPresentationStyle)presentationStyle modalTransitionStyle:(UIModalTransitionStyle)transitionStyle animated:(BOOL)animated navigationBarHidden:(BOOL)navigationBarHidden;
- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title animated:(BOOL)animated navigationController:(UINavigationController *)navigationController;

- (IBAction)sendFeedback:(nullable id)sender;
- (IBAction)signUpForOmniNewsletter:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
