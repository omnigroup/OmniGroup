// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIAppController+InAppStore.h>

#import <MessageUI/MFMailComposeViewController.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/UTType.h>
#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniBase/OBRuntimeCheck.h>
#import <OmniBase/system.h>
#import <OmniFoundation/NSString-OFURLEncoding.h>
#import <OmniFoundation/OFBundleRegistry.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniUI/OUIAboutThisAppViewController.h>
#import <OmniUI/OUIAppController+SpecialURLHandling.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIChangePreferenceURLCommand.h>
#import <OmniUI/OUIDebugURLCommand.h>
#import <OmniUI/OUIKeyboardNotifier.h>
#import <OmniUI/OUIPurchaseURLCommand.h>
#import <OmniUI/OUIMenuController.h>
#import <OmniUI/OUIMenuOption.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/UIViewController-OUIExtensions.h>
#import <OmniUI/OUIAttentionSeekingButton.h>

#import <sys/sysctl.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

NSString * const OUISystemIsSnapshottingNotification = @"OUISystemIsSnapshottingNotification";
NSString * const NeedToShowURLKey = @"OSU_need_to_show_URL";
NSString * const PreviouslyShownURLsKey = @"OSU_previously_shown_URLs";

NSString *OUIAttentionSeekingNotification = @"OUIAttentionSeekingNotification";
NSString *OUIAttentionSeekingForNewsKey = @"OUIAttentionSeekingForNewsKey";

@interface OUIAppController ()
@property(strong, nonatomic) NSTimer *timerForSnapshots;
@property(strong, nonatomic) NSMapTable *appMenuUnderlyingButtonsMappedToAssociatedBarButtonItems;
@end

@implementation OUIAppController
{
    NSMutableArray *_launchActions;
    OUIMenuController *_appMenuController;
    NSOperationQueue *_backgroundPromptQueue;
}

BOOL OUIShouldLogPerformanceMetrics = NO;


// This should be called right at the top of main() to meausre the time spent in the kernel, dyld, C++ constructors, etc.
// Since we don't have iOS kernel source, we don't know exactly when p_starttime gets set, so this may miss/include extra stuff.
NSTimeInterval OUIElapsedTimeSinceProcessCreation(void)
{
    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    
    struct kinfo_proc kp;
    size_t len = sizeof(kp);
    if (sysctl(mib, 4, &kp, &len, NULL, 0) < 0) {
        perror("sysctl");
        return 1;
    }
    
    struct timeval start_time = kp.kp_proc.p_starttime;
    
    struct timeval now;
    if (gettimeofday(&now, NULL) < 0) {
        perror("gettimeofday");
        return 0;
    }
    
    //fprintf(stderr, "start_time.tv_sec:%lu, start_time.tv_usec:%d\n", start_time.tv_sec, start_time.tv_usec);
    //fprintf(stderr, "now.tv_sec:%lu, now.tv_usec:%d\n", now.tv_sec, now.tv_usec);
    
    NSTimeInterval sec = ((now.tv_sec - start_time.tv_sec) * 1e6 + (now.tv_usec - start_time.tv_usec)) / 1e6;
    //NSLog(@"sec = %f", sec);
    
    return sec;
}

static NSTimeInterval OUIAppStartTime;

NSTimeInterval OUIElapsedTimeSinceApplicationStarted(void)
{
    return CFAbsoluteTimeGetCurrent() - OUIAppStartTime;
}

#ifdef DEBUG
typedef int (*PYStdWriter)(void *, const char *, int);

static PYStdWriter _oldStdWrite;

int __pyStderrWrite(void *inFD, const char *buffer, int size);
int __pyStderrWrite(void *inFD, const char *buffer, int size)
{
    if ( strncmp(buffer, "AssertMacros:", 13) == 0 ) {
        return size;
    }
    return _oldStdWrite(inFD, buffer, size);
}

static void __iOS7B5CleanConsoleOutput(void)
{
    _oldStdWrite = stderr->_write;
    stderr->_write = __pyStderrWrite;
}
#endif

+ (void)initialize;
{
    OBINITIALIZE;

    OUIAppStartTime = CFAbsoluteTimeGetCurrent();
    
#ifdef DEBUG
    __iOS7B5CleanConsoleOutput();
#endif
    
    @autoreleasepool {
        
        // Poke OFPreference to get default values registered
#ifdef DEBUG
        BOOL showNonLocalizedStrings = YES;
#else
        BOOL showNonLocalizedStrings = NO;
#endif
        NSDictionary *defaults = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithBool:showNonLocalizedStrings], @"NSShowNonLocalizableStrings",
                                  [NSNumber numberWithBool:showNonLocalizedStrings], @"NSShowNonLocalizedStrings",
                                  nil
                                  ];
        [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
        [OFBundleRegistry registerKnownBundles];
        [OFPreference class];
        
        // Ensure that OUIKeyboardNotifier instantiates the shared notifier before the keyboard is shown for the first time, otherwise `lastKnownKeyboardHeight` and `keyboardVisible` may be incorrect.
        [OUIKeyboardNotifier sharedNotifier];
        
        OUIShouldLogPerformanceMetrics = [[NSUserDefaults standardUserDefaults] boolForKey:@"LogPerformanceMetrics"];
        
        if (OUIShouldLogPerformanceMetrics)
            NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
        
#ifdef OMNI_ASSERTIONS_ON
        OBRequestRuntimeChecks();
#endif
    }
}

+ (instancetype)controller;
{
    id controller = [[UIApplication sharedApplication] delegate];
    OBASSERT([controller isKindOfClass:self]);
    return controller;
}

+ (instancetype)sharedController;
{
    return [self controller];
}

- (id)init NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    if (!(self = [super init])) {
        return nil;
    }
    
    [[self class] registerCommandClass:[OUIChangePreferenceURLCommand class] forSpecialURLPath:@"/change-preference"];
    [[self class] registerCommandClass:[OUIDebugURLCommand class] forSpecialURLPath:@"/debug"];
    [[self class] registerCommandClass:[OUIPurchaseURLCommand class] forSpecialURLPath:@"/purchase"];
    
    // Setup vendorID at app launch to fix <bug:///107092>. See bug notes for more details.
    [self vendorID];
    
    return self;
}

+ (NSString *)applicationName;
{
    // The kCFBundleNameKey is often in the format "AppName-iPad".  If so, define an OUIApplicationName key in Info.plist and provide a better human-readable name, such as "AppName" or "AppName for iPad".
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *appName = [infoDictionary objectForKey:@"OUIApplicationName"];
    if (!appName) {
        appName = [infoDictionary objectForKey:(NSString *)kCFBundleNameKey];
    }
    return appName;
}

+ (BOOL)canHandleURLScheme:(NSString *)urlScheme;
{
    // Treat URL schemes as case insensitive
    urlScheme = [urlScheme lowercaseString];
    
    NSArray *urlTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleURLTypes"];
    for (NSDictionary *urlType in urlTypes) {
        NSArray *urlSchemes = [urlType objectForKey:@"CFBundleURLSchemes"];
        for (NSString *supportedScheme in urlSchemes) {
            if ([urlScheme isEqualToString:supportedScheme]) {
                return YES;
            }
        }
    }
    return NO;
}

// Very basic.
+ (void)presentError:(NSError *)error;
{
    UIViewController *viewController = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
    OBASSERT(viewController.presentedViewController == nil, "Error presentation is unlikely to work; the +presentError:fromViewController: method is preferred.");
    [self presentError:error fromViewController:viewController file:NULL line:0];
}

+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController;
{
    OBASSERT(viewController.presentedViewController == nil);
    [self presentError:error fromViewController:viewController file:NULL line:0];
}

+ (void)_presentError:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char * _Nullable)file line:(int)line cancelButtonTitle:(NSString *)cancelButtonTitle optionalActionTitle:(NSString *)optionalActionTitle optionalAction:(void (^ __nullable)(UIAlertAction *action))optionalAction;
{
    if (error == nil || [error causedByUserCancelling])
        return;

    if (file)
        NSLog(@"Error reported from %s:%d", file, line);
    NSLog(@"%@", [error toPropertyList]);

    // This delayed presentation avoids the "wait_fences: failed to receive reply: 10004003" lag/timeout which can happen depending on the context we start the reporting from.
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        NSMutableArray *messages = [NSMutableArray array];

        NSString *reason = [error localizedFailureReason];
        if (![NSString isEmptyString:reason])
            [messages addObject:reason];

        NSString *suggestion = [error localizedRecoverySuggestion];
        if (![NSString isEmptyString:suggestion])
            [messages addObject:suggestion];

        NSString *message = [messages componentsJoinedByString:@"\n"];

        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:[error localizedDescription] message:message preferredStyle:UIAlertControllerStyleAlert];

        [alertController addAction:[UIAlertAction actionWithTitle:cancelButtonTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {}]];
        if (optionalActionTitle && optionalAction) {
            [alertController addAction:[UIAlertAction actionWithTitle:optionalActionTitle style:UIAlertActionStyleDefault handler:optionalAction]];
        }

        [viewController presentViewController:alertController animated:YES completion:^{}];
        
    }];
}

+ (void)_presentError:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char * _Nullable)file line:(int)line cancelButtonTitle:(NSString *)cancelButtonTitle;
{
    [self _presentError:error fromViewController:viewController file:file line:line cancelButtonTitle:cancelButtonTitle optionalActionTitle:nil optionalAction:NULL];
}

+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char *)file line:(int)line optionalActionTitle:(NSString *)optionalActionTitle optionalAction:(void (^ __nullable)(UIAlertAction *action))optionalAction;
{
    [self _presentError:error fromViewController:viewController file:file line:line cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title") optionalActionTitle:optionalActionTitle optionalAction:optionalAction];
}

+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char *)file line:(int)line;
{
    [self _presentError:error fromViewController:viewController file:file line:line cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title")];
}

+ (void)presentAlert:(NSError *)error file:(const char * _Nullable)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title
{
    [self _presentError:error fromViewController:[[[[UIApplication sharedApplication] delegate] window] rootViewController] file:file line:line cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"button title")];
}

+ (void)presentAlert:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char * _Nullable)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title
{
    [self _presentError:error fromViewController:viewController file:file line:line cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"button title")];
}

- (void)resetKeychain;
{
    OBFinishPorting; // Make this public? Move the credential stuff into OmniFoundation instead of OmniFileStore?
//    OUIDeleteAllCredentials();
}

- (NSOperationQueue *)backgroundPromptQueue;
{
    @synchronized (self) {
        if (!_backgroundPromptQueue) {
            _backgroundPromptQueue = [[NSOperationQueue alloc] init];
            _backgroundPromptQueue.maxConcurrentOperationCount = 1;
            _backgroundPromptQueue.qualityOfService = NSQualityOfServiceUserInitiated;
            _backgroundPromptQueue.name = @"Serialized Queue for Background-Initiated Prompts";
        }
        return _backgroundPromptQueue;
    }
}

- (void)showOnlineHelp:(id)sender;
{
    [self _showOnlineHelp:sender];
}

- (void)setShouldPostponeLaunchActions:(BOOL)shouldPostpone;
{
    OBPRECONDITION(_shouldPostponeLaunchActions ^ shouldPostpone);
    
    _shouldPostponeLaunchActions = shouldPostpone;
    
    // Invoking actions might re-postpone.
    while (_shouldPostponeLaunchActions == NO && [_launchActions count] > 0) {
        void (^launchAction)(void) = [_launchActions objectAtIndex:0];
        [_launchActions removeObjectAtIndex:0];
        
        launchAction();
    }
}

- (void)addLaunchAction:(void (^)(void))launchAction;
{
    if (!_shouldPostponeLaunchActions) {
        launchAction();
        return;
    }

    if (!_launchActions)
        _launchActions = [NSMutableArray new];
    
    launchAction = [launchAction copy];
    [_launchActions addObject:launchAction];
}

- (UIResponder *)defaultFirstResponder;
{
    return self.window.rootViewController;
}


#pragma mark - Subclass responsibility

- (NSArray *)additionalAppMenuOptionsAtPosition:(OUIAppMenuOptionPosition)position;
{
    return @[];
}

- (BOOL)isRunningRetailDemo;
{
    return [[OFPreference preferenceForKey:@"IPadRetailDemo"] boolValue];
}

- (BOOL)showFeatureDisabledForRetailDemoAlertFromViewController:(UIViewController *)presentingViewController;
{
    if ([self isRunningRetailDemo]) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Feature not enabled for this demo", @"OmniUI", OMNI_BUNDLE, @"disabled for demo") message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Done", @"OmniUI", OMNI_BUNDLE, @"Done") style:UIAlertActionStyleDefault handler:^(UIAlertAction * __nonnull action) {}]];

        [presentingViewController presentViewController:alertController animated:YES completion:NULL];

        return YES;
    }
    
    return NO;
}

- (NSString *)fullReleaseString;
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *testFlightString = [OUIAppController inSandboxStore] ? @" TestFlight" : @"";
    NSString *proString = [self isPurchaseUnlocked:[self proUpgradeProductIdentifier]] ? @" [Pro]" : @"";
    return [NSString stringWithFormat:@"%@ %@%@%@ (v%@)", [OUIAppController applicationName], [infoDictionary objectForKey:@"CFBundleShortVersionString"], proString, testFlightString, [infoDictionary objectForKey:@"CFBundleVersion"]];
}


- (void)sendFeedbackWithSubject:(NSString *)subject body:(NSString * _Nullable)body;
{
    // May need to allow the app delegate to provide this conditionally later (OmniFocus has a retail build, for example)
    NSString *feedbackAddress = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIFeedbackAddress"];
    OBASSERT(feedbackAddress);
    if (feedbackAddress == nil)
        return;
    
    UIViewController *viewControllerToPresentFrom = self.window.rootViewController;
    while (viewControllerToPresentFrom.presentedViewController != nil)
        viewControllerToPresentFrom = viewControllerToPresentFrom.presentedViewController;

    BOOL useComposeView = viewControllerToPresentFrom != nil && [MFMailComposeViewController canSendMail];
    if (!useComposeView) {
        NSString *urlString = [NSString stringWithFormat:@"mailto:%@?subject=%@", feedbackAddress,
                               [NSString encodeURLString:subject asQuery:NO leaveSlashes:NO leaveColons:NO]];
        
        if (![NSString isEmptyString:body])
            urlString = [urlString stringByAppendingFormat:@"&body=%@", [NSString encodeURLString:body asQuery:NO leaveSlashes:NO leaveColons:NO]];
        
        NSURL *url = [NSURL URLWithString:urlString];
        OBASSERT(url);
        if (![[UIApplication sharedApplication] openURL:url]) {
            // Need to pop up an alert telling the user? Might happen now since we don't have Mail,  but they shouldn't be able to delete that in the real world.  Though maybe our url string is bad.
            NSLog(@"Unable to open mail url %@ from string\n%@\n", url, urlString);
            OBASSERT_NOT_REACHED("Couldn't open mail url");
        }
        return;
    }
    
    // TODO: Allow sending a document with the mail?
    
    MFMailComposeViewController *controller = [[MFMailComposeViewController alloc] init];
    controller.navigationBar.barStyle = UIBarStyleDefault;
    controller.mailComposeDelegate = self;
    [controller setToRecipients:[NSArray arrayWithObject:feedbackAddress]];
    [controller setSubject:subject];
    
    // N.B. The static analyzer doesn't know that +isEmptyString: is also a null check, so we duplicate it here
    if (body != nil && ![NSString isEmptyString:body])
        [controller setMessageBody:body isHTML:NO];
    
    [viewControllerToPresentFrom presentViewController:controller animated:YES completion:nil];
}

- (UIImage *)settingsMenuImage;
{
    return menuImage(@"OUIMenuItemSettings.png");
}

- (UIImage *)inAppPurchasesMenuImage;
{
    return menuImage(@"OUIMenuItemPurchases.png");
}

#pragma mark - App menu support

- (NSString *)feedbackMenuTitle;
{
    OBASSERT_NOT_REACHED("Should be subclassed to provide something nicer.");
    return @"HALP ME!";
}

- (NSString *)aboutMenuTitle;
{
    NSString *format = NSLocalizedStringFromTableInBundle(@"About %@", @"OmniUI", OMNI_BUNDLE, @"Default title for the About menu item");
    return [NSString stringWithFormat:format, [[self class] applicationName]];
}

- (NSString *)aboutScreenTitle;
{
    return [self aboutMenuTitle];
}

- (NSURL *)aboutScreenURL;
{
    OBRequestConcreteImplementation(self, _cmd);
}

NSString *const OUIAboutScreenBindingsDictionaryVersionStringKey = @"versionString";
NSString *const OUIAboutScreenBindingsDictionaryCopyrightStringKey = @"copyrightString";
NSString *const OUIAboutScreenBindingsDictionaryFeedbackAddressKey = @"feedbackAddress";

- (NSDictionary *)aboutScreenBindingsDictionary;
{
    // N.B.: specifically using mainBundle here rather than OMNI_BUNDLE because OmniUI will (hopefully) eventually become a framework.
    
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *versionString = infoDictionary[@"CFBundleShortVersionString"];
    NSString *copyrightString = infoDictionary[@"NSHumanReadableCopyright"];
    NSString *feedbackAddress = infoDictionary[@"OUIFeedbackAddress"];
    
    return @{
             OUIAboutScreenBindingsDictionaryVersionStringKey : versionString,
             OUIAboutScreenBindingsDictionaryCopyrightStringKey : copyrightString,
             OUIAboutScreenBindingsDictionaryFeedbackAddressKey : feedbackAddress,
    };
}

- (UIBarButtonItem *)newAppMenuBarButtonItem;
{
    
    BOOL needsAttentionDot = [self newsWantsAttention];
    
    NSString *imageName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIAppMenuImage"];
    if ([NSString isEmptyString:imageName])
        imageName = @"OUIAppMenu";
    UIImage *normalImage = menuImage(imageName);
    
    imageName = [imageName stringByAppendingString:@"-Badged"];
    UIImage *attentionImage = menuImage(imageName);
    
    OUIAttentionSeekingButton *button = [[OUIAttentionSeekingButton alloc] initForAttentionKey:OUIAttentionSeekingForNewsKey normalImage:normalImage attentionSeekingImage:attentionImage dotOrigin:CGPointMake(15, 0)];
    [button addTarget:self action:@selector(_showAppMenu:) forControlEvents:UIControlEventTouchUpInside];
    
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:button];
    
    if (needsAttentionDot) {
        button.seekingAttention = YES;
    }
    
    item.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Help and Settings", @"OmniUI", OMNI_BUNDLE, @"Help and Settings toolbar item accessibility label.");
    
    if (!self.appMenuUnderlyingButtonsMappedToAssociatedBarButtonItems) {
        self.appMenuUnderlyingButtonsMappedToAssociatedBarButtonItems = [NSMapTable weakToWeakObjectsMapTable];
    }
    [self.appMenuUnderlyingButtonsMappedToAssociatedBarButtonItems setObject:item forKey:button];
    
    return item;
}

- (UIBarButtonItem *)barButtonItemForSender:(id)sender
{
    UIBarButtonItem *item = [self.appMenuUnderlyingButtonsMappedToAssociatedBarButtonItems objectForKey:sender];
    return item;
}

#pragma mark App menu actions
- (void)dismissAppMenuIfVisible:(UINavigationController *)navigationController;
{
    if (navigationController.presentedViewController != nil && navigationController.presentedViewController == _appMenuController) {
        [navigationController dismissViewControllerAnimated:NO completion:^{
        }];
    }
}

- (void)_showAppMenu:(id)sender NS_EXTENSION_UNAVAILABLE_IOS("");
{
    if ([self.window.rootViewController presentedViewController]) {
        return;
    }
    if (!_appMenuController)
        _appMenuController = [[OUIMenuController alloc] init];
    
    _appMenuController.topOptions = [self _appMenuTopOptions];
    _appMenuController.tintColor = self.window.tintColor;
    
    UIBarButtonItem *appropriatePresenter = nil;
    if ([sender isKindOfClass:[UIBarButtonItem class]])
    {
        appropriatePresenter = sender;
    } else {
        appropriatePresenter = [self barButtonItemForSender:sender];
    }
    OBASSERT(appropriatePresenter != nil);
    OBASSERT([appropriatePresenter isKindOfClass:[UIBarButtonItem class]]); // ...or we shouldn't be passing it as the bar item in the next call
    _appMenuController.popoverPresentationController.barButtonItem = appropriatePresenter;
    [self.window.rootViewController presentViewController:_appMenuController animated:YES completion:nil];
}

- (void)_sendFeedback:(id)sender NS_EXTENSION_UNAVAILABLE_IOS("");
{
    NSString *subject = [NSString stringWithFormat:@"%@ Feedback", self.fullReleaseString];
    
    [self sendFeedbackWithSubject:subject body:nil];
}

- (OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(NSString * _Nullable)title withModalPresentationStyle:(UIModalPresentationStyle)presentationStyle
{
    OBASSERT(url != nil); //Seems like it would be a mistake to ask to show nothing. —LM
    if (url == nil)
        return nil;
    
    OUIWebViewController *webController = [[OUIWebViewController alloc] init];
    webController.delegate = self;
    webController.title = title;
    webController.URL = url;
    UINavigationController *webNavigationController = [[UINavigationController alloc] initWithRootViewController:webController];
    webNavigationController.navigationBar.barStyle = UIBarStyleDefault;
    
    webNavigationController.modalPresentationStyle = presentationStyle;
    
    [self.window.rootViewController presentViewController:webNavigationController animated:YES completion:nil];
    return webController;
}

- (OUIWebViewController *)showWebViewWithURL:(NSURL *)url title:(NSString * _Nullable)title;
{
    return [self showWebViewWithURL:url title:title withModalPresentationStyle:UIModalPresentationFullScreen];
}

- (void)_showLatestNewsMessage
{
    [self showNewsURLString:[self mostRecentNewsURLString] evenIfShownAlready:YES];
}

- (void)setNewsURLStringToShowWhenReady:(NSString *)newsURLStringToShowWhenReady
{
    if (newsURLStringToShowWhenReady) {
        [[NSUserDefaults standardUserDefaults] setObject:newsURLStringToShowWhenReady forKey:NeedToShowURLKey];
        // Post notification after saving the URL, so observers of the notification get correct property values when they query us.
        [[NSNotificationCenter defaultCenter] postNotificationName:OUIAttentionSeekingNotification object:self userInfo:@{ OUIAttentionSeekingForNewsKey : @(YES) }];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:NeedToShowURLKey];
    }
}

- (NSString *)newsURLStringToShowWhenReady
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:NeedToShowURLKey];
}

- (BOOL)hasUnreadNews
{
    BOOL result = [self newsWantsAttention];
    return result;
}

- (BOOL)hasAnyNews
{
    BOOL result = !OFIsEmptyString([self mostRecentNewsURLString]);
    return result;
}

- (NSString *)mostRecentNewsURLString
{
    NSString *newsURLToShow = self.newsURLStringToShowWhenReady;
    if (!newsURLToShow) {
        NSArray<NSString *> *previouslyShown = [[NSUserDefaults standardUserDefaults] arrayForKey:PreviouslyShownURLsKey];
        newsURLToShow = [previouslyShown lastObject];
    }
    return newsURLToShow;
}

- (OUIWebViewController * _Nullable)showNewsURLString:(NSString *)urlString evenIfShownAlready:(BOOL)showNoMatterWhat
{
#if 0 && DEBUG_shannon
    NSLog(@"asked to show news.  root view controller is %@", self.window.rootViewController);
    showNoMatterWhat = YES;
#endif
    if (self.window.rootViewController.presentedViewController) {
        self.newsURLStringToShowWhenReady = urlString;
        return nil;  // we don't want to interrupt the user to show the news message (or try to work around every issue that could arise with trying to present this news message when something else is already presented)
    }
    
    if (showNoMatterWhat || ![self haveShownReleaseNotes:urlString]) {
        self.newsViewController = [self showWebViewWithURL:[NSURL URLWithString:urlString] title:NSLocalizedStringFromTableInBundle(@"News", @"OmniUI", OMNI_BUNDLE, @"News view title") withModalPresentationStyle:UIModalPresentationFormSheet];
    }
    
    self.newsURLCurrentlyShowing = urlString;
    return self.newsViewController;
}

- (BOOL)haveShownReleaseNotes:(NSString *)urlString
{
    NSArray<NSString *> *previouslyShown = [[NSUserDefaults standardUserDefaults] arrayForKey:PreviouslyShownURLsKey];
    __block BOOL foundIt = NO;
    [previouslyShown enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj isEqualToString:urlString]) {
            foundIt = YES;
            *stop = YES;
        }
    }];
    return foundIt;
}

- (void)showAboutScreenInNavigationController:(UINavigationController * _Nullable)navigationController;
{
    OUIAboutThisAppViewController *aboutController = [[OUIAboutThisAppViewController alloc] init];
    [aboutController loadAboutPanelWithTitle:[self aboutScreenTitle] URL:[self aboutScreenURL] javascriptBindingsDictionary:[self aboutScreenBindingsDictionary]];

    if (navigationController) {
        [navigationController pushViewController:aboutController animated:YES];
    } else {
        navigationController = [[UINavigationController alloc] initWithRootViewController:aboutController];
        navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
        navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;

        UIViewController *viewController = self.window.rootViewController;
        [viewController presentViewController:navigationController animated:YES completion:nil];
    }
}

- (void)_showAboutScreen:(id)sender;
{
    [self showAboutScreenInNavigationController:nil];
}

- (void)_showReleaseNotes:(id)sender;
{
    [self showWebViewWithURL:[[NSBundle mainBundle] URLForResource:@"MessageOfTheDay" withExtension:@"html"] title:NSLocalizedStringFromTableInBundle(@"Release Notes", @"OmniUI", OMNI_BUNDLE, @"release notes html screen title")];
}

static NSString * const OUIHelpBookNameKey = @"OUIHelpBookName";

- (NSURL *)_onlineHelpURL;
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *helpBookName = [mainBundle objectForInfoDictionaryKey:OUIHelpBookNameKey];
    if ([NSString isEmptyString:helpBookName])
        return nil;
    
    NSString *helpBookFolder = [mainBundle objectForInfoDictionaryKey:@"OUIHelpBookFolder"];
    NSURL *helpIndexURL = [mainBundle URLForResource:@"index" withExtension:@"html" subdirectory:helpBookFolder];
    
    if (helpIndexURL == nil) {
        helpIndexURL = [mainBundle URLForResource:@"contents" withExtension:@"html" subdirectory:helpBookFolder];
    }
    
    if (helpIndexURL == nil) {
        helpIndexURL = [mainBundle URLForResource:@"top" withExtension:@"html" subdirectory:helpBookFolder];
    }
    
    OBASSERT(helpIndexURL != nil);
    return helpIndexURL;
}

- (NSString *)_onlineHelpTitle;
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *helpBookName = [mainBundle objectForInfoDictionaryKey:OUIHelpBookNameKey];
    if ([NSString isEmptyString:helpBookName])
        return nil;
    
    return [mainBundle localizedStringForKey:OUIHelpBookNameKey value:helpBookName table:@"InfoPlist"];
}

- (void)_showOnlineHelp:(id)sender;
{
    NSURL *helpIndexURL = [self _onlineHelpURL];
    if (!helpIndexURL) {
        OBASSERT_NOT_REACHED("Action should not have been enabled");
        return;
    }
    
    NSString *webViewTitle = [self _onlineHelpTitle];
    
    OUIWebViewController *webController = [self showWebViewWithURL:helpIndexURL title:webViewTitle];
    [webController invokeJavaScriptAfterLoad:[self _rewriteHelpURLJavaScript] completionHandler:nil];
}

- (NSString *)_rewriteHelpURLJavaScript;
{
    NSString *helpForwardString = [[self _helpForwardURL] absoluteString];
    return [NSString stringWithFormat:@"\
            var a = document.getElementById(\"OUIHelpLinkTag\");\
            a.setAttribute(\"href\", \"%@\")",
            helpForwardString];
}

- (NSURL *)_helpForwardURL;
{
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"https";
    components.host = @"www.omnigroup.com";

    NSString *path = @"/forward/documentation/html";
    
    // Deliberately use the app bundle, not OMNI_BUNDLE – we want to redirect to the running app's documentation
    path = [path stringByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]];
    
    // Only use language codes we localize into, and when all else fails, fall back to English
    NSString *languageCode = [[[NSBundle mainBundle] preferredLocalizations] firstObject] ?: @"en";
    path = [path stringByAppendingPathComponent:languageCode];
    
    // Clean the version string through OFVersionNumber so that it doesn't include "private test" or other suffixes
    NSString *versionString = OB_CHECKED_CAST(NSString, [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
    OFVersionNumber *versionNumber = [[OFVersionNumber alloc] initWithVersionString:versionString];
    path = [path stringByAppendingPathComponent:[versionNumber cleanVersionString]];
    
    components.path = path;
    return [components URL];
}

#pragma mark - OUIMenuControllerDelegate

- (BOOL)newsWantsAttention
{
    return [self mostRecentNewsURLString].length > 0 && ![self haveShownReleaseNotes:self.mostRecentNewsURLString];
}

static UIImage *menuImage(NSString *name)
{
    UIImage *image = [[UIImage imageNamed:name inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (!image)
        image = [UIImage imageNamed:name];
    
    OBASSERT(image);
    return image;
}

- (NSArray *)_appMenuTopOptions NS_EXTENSION_UNAVAILABLE_IOS("");
{
    NSMutableArray *options = [NSMutableArray array];
    OUIMenuOption *option;
    NSArray *additionalOptions;
    
    NSString *aboutMenuTitle = [self aboutMenuTitle];
    if (![NSString isEmptyString:aboutMenuTitle]) {
        option = [OUIMenuOption optionWithFirstResponderSelector:@selector(_showAboutScreen:) title:aboutMenuTitle image:menuImage(@"OUIMenuItemAbout.png")];
        [options addObject:option];
    }

    if ([self _onlineHelpURL]) {
        option = [OUIMenuOption optionWithFirstResponderSelector:@selector(_showOnlineHelp:)
                                                           title:[[NSBundle mainBundle] localizedStringForKey:@"OUIHelpBookName" value:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"OUIHelpBookName"] table:@"InfoPlist"]
                                                           image:menuImage(@"OUIMenuItemHelp.png")];
        [options addObject:option];
    }
    
    NSString *feedbackMenuTitle = [self feedbackMenuTitle];
    if (![NSString isEmptyString:feedbackMenuTitle] && ![self isRunningRetailDemo]) {
        option = [OUIMenuOption optionWithFirstResponderSelector:@selector(_sendFeedback:)
                                                           title:feedbackMenuTitle
                                                           image:menuImage(@"OUIMenuItemSendFeedback.png")];
        [options addObject:option];
    }

    if ([self mostRecentNewsURLString]){
        OUIMenuOption *newsOption = [OUIMenuOption optionWithFirstResponderSelector:@selector(_showLatestNewsMessage)
                                                                              title:NSLocalizedStringFromTableInBundle(@"News", @"OmniUI", OMNI_BUNDLE, @"News menu item")
                                                                              image:menuImage(@"OUIMenuItemAnnouncement.png")];
        [options addObject:newsOption];
        OUIAttentionSeekingButton *newsButton = [[OUIAttentionSeekingButton alloc] initForAttentionKey:OUIAttentionSeekingForNewsKey normalImage:menuImage(@"OUIMenuItemAnnouncement.png") attentionSeekingImage:menuImage(@"OUIMenuItemAnnouncement-Badged.png") dotOrigin:CGPointMake(25, 2)];
        newsButton.seekingAttention = [self newsWantsAttention];
        newsButton.userInteractionEnabled = NO;
        newsOption.attentionDotView = newsButton;
        
    }
    
    option = [OUIMenuOption optionWithFirstResponderSelector:@selector(_showReleaseNotes:)
                                                       title:NSLocalizedStringFromTableInBundle(@"Release Notes", @"OmniUI", OMNI_BUNDLE, @"App menu item title")
                                                       image:menuImage(@"OUIMenuItemReleaseNotes.png")];
    [options addObject:option];
    
    additionalOptions = [self additionalAppMenuOptionsAtPosition:OUIAppMenuOptionPositionAfterReleaseNotes];
    if (additionalOptions)
        [options addObjectsFromArray:additionalOptions];
    
    for (NSString *productIdentifier in [self inAppPurchaseIdentifiers]) {
        if ([self isPurchaseUnlocked:productIdentifier])
            continue;

        NSString *purchaseTitle = [self purchaseMenuItemTitleForInAppStoreProductIdentifier:productIdentifier];
        if ([NSString isEmptyString:purchaseTitle])
            continue;
        
        option = [[OUIMenuOption alloc] initWithTitle:purchaseTitle image:self.inAppPurchasesMenuImage action:^{
            [[OUIAppController controller] showInAppPurchases:productIdentifier viewController:self.window.rootViewController];
        }];
        [options addObject:option];
    }
    
    additionalOptions = [self additionalAppMenuOptionsAtPosition:OUIAppMenuOptionPositionAtEnd];
    if (additionalOptions)
        [options addObjectsFromArray:additionalOptions];
    
    return options;
}

- (UIViewController *)viewControllerForPresentingMenuController:(OUIMenuController *)menuController;
{
    return self.window.rootViewController;
}

#pragma mark - OUIWebViewControllerDelegate

- (void)webViewControllerDidClose:(OUIWebViewController *)webViewController;
{
    if (webViewController == self.newsViewController
        && self.newsURLCurrentlyShowing != nil
        && webViewController.webView.URL) {
        if (![self haveShownReleaseNotes:self.newsURLCurrentlyShowing]) {
            // remember that we showed this url
            NSArray<NSString *> *previouslyShown = [[NSUserDefaults standardUserDefaults] arrayForKey:PreviouslyShownURLsKey];
            if (!previouslyShown) {
                previouslyShown = @[];
            }
            previouslyShown = [previouslyShown arrayByAddingObject:self.newsURLCurrentlyShowing];
            [[NSUserDefaults standardUserDefaults] setObject:previouslyShown forKey:PreviouslyShownURLsKey];
            
            if ([self.newsURLCurrentlyShowing isEqualToString:self.newsURLStringToShowWhenReady]) {
                self.newsURLStringToShowWhenReady = nil;
            }
        }
        
        self.newsViewController = nil;
        self.newsURLCurrentlyShowing = nil;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:OUIAttentionSeekingNotification object:self userInfo:@{ OUIAttentionSeekingForNewsKey : @(NO) }];
    }
    
    [webViewController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIResponder subclass

- (BOOL)canBecomeFirstResponder;
{
    // In some cases when the keyboard is dismissing (after editing a text view on a popover in one case), we'll lose first responder if we don't do something. UIKit normally seems to try to nominate the nearest nextResponder of the UITextView that is ending editing, but in the case of a popover it has no good recourse. It *does* ask the UIApplication and the application's delegate (at least in the case of it being a UIResponder subclass). We'll pass this off to an object nominated by subclasses.
    UIResponder *defaultFirstResponder = self.defaultFirstResponder;
    
    if (defaultFirstResponder == self)
        return [super canBecomeFirstResponder];
    return [defaultFirstResponder canBecomeFirstResponder];
}

- (BOOL)becomeFirstResponder;
{
    UIResponder *defaultFirstResponder = self.defaultFirstResponder;
    
    if (defaultFirstResponder == self)
        return [super becomeFirstResponder];
    return [defaultFirstResponder becomeFirstResponder];
}

- (id)targetForAction:(SEL)action withSender:(id)sender;
{
    // The documentation for -[UIResponder targetForAction:withSender:] seems to not be true in some base case. This can return 'self' if our nextResponder is nil (our -canPerformAction:withSender: doesn't get called in this case).
    id target = [super targetForAction:action withSender:sender];
    if (![target respondsToSelector:action])
        return nil;
    
    return target;
}

#pragma mark - UIApplicationDelegate

// For when running on iOS 3.2.
- (void)applicationWillTerminate:(UIApplication *)application;
{
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationDidEnterBackground:(UIApplication *)application;
{
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application;
{
    [OAFontDescriptor forgetUnusedInstances];
}

#pragma mark -
#pragma mark MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error;
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [controller.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    }];
}

#pragma mark - Snapshots

- (void)willWaitForSnapshots
{
    [self destroyCurrentSnapshotTimer];
    [self startNewSnapshotTimer];
}

- (void)startNewSnapshotTimer
{
    NSTimeInterval secondsToWaitForSnapshots = 5.0;
    NSTimer *newTimerForSnapshots = [NSTimer scheduledTimerWithTimeInterval:secondsToWaitForSnapshots target:self selector: @selector(didFinishWaitingForSnapshots) userInfo: nil repeats: NO];
    [self setTimerForSnapshots:newTimerForSnapshots];
}

- (void)destroyCurrentSnapshotTimer
{
    [[self timerForSnapshots] invalidate];
    [self setTimerForSnapshots:nil];
}

- (void)didFinishWaitingForSnapshots
{
    //Whatever work you want done after the app finishes waiting for Apple's snapshots, implement it inside this method in your subclasses.
}

@end
