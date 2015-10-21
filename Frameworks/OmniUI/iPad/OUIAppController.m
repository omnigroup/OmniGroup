// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
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
#import <OmniUI/OUIWebViewController.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/UIViewController-OUIExtensions.h>

#import <sys/sysctl.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

NSString * const OUISystemIsSnapshottingNotification = @"OUISystemIsSnapshottingNotification";

@interface OUIAppController () <OUIWebViewControllerDelegate>
@property(strong, nonatomic) NSTimer *timerForSnapshots;
@end

@implementation OUIAppController
{
    NSMutableArray *_launchActions;
    OUIMenuController *_appMenuController;
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
        OBPerformRuntimeChecks();
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

+ (void)_presentError:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char *)file line:(int)line cancelButtonTitle:(NSString *)cancelButtonTitle;
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

        [viewController presentViewController:alertController animated:YES completion:^{}];

    }];
}

+ (void)presentError:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char *)file line:(int)line;
{
    [self _presentError:error fromViewController:viewController file:file line:line cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title")];
}

+ (void)presentAlert:(NSError *)error file:(const char *)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title
{
    [self _presentError:error fromViewController:[[[[UIApplication sharedApplication] delegate] window] rootViewController] file:file line:line cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"button title")];
}

+ (void)presentAlert:(NSError *)error fromViewController:(UIViewController *)viewController file:(const char *)file line:(int)line;  // 'OK' instead of 'Cancel' for the button title
{
    [self _presentError:error fromViewController:viewController file:file line:line cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"button title")];
}

- (void)resetKeychain;
{
    OBFinishPorting; // Make this public? Move the credential stuff into OmniFoundation instead of OmniFileStore?
//    OUIDeleteAllCredentials();
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
    return [NSString stringWithFormat:@"%@ %@%@ (v%@)", [OUIAppController applicationName], [infoDictionary objectForKey:@"CFBundleShortVersionString"], testFlightString, [infoDictionary objectForKey:@"CFBundleVersion"]];
}


- (void)sendFeedbackWithSubject:(NSString *)subject body:(NSString *)body;
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
    if (![NSString isEmptyString:body])
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
    NSString *imageName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIAppMenuImage"];
    if ([NSString isEmptyString:imageName])
        imageName = @"OUIAppMenu";
    
    UIImage *appMenuImage = menuImage(imageName);
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:appMenuImage style:UIBarButtonItemStylePlain target:self action:@selector(_showAppMenu:)];
    
    item.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Help and Settings", @"OmniUI", OMNI_BUNDLE, @"Help and Settings toolbar item accessibility label.");
    
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
    
    OBASSERT([sender isKindOfClass:[UIBarButtonItem class]]); // ...or we shouldn't be passing it as the bar item in the next call
    _appMenuController.popoverPresentationController.barButtonItem = sender;
    [self.window.rootViewController presentViewController:_appMenuController animated:YES completion:nil];
}

- (void)_sendFeedback:(id)sender NS_EXTENSION_UNAVAILABLE_IOS("");
{
    NSString *subject = [NSString stringWithFormat:@"%@ Feedback", self.fullReleaseString];
    
    [self sendFeedbackWithSubject:subject body:nil];
}

- (void)_showWebViewWithURL:(NSURL *)url title:(NSString *)title;
{
    if (url == nil)
        return;
    
    OUIWebViewController *webController = [[OUIWebViewController alloc] init];
    webController.delegate = self;
    webController.title = title;
    webController.URL = url;
    UINavigationController *webNavigationController = [[UINavigationController alloc] initWithRootViewController:webController];
    webNavigationController.navigationBar.barStyle = UIBarStyleDefault;
    
    [self.window.rootViewController presentViewController:webNavigationController animated:YES completion:nil];
}

- (void)showAboutScreenInNavigationController:(UINavigationController *)navigationController;
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
    [self _showWebViewWithURL:[[NSBundle mainBundle] URLForResource:@"MessageOfTheDay" withExtension:@"html"] title:NSLocalizedStringFromTableInBundle(@"Release Notes", @"OmniUI", OMNI_BUNDLE, @"release notes html screen title")];
}

- (void)_showOnlineHelp:(id)sender;
{
    NSString *helpBookName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"OUIHelpBookName"];
    OBASSERT(helpBookName != nil);
    NSString *webViewTitle = [[NSBundle mainBundle] localizedStringForKey:@"OUIHelpBookName" value:helpBookName table:@"InfoPlist"];

    NSString *helpBookFolder = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"OUIHelpBookFolder"];
    NSURL *helpIndexURL = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html" subdirectory:helpBookFolder];
    if (!helpIndexURL)
        helpIndexURL = [[NSBundle mainBundle] URLForResource:@"top" withExtension:@"html" subdirectory:helpBookFolder];
    OBASSERT(helpIndexURL != nil);
    [self _showWebViewWithURL:helpIndexURL title:webViewTitle];
}

#pragma mark - OUIMenuControllerDelegate

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

    option = [OUIMenuOption optionWithFirstResponderSelector:@selector(_showOnlineHelp:)
                                                       title:[[NSBundle mainBundle] localizedStringForKey:@"OUIHelpBookName" value:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"OUIHelpBookName"] table:@"InfoPlist"]
                                                       image:menuImage(@"OUIMenuItemHelp.png")];
    [options addObject:option];
    
    NSString *feedbackMenuTitle = [self feedbackMenuTitle];
    if (![NSString isEmptyString:feedbackMenuTitle] && ![self isRunningRetailDemo]) {
        option = [OUIMenuOption optionWithFirstResponderSelector:@selector(_sendFeedback:)
                                                           title:feedbackMenuTitle
                                                           image:menuImage(@"OUIMenuItemSendFeedback.png")];
        [options addObject:option];
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
