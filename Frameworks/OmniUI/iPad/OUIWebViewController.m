// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIWebViewController.h>

#import <MessageUI/MessageUI.h>
#import <WebKit/WebKit.h>

#import <OmniFoundation/OFVersionNumber.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniFoundation/OFVersionNumber.h>


RCS_ID("$Id$")

@interface OUIWebViewController () <MFMailComposeViewControllerDelegate>
@end

@implementation OUIWebViewController

- (void)loadView 
{
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 320, 100)];
    webView.navigationDelegate = self;

    self.view = webView;
}

- (void)dealloc;
{
    if ([self isViewLoaded]) {
        WKWebView *webView = (WKWebView *)self.view;
        webView.navigationDelegate = nil;
    }
}

- (IBAction)openInSafari:(id)sender NS_EXTENSION_UNAVAILABLE_IOS("");
{
    [[UIApplication sharedApplication] openURL:[self URL]];
}

- (IBAction)goBack:(id)sender;
{
    UIWebView *webView = (UIWebView *)self.view;
    [webView goBack];
}

- (IBAction)close:(id)sender;
{
    if ([_delegate respondsToSelector:@selector(webViewControllerDidClose:)]) {
        [_delegate webViewControllerDidClose:self];
    }
}

- (void)_updateBarButtonItemForURL:(NSURL *)aURL;
{
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close:)];
}

- (void)setURL:(NSURL *)aURL;
{
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:aURL];
    [(UIWebView *)self.view loadRequest:request];
    [self _updateBarButtonItemForURL:aURL];
}

- (NSURL *)URL;
{
    return [[(UIWebView *)self.view request] URL];
}

- (UIWebView *)webView;
{
    return (UIWebView *)self.view;
}

- (void)loadData:(NSData *)data ofType:(NSString *)mimeType;
{
    UIWebView *webView = OB_CHECKED_CAST(UIWebView, self.view);
    NSURL *baseURL = [NSURL URLWithString:@"x-invalid:"];
    
    if (data == nil) {
        data = [NSData data];
    }
    
    [webView loadData:data MIMEType:mimeType textEncodingName:@"utf-8" baseURL:baseURL];
}

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error;
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler NS_EXTENSION_UNAVAILABLE_IOS("");
{
    NSURL *requestURL = [navigationAction.request URL];

    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
#ifdef DEBUG_kc
        NSLog(@"WebView link: %@", requestURL);
#endif

        NSString *scheme = [[requestURL scheme] lowercaseString];

        // Mailto link
        if ([scheme isEqualToString:@"mailto"]) {
            MFMailComposeViewController *controller = [[MFMailComposeViewController alloc] init];
            controller.mailComposeDelegate = self;
            [controller setToRecipients:[NSArray arrayWithObject:[requestURL resourceSpecifier]]];
            [self presentViewController:controller animated:YES completion:nil];
            decisionHandler(WKNavigationActionPolicyCancel);
            return; // Don't load this in the WebView
        }

        // Explicitly kick over to Safari
        if ([scheme isEqualToString:@"x-safari"]) { // Hand off x-safari URLs to the OS
            NSURL *safariURL = [NSURL URLWithString:[requestURL resourceSpecifier]];
            if (safariURL != nil && [[UIApplication sharedApplication] openURL:safariURL]) {
                decisionHandler(WKNavigationActionPolicyCancel);
                return; // Don't load this in the WebView
            }
        }


        // Implicitly kick web all URLs over to Safari 
        BOOL isWebURL = !([requestURL isFileURL]);

        if (isWebURL) {
            if ([[UIApplication sharedApplication] openURL:requestURL] == NO) {
                NSString *alertTitle = NSLocalizedStringFromTableInBundle(@"Link could not be opened. Please check Safari restrictions in Settings.", @"OmniUI", OMNI_BUNDLE, @"Web view error opening URL title.");

                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:alertTitle message:nil preferredStyle:UIAlertControllerStyleAlert];

                UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Web view error opening URL cancel button.") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {}];

                [alertController addAction:okAction];
                [self presentViewController:alertController animated:YES completion:^{}];
            }

            // The above call to -openURL can return no if Safari is off due to restriction. We still don't want to handle the URL.
            decisionHandler(WKNavigationActionPolicyCancel);
            return;
        }

        // Special URL
        if ([OUIAppController canHandleURLScheme:scheme] && [[[UIApplication sharedApplication] delegate] application:[UIApplication sharedApplication] openURL:requestURL options:@{UIApplicationOpenURLOptionsOpenInPlaceKey : @(NO), UIApplicationOpenURLOptionsSourceApplicationKey : [[NSBundle mainBundle] bundleIdentifier]}]) {
            decisionHandler(WKNavigationActionPolicyCancel);
            return; // Don't load this in the WebView
        }
    }

    // Go ahead and load this in the WebView
    [self _updateBarButtonItemForURL:requestURL];

    // we have removed the back button so if you get here, hopefully you are our initial launch page and nothing else.
    decisionHandler(WKNavigationActionPolicyAllow);
}

#pragma mark - UIViewController subclass

- (BOOL)shouldAutorotate;
{
    return YES;
}

@end
