// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController.h>

#import <MessageUI/MFMailComposeViewController.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/UTType.h>
#import <OmniAppKit/OAFontDescriptor.h>
#import <OmniBase/OBRuntimeCheck.h>
#import <OmniBase/system.h>
#import <OmniFileStore/OFSDocumentStore.h>
#import <OmniFileStore/OFSDocumentStoreFileItem.h>
#import <OmniFoundation/NSString-OFURLEncoding.h>
#import <OmniFoundation/OFBundleRegistry.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIAboutPanel.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIMenuController.h>
#import <OmniUI/OUISpecialURLActionSheet.h>
#import <OmniUI/OUIWebViewController.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <SenTestingKit/SenTestSuite.h>

#import <sys/sysctl.h>

#import "OUICredentials.h"
#import "OUIParameters.h"
#import "OUISoftwareUpdateController.h"
#import "OUISyncMenuController.h"
#import "UIViewController-OUIExtensions.h"
#import "OUISingleDocumentAppController-Internal.h" // Terrible -- for _setupCloud:

RCS_ID("$Id$");

@interface OUIAppController (/*Private*/)
- (NSString *)_fullReleaseString;
@end

@implementation OUIAppController
{
    OUIDocumentPicker *_documentPicker;
    UIBarButtonItem *_appMenuBarItem;
    OUIMenuController *_appMenuController;
    OUISyncMenuController *_syncMenuController;
    
#if OUI_SOFTWARE_UPDATE_CHECK
    OUISoftwareUpdateController *_softwareUpdateController;
#endif
    
    dispatch_once_t _roleByFileTypeOnce;
    NSDictionary *_roleByFileType;
    
    NSArray *_editableFileTypes;

    UIPopoverController *_possiblyVisiblePopoverController;
    UIPopoverArrowDirection _possiblyVisiblePopoverControllerArrowDirections;
    UIBarButtonItem *_possiblyTappedButtonItem;
    
    OUIActionSheet *_possiblyVisibleActionSheet;
}

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

    // Poke OFPreference to get default values registered
#ifdef DEBUG
    NSDictionary *defaults = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithBool:YES], @"NSShowNonLocalizableStrings",
                              [NSNumber numberWithBool:YES], @"NSShowNonLocalizedStrings",
                              nil
                              ];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
#endif
    [OFBundleRegistry registerKnownBundles];
    [OFPreference class];
    
    OUIShouldLogPerformanceMetrics = [[NSUserDefaults standardUserDefaults] boolForKey:@"LogPerformanceMetrics"];

    if (OUIShouldLogPerformanceMetrics)
        NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
    
    [UIViewController installOUIViewControllerExtensions];
    
#ifdef OMNI_ASSERTIONS_ON
    OBPerformRuntimeChecks();
#endif
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
    
    dispatch_once(&_roleByFileTypeOnce, ^{
        // Make a fast index of all our declared UTIs
        NSMutableDictionary *contentTypeRoles = [[NSMutableDictionary alloc] init];
        NSArray *documentTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDocumentTypes"];
        for (NSDictionary *documentType in documentTypes) {
            NSString *role = [documentType objectForKey:@"CFBundleTypeRole"];
            if (![role isEqualToString:@"Editor"] && ![role isEqualToString:@"Viewer"])
                continue;
            
            NSArray *contentTypes = [documentType objectForKey:@"LSItemContentTypes"];
            for (NSString *contentType in contentTypes)
                [contentTypeRoles setObject:role forKey:[contentType lowercaseString]];
        }
        
        _roleByFileType = [contentTypeRoles copy];
        [contentTypeRoles release];
    });
    OBASSERT(_roleByFileType);

    
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
        
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:[error localizedDescription] message:message delegate:nil cancelButtonTitle:cancelButtonTitle otherButtonTitles:nil] autorelease];
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
        if ([NSString isEmptyString:imageName])
            imageName = @"OUIAppMenu.png";
        
        UIImage *appMenuImage = [UIImage imageNamed:imageName];
        OBASSERT(appMenuImage);
        _appMenuBarItem = [[UIBarButtonItem alloc] initWithImage:appMenuImage style:UIBarButtonItemStylePlain target:self action:@selector(showAppMenu:)];
        
        _appMenuBarItem.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Help and Settings", @"OmniUI", OMNI_BUNDLE, @"Help and Settings toolbar item accessibility label.");
    }
    
    return _appMenuBarItem;
}

- (void)resetKeychain;
{
    OUIDeleteAllCredentials();
}

@synthesize documentPicker = _documentPicker;

#pragma mark -
#pragma mark Subclass responsibility

- (UIViewController *)topViewController;
{
    OBASSERT_NOT_REACHED("Must subclass");
    return nil;
}

- (NSString *)applicationName;
{
    // The kCFBundleNameKey is often in the format "AppName-iPad".  If so, define an OUIApplicationName key in Info.plist and provide a better human-readable name, such as "AppName" or "AppName for iPad".
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    NSString *appName = [infoDictionary objectForKey:@"OUIApplicationName"];
    if (!appName) {
        appName = [infoDictionary objectForKey:(NSString *)kCFBundleNameKey];
    }
    return appName;
}

#pragma mark -
#pragma mark NSObject (OUIAppMenuTarget)

- (NSString *)feedbackMenuTitle;
{
    OBASSERT_NOT_REACHED("Should be subclassed to provide something nicer.");
    return @"HALP ME!";
}

- (NSString *)aboutMenuTitle;
{
    NSString *format = NSLocalizedStringFromTableInBundle(@"About %@", @"OmniUI", OMNI_BUNDLE, @"Default title for the About menu item");
    return [NSString stringWithFormat:format, self.applicationName];
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

- (void)showAboutPanel:(id)sender;
{
    [OUIAboutPanel displayInSheet];
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
    if (!_appMenuController)
        _appMenuController = [[OUIMenuController alloc] initWithDelegate:self];

    OBASSERT([sender isKindOfClass:[UIBarButtonItem class]]); // ...or we shouldn't be passing it as the bar item in the next call
    [_appMenuController showMenuFromBarItem:sender];
}

- (void)showSyncMenu:(id)sender;
// aka "import from webDAV"
{
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
        
        UIPopoverController *dismissingPopover = [possiblyVisblePopover autorelease];
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
        [_possiblyVisiblePopoverController dismissPopoverAnimated:NO];
    }
}

// Returns NO without displaying the popover, if a previously displayed popover refuses to be dismissed.
- (BOOL)presentPopover:(UIPopoverController *)popover fromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
{
    OBPRECONDITION(popover);
    
    // If _possiblyVisibleActionSheet is not nil, then we have a visable actionSheet. Dismiss it.
    if (_possiblyVisibleActionSheet) {
        [self dismissActionSheetAndPopover:YES];
    }
    
    if (!_dismissVisiblePopoverInFavorOfPopover(self, popover, animated))
        return NO;
    
    OBASSERT(_possiblyVisiblePopoverController == nil);
    _possiblyVisiblePopoverController = [popover retain];
    _possiblyVisiblePopoverControllerArrowDirections = arrowDirections;
    
    [popover presentPopoverFromRect:rect inView:view permittedArrowDirections:arrowDirections animated:animated];
    return YES;
}

- (BOOL)presentPopover:(UIPopoverController *)popover fromBarButtonItem:(UIBarButtonItem *)item permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated;
{
    OBPRECONDITION(popover);

    // If _possiblyVisibleActionSheet is not nil, then we have a visable actionSheet. Dismiss it.
    if (_possiblyVisibleActionSheet) {
        [self dismissActionSheetAndPopover:YES];
    }
    
    if (!_dismissVisiblePopoverInFavorOfPopover(self, popover, animated))
        return NO;
    
    if (_possiblyVisiblePopoverController != popover) { // Might be re-displaying a popover after an orientation change.
        OBASSERT(_possiblyVisiblePopoverController == nil);
        _possiblyVisiblePopoverController = [popover retain];
        _possiblyVisiblePopoverControllerArrowDirections = arrowDirections;
    }

    // This is here to fix <bug:///69210> (Weird alignment between icon and popover arrow for the contents popover).  When we have a UIBarButtonItem with a custom view the arrow on the popup does not align correctly.  A radar #9293627 has been filed against this.  When we have a UIBarButtonItem with a custom view we present it using presentPopoverFromRect:inView:permittedArrowDirections:animated: instead of the standard presentPopoverFromBarButtonItem:permittedArrowDirections:animated:, which will align the popover arrow in the correct place.  We have to adjust the rect height to get the popover to appear in the correct place, since our buttons view size is for the toolbar height and not the actual button.
#define kOUIToolbarEdgePadding (5.0f)
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
    _possiblyVisiblePopoverControllerArrowDirections = UIPopoverArrowDirectionUnknown;

    _performDismissPopover(dismissingPopover, animated);
}

- (void)dismissPopoverAnimated:(BOOL)animated;
{
    [self dismissPopover:_possiblyVisiblePopoverController animated:animated];
}

- (void)forgetPossiblyVisiblePopoverIfAlreadyHidden;
{
    _forgetPossiblyVisiblePopoverIfAlreadyHidden(self);
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

- (void)dismissActionSheetAndPopover:(BOOL)animated;
{
    [self dismissPopover:_possiblyVisiblePopoverController animated:animated];
    
    if (_possiblyVisibleActionSheet) {
        [_possiblyVisibleActionSheet dismissWithClickedButtonIndex:_possiblyVisibleActionSheet.cancelButtonIndex animated:animated];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:OUIActionSheetDidDismissNotification object:_possiblyVisibleActionSheet];        
    }
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
        NSString *titleFormat = NSLocalizedStringFromTableInBundle(@"You have tapped on a link which will run the following debugging command:\n\n\"%@\"\n\nIf you weren’t instructed to do this by Omni Support Ninjas, please don’t.\nDo you wish to run this command?", @"OmniUI", OMNI_BUNDLE, @"debug setting alert message");
        actionSheet = [[OUISpecialURLActionSheet alloc] initWithURL:url titleFormat:titleFormat handler:[self debugURLHandler]];
    }
    
    if (actionSheet) {
        [actionSheet showInView:activeView]; // returns immediately
        [actionSheet release];
    }

    return YES;
}

- (OUISpecialURLHandler)debugURLHandler;
{
    // subclass should override to provide handler for app-specific debug URLs of format [appName]:///debug?command, e.g. omnioutliner:///debug?reset-keychain
    return [[^(NSURL *url){ return NO; } copy] autorelease];
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
#ifdef DEBUG_rachael
    NSLog(@"demo mode = %d", [[OFPreference preferenceForKey:@"IPadRetailDemo"] boolValue]);
#endif
    return [[OFPreference preferenceForKey:@"IPadRetailDemo"] boolValue];
}

#pragma mark -
#pragma mark UIApplicationDelegate

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
    [self.topViewController dismissModalViewControllerAnimated:YES];
}

#pragma mark -
#pragma mark OFSDocumentStoreDelegate

- (Class)documentStore:(OFSDocumentStore *)store fileItemClassForURL:(NSURL *)fileURL;
{
    return [OFSDocumentStoreFileItem class];
}

- (NSString *)documentStoreBaseNameForNewFiles:(OFSDocumentStore *)store;
{
    return NSLocalizedStringFromTableInBundle(@"My Document", @"OmniUI", OMNI_BUNDLE, @"Base name for newly created documents. This will have an number appended to it to make it unique.");
}

- (NSArray *)documentStoreEditableDocumentTypes:(OFSDocumentStore *)store;
{
    return [self editableFileTypes];
}

- (void)createNewDocumentAtURL:(NSURL *)url completionHandler:(void (^)(NSURL *url, NSError *error))completionHandler;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (BOOL)documentStore:(OFSDocumentStore *)store canViewFileTypeWithIdentifier:(NSString *)uti;
{
    return [self canViewFileTypeWithIdentifier:uti];
}

#pragma mark - OUIMenuControllerDelegate

//#define SHOW_ABOUT_MENU_ITEM 1

- (NSArray *)menuControllerOptions:(OUIMenuController *)menu;
{
    if (menu == _appMenuController) {
        NSMutableArray *options = [NSMutableArray array];
        OUIMenuOption *option;

#ifdef SHOW_ABOUT_MENU_ITEM
        option = [OUIMenuController menuOptionWithFirstResponderSelector:@selector(showAboutPanel:)
                                                                   title:NSLocalizedStringFromTableInBundle(@"About", @"OmniUI", OMNI_BUNDLE, @"App menu item title")
                                                                   image:[UIImage imageNamed:@"OUIMenuItemAbout.png"]];
        [options addObject:option];
#endif
        
        if ([OFSDocumentStore canPromptForUbiquityAccess]) {
            // -_setupCloud: is on OUISingleDocumentAppController. Perhaps its iCloud support should be merged up, or split into a OUIDocumentController...
            option = [OUIMenuController menuOptionWithFirstResponderSelector:@selector(_setupCloud:)
                                                                       title:NSLocalizedStringFromTableInBundle(@"Set Up iCloud", @"OmniUI", OMNI_BUNDLE, @"App menu item title")
                                                                       image:[UIImage imageNamed:@"OUIMenuItemCloudSetUp.png"]];
            [options addObject:option];
        }
        
        option = [OUIMenuController menuOptionWithFirstResponderSelector:@selector(showOnlineHelp:)
                                                                   title:[[NSBundle mainBundle] localizedStringForKey:@"OUIHelpBookName" value:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"OUIHelpBookName"] table:@"InfoPlist"]
                                                                   image:[UIImage imageNamed:@"OUIMenuItemHelp.png"]];
        [options addObject:option];
        
        option = [OUIMenuController menuOptionWithFirstResponderSelector:@selector(sendFeedback:)
                                                                   title:[[OUIAppController controller] feedbackMenuTitle]
                                                                   image:[UIImage imageNamed:@"OUIMenuItemSendFeedback.png"]];
        [options addObject:option];
        
        option = [OUIMenuController menuOptionWithFirstResponderSelector:@selector(showReleaseNotes:)
                                                                   title:NSLocalizedStringFromTableInBundle(@"Release Notes", @"OmniUI", OMNI_BUNDLE, @"App menu item title")
                                                                   image:[UIImage imageNamed:@"OUIMenuItemReleaseNotes.png"]];
        [options addObject:option];
#if defined(DEBUG)
        BOOL includedTestsMenu = YES;
#else
        BOOL includedTestsMenu = [[NSUserDefaults standardUserDefaults] boolForKey:@"OUIIncludeTestsMenu"];
#endif
        if (includedTestsMenu && NSClassFromString(@"SenTestSuite")) {
            option = [OUIMenuController menuOptionWithFirstResponderSelector:@selector(runTests:)
                                                                       title:NSLocalizedStringFromTableInBundle(@"Run Tests", @"OmniUI", OMNI_BUNDLE, @"App menu item title")
                                                                       image:[UIImage imageNamed:@"OUIMenuItemRunTests.png"]];
            [options addObject:option];
        }
        
        return options;
    }
    
    OBASSERT_NOT_REACHED("Unknown menu");
    return nil;
}

#pragma mark -
#pragma mark Private

- (NSString *)_fullReleaseString;
{
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    return [NSString stringWithFormat:@"%@ %@ (v%@)", [infoDictionary objectForKey:@"CFBundleName"], [infoDictionary objectForKey:@"CFBundleShortVersionString"], [infoDictionary objectForKey:@"CFBundleVersion"]];
}

@end
