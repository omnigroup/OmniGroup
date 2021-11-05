// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIWebViewController.h>

#import <MessageUI/MessageUI.h>
#import <WebKit/WebKit.h>
#import <MobileCoreServices/MobileCoreServices.h>

#import <OmniFoundation/OFOrderedMutableDictionary.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIAppController+SpecialURLHandling.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/UIPopoverPresentationController-OUIExtensions.h>
#import <OmniUI/UIViewController-OUIExtensions.h>
#import <OmniUI/OUIKeyCommands.h>

RCS_ID("$Id$")

static NSString * const InvalidScheme = @"x-invalid";

@interface OUIWebViewController () <MFMailComposeViewControllerDelegate, OUIKeyCommandProvider>

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

- (IBAction)openInSafari:(id)sender NS_EXTENSION_UNAVAILABLE_IOS("");
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
    id <OUIWebViewControllerDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(webViewControllerShouldClose:)] && ![delegate webViewControllerShouldClose:self])
        return;

    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIResponder

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender;
{
    if (action == @selector(reload:)) {
        NSURL *URL = self.webView.URL;
        if (!URL || [[URL scheme] isEqual:InvalidScheme]) {
            return NO;
        }
        return YES;
    }
    if (action == @selector(goBack:)) {
        return self.webView.canGoBack;
    }
    if (action == @selector(goForward:)) {
        return self.webView.canGoForward;
    }
    if (action == @selector(stopLoading:)) {
        return self.webView.isLoading;
    }

    return [super canPerformAction:action withSender:sender];
}

#pragma mark - OUIKeyCommandProvider

- (nullable NSOrderedSet<NSString *> *)keyCommandCategories;
{
    return [[NSOrderedSet<NSString *> alloc] initWithObjects:@"webView", nil];
}

- (nullable NSArray<UIKeyCommand *> *)keyCommands;
{
    return [OUIKeyCommands keyCommandsForCategories:self.keyCommandCategories];
}

#pragma mark - API

- (void)_updateBarButtonItems;
{
    if (_wantsDoneButton) {
        NSMutableArray <UIBarButtonItem *> *items = [NSMutableArray array];

        [items addObject: [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close:)]];

        self.navigationItem.rightBarButtonItems = items;
    }
}

- (void)setURL:(NSURL *)URL;
{
    if ([URL isFileURL]) {
        NSURL *bundleDirectory = NSBundle.mainBundle.bundleURL;
        NSURL *directory = [URL URLByDeletingLastPathComponent];

        if ([directory.path hasPrefix:bundleDirectory.path]) {
            directory = bundleDirectory;
        }

        [self.webView loadFileURL:URL allowingReadAccessToURL:directory];
    } else {
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL:URL];
        [self.webView loadRequest:request];
    }
    
    [self _updateBarButtonItems];
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

- (void)invokeJavaScriptBeforeLoad:(NSString *)javaScript;
{
    OBPRECONDITION(javaScript != nil);
    if (javaScript == nil) {
        return;
    }
    
    WKUserScript *userScript = [[WKUserScript alloc] initWithSource:javaScript injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
    [self.webView.configuration.userContentController addUserScript:userScript];
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

- (void)callJavaScript:(NSString *)javaScript completionHandler:(void (^)(id, NSError *error))completionHandler;
{
#ifdef DEBUG_kc
    NSLog(@"DEBUG JAVASCRIPT: %@", javaScript);
#endif
    [self.webView evaluateJavaScript:javaScript completionHandler:completionHandler];
}

- (void)callJavaScriptFunction:(NSString *)function withJSONParameters:(id)parameters completionHandler:(void (^)(id, NSError *error))completionHandler;
{
    NSError *jsonError = nil;
    NSString *parametersArchive = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:parameters options:0 error:&jsonError] encoding:NSUTF8StringEncoding];
    if (parametersArchive == nil) {
        completionHandler(nil, jsonError);
    } else {
        [self callJavaScript:[NSString stringWithFormat:@"%@(%@)", function, parametersArchive] completionHandler:completionHandler];
    }
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
    NSString *scheme = [[requestURL scheme] lowercaseString];
    
    // Callback
    if ([scheme isEqualToString:@"callback"]) {
        if (_callbackBlock != NULL) {
            NSString *callback = requestURL.resourceSpecifier;
            _callbackBlock(self, callback);
        }
        decisionHandler(WKNavigationActionPolicyCancel);
        return; // Don't load this in the WebView
    }

    // Special URL
    if ([OUIAppController canHandleURLScheme:scheme]) {
        decisionHandler(WKNavigationActionPolicyCancel); // Never try to load our URLs in the web view

        OUIAppController *appController = OUIAppController.sharedController;
        if ([appController isSpecialURL:requestURL] && [appController handleSpecialURL:requestURL senderBundleIdentifier:[[NSBundle mainBundle] bundleIdentifier] presentingFromViewController:self]) {
            return;
        }

        UIScene *scene = self.containingScene;
        [scene openURL:requestURL options:nil completionHandler:^(BOOL success) {}];
        return;
    }

    // Mailto link
    if ([scheme isEqualToString:@"mailto"]) {
        MFMailComposeViewController *controller = [[MFMailComposeViewController alloc] init];
        controller.mailComposeDelegate = self;
        [controller setToRecipients:[NSArray arrayWithObject:[requestURL resourceSpecifier]]];
        [self presentViewController:controller animated:YES completion:nil];
        decisionHandler(WKNavigationActionPolicyCancel);
        return; // Don't load this in the WebView
    }

    if (navigationAction.navigationType == WKNavigationTypeLinkActivated || navigationAction.navigationType == WKNavigationTypeOther) {
#ifdef DEBUG_kc
        NSLog(@"WebView link: %@", requestURL);
#endif

        // Explicitly kick over to Safari
        if ([scheme isEqualToString:@"x-safari"]) { // Hand off x-safari URLs to the OS
            NSURL *safariURL = [NSURL URLWithString:[requestURL resourceSpecifier]];
            if (safariURL != nil && [[UIApplication sharedApplication] openURL:safariURL]) {
                decisionHandler(WKNavigationActionPolicyCancel);
                return; // Don't load this in the WebView
            }
        }

        // Our load request should be handled locally
        BOOL isLoadRequest = [requestURL isEqual:self.URL] && (navigationAction.navigationType == WKNavigationTypeOther);

        NSString *fragment = requestURL.fragment;
        BOOL isLocalAnchor = !OFIsEmptyString(fragment);
        if (isLocalAnchor && _localAnchorNavigationBlock) {
            BOOL handled = _localAnchorNavigationBlock(self, decisionHandler, fragment);
            if (handled) {
                return;
            }
        }

        // Implicitly kick web all URLs over to Safari
        BOOL isWebURL = !isLoadRequest && !isLocalAnchor && ![requestURL isFileURL];
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
    }

    // Go ahead and load this in the WebView
    [self _updateBarButtonItems];

    // we have removed the back button so if you get here, hopefully you are our initial launch page and nothing else.
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(null_unspecified WKNavigation *)navigation;
{
    if (_commitLoadBlock != NULL) {
        _commitLoadBlock(self, webView.URL);
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation;
{
    [self endSpinner];

    if (_reloadBlock != NULL) {
        _reloadBlock(self, webView.URL);
    }

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
        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
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

- (WKWebViewConfiguration *)makeConfiguration;
{
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.suppressesIncrementalRendering = YES;
    configuration.allowsInlineMediaPlayback = YES;
    return configuration;
}

- (void)loadView
{
    WKWebViewConfiguration *configuration = [self makeConfiguration];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    webView.navigationDelegate = self;
    
    self.view = webView;
}

- (void)viewWillAppear:(BOOL)animated;
{
    [self _updateBarButtonItems];

    [super viewWillAppear:animated];
}

- (void)viewDidDisappear:(BOOL)animated;
{
    [super viewDidDisappear:animated];
    
    [self.webView stopLoading];
    
    id <OUIWebViewControllerDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(webViewControllerDidClose:)]) {
        [delegate webViewControllerDidClose:self];
    }
    
    // Can't include this in the close: method because we can be dismissed via swipe to delete as well.
    if (_closeBlock != NULL) {
        _closeBlock(self);
    }
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
    [self.webView evaluateJavaScript:javaScript completionHandler:^(id result, NSError *error) {
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
