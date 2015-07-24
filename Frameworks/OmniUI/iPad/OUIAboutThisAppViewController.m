// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIAboutThisAppViewController.h"

#import <MessageUI/MessageUI.h>
#import <OmniUI/OUIAlert.h>
#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$")

@interface OUIAboutThisAppViewController () <UIWebViewDelegate, MFMailComposeViewControllerDelegate>
@property (nonatomic, strong) NSURL *aboutURL;
@property (nonatomic, strong) NSDictionary *javascriptBindingsDictionary;
@end

@implementation OUIAboutThisAppViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    OBPRECONDITION(nibNameOrNil == nil);
    OBPRECONDITION(nibBundleOrNil == nil);
    
    self = [super initWithNibName:@"OUIAboutThisAppViewController" bundle:OMNI_BUNDLE];
    if (self == nil)
        return nil;
    
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done:)];
    self.navigationItem.rightBarButtonItem = done;

    return self;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.

    OBASSERT(_webView != nil); // This should be hooked up in our xib

    _webView.scalesPageToFit = NO;
    _webView.dataDetectorTypes = UIDataDetectorTypeNone;

    if (_aboutURL != nil)
        [_webView loadRequest:[NSURLRequest requestWithURL:_aboutURL]];
}

- (void)didReceiveMemoryWarning;
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Actions

- (IBAction)done:(id)sender;
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - API

- (void)loadAboutPanelWithTitle:(NSString *)title URL:(NSURL *)URL javascriptBindingsDictionary:(NSDictionary *)javascriptBindingsDictionary;
{
    self.navigationItem.title = title;
    _aboutURL = [URL copy];
    _javascriptBindingsDictionary = [javascriptBindingsDictionary copy];

    if (_webView != nil)
        [_webView loadRequest:[NSURLRequest requestWithURL:_aboutURL]];
}

#pragma mark - Private

- (NSString *)_javascriptBindingsString;
{
    if (_javascriptBindingsDictionary == nil)
        return @"";

    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_javascriptBindingsDictionary options:0 error:&jsonError];
    assert(jsonData != nil);

    NSString *jsonValue = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSString *jsonBindingsString = [NSString stringWithFormat:@"aboutBindings=%@;", jsonValue];
    return jsonBindingsString;
}

#pragma mark - UIWebViewDelegate protocol

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType;
{
    NSURL *requestURL = [request URL];
    
    if (navigationType == UIWebViewNavigationTypeLinkClicked) {
#ifdef DEBUG_kc
        NSLog(@"WebView link: %@", requestURL);
#endif
        
	NSString *scheme = [[requestURL scheme] lowercaseString];
	
        // Mailto link
        OUIAppController *appController = [OUIAppController controller];
	if ([scheme isEqualToString:@"mailto"]) {
            if (![appController showFeatureDisabledForRetailDemoAlert]) {
                MFMailComposeViewController *controller = [[MFMailComposeViewController alloc] init];
                controller.mailComposeDelegate = self;
                [controller setToRecipients:[NSArray arrayWithObject:[requestURL resourceSpecifier]]];
                [self presentViewController:controller animated:YES completion:nil];
            }
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

        if (isWebURL) {
            if ([[UIApplication sharedApplication] openURL:requestURL] == NO) {
                NSString *alertTitle = NSLocalizedStringFromTableInBundle(@"Link could not be opened. Please check Safari restrictions in Settings.", @"OmniUI", OMNI_BUNDLE, @"Web view error opening URL title.");
                
                OUIAlert *alert = [[OUIAlert alloc] initWithTitle:alertTitle message:nil cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"Web view error opening URL cancel button.") cancelAction:NULL];
                
                [alert show];
            }
            
            // The above call to -openURL can return no if Safari is off due to restriction. We still don't want to handle the URL.
            return NO;
        }

        // Special URL
        if ([OUIAppController canHandleURLScheme:scheme]) {
            UIApplication *sharedApplication = [UIApplication sharedApplication];
            if ([[sharedApplication delegate] application:sharedApplication handleOpenURL:requestURL]) {
                return NO; // Don't load this in the WebView
            }
        }
    }

    return YES;
}

- (void)webViewDidStartLoad:(UIWebView *)webView;
{
    [_webView stringByEvaluatingJavaScriptFromString:[self _javascriptBindingsString]];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView;
{
    [_webView stringByEvaluatingJavaScriptFromString:[self _javascriptBindingsString]];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error;
{
    NSLog(@"About: Load failed: %@", [error userInfo]);
    OBASSERT_NOT_REACHED("Bad link? The About screen shouldn't be trying to load things that could fail to load.");
}

#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error;
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
