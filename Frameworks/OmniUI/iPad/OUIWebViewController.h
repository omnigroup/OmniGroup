// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
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
@interface OUIWebViewController : UIViewController <WKNavigationDelegate>

@property (nonatomic, weak) id<OUIWebViewControllerDelegate> delegate;

@property (nonatomic, copy) NSURL *URL; // loads URL as a side effect of setting it
@property (nonatomic, readonly, strong) WKWebView *webView;

- (void)loadData:(NSData *)data ofType:(NSString *)mimeType;

- (void)invokeJavaScriptAfterLoad:(NSString *)javaScript completionHandler:(void (^)(id, NSError *))completionHandler;

- (IBAction)openInSafari:(id)sender NS_EXTENSION_UNAVAILABLE_IOS("Safari cannot be launched from app extensions.");
- (IBAction)goBack:(id)sender;
- (IBAction)goForward:(id)sender;
- (IBAction)stopLoading:(id)sender;
- (IBAction)reload:(id)sender;
- (IBAction)close:(id)sender;

@end


@protocol OUIWebViewControllerDelegate <NSObject>

@optional
/*!
 * \brief Called when the close button is tapped. It is the delegate's responsibility to dismiss the OUIWebViewController.
 */
- (void)webViewControllerDidClose:(OUIWebViewController *)webViewController;

@end
