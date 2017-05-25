// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>
#import <WebKit/WKWebView.h>
#import <WebKit/WKNavigationDelegate.h>

@protocol OUIWebViewControllerDelegate;

/*!
 OUIWebViewController provides a way to present Web content modally. It is intended for use as the root view controller of a UINavigationController; instances will use the navigation bar and toolbar for controls. The caller is responsible for wrapping an instance in a navigation controller before presentation.
 */
NS_EXTENSION_UNAVAILABLE_IOS("OUIWebViewController not available in app extensions.")
@interface OUIWebViewController : UIViewController <WKNavigationDelegate>

@property (nonatomic, weak) id <OUIWebViewControllerDelegate> delegate;
@property (nonatomic, copy) void (^closeBlock)(OUIWebViewController *webViewController);
@property (nonatomic, copy) void (^commitLoadBlock)(OUIWebViewController *webViewController, NSURL *url);
@property (nonatomic, copy) void (^reloadBlock)(OUIWebViewController *webViewController, NSURL *url);
@property (nonatomic, copy) void (^callbackBlock)(OUIWebViewController *webViewController, NSString *callback);

@property (nonatomic, copy) NSURL *URL; // loads URL as a side effect of setting it
@property (nonatomic, readonly, strong) WKWebView *webView;

- (void)_updateBarButtonItems;

- (void)loadData:(NSData *)data ofType:(NSString *)mimeType;

- (void)invokeJavaScriptBeforeLoad:(NSString *)javaScript;
- (void)invokeJavaScriptAfterLoad:(NSString *)javaScript completionHandler:(void (^)(id, NSError *))completionHandler;
- (void)callJavaScript:(NSString *)javaScript completionHandler:(void (^)(id, NSError *error))completionHandler;
- (void)callJavaScriptFunction:(NSString *)function withJSONParameters:(id)parameters completionHandler:(void (^)(id, NSError *error))completionHandler;

- (IBAction)openInSafari:(id)sender;
- (IBAction)goBack:(id)sender;
- (IBAction)goForward:(id)sender;
- (IBAction)stopLoading:(id)sender;
- (IBAction)reload:(id)sender;
- (IBAction)close:(id)sender;

@end


@protocol OUIWebViewControllerDelegate <NSObject>

@optional
/*!
 * \brief Called when the close button is tapped. Return YES if the view controller should dismiss itself.
 */
- (BOOL)webViewControllerShouldClose:(OUIWebViewController *)webViewController NS_EXTENSION_UNAVAILABLE_IOS("OUIWebViewController not available in app extensions.");

@end
