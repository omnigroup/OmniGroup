// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppControllerSceneHelper.h>

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIAttentionSeekingButton.h>
#import <OmniUI/OUIMenuController.h>
#import <OmniUI/OUIMenuOption.h>

@interface OUIAppControllerSceneHelper () <OUIWebViewControllerDelegate, UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) NSMapTable *appMenuUnderlyingButtonsMappedToAssociatedBarButtonItems;
@property (nonatomic, weak) OUIWebViewController *newsViewController;
@property (nonatomic, strong, nullable) NSString *newsURLStringCurrentlyShowing;
@end

@protocol UIApplicationNewsletterExtensions
@optional
@property (nonatomic, readonly) NSArray<NSURLQueryItem *> *signUpForOmniNewsletterQueryItems;
@end

@implementation OUIAppControllerSceneHelper
{
    OUIMenuController *_appMenuController;
}

- (UIBarButtonItem *)newAppMenuBarButtonItem;
{
    UIImage *normalImage = OUIAppController.sharedController.appMenuImage;
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:normalImage style:UIBarButtonItemStylePlain target:self action:@selector(_showAppMenu:)];
    item.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Help and Settings", @"OmniUI", OMNI_BUNDLE, @"Help and Settings toolbar item accessibility label.");
    return item;
}

#pragma mark -

- (void)_showAboutScreen:(id)sender;
{
    [self showAboutScreenInNavigationController:nil];
}

- (void)showReleaseNotes:(nullable id)sender;
{
    [self showWebViewWithURL:[[NSBundle mainBundle] URLForResource:@"MessageOfTheDay" withExtension:@"html"] title:NSLocalizedStringFromTableInBundle(@"Release Notes", @"OmniUI", OMNI_BUNDLE, @"release notes html screen title")];
}

- (void)_showOnlineHelp:(id)sender;
{
    NSURL *helpIndexURL = OUIAppController.sharedController.onlineHelpURL;
    if (!helpIndexURL) {
        OBASSERT_NOT_REACHED("Action should not have been enabled");
        return;
    }

    if (![helpIndexURL isFileURL]) {
        // The help URL doesn't refer to built-in documentation files, so let's send this over to Safari
        [UIApplication.sharedApplication openURL:helpIndexURL options:@{} completionHandler:NULL];
        return;
    }

    NSString *webViewTitle = [[OUIAppController.sharedController class] helpTitle];

    OUIWebViewController *webController = [self showWebViewWithURL:helpIndexURL title:webViewTitle];
    [webController invokeJavaScriptAfterLoad:[self _rewriteHelpURLJavaScript] completionHandler:nil];
}

- (NSString *)_rewriteHelpURLJavaScript;
{
    NSString *helpForwardString = OUIAppController.sharedController.helpForwardURL.absoluteString;
    return [NSString stringWithFormat:@"\
            var a = document.getElementById(\"OUIHelpLinkTag\");\
            a.setAttribute(\"href\", \"%@\")",
            helpForwardString];
}

- (void)_showLatestNewsMessage;
{
    [self showNewsURLString:OUIAppController.sharedController.mostRecentNewsURLString evenIfShownAlready:YES];
}

- (NSArray <OUIMenuOption *> *)_appMenuTopOptions;
{
    OUIAppController *appController = OUIAppController.sharedController;
    NSMutableArray *options = [NSMutableArray array];
    OUIMenuOption *option;
    NSArray *additionalOptions;

    option = appController.specialFirstAppMenuOption;
    if (option) {
        // The special option (if it exists) gets spacers on either side of it. The title must be non-empty for the spacer to have non-zero height, so just make it a space.
        [options addObject:option];
        [options addObject:[OUIMenuOption separatorWithTitle:@" "]];
    }

    NSString *aboutMenuTitle = appController.aboutMenuTitle;
    if (![NSString isEmptyString:aboutMenuTitle]) {
        option = [OUIMenuOption optionWithTarget:self selector:@selector(_showAboutScreen:) title:aboutMenuTitle image:appController.aboutMenuImage];
        [options addObject:option];
    }

    if (appController.hasOnlineHelp) {
        option = [OUIMenuOption optionWithTarget:self selector:@selector(_showOnlineHelp:)
                                                           title:[[NSBundle mainBundle] localizedStringForKey:@"OUIHelpBookName" value:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"OUIHelpBookName"] table:@"InfoPlist"]
                                                           image:appController.helpMenuImage];
        [options addObject:option];
    }

    NSString *feedbackMenuTitle = appController.feedbackMenuTitle;
    if (![NSString isEmptyString:feedbackMenuTitle] && ![appController isRunningRetailDemo]) {
        option = [OUIMenuOption optionWithTarget:self selector:@selector(sendFeedback:)
                                                           title:feedbackMenuTitle
                                                           image:appController.sendFeedbackMenuImage];
        [options addObject:option];
    }

    {   // Sign up for the Omni Newsletter
        NSString *newsletterTitle = NSLocalizedStringFromTableInBundle(@"Omni Newsletter Signup", @"OmniUI", OMNI_BUNDLE, @"Menu item to subscribe to Omni's newsletter");
        OUIMenuOption *newsletterOption = [OUIMenuOption optionWithTarget:self selector:@selector(signUpForOmniNewsletter:)
                                                                                    title:newsletterTitle
                                                                                    image:appController.newsletterMenuImage];
        [options addObject:newsletterOption];
    }

    if ([appController mostRecentNewsURLString]) {
        OUIMenuOption *newsOption = [OUIMenuOption optionWithTarget:self selector:@selector(_showLatestNewsMessage)
                                                                              title:NSLocalizedStringFromTableInBundle(@"News", @"OmniUI", OMNI_BUNDLE, @"News menu item")
                                                                              image:appController.announcementMenuImage];
        [options addObject:newsOption];
        OUIAttentionSeekingButton *newsButton = [[OUIAttentionSeekingButton alloc] initForAttentionKey:OUIAttentionSeekingForNewsKey normalImage:appController.announcementMenuImage attentionSeekingImage:appController.announcementBadgedMenuImage dotOrigin:CGPointMake(25, 2)];
        newsButton.seekingAttention = appController.newsWantsAttention;
        newsButton.userInteractionEnabled = NO;
        newsOption.attentionDotView = newsButton;

    }

    additionalOptions = [appController additionalAppMenuOptionsAtPosition:OUIAppMenuOptionPositionBeforeReleaseNotes];
    if (additionalOptions)
        [options addObjectsFromArray:additionalOptions];

    option = [OUIMenuOption optionWithTarget:self selector:@selector(showReleaseNotes:)
                                                       title:NSLocalizedStringFromTableInBundle(@"Release Notes", @"OmniUI", OMNI_BUNDLE, @"App menu item title")
                                                       image:appController.releaseNotesMenuImage];
    [options addObject:option];

    additionalOptions = [appController additionalAppMenuOptionsAtPosition:OUIAppMenuOptionPositionAfterReleaseNotes];
    if (additionalOptions)
        [options addObjectsFromArray:additionalOptions];

    additionalOptions = [appController additionalAppMenuOptionsAtPosition:OUIAppMenuOptionPositionAtEnd];
    if (additionalOptions)
        [options addObjectsFromArray:additionalOptions];

    return options;
}

- (UIBarButtonItem *)_barButtonItemForSender:(id)sender
{
    if ([sender isKindOfClass:[UIBarButtonItem class]]) {
        return sender;
    }

    UIBarButtonItem *item = [self.appMenuUnderlyingButtonsMappedToAssociatedBarButtonItems objectForKey:sender];
    return item;
}

- (void)_showAppMenu:(id)sender;
{
    if ([self.window.rootViewController presentedViewController]) {
        return;
    }

    if (!_appMenuController)
        _appMenuController = [[OUIMenuController alloc] init];

    _appMenuController.topOptions = [self _appMenuTopOptions];

    _appMenuController.tintColor = UIColor.labelColor; // The icons are many colors for iOS 11 flavor, so menu text looks better untinted.
    _appMenuController.menuOptionBackgroundColor = UIColor.clearColor;
    _appMenuController.menuBackgroundColor = UIColor.secondarySystemBackgroundColor; // Separator and scroll-bounce region
    _appMenuController.showsDividersBetweenOptions = YES;
    _appMenuController.sizesToOptionWidth = YES;

    _appMenuController.title = [OUIAppController applicationName];
    _appMenuController.alwaysShowsNavigationBar = YES;

    UIViewController *rootViewController = self.window.rootViewController;
    if ([rootViewController isKindOfClass:[UIDocumentBrowserViewController class]]) {
        // In iOS 10.13 beta 7, you can't present a popover from a document browser's navigation button. See <bug:///176777> (iOS-OmniGraffle Bug: Gear menu popover appears on far left of display).
        _appMenuController.modalPresentationStyle = UIModalPresentationFormSheet;
        // popoverPresentationController.sourceView = rootViewController.view;
        // popoverPresentationController.canOverlapSourceViewRect = YES;
        // CGRect browserFrame = rootViewController.view.frame;
        // popoverPresentationController.sourceRect = rootViewController.view.frame;
    } else {
        UIPopoverPresentationController *popoverPresentationController = _appMenuController.popoverPresentationController;
        UIBarButtonItem *appropriatePresenter = nil;
        if ([sender isKindOfClass:[UIBarButtonItem class]]) {
            appropriatePresenter = sender;
        } else {
            appropriatePresenter = [self _barButtonItemForSender:sender];
        }
        OBASSERT(appropriatePresenter != nil);
        OBASSERT([appropriatePresenter isKindOfClass:[UIBarButtonItem class]]); // ...or we shouldn't be passing it as the bar item in the next call
        popoverPresentationController.barButtonItem = appropriatePresenter;
    }

    [rootViewController presentViewController:_appMenuController animated:YES completion:nil];
}

- (NSString *)_aboutPanelJSONBindingsString;
{
    __autoreleasing NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:OUIAppController.sharedController.aboutScreenBindingsDictionary options:0 error:&jsonError];
    assert(jsonData != nil);

    NSString *jsonValue = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSString *jsonBindingsString = [NSString stringWithFormat:@"aboutBindings=%@;", jsonValue];
    return jsonBindingsString;
}

- (void)showAboutScreenInNavigationController:(nullable UINavigationController *)navigationController withDoneButton:(BOOL)withDoneButton;
{
    OUIAppController *appController = OUIAppController.sharedController;
    OUIWebViewController *webViewController;
    if (navigationController == nil)
        webViewController = [self showWebViewWithURL:appController.aboutScreenURL title:appController.aboutScreenTitle modalPresentationStyle:UIModalPresentationFormSheet modalTransitionStyle:UIModalTransitionStyleCoverVertical animated:YES navigationBarHidden:NO withDoneButton:withDoneButton];
    else
        webViewController = [self showWebViewWithURL:appController.aboutScreenURL title:appController.aboutScreenTitle animated:YES navigationController:navigationController withDoneButton:withDoneButton];
    [webViewController invokeJavaScriptBeforeLoad:[self _aboutPanelJSONBindingsString]];
}

- (void)showAboutScreenInNavigationController:(nullable UINavigationController *)navigationController;
{
    [self showAboutScreenInNavigationController:navigationController withDoneButton:YES];
}

- (nullable OUIWebViewController *)showNewsURLString:(NSString *)urlString evenIfShownAlready:(BOOL)showNoMatterWhat
{
#if 0 && DEBUG_shannon
    NSLog(@"asked to show news.  root view controller is %@", self.window.rootViewController);
    showNoMatterWhat = YES;
#endif

    OUIAppController *appController = OUIAppController.sharedController;
    if ([appController haveShownReleaseNotes:urlString] && !showNoMatterWhat)
        return nil;

    if (self.window.rootViewController.presentedViewController) {
        appController.newsURLStringToShowWhenReady = urlString;
        return nil;  // we don't want to interrupt the user to show the news message (or try to work around every issue that could arise with trying to present this news message when something else is already presented)
    }

    OUIWebViewController *newsViewController = [self showWebViewWithURL:[NSURL URLWithString:urlString] title:NSLocalizedStringFromTableInBundle(@"News", @"OmniUI", OMNI_BUNDLE, @"News view title")];
    _newsURLStringCurrentlyShowing = urlString;
    _newsViewController = newsViewController;
    return newsViewController;
}

- (void)showOnlineHelp:(id)sender;
{
    [self _showOnlineHelp:sender];
}

#pragma mark -

- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title;
{
    // If the user doesn't specify a modal presentation style, we become the adaptive presentation delegate and present as a page sheet in compact and full screen in regular.
    BOOL isRegular = self.window.rootViewController.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular;
    UIModalPresentationStyle presentationStyle = isRegular ? UIModalPresentationFullScreen : UIModalPresentationAutomatic;
    UIModalTransitionStyle transitionStyle = isRegular ? UIModalTransitionStyleCrossDissolve : UIModalTransitionStyleCoverVertical;
    return [self _showWebViewWithURL:url title:title modalPresentationStyle:presentationStyle modalTransitionStyle:transitionStyle animated:YES navigationBarHidden:NO withDoneButton:YES wantsModalPresentationDelegate:YES];
}

- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title modalPresentationStyle:(UIModalPresentationStyle)presentationStyle modalTransitionStyle:(UIModalTransitionStyle)transitionStyle animated:(BOOL)animated;
{
    return [self showWebViewWithURL:url title:title modalPresentationStyle:presentationStyle modalTransitionStyle:transitionStyle animated:animated navigationBarHidden:NO];
}

- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title modalPresentationStyle:(UIModalPresentationStyle)presentationStyle modalTransitionStyle:(UIModalTransitionStyle)transitionStyle animated:(BOOL)animated navigationBarHidden:(BOOL)navigationBarHidden;
{
    return [self showWebViewWithURL:url title:title modalPresentationStyle:presentationStyle modalTransitionStyle:UIModalTransitionStyleCoverVertical animated:animated navigationBarHidden:navigationBarHidden withDoneButton:YES];
}

- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title modalPresentationStyle:(UIModalPresentationStyle)presentationStyle modalTransitionStyle:(UIModalTransitionStyle)transitionStyle animated:(BOOL)animated navigationBarHidden:(BOOL)navigationBarHidden withDoneButton:(BOOL)withDoneButton;
{
    return [self _showWebViewWithURL:url title:title modalPresentationStyle:presentationStyle modalTransitionStyle:transitionStyle animated:animated navigationBarHidden:navigationBarHidden withDoneButton:withDoneButton wantsModalPresentationDelegate:NO];
}

- (nullable OUIWebViewController *)_showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title modalPresentationStyle:(UIModalPresentationStyle)presentationStyle modalTransitionStyle:(UIModalTransitionStyle)transitionStyle animated:(BOOL)animated navigationBarHidden:(BOOL)navigationBarHidden withDoneButton:(BOOL)withDoneButton wantsModalPresentationDelegate:(BOOL)wantsModalPresentationDelegate;
{
    UINavigationController *webNavigationController = [[UINavigationController alloc] init];
    webNavigationController.navigationBar.barStyle = UIBarStyleDefault;
    webNavigationController.navigationBarHidden = navigationBarHidden;
    webNavigationController.modalPresentationStyle = presentationStyle;
    webNavigationController.modalTransitionStyle = transitionStyle;
    if (wantsModalPresentationDelegate) {
        webNavigationController.presentationController.delegate = self;
    }

    OUIWebViewController *webController = [self showWebViewWithURL:url title:title animated:NO /* will animate the presentation of webNavigationController instead */ navigationController:webNavigationController];
    webController.wantsDoneButton = withDoneButton;
    
    // Ensure we live until the controller has closed.
    webController.closeBlock = ^(OUIWebViewController *webViewController) {
        (void)self;
    };
    
    UIViewController *controllerToPresentFrom = self.window.rootViewController;
    while (controllerToPresentFrom.presentedViewController != nil) {
        controllerToPresentFrom = controllerToPresentFrom.presentedViewController;
    }
    [controllerToPresentFrom presentViewController:webNavigationController animated:animated completion:nil];
    return webController;
}

- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title animated:(BOOL)animated navigationController:(UINavigationController *)navigationController;
{
    return [self showWebViewWithURL:url title:title animated:animated navigationController:navigationController withDoneButton:YES];
}

- (nullable OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(nullable NSString *)title animated:(BOOL)animated navigationController:(UINavigationController *)navigationController withDoneButton:(BOOL)withDoneButton;
{
    OBASSERT(url != nil); //Seems like it would be a mistake to ask to show nothing. —LM
    if (url == nil) {
        return nil;
    }

    OUIWebViewController *webController = [[OUIWebViewController alloc] init];
    webController.delegate = self;
    webController.title = title;
    webController.URL = url;
    webController.wantsDoneButton = withDoneButton;

    assert(navigationController != nil); // This is no longer nullable
    [navigationController pushViewController:webController animated:animated];
    return webController;
}

#pragma mark -

- (IBAction)sendFeedback:(id)sender NS_EXTENSION_UNAVAILABLE_IOS("");
{
    [OUIAppController.sharedController sendFeedbackWithSubject:nil body:nil inScene:self.window.windowScene completion:^{}];
}

- (IBAction)signUpForOmniNewsletter:(nullable id)sender NS_EXTENSION_UNAVAILABLE_IOS("");
{
    NSArray *queryItems = nil;

    // Omni apps provide additional parameters
    id <NSObject, UIApplicationNewsletterExtensions> app = (id)UIApplication.sharedApplication;
    if ([app respondsToSelector:@selector(signUpForOmniNewsletterQueryItems)]) {
        queryItems = app.signUpForOmniNewsletterQueryItems;
    }

    NSString *urlString = @"https://www.omnigroup.com/forward/letters/";
    NSURLComponents *urlComponents = [NSURLComponents componentsWithString:urlString];
    urlComponents.queryItems = queryItems;

    NSURL *signUpURL = urlComponents.URL;
    [[UIApplication sharedApplication] openURL:signUpURL options:@{} completionHandler:nil];
}

#pragma mark - UIAdaptivePresentationControllerDelegate
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller traitCollection:(UITraitCollection *)traitCollection
{
    if (traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular) {
        return UIModalPresentationFullScreen;
    } else {
        return UIModalPresentationAutomatic;
    }
}

#pragma mark - OUIWebViewControllerDelegate

- (void)webViewControllerDidClose:(OUIWebViewController *)webViewController;
{
    NSString *newsURLStringCurrentlyShowing = _newsURLStringCurrentlyShowing;
    if (webViewController == _newsViewController && newsURLStringCurrentlyShowing != nil && webViewController.webView.URL) {
        [OUIAppController.sharedController didShowReleaseNotes:newsURLStringCurrentlyShowing];

        _newsViewController = nil;
        _newsURLStringCurrentlyShowing = nil;

        [[NSNotificationCenter defaultCenter] postNotificationName:OUIAttentionSeekingNotification object:self userInfo:@{ OUIAttentionSeekingForNewsKey : @(NO) }];
    }
}

@end
