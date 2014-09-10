// Copyright 2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIAppController+SpecialURLHandling.h>

#import <UIKit/UIAlert.h>

RCS_ID("$Id$");

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

+ (BOOL)invokeSpecialURL:(NSURL *)url confirmingIfNeededWithStyle:(UIAlertControllerStyle)alertStyle fromViewController:(UIViewController *)sourceController;
{
    OBPRECONDITION(url != nil);
    OBPRECONDITION(sourceController != nil);
    
    Class commandCls = [[OUIAppController commandClassesBySpecialURLPath] objectForKey:[url path]];
    if (commandCls == Nil) {
        return NO;
    }
    
    OUISpecialURLCommand *command = [[commandCls alloc] initWithURL:url];
    if (command == nil) {
        return NO;
    }
    
    command.viewControllerForPresentation = sourceController;
    
    if ([command skipsConfirmation]) {
        [command invoke];
        return YES;
    }
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:[command confirmationMessage] preferredStyle:alertStyle];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title") style:UIAlertActionStyleCancel handler:nil]];
    [alertController addAction:[UIAlertAction actionWithTitle:[command confirmButtonTitle] style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [command invoke];
    }]];
    
    [sourceController presentViewController:alertController animated:YES completion:nil];
    return YES;
}

- (UIViewController *)viewControllerForSpecialURLHandlingPresentation;
{
    UIViewController *activeController = self.window.rootViewController;
    while (activeController.presentedViewController != nil)
        activeController = activeController.presentedViewController;
    return activeController;
}

- (BOOL)isSpecialURL:(NSURL *)url;
{
    NSString *scheme = [url scheme];
    if (![OUIAppController canHandleURLScheme:scheme]) {
        return NO;
    }
    
    NSString *path = [url path];
    if (![[[[self class] commandClassesBySpecialURLPath] allKeys] containsObject:path]) {
        return NO;
    }
    
    return YES;
}

- (BOOL)handleSpecialURL:(NSURL *)url;
{
    OBPRECONDITION([self isSpecialURL:url]);
    
    UIViewController *viewControllerForSpecialURLHandlingPresentation = [self viewControllerForSpecialURLHandlingPresentation];
    if (viewControllerForSpecialURLHandlingPresentation == nil)
        return NO;
    
    return [[self class] invokeSpecialURL:url confirmingIfNeededWithStyle:UIAlertControllerStyleAlert fromViewController:viewControllerForSpecialURLHandlingPresentation];
}

@end

@implementation OUISpecialURLCommand

- (id)initWithURL:(NSURL *)url;
{
    if (!(self = [super init])) {
        return nil;
    }
    _url = [url copy];
    return self;
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

@end
