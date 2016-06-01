// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIWebViewController.h>

#import <MessageUI/MessageUI.h>
#import <WebKit/WebKit.h>

#import <OmniFoundation/OFOrderedMutableDictionary.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>

RCS_ID("$Id$")

@interface OUIWebViewController () <MFMailComposeViewControllerDelegate>

@property (nonatomic, strong) OFOrderedMutableDictionary *onLoadJavaScripts;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *errorLabel;

@end

@implementation OUIWebViewController

- (void)dealloc;
{
    if ([self isViewLoaded]) {
        self.webView.navigationDelegate = nil;
    }
}

#pragma mark - Actions

- (IBAction)openInSafari:(id)sender;
{
    [[UIApplication sharedApplication] openURL:[self URL]];
}

- (IBAction)goBack:(id)sender;
{
    [self.webView goBack];
}

- (IBAction)goForward:(id)sender;
{
    [self.webView goForward];
}

- (IBAction)stopLoading:(id)sender;
{
    [self.webView stopLoading];
}

- (IBAction)reload:(id)sender;
{
    [self.webView reload];
}

- (IBAction)close:(id)sender;
{
    if ([_delegate respondsToSelector:@selector(webViewControllerDidClose:)]) {
        [_delegate webViewControllerDidClose:self];
    }
}

#pragma mark - API

- (void)_updateBarButtonItemForURL:(NSURL *)aURL;
{
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close:)];
}

- (void)setURL:(NSURL *)aURL;
{
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:aURL];
    [self.webView loadRequest:request];
    [self _updateBarButtonItemForURL:aURL];
    [self startSpinner];
}

- (NSURL *)URL;
{
    return [self.webView URL];
}

- (WKWebView *)webView;
{
    return OB_CHECKED_CAST(WKWebView, self.view);
}

- (void)loadData:(NSData *)data ofType:(NSString *)mimeType;
{
    NSURL *baseURL = [NSURL URLWithString:@"x-invalid:"];
    
    if (data == nil) {
        data = [NSData data];
    }
    
    [self.webView loadData:data MIMEType:mimeType characterEncodingName:@"utf-8" baseURL:baseURL];
}

- (void)invokeJavaScriptAfterLoad:(NSString *)javaScript completionHandler:(void (^)(id, NSError *))completionHandler;
{
    OBPRECONDITION(javaScript != nil);
    if (javaScript == nil) {
        return;
    }
    
    if (![self.webView isLoading] && self.webView.URL != nil) {
        [self.webView evaluateJavaScript:javaScript completionHandler:completionHandler];
        return;
    }
    
    // Still loading, or no URL yet – hang on to the script and handler for later
    self.onLoadJavaScripts[javaScript] = [completionHandler copy] ?: [NSNull null];
}

#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error;
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - WKNavigationDelegate

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

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation;
{
    [self endSpinner];
    [self _runOnLoadJavaScripts];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self endSpinner];
    [self showError:error];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self endSpinner];
    [self showError:error];
}

- (void)startSpinner
{
    if (!self.spinner) {
        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    }
    if (self.spinner.superview != self.webView) {
        [self.webView addSubview:self.spinner];
        NSArray *layoutConstraints = @[
                                       [self.spinner.centerXAnchor constraintEqualToAnchor:self.spinner.superview.centerXAnchor],
                                       [self.spinner.centerYAnchor constraintEqualToAnchor:self.spinner.superview.centerYAnchor]
                                       ];
        [NSLayoutConstraint activateConstraints:layoutConstraints];
    }
    [self.spinner startAnimating];
    self.spinner.hidden = NO;
}

- (void)endSpinner
{
    [self.spinner stopAnimating];
}

- (void)showError:(NSError *)error
{
    if (!self.errorLabel) {
        self.errorLabel = [[UILabel alloc] init];
        self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    }
    
    self.errorLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.text = error.localizedDescription;
    
    if (self.errorLabel.superview != self.webView) {
        [self.webView addSubview:self.errorLabel];
        CGFloat reasonableWidth = fmin(250, self.webView.frame.size.width * 0.75);
        NSArray *constraints = @[
                                 [self.errorLabel.centerXAnchor constraintEqualToAnchor:self.errorLabel.superview.centerXAnchor],
                                 [self.errorLabel.centerYAnchor constraintEqualToAnchor:self.errorLabel.superview.centerYAnchor],
                                 [NSLayoutConstraint constraintWithItem:self.errorLabel
                                                              attribute:NSLayoutAttributeWidth
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:nil
                                                              attribute:NSLayoutAttributeNotAnAttribute
                                                             multiplier:1
                                                               constant:reasonableWidth]
                                 ];
        [NSLayoutConstraint activateConstraints:constraints];
    }
}

#pragma mark - UIViewController subclass

- (void)loadView
{
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 320, 100)];
    webView.navigationDelegate = self;
    
    self.view = webView;
}

- (void)viewDidDisappear:(BOOL)animated;
{
    [super viewDidDisappear:animated];
    
    [self.webView stopLoading];
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

#pragma mark - Private

- (OFOrderedMutableDictionary *)onLoadJavaScripts;
{
    if (_onLoadJavaScripts == nil) {
        _onLoadJavaScripts = [OFOrderedMutableDictionary dictionary];
    }
    return _onLoadJavaScripts;
}

- (void)_runOnLoadJavaScripts;
{
    if ([self.onLoadJavaScripts count] == 0) {
        // Nothing to do? Break the recursion
        return;
    }
    
    if ([self.webView isLoading] || self.webView.URL == nil) {
        // Shouldn't invoke JavaScript now – wait for the next time a URL is fully loaded
        return;
    }
    
    // Avoid creating a retain cycle here; we don't want to keep the web view alive and processing onload scripts when this view controller has been dismissed
    __weak typeof(self) weakSelf = self;
    NSString *javaScript = OB_CHECKED_CAST(NSString, [self.onLoadJavaScripts keyAtIndex:0]);
    [self.webView evaluateJavaScript:javaScript completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        
        // We must check whether the value is [NSNull null] before assigning it to a local variable typed as a block.
        // As soon as we assign it to a local typed as a block, the compiler may try to copy the block on our behalf, which will crash if the object is not a block.
        if (!OFISNULL(strongSelf.onLoadJavaScripts[javaScript])) {
            void (^completionHandler)(id, NSError*) = strongSelf.onLoadJavaScripts[javaScript];
            completionHandler(result, error);
        }
        
        // Remove the script that we just ran
        [strongSelf.onLoadJavaScripts removeObjectForKey:javaScript];

        // Recurse and run any remaining onLoad scripts
        [strongSelf _runOnLoadJavaScripts];
    }];
}

@end
