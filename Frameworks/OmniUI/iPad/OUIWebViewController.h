// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@protocol OUIWebViewControllerDelegate;

@interface OUIWebViewController : UIViewController <UIWebViewDelegate>
{
}

@property (nonatomic, weak) id<OUIWebViewControllerDelegate> delegate;

@property (strong) NSURL *URL;
@property (nonatomic, readonly, strong) UIWebView *webView;

- (void)loadData:(NSData *)data ofType:(NSString *)mimeType;

@end


@protocol OUIWebViewControllerDelegate <NSObject>

@optional
/*!
 * \brief Called when the close button is tapped. It is the delegate's responsibility to dismiss the OUIWebViewController.
 */
- (void)webViewControllerDidClose:(OUIWebViewController *)webViewController;

@end
