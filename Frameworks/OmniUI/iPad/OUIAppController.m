// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
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
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIMenuController.h>
#import <OmniUI/OUIMenuOption.h>
#import <OmniUI/OUISpecialURLActionSheet.h>
#import <OmniUI/OUIWebViewController.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/UIViewController-OUIExtensions.h>
#import <SenTestingKit/SenTestSuite.h>

#import <sys/sysctl.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@interface OUIAppController () <OUIMenuControllerDelegate, OUIWebViewControllerDelegate>
@end

@implementation OUIAppController
{
    NSMutableArray *_launchActions;
    
    UIPopoverController *_possiblyVisiblePopoverController;
    UIPopoverArrowDirection _possiblyVisiblePopoverControllerArrowDirections;
    UIBarButtonItem *_possiblyTappedButtonItem;
    
    OUIMenuController *_appMenuController;
    
    OUIActionSheet *_possiblyVisibleActionSheet;
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
    
    OUIShouldLogPerformanceMetrics = [[NSUserDefaults standardUserDefaults] boolForKey:@"LogPerformanceMetrics"];

    if (OUIShouldLogPerformanceMetrics)
        NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));

#ifdef OMNI_ASSERTIONS_ON
    OBPerformRuntimeChecks();
#endif
}

+ (instancetype)controller;
{
    id controller = [[UIApplication sharedApplication] delegate];
    OBASSERT([controller isKindOfClass:self]);
    return controller;
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
    [self presentError:error file:NULL line:0];
}

+ (void)_presentError:(NSError *)error file:(const char *)file line:(int)line cancelButtonTitle:(NSString *)cancelButtonTitle;
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
        
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[error localizedDescription] message:message delegate:nil cancelButtonTitle:cancelButtonTitle otherButtonTitles:nil];
        [alert show];
    }];
}

+ (void)presentError:(NSError *)error file:(const char *)file line:(int)line;
{
    [self _presentError:error file:file line:line cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title")];
}

+ (void)presentAlert:(NSError *)error file:(const char *)file line:(int)line;
{
    [self _presentError:error file:file line:line cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"button title")];
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

#pragma mark -
#pragma mark Popover Helpers

static void _forgetPossiblyVisiblePopoverIfAlreadyHidden(OUIAppController *self)
{
    if (self->_possiblyVisiblePopoverController && !self->_possiblyVisiblePopoverController.popoverVisible) {
        // The user may have tapped outside the popover and dismissed it automatically (or it could have been dismissed in code without going through code). We'd have to interpose ourselves as the delegate to tell the difference to assert about it. Really, it seems like too much trouble since we just want to make sure multiple popovers aren't visible.
        self->_possiblyVisiblePopoverController = nil;
        self->_possiblyVisiblePopoverControllerArrowDirections = UIPopoverArrowDirectionUnknown;
    }
}
    
static void _performDismissPopover(UIPopoverController *dismissingPopover, BOOL animated)
{
    OBPRECONDITION(dismissingPopover);
    
    [dismissingPopover dismissPopoverAnimated:animated]; // Might always want to snap the old one out...
    
    // Like the normal case of popovers disappearing (when tapping out), we send this *before* the animation finishes.
    id <UIPopoverControllerDelegate> delegate = dismissingPopover.delegate;
    if ([delegate respondsToSelector:@selector(popoverControllerDidDismissPopover:)])
        [delegate popoverControllerDidDismissPopover:dismissingPopover];
}

static BOOL _dismissVisiblePopoverInFavorOfPopover(OUIAppController *self, UIPopoverController *popoverToPresent, BOOL animated)
{
    _forgetPossiblyVisiblePopoverIfAlreadyHidden(self);
    
    UIPopoverController *possiblyVisblePopover = self->_possiblyVisiblePopoverController;
    
    // Hide the old popover if it is still visible (and we aren't re-presenting the same one).
    if (possiblyVisblePopover && popoverToPresent != possiblyVisblePopover) {
        // The popover dismissal delegate is called when your popover is implicitly hidden, but not when you dismiss it in code.
        // We'll interpret the presentation of a different popover as an implicit dismissal that should tell the delegate.
        id <UIPopoverControllerDelegate> delegate = possiblyVisblePopover.delegate;
        if ([delegate respondsToSelector:@selector(popoverControllerShouldDismissPopover:)] && ![delegate popoverControllerShouldDismissPopover:possiblyVisblePopover])
            // Nobody puts popover in the corner!
            return NO;
        
        UIPopoverController *dismissingPopover = possiblyVisblePopover;
        self->_possiblyVisiblePopoverController = nil;
        self->_possiblyVisiblePopoverControllerArrowDirections = UIPopoverArrowDirectionUnknown;

        _performDismissPopover(dismissingPopover, animated);
    }
    
    return YES;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    if (_possiblyTappedButtonItem && _possiblyVisiblePopoverController.popoverVisible) {
        // Hiding a popover sets its allowed arrow directions to UIPopoverArrowDirectionUnknown under iOS 5, which causes an exception here on representation. So, we now remember the original argument passed in ourselves rather than calling -arrowDirections on the popover.
        [self presentPopover:_possiblyVisiblePopoverController fromBarButtonItem:_possiblyTappedButtonItem permittedArrowDirections:_possiblyVisiblePopoverControllerArrowDirections animated:NO];
    } else if (_possiblyVisiblePopoverController.popoverVisible) {
        // popover was shown with -presentPopover:fromRect:inView:permittedArrowDirections:animated: which does not automatically reposition on rotation, so going to dismiss this popover
        [self dismissPopoverAnimated:YES];
    }
}

- (BOOL)hasVisiblePopover;
{
    _forgetPossiblyVisiblePopoverIfAlreadyHidden(self);
    return _possiblyVisiblePopoverController != nil;
}

// Returns NO without displaying the popover, if a previously displayed popover refuses to be dismissed.
- (BOOL)presentPopover:(UIPopoverController *)popover fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
{
    OBPRECONDITION(popover);
    
    // Treat a print sheet the same way as a popover and dismiss it when presenting something else. Sure would be nice if UIPrintInteractionController was a subclass of UIPopoverController as would make sense... 
    [[UIPrintInteractionController sharedPrintController] dismissAnimated:animated];
    
    // If _possiblyVisibleActionSheet is not nil, then we have a visable actionSheet. Dismiss it.
    if (_possiblyVisibleActionSheet) {
        [self dismissActionSheetAndPopover:YES];
    }
    
    if (!_dismissVisiblePopoverInFavorOfPopover(self, popover, animated))
        return NO;
    
    OBASSERT(_possiblyVisiblePopoverController == nil);
    _possiblyVisiblePopoverController = popover;
    _possiblyVisiblePopoverControllerArrowDirections = arrowDirections;
    
    [popover presentPopoverFromRect:rect inView:view permittedArrowDirections:arrowDirections animated:animated];
    return YES;
}

- (BOOL)presentPopover:(UIPopoverController *)popover fromBarButtonItem:(UIBarButtonItem *)item permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
{
    OBPRECONDITION(popover);

    // Treat a print sheet the same way as a popover and dismiss it when presenting something else. Sure would be nice if UIPrintInteractionController was a subclass of UIPopoverController as would make sense...
    [[UIPrintInteractionController sharedPrintController] dismissAnimated:animated];

    // If _possiblyVisibleActionSheet is not nil, then we have a visable actionSheet. Dismiss it.
    if (_possiblyVisibleActionSheet) {
        [self dismissActionSheetAndPopover:YES];
    }
    
    if (!_dismissVisiblePopoverInFavorOfPopover(self, popover, animated))
        return NO;
    
    if (_possiblyVisiblePopoverController != popover) { // Might be re-displaying a popover after an orientation change.
        OBASSERT(_possiblyVisiblePopoverController == nil);
        _possiblyVisiblePopoverController = popover;
        _possiblyVisiblePopoverControllerArrowDirections = arrowDirections;
    }

    // This is here to fix <bug:///69210> (Weird alignment between icon and popover arrow for the contents popover).  When we have a UIBarButtonItem with a custom view the arrow on the popup does not align correctly.  A radar #9293627 has been filed against this.  When we have a UIBarButtonItem with a custom view we present it using presentPopoverFromRect:inView:permittedArrowDirections:animated: instead of the standard presentPopoverFromBarButtonItem:permittedArrowDirections:animated:, which will align the popover arrow in the correct place.  We have to adjust the rect height to get the popover to appear in the correct place, since our buttons view size is for the toolbar height and not the actual button.
#define kOUIToolbarEdgePadding (5.0f)
    if (item.customView) {
        CGRect rect = [item.customView convertRect:item.customView.bounds toView:[item.customView superview]];
        rect.size.height -= kOUIToolbarEdgePadding;
        [popover presentPopoverFromRect:rect inView:[item.customView superview] permittedArrowDirections:arrowDirections animated:animated];
    } else {
        [popover presentPopoverFromBarButtonItem:item permittedArrowDirections:arrowDirections animated:animated];

        // This automatically adds the containing navigation bar as a passthrough view. We don't want tapping on toolbar items to be enabled when a popover item is up. Otherwise, we have dimmed toolbar items that can be tapped and perform actions unexpectedly (or every action needs to check if there is a popover up and dismiss it instead).
        popover.passthroughViews = nil;
    }

    _possiblyTappedButtonItem = item;
    return YES;
}

- (BOOL)dismissPopover:(UIPopoverController *)popover animated:(BOOL)animated;
{
    // Treat a print sheet the same way as a popover and dismiss it when presenting something else. Sure would be nice if UIPrintInteractionController was a subclass of UIPopoverController as would make sense...
    [[UIPrintInteractionController sharedPrintController] dismissAnimated:animated];
    
    // Unlike the plain UIPopoverController dismissal, this does send the 'did' hook. The reasoning here is that the caller doesn't necessarily know what popover it is dismissing.
    // If you still want to avoid the delegate method, just call the UIPopoverController method directly on your popover.
    
    _forgetPossiblyVisiblePopoverIfAlreadyHidden(self);
    _possiblyTappedButtonItem = nil;
    
    if (!_possiblyVisiblePopoverController || popover != _possiblyVisiblePopoverController)
        return NO;
    
    UIPopoverController *dismissingPopover = _possiblyVisiblePopoverController;
    _possiblyVisiblePopoverController = nil;
    _possiblyVisiblePopoverControllerArrowDirections = UIPopoverArrowDirectionUnknown;

    _performDismissPopover(dismissingPopover, animated);
    return YES;
}

- (void)dismissPopoverAnimated:(BOOL)animated;
{
    [self dismissPopover:_possiblyVisiblePopoverController animated:animated];
}

- (void)forgetPossiblyVisiblePopoverIfAlreadyHidden;
{
    _forgetPossiblyVisiblePopoverIfAlreadyHidden(self);
}

- (BOOL)hasVisibleActionSheet;
{
    return _possiblyVisibleActionSheet.visible;
}

// Action Sheet Helpers
- (void)showActionSheet:(OUIActionSheet *)actionSheet fromSender:(id)sender animated:(BOOL)animated;
{
    // Test to see if the user is trying to show the same actionSheet that is already visible. If so, dismiss it and return.
    if (_possiblyVisibleActionSheet &&
        [actionSheet.identifier isEqualToString:_possiblyVisibleActionSheet.identifier]) {
        [self dismissActionSheetAndPopover:YES];
        return;
    }

    [self dismissActionSheetAndPopover:YES];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(actionSheetDidDismiss:)
                                                 name:OUIActionSheetDidDismissNotification
                                               object:actionSheet];
    
    if ([sender isKindOfClass:[UIView class]])
        [actionSheet showFromRect:[sender frame] inView:[sender superview] animated:animated];
    else {
        OBASSERT([sender isKindOfClass:[UIBarButtonItem class]]);
        [actionSheet showFromBarButtonItem:sender animated:animated];
    }
    
    _possiblyVisibleActionSheet = actionSheet;
}

- (BOOL)dismissActionSheetAndPopover:(BOOL)animated;
{
    BOOL didDismiss = NO;
    
    if ([self hasVisiblePopover]) {
        [self dismissPopover:_possiblyVisiblePopoverController animated:animated];
        didDismiss = YES;
    }
    
    if ([self hasVisibleActionSheet]) {
        [_possiblyVisibleActionSheet dismissWithClickedButtonIndex:_possiblyVisibleActionSheet.cancelButtonIndex animated:animated];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:OUIActionSheetDidDismissNotification object:_possiblyVisibleActionSheet];
        didDismiss = YES;
    }
    
    return didDismiss;
}

#pragma mark -
#pragma mark Special URL handling

- (UIViewController *)_activeController;
{
    UIViewController *activeController = self.window.rootViewController;
    while (activeController.presentedViewController != nil)
        activeController = activeController.presentedViewController;
    return activeController;
}

- (BOOL)isSpecialURL:(NSURL *)url;
{
    NSString *scheme = [url scheme];
    return [OUIAppController canHandleURLScheme:scheme];
}

- (BOOL)handleSpecialURL:(NSURL *)url;
{
    OBPRECONDITION([self isSpecialURL:url]);

    UIViewController *activeController = [self _activeController];
    UIView *activeView = activeController.view;
    if (activeView == nil)
        return NO; 

    NSString *path = [url path];
    UIActionSheet *actionSheet = nil;
    
    if ([path isEqualToString:@"/change-preference"]) {
        NSString *titleFormat = NSLocalizedStringFromTableInBundle(@"You have tapped on a link which will change the following preferences:\n\n\"%@\"\n\nDo you wish to accept these changes?", @"OmniUI", OMNI_BUNDLE, @"alert message");
        actionSheet = [[OUISpecialURLActionSheet alloc] initWithURL:url titleFormat:titleFormat handler:OUIChangePreferenceURLHandler];
    } else if ([path isEqualToString:@"/debug"]) {
        NSString *titleFormat = NSLocalizedStringFromTableInBundle(@"You have tapped on a link which will run the following debugging command:\n\n\"%@\"\n\nIf you weren’t instructed to do this by Omni Support Humans, please don’t.\nDo you wish to run this command?", @"OmniUI", OMNI_BUNDLE, @"debug setting alert message");
        actionSheet = [[OUISpecialURLActionSheet alloc] initWithURL:url titleFormat:titleFormat handler:[self debugURLHandler]];
    }
    
    if (actionSheet) {
        [actionSheet showInView:activeView]; // returns immediately
        return YES;
    }

    return NO;
}

- (OUISpecialURLHandler)debugURLHandler;
{
    // subclass should override to provide handler for app-specific debug URLs of format [appName]:///debug?command, e.g. omnioutliner:///debug?reset-keychain
    return [^(NSURL *url){ return NO; } copy];
}

- (void)actionSheetDidDismiss:(NSNotification *)notification;
{
    OUIActionSheet *actionSheet = (OUIActionSheet *)notification.object;
    
    // The user could be switching between action sheets. When it's dismissed with animation, we may have already reassigned _nonretaind_actionSheet. So we don't always want to set it to nil. If the user is actually just dismissing it, the _possiblyVisibleActionSheet should still match actionSheet, so we're good to set it to nil.
    if (actionSheet == _possiblyVisibleActionSheet) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:OUIActionSheetDidDismissNotification object:_possiblyVisibleActionSheet];

        _possiblyVisibleActionSheet = nil;
    }
}

- (BOOL)isRunningRetailDemo;
{
    return [[OFPreference preferenceForKey:@"IPadRetailDemo"] boolValue];
}

- (BOOL)showFeatureDisabledForRetailDemoAlert;
{
    if ([self isRunningRetailDemo]) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Feature not enabled for this demo", @"OmniUI", OMNI_BUNDLE, @"disabled for demo") message:nil delegate:nil cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Done", @"OmniUI", OMNI_BUNDLE, @"Done") otherButtonTitles:nil];
        [alert show];
        return YES;
    }
    
    return NO;
}

- (NSString *)fullReleaseString;
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    return [NSString stringWithFormat:@"%@ %@ (v%@)", [infoDictionary objectForKey:@"CFBundleName"], [infoDictionary objectForKey:@"CFBundleShortVersionString"], [infoDictionary objectForKey:@"CFBundleVersion"]];
}


- (void)sendFeedbackWithSubject:(NSString *)subject body:(NSString *)body;
{
    // May need to allow the app delegate to provide this conditionally later (OmniFocus has a retail build, for example)
    NSString *feedbackAddress = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIFeedbackAddress"];
    OBASSERT(feedbackAddress);
    if (!feedbackAddress)
        return;
    
    UIViewController *viewControllerToPresentFrom = self.window.rootViewController;
    OBASSERT(viewControllerToPresentFrom);
    if (!viewControllerToPresentFrom)
        return;

    // If the caller left up a different modal view controller, our attempt to show another modal view controller would just log a warning and do nothing.
    BOOL allowInAppCompose = (viewControllerToPresentFrom.presentedViewController == nil);

    BOOL useComposeView = allowInAppCompose && [MFMailComposeViewController canSendMail];
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

- (UIBarButtonItem *)newAppMenuBarButtonItem;
{
    NSString *imageName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIAppMenuImage"];
    if ([NSString isEmptyString:imageName])
        imageName = @"OUIAppMenu.png";
    
    UIImage *appMenuImage = menuImage(imageName);
    OBASSERT(appMenuImage);
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:appMenuImage style:UIBarButtonItemStylePlain target:self action:@selector(_showAppMenu:)];
    
    item.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Help and Settings", @"OmniUI", OMNI_BUNDLE, @"Help and Settings toolbar item accessibility label.");
    
    return item;
}

#pragma mark App menu actions
- (void)_showAppMenu:(id)sender;
{
    if (!_appMenuController)
        _appMenuController = [[OUIMenuController alloc] initWithDelegate:self];
    
    _appMenuController.tintColor = self.window.tintColor;
    
    OBASSERT([sender isKindOfClass:[UIBarButtonItem class]]); // ...or we shouldn't be passing it as the bar item in the next call
    [_appMenuController showMenuFromSender:sender];
}

- (void)_sendFeedback:(id)sender;
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

- (void)_runTests:(id)sender;
{
    Class cls = NSClassFromString(@"SenTestSuite");
    OBASSERT(cls);
    
    SenTestSuite *suite = [cls defaultTestSuite];
    [suite run];
}

#pragma mark - OUIMenuControllerDelegate

static UIImage *menuImage(NSString *name)
{
    return [[UIImage imageNamed:name] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}
- (NSArray *)menuControllerOptions:(OUIMenuController *)menu;
{
    if (menu != _appMenuController) {
        OBASSERT_NOT_REACHED("Unknown menu %@!", menu);
        return nil;
    }
    
    NSMutableArray *options = [NSMutableArray array];
    OUIMenuOption *option;
    NSArray *additionalOptions;
    
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
    
    for (NSString *inAppPurchaseIdentifier in [self inAppPurchaseIdentifiers]) {
        NSString *inAppPurchaseTitle = [self purchaseMenuItemTitleForInAppStoreProductIdentifier:inAppPurchaseIdentifier];
        if (!inAppPurchaseIdentifier)
            continue;
        
        option = [[OUIMenuOption alloc] initWithTitle:inAppPurchaseTitle image:menuImage(@"OUIMenuItemPurchases.png") action:^{
            [[OUIAppController controller] showInAppPurchases:inAppPurchaseIdentifier navigationController:nil];
        }];
        [options addObject:option];
    }
    
    additionalOptions = [self additionalAppMenuOptionsAtPosition:OUIAppMenuOptionPositionAtEnd];
    if (additionalOptions)
        [options addObjectsFromArray:additionalOptions];
    
#if defined(DEBUG)
    BOOL includedTestsMenu = YES;
#else
    BOOL includedTestsMenu = [[NSUserDefaults standardUserDefaults] boolForKey:@"OUIIncludeTestsMenu"];
#endif
    if (includedTestsMenu && NSClassFromString(@"SenTestSuite")) {
        option = [OUIMenuOption optionWithFirstResponderSelector:@selector(_runTests:)
                                                           title:NSLocalizedStringFromTableInBundle(@"Run Tests", @"OmniUI", OMNI_BUNDLE, @"App menu item title")
                                                           image:menuImage(@"OUIMenuItemRunTests.png")];
        [options addObject:option];
    }
    
    return options;
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
    
    _forgetPossiblyVisiblePopoverIfAlreadyHidden(self);
}

#pragma mark -
#pragma mark MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error;
{
    [controller.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end
