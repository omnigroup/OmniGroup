// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIWebViewController.h>

#import <MessageUI/MessageUI.h>
#import <OmniUI/OUIAlert.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>

RCS_ID("$Id$")

@interface OUIWebViewController () <MFMailComposeViewControllerDelegate>
@end

@implementation OUIWebViewController

- (void)loadView 
{
    UIWebView *webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, 320, 100)];
    webView.delegate = self;
    webView.scalesPageToFit = YES;
    webView.dataDetectorTypes = UIDataDetectorTypeAll;

#if 0
    // Transparent?
    webView.opaque = NO;
    webView.backgroundColor = [UIColor clearColor];
#endif

    _backButton = [[OUIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Back", @"OmniUI", OMNI_BUNDLE, @"Web view nagivation button for going back in history.")
                                                   style:UIBarButtonItemStyleBordered target:self action:@selector(goBack:)];
    self.navigationItem.leftBarButtonItem = _backButton;

    self.view = webView;
}

- (void)dealloc;
{
    if ([self isViewLoaded]) {
        UIWebView *webView = (UIWebView *)self.view;
        webView.delegate = nil;
    }
}

- (IBAction)openInSafari:(id)sender;
{
    [[UIApplication sharedApplication] openURL:[self URL]];
}

- (IBAction)goBack:(id)sender;
{
    UIWebView *webView = (UIWebView *)self.view;
    [webView goBack];
    _backButton.enabled = webView.canGoBack;
}

- (IBAction)close:(id)sender;
{
    if ([_delegate respondsToSelector:@selector(webViewControllerDidClose:)]) {
        [_delegate webViewControllerDidClose:self];
    }
}

- (void)_updateBarButtonItemForURL:(NSURL *)aURL;
{
    self.navigationItem.rightBarButtonItem = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close:)];
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
    [(UIWebView *)self.view loadData:data MIMEType:mimeType textEncodingName:@"utf-8" baseURL:nil];
}

- (NSArray *)saveControllerState;
{
    return nil;
}

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error;
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType;
{
    NSURL *requestURL = [request URL];
    
    if (navigationType == UIWebViewNavigationTypeLinkClicked) {
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
            return NO; // Don't load this in the WebView
	}
        
        // Explicitly kick over to Safari
        if ([scheme isEqualToString:@"x-safari"]) { // Hand off x-safari URLs to the OS
            NSURL *safariURL = [NSURL URLWithString:[requestURL resourceSpecifier]];
            if (safariURL != nil && [[UIApplication sharedApplication] openURL:safariURL])
                return NO; // Don't load this in the WebView
        }
        
        
        // Implicitly kick web URLs not pointing to *.omnigroup.com over to Safari (or all URLs in retail demos)
        BOOL isWebURL = !([requestURL isFileURL]);
        NSURLComponents *components = [NSURLComponents componentsWithURL:requestURL resolvingAgainstBaseURL:NO];
        NSString *host = [components.host lowercaseString];
        BOOL isOmniURL = isWebURL && ([host hasSuffix:@"omnigroup.com"] || [host hasSuffix:@"sync.omnigroup.com"]);
        
        if (isWebURL && (!isOmniURL || [[OUIAppController controller] isRunningRetailDemo])) {
            if ([[UIApplication sharedApplication] openURL:requestURL] == NO) {
                NSString *alertTitle = NSLocalizedStringFromTableInBundle(@"Link could not be opened. Please check Safari restrictions in Settings.", @"OmniUI", OMNI_BUNDLE, @"Web view error opening URL title.");
                
                OUIAlert *alert = [[OUIAlert alloc] initWithTitle:alertTitle message:nil cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Web view error opening URL cancel button.") cancelAction:NULL];
                
                [alert show];
            }
            
            // The above call to -openURL can return no if Safari is off due to restriction. We still don't want to handle the URL.
            return NO;
        }

        // Special URL
        if ([OUIAppController canHandleURLScheme:scheme] && [[[UIApplication sharedApplication] delegate] application:nil handleOpenURL:requestURL]) {
                return NO; // Don't load this in the WebView
        }
    }

    // Go ahead and load this in the WebView
    [self _updateBarButtonItemForURL:requestURL];

    
    return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView;
{
    _backButton.enabled = webView.canGoBack;
}

#pragma mark - UIViewController subclass

- (BOOL)shouldAutorotate;
{
    return YES;
}

@end
