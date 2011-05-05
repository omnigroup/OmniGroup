// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController.h>

#import "OUIAppMenuController.h"
#import "OUIEventBlockingView.h"
#import "OUIParameters.h"
#import "OUISyncMenuController.h"
#import "OUISoftwareUpdateController.h"

#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIChangePreferencesActionSheet.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIDocumentProxy.h>
#import <OmniUI/OUIWebViewController.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import <MessageUI/MFMailComposeViewController.h>
#import <OmniFoundation/NSString-OFURLEncoding.h>
#import "UIViewController-OUIExtensions.h"

#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/UTType.h>

#import <SenTestingKit/SenTestSuite.h>
#import <OmniBase/system.h>
#import <sys/sysctl.h>

RCS_ID("$Id$");

@interface OUIAppController (/*Private*/)
- (NSString *)_fullReleaseString;
@end

@implementation OUIAppController

BOOL OUIShouldLogPerformanceMetrics;

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

+ (void)initialize;
{
    OBINITIALIZE;

    OUIShouldLogPerformanceMetrics = [[NSUserDefaults standardUserDefaults] boolForKey:@"LogPerformanceMetrics"];

    if (OUIShouldLogPerformanceMetrics)
        NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
    
    [UIViewController installOUIExtensions];
}

+ (id)controller;
{
    id controller = [[UIApplication sharedApplication] delegate];
    OBASSERT([controller isKindOfClass:self]);
    return controller;
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

- (NSArray *)editableFileTypes;
{
    if (!_editableFileTypes) {
        NSMutableArray *types = [NSMutableArray array];
        
        NSArray *documentTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDocumentTypes"];
        for (NSDictionary *documentType in documentTypes) {
            NSString *role = [documentType objectForKey:@"CFBundleTypeRole"];
            OBASSERT([role isEqualToString:@"Editor"] || [role isEqualToString:@"Viewer"]);
            if ([role isEqualToString:@"Editor"]) {
                NSArray *contentTypes = [documentType objectForKey:@"LSItemContentTypes"];
                for (NSString *contentType in contentTypes)
                    [types addObject:[contentType lowercaseString]];
            }
        }
        
        _editableFileTypes = [types copy];
    }
    
    return _editableFileTypes;
}

- (BOOL)canViewFileTypeWithIdentifier:(NSString *)uti;
{
    OBPRECONDITION(!uti || [uti isEqualToString:[uti lowercaseString]]); // our cache uses lowercase keys.
    
    if (uti == nil)
        return NO;
    
    if (!_roleByFileType) {
        static NSMutableDictionary *contentTypeRoles = nil;
        if (contentTypeRoles == nil) {
            // Make a fast index of all our declared UTIs
            contentTypeRoles = [[NSMutableDictionary alloc] init];
            NSArray *documentTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDocumentTypes"];
            for (NSDictionary *documentType in documentTypes) {
                NSString *role = [documentType objectForKey:@"CFBundleTypeRole"];
                if (![role isEqualToString:@"Editor"] && ![role isEqualToString:@"Viewer"])
                    continue;

                NSArray *contentTypes = [documentType objectForKey:@"LSItemContentTypes"];
                for (NSString *contentType in contentTypes)
                    [contentTypeRoles setObject:role forKey:[contentType lowercaseString]];
            }
        }
        _roleByFileType = [contentTypeRoles copy];
    }
    
    
    for (NSString *candidateUTI in _roleByFileType) {
        if (UTTypeConformsTo((CFStringRef)uti, (CFStringRef)candidateUTI))
            return YES;
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
        NSLog(@"Error source file:%s line:%d", file, line);
    NSLog(@"%@", [error toPropertyList]);
    
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:[error localizedDescription] message:[error localizedRecoverySuggestion] delegate:self cancelButtonTitle:cancelButtonTitle otherButtonTitles:nil] autorelease];
    [alert show];
}

+ (void)presentError:(NSError *)error file:(const char *)file line:(int)line;
{
    [self _presentError:error file:file line:line cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title")];
}

+ (void)presentAlert:(NSError *)error file:(const char *)file line:(int)line;
{
    [self _presentError:error file:file line:line cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"button title")];
}

- (id)init;
{
    if (!(self = [super init]))
        return nil;
    
#if OUI_SOFTWARE_UPDATE_CHECK
    _softwareUpdateController = [[OUISoftwareUpdateController alloc] init];
#endif
    
    return self;
}

- (void)dealloc;
{
#if OUI_SOFTWARE_UPDATE_CHECK
    [_softwareUpdateController release];
#endif
    [_documentPicker release];
    [_appMenuBarItem release];;
    [_appMenuController release];
    [_syncMenuController release];
    
    [super dealloc];
}

- (UIBarButtonItem *)appMenuBarItem;
{
    if (!_appMenuBarItem) {
        NSString *imageName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIAppMenuImage"];
        if (!imageName) {
            // This image says 'REPLACE' on it -- you should put something nicer in your app bundle.
            imageName = @"OUIAppMenu.png";
        }
        
        UIImage *appMenuImage = [UIImage imageNamed:imageName];
        OBASSERT(appMenuImage);
        _appMenuBarItem = [[OUIBarButtonItem alloc] initWithImage:appMenuImage style:UIBarButtonItemStyleBordered target:self action:@selector(showAppMenu:)];
    }
    
    return _appMenuBarItem;
}

@synthesize documentPicker = _documentPicker;

#pragma mark -
#pragma mark Subclass responsibility

- (UIViewController *)topViewController;
{
    OBASSERT_NOT_REACHED("Must subclass");
    return nil;
}

#pragma mark -
#pragma mark NSObject (OUIAppMenuTarget)

- (NSString *)feedbackMenuTitle;
{
    OBASSERT_NOT_REACHED("Should be subclassed to provide something nicer.");
    return @"HALP ME!";
}

// Invoked by the app menu
- (void)sendFeedback:(id)sender;
{
    // May need to allow the app delegate to provide this conditionally later (OmniFocus has a retail build, for example)
    NSString *feedbackAddress = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OUIFeedbackAddress"];
    OBASSERT(feedbackAddress);
    if (!feedbackAddress)
        return;

    UIViewController *topViewController = self.topViewController;
    OBASSERT(topViewController);
    if (!topViewController)
        return;
    
    NSString *subject = [NSString stringWithFormat:@"%@ Feedback", [self _fullReleaseString]];
    
    if (![MFMailComposeViewController canSendMail]) {
        NSString *urlString = [NSString stringWithFormat:@"mailto:%@?subject=%@", feedbackAddress,
                               [NSString encodeURLString:subject asQuery:NO leaveSlashes:NO leaveColons:NO]];
        NSURL *url = [NSURL URLWithString:urlString];
        OBASSERT(url);
        if (![[UIApplication sharedApplication] openURL:url]) {
            // Need to pop up an alert telling the user? Might happen now since we don't have Mail,  but they shouldn't be able to delete that in the real world.  Though maybe our url string is bad.
            NSLog(@"Unable to open mail url %@ from string\n%@\n", url, urlString);
            OBASSERT_NOT_REACHED("Couldn't open mail url");
        }
        return;
    }
    
    // TODO: Check +canSendMail. We're supposed to open a mailto: url if we can't.
    // TODO: Allow sending a document with the mail?
    
    MFMailComposeViewController *controller = [[MFMailComposeViewController alloc] init];
    controller.navigationBar.barStyle = UIBarStyleBlack;
    controller.mailComposeDelegate = self;
    [controller setToRecipients:[NSArray arrayWithObject:feedbackAddress]];
    [controller setSubject:subject];
    [self.topViewController presentModalViewController:controller animated:YES];
    [controller autorelease];
}

- (BOOL)activityIndicatorVisible;
{
    return (_activityIndicator.superview != nil);
}

- (void)showActivityIndicatorInView:(UIView *)view;
{
    OBPRECONDITION(view);
    OBPRECONDITION(view.window); // should already be on screen
    
    if (_activityIndicator || _eventBlockingView) {
        OBASSERT_NOT_REACHED("Not supporting nested calls");
        return;
    }
    
    OUIBeginWithoutAnimating
    {
        _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        _activityIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;
        
        _eventBlockingView = [[OUIEventBlockingView alloc] initWithFrame:CGRectZero];
        _eventBlockingView.opaque = NO;
        _eventBlockingView.backgroundColor = nil;
        
        _activityIndicator.center = view.center;
        
        _activityIndicator.layer.zPosition = 2;
        [_activityIndicator startAnimating];
        _activityIndicator.hidden = YES;
        
        [view.superview addSubview:_activityIndicator];
        
        UIView *topView = self.topViewController.view;
        OBASSERT(topView.window == view.window);
        
        _eventBlockingView.frame = topView.bounds;
        [topView addSubview:_eventBlockingView];
    }
    OUIEndWithoutAnimating;
    
    // Just fade this in
    _activityIndicator.hidden = NO;
}

- (void)hideActivityIndicator;
{
    [_eventBlockingView removeFromSuperview];
    [_eventBlockingView release];
    _eventBlockingView = nil;
    
    [_activityIndicator stopAnimating];
    [_activityIndicator removeFromSuperview];
    [_activityIndicator release];
    _activityIndicator = nil;
}

- (void)_showWebViewWithURL:(NSURL *)url title:(NSString *)title;
{
    if (url == nil)
        return;

    OUIWebViewController *webController = [[OUIWebViewController alloc] init];
    webController.title = title;
    webController.URL = url;
    UINavigationController *webNavigationController = [[UINavigationController alloc] initWithRootViewController:webController];
    webNavigationController.navigationBar.barStyle = UIBarStyleBlack;
    [webController release];

    [self.topViewController presentModalViewController:webNavigationController animated:YES];        
    [webNavigationController release];
}

- (void)_showWebViewWithPath:(NSString *)path title:(NSString *)title;
{
    if (!path)
        return;
    return [self _showWebViewWithURL:[NSURL fileURLWithPath:path] title:title];
}

- (void)showReleaseNotes:(id)sender;
{
    [self _showWebViewWithPath:[[NSBundle mainBundle] pathForResource:@"MessageOfTheDay" ofType:@"html"] title:NSLocalizedStringFromTableInBundle(@"Release Notes", @"OmniUI", OMNI_BUNDLE, @"release notes html screen title")];
}

- (void)showOnlineHelp:(id)sender;
{
    NSString *helpBookFolder = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"OUIHelpBookFolder"];
    NSString *helpBookName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"OUIHelpBookName"];
    OBASSERT(helpBookName != nil);
    NSString *webViewTitle = [[NSBundle mainBundle] localizedStringForKey:@"OUIHelpBookName" value:helpBookName table:@"InfoPlist"];

    NSString *indexPath = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html" inDirectory:helpBookFolder];
    if (indexPath == nil)
        indexPath = [[NSBundle mainBundle] pathForResource:@"top" ofType:@"html" inDirectory:helpBookFolder];
    OBASSERT(indexPath != nil);
    [self _showWebViewWithPath:indexPath title:webViewTitle];
}

- (void)runTests:(id)sender;
{
    Class cls = NSClassFromString(@"SenTestSuite");
    OBASSERT(cls);

    SenTestSuite *suite = [cls defaultTestSuite];
    [suite run];
}

- (void)showAppMenu:(id)sender;
{
    [self dismissPopoverAnimated:YES];
    
    if (!_appMenuController)
        _appMenuController = [[OUIAppMenuController alloc] init];

    OBASSERT([sender isKindOfClass:[UIBarButtonItem class]]); // ...or we shouldn't be passing it as the bar item in the next call
    [_appMenuController showMenuFromBarItem:sender];
}

- (void)showSyncMenu:(id)sender;
// aka "import from webDAV"
{
    [self dismissPopoverAnimated:YES];
    
    if (!_syncMenuController)
        _syncMenuController = [[OUISyncMenuController alloc] init];
    
    OBASSERT([sender isKindOfClass:[UIBarButtonItem class]]); // ...or we shouldn't be passing it as the bar item in the next call
    [_syncMenuController showMenuFromBarItem:sender];
}

#pragma mark -
#pragma mark Popover Helpers

static void _forgetPossiblyVisiblePopoverIfAlreadyHidden(OUIAppController *self)
{
    if (self->_possiblyVisiblePopoverController && !self->_possiblyVisiblePopoverController.popoverVisible) {
        // The user may have tapped outside the popover and dismissed it automatically (or it could have been dismissed in code without going through code). We'd have to interpose ourselves as the delegate to tell the difference to assert about it. Really, it seems like too much trouble since we just want to make sure multiple popovers aren't visible.
        [self->_possiblyVisiblePopoverController release];
        self->_possiblyVisiblePopoverController = nil;
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
        
        UIPopoverController *dismissingPopover = [possiblyVisblePopover autorelease];
        self->_possiblyVisiblePopoverController = nil;
        
        _performDismissPopover(dismissingPopover, animated);
    }
    
    return YES;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    if (_possiblyTappedButtonItem && _possiblyVisiblePopoverController.popoverVisible) {
        [self presentPopover:_possiblyVisiblePopoverController fromBarButtonItem:_possiblyTappedButtonItem permittedArrowDirections:[_possiblyVisiblePopoverController popoverArrowDirection] animated:NO];
    }
}

// Returns NO without displaying the popover, if a previously displayed popover refuses to be dismissed.
- (BOOL)presentPopover:(UIPopoverController *)popover fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
{
    OBPRECONDITION(popover);
    
    if (!_dismissVisiblePopoverInFavorOfPopover(self, popover, animated))
        return NO;
    
    OBASSERT(_possiblyVisiblePopoverController == nil);
    _possiblyVisiblePopoverController = [popover retain];
    
    [popover presentPopoverFromRect:rect inView:view permittedArrowDirections:arrowDirections animated:animated];
    return YES;
}

- (BOOL)presentPopover:(UIPopoverController *)popover fromBarButtonItem:(UIBarButtonItem *)item permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
{
    OBPRECONDITION(popover);
    
    if (!_dismissVisiblePopoverInFavorOfPopover(self, popover, animated))
        return NO;
    
    if (_possiblyVisiblePopoverController != popover) { // Might be re-displaying a popover after an orientation change.
        OBASSERT(_possiblyVisiblePopoverController == nil);
        _possiblyVisiblePopoverController = [popover retain];
    }

    // This is here to fix <bug:///69210> (Weird alignment between icon and popover arrow for the contents popover).  When we have a UIBarButtonItem with a custom view the arrow on the popup does not align correctly.  A radar #9293627 has been filed against this.  When we have a UIBarButtonItem with a custom view we present it using presentPopoverFromRect:inView:permittedArrowDirections:animated: instead of the standard presentPopoverFromBarButtonItem:permittedArrowDirections:animated:, which will align the popover arrow in the correct place.  We have to adjust the rect height to get the popover to appear in the correct place, since our buttons view size is for the toolbar height and not the actual button.
    if (item.customView) {
        CGRect rect = [item.customView convertRect:item.customView.bounds toView:[item.customView superview]];
        rect.size.height -= kOUIToolbarEdgePadding;
        [_possiblyTappedButtonItem release];
        _possiblyTappedButtonItem = [item retain];
        [popover presentPopoverFromRect:rect inView:[item.customView superview] permittedArrowDirections:arrowDirections animated:animated];
    } else
        [popover presentPopoverFromBarButtonItem:item permittedArrowDirections:arrowDirections animated:animated];
    return YES;
}

- (void)dismissPopover:(UIPopoverController *)popover animated:(BOOL)animated;
{
    // Unlike the plain UIPopoverController dismissal, this does send the 'did' hook. The reasoning here is that the caller doesn't necessarily know what popover it is dismissing.
    // If you still want to avoid the delegate method, just call the UIPopoverController method directly on your popover.
    
    _forgetPossiblyVisiblePopoverIfAlreadyHidden(self);
    [_possiblyTappedButtonItem release];
    _possiblyTappedButtonItem = nil;
    
    if (!_possiblyVisiblePopoverController || popover != _possiblyVisiblePopoverController)
        return;
    
    UIPopoverController *dismissingPopover = [_possiblyVisiblePopoverController autorelease];
    _possiblyVisiblePopoverController = nil;
    
    _performDismissPopover(dismissingPopover, animated);
}

- (void)dismissPopoverAnimated:(BOOL)animated;
{
    [self dismissPopover:_possiblyVisiblePopoverController animated:animated];
}

#pragma mark -
#pragma mark Special URL handling

- (UIViewController *)_activeController;
{
    UIViewController *activeController = self.topViewController;
    while (activeController.modalViewController != nil)
        activeController = activeController.modalViewController;
    return activeController;
}

- (BOOL)isSpecialURL:(NSURL *)url;
{
    NSString *scheme = [url scheme];
    return [OUIAppController canHandleURLScheme:scheme];
}

- (BOOL)handleSpecialURL:(NSURL *)url;
{
    if (![self isSpecialURL:url])
        return NO;

    NSString *path = [url path];
    if ([path isEqualToString:@"/change-preference"]) {
        UIViewController *activeController = [self _activeController];
        UIView *activeView = activeController.view;
        if (activeView != nil) {
            OUIChangePreferencesActionSheet *actionSheet = [[OUIChangePreferencesActionSheet alloc] initWithChangePreferenceURL:url];
            // [actionSheet showFromRect:[_exportButton frame] inView:[_exportButton superview] animated:YES];
            [actionSheet showInView:activeView]; // returns immediately
            [actionSheet release];
        }
    }

    return YES;
}

#pragma mark -
#pragma mark UIApplicationDelegate

// For when running on iOS 3.2.
- (void)applicationWillTerminate:(UIApplication *)application;
{
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application;
{
    _forgetPossiblyVisiblePopoverIfAlreadyHidden(self);
}

#pragma mark -
#pragma mark MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error;
{
    [self.topViewController dismissModalViewControllerAnimated:YES];
}

#pragma mark -
#pragma mark OUIDocumentPickerDelegate

- (Class)documentPicker:(OUIDocumentPicker *)picker proxyClassForURL:(NSURL *)proxyURL;
{
    return [OUIDocumentProxy class];
}

- (NSString *)documentPickerBaseNameForNewFiles:(OUIDocumentPicker *)picker;
{
    return NSLocalizedStringFromTableInBundle(@"My Document", @"OmniUI", OMNI_BUNDLE, @"Base name for newly created documents. This will have an number appended to it to make it unique.");
}

- (BOOL)createNewDocumentAtURL:(NSURL *)url error:(NSError **)outError;
{
    OBRequestConcreteImplementation(self, _cmd);
}

#pragma mark -
#pragma mark Private

- (NSString *)_fullReleaseString;
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    return [NSString stringWithFormat:@"%@ %@ (v%@)", [infoDictionary objectForKey:@"CFBundleName"], [infoDictionary objectForKey:@"CFBundleShortVersionString"], [infoDictionary objectForKey:@"CFBundleVersion"]];
}

@end
