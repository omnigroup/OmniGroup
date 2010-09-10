// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController.h>

#import "OUIAppMenuController.h"
#import "OUIEventBlockingView.h"

#import <OmniUI/OUIDocumentPicker.h>
#import <OmniUI/OUIDocumentProxy.h>
#import <OmniUI/OUIWebViewController.h>
#import <OmniUI/OUIChangePreferencesActionSheet.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <MessageUI/MFMailComposeViewController.h>
#import <OmniFoundation/NSString-OFURLEncoding.h>

#import <SenTestingKit/SenTestSuite.h>

RCS_ID("$Id$");

@interface OUIAppController (/*Private*/)
- (NSString *)_fullReleaseString;
@end

@implementation OUIAppController

BOOL OUIShouldLogPerformanceMetrics;

+ (void)initialize;
{
    OBINITIALIZE;

    OUIShouldLogPerformanceMetrics = [[NSUserDefaults standardUserDefaults] boolForKey:@"LogPerformanceMetrics"];

    if (OUIShouldLogPerformanceMetrics)
        NSLog(@"-[%@ %@]", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
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

- (void)dealloc;
{
    [_documentPicker release];
    [_appMenuBarItem release];;
    [_appMenuController release];
    
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
        _appMenuBarItem = [[UIBarButtonItem alloc] initWithImage:appMenuImage style:UIBarButtonItemStyleBordered target:self action:@selector(showAppMenu:)];
    }
    
    return _appMenuBarItem;
}

- (void)dismissAppMenu;
{
    [_appMenuController dismiss];
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
    if (!_appMenuController)
        _appMenuController = [[OUIAppMenuController alloc] init];

    OBASSERT([sender isKindOfClass:[UIBarButtonItem class]]); // ...or we shouldn't be passing it as the bar item in the next call
    [_appMenuController showMenuFromBarItem:sender];
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

- (void)applicationWillTerminate:(UIApplication *)application;
{
    [[NSUserDefaults standardUserDefaults] synchronize];
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

- (NSString *)documentPickerDocumentTypeForNewFiles:(OUIDocumentPicker *)picker;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (id <OUIDocument>)createNewDocumentAtURL:(NSURL *)url error:(NSError **)outError;
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
