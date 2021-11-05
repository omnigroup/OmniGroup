// Copyright 2014-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController+SpecialURLHandling.h>

#import <UIKit/UIAlert.h>

RCS_ID("$Id$");

@interface OUISpecialURLCommand () {
  @private
    UIWindow *_window;
    UIViewController *_viewController;
}

- (UIWindow *)_createTemporaryWindowForAlertPresentation;

@end

#pragma mark -

@implementation OUIAppController (OUISpecialURLHandling)

+ (NSMutableDictionary *)commandClassesBySpecialURLPath;
{
    static NSMutableDictionary *_commandClassesBySpecialURLPath;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _commandClassesBySpecialURLPath = [NSMutableDictionary dictionary];
    });
    return _commandClassesBySpecialURLPath;
}

+ (void)registerCommandClass:(Class)cls forSpecialURLPath:(NSString *)specialURLPath;
{
    OBPRECONDITION([cls isSubclassOfClass:[OUISpecialURLCommand class]]);
    if (![cls isSubclassOfClass:[OUISpecialURLCommand class]]) {
        return;
    }
    
    [[self commandClassesBySpecialURLPath] setObject:cls forKey:specialURLPath];
}

+ (BOOL)invokeSpecialURL:(NSURL *)url senderBundleIdentifier:(NSString *)senderBundleIdentifier confirmingIfNeededWithStyle:(UIAlertControllerStyle)alertStyle fromViewController:(UIViewController *)sourceController NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
{
    OBPRECONDITION(url != nil);
    OBPRECONDITION(sourceController != nil);
    
    Class commandCls = [[OUIAppController commandClassesBySpecialURLPath] objectForKey:[url path]];
    if (commandCls == Nil) {
        return NO;
    }
    
    OUISpecialURLCommand *command = [[commandCls alloc] initWithURL:url senderBundleIdentifier:senderBundleIdentifier];
    if (command == nil) {
        return NO;
    }
    
    if (sourceController == nil) {
        // Perhaps we are early enough in the startup process that we haven't created our main window yeet.
        UIWindow *window = [command _createTemporaryWindowForAlertPresentation];
        if (window == nil || window.rootViewController == nil) {
            return NO;
        }
        
        sourceController = window.rootViewController;
    }
    
    command.viewControllerForPresentation = sourceController;
    
    if ([command skipsConfirmation]) {
        [command invoke];
        return YES;
    }
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:[command confirmationMessage] preferredStyle:alertStyle];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        OUIAppController *controller = [OUIAppController controller];
        controller.shouldPostponeLaunchActions = NO;
    }]];
     
    [alertController addAction:[UIAlertAction actionWithTitle:[command confirmButtonTitle] style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [command invoke];
    }]];
    
    [sourceController presentViewController:alertController animated:YES completion:nil];
    return YES;
}

- (UIViewController *)viewControllerForSpecialURLHandlingPresentation;
{
    UIWindow *window = [[self class] windowForScene:nil options:OUIWindowForSceneOptionsAllowFallbackLookup];
    UIViewController *viewController = window.rootViewController;

    while (viewController.presentedViewController != nil) {
        viewController = viewController.presentedViewController;
    }

    return viewController;
}

- (BOOL)isSpecialURL:(NSURL *)url;
{
    NSString *scheme = [[url scheme] lowercaseString];
    if (![OUIAppController canHandleURLScheme:scheme]) {
        return NO;
    }
    
    NSString *path = [url path];
    if (![[[[self class] commandClassesBySpecialURLPath] allKeys] containsObject:path]) {
        return NO;
    }
    
    return YES;
}

- (BOOL)handleSpecialURL:(NSURL *)url senderBundleIdentifier:(NSString *)senderBundleIdentifier;
{
    return [self handleSpecialURL:url senderBundleIdentifier:senderBundleIdentifier presentingFromViewController:[self viewControllerForSpecialURLHandlingPresentation]];
}

- (BOOL)handleSpecialURL:(NSURL *)url senderBundleIdentifier:(NSString *)senderBundleIdentifier presentingFromViewController:(UIViewController *)controller;
{
    OBPRECONDITION([self isSpecialURL:url]);
    
    return [[self class] invokeSpecialURL:url senderBundleIdentifier:senderBundleIdentifier confirmingIfNeededWithStyle:UIAlertControllerStyleAlert fromViewController:controller];
}

@end

#pragma mark -

@implementation OUISpecialURLCommand

- (id)initWithURL:(NSURL *)url senderBundleIdentifier:(NSString *)senderBundleIdentifier;
{
    if (!(self = [super init])) {
        return nil;
    }
    _url = [url copy];
    _senderBundleIdentifier = [senderBundleIdentifier copy];
    return self;
}

// Must override superclass designated initializers since we declared our own.
- (instancetype)init NS_EXTENSION_UNAVAILABLE_IOS("Special URL handling is not available in extensions");
{
    OBRejectUnusedImplementation(self, _cmd);
    return [self initWithURL:nil senderBundleIdentifier:nil];
}

- (void)dealloc;
{
    _window.hidden = YES;
    _window = nil;

    _viewController = nil;
}

- (NSString *)commandDescription;
{
    return [self.url query];
}

- (BOOL)skipsConfirmation;
{
    return NO;
}

- (NSString *)confirmationMessage;
{
    NSString *messageFormat = NSLocalizedStringFromTableInBundle(@"You have tapped on an Omni special URL:\n\n\"%@\"\n\nRun this command?", @"OmniUI", OMNI_BUNDLE, @"default special URL alert message");
    NSString *message = [NSString stringWithFormat:messageFormat, [self commandDescription]];
    return message;
}

- (NSString *)confirmButtonTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Invoke", @"OmniUI", OMNI_BUNDLE, @"default special URL confirm button title");
}

- (void)invoke;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (UIWindow *)_createTemporaryWindowForAlertPresentation;
{
    _viewController = [[UIViewController alloc] init];
    _viewController.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"OUICrashAlertBackground" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil]];
    
    CGRect screenRect = [[UIScreen mainScreen] bounds];
    _window = [[UIWindow alloc] initWithFrame:screenRect];
    _window.rootViewController = _viewController;
    [_window makeKeyAndVisible];
    
    return _window;
}

@end
