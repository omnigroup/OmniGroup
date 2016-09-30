// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIPasswordAlert-Internal.h>

#import <OmniFoundation/OFVersionNumber.h>

RCS_ID("$Id$");

NSString * const OUIPasswordAlertObfuscatedPasswordPlaceholder = @"********";

@interface OUIPasswordAlert () <UITextFieldDelegate>
{
  @private
    NSString *_username;
    
    struct {
        NSUInteger dismissed:1;
        NSUInteger needsLoginActionStateUpdate:1;
    } _flags;
}

@property (nonatomic, strong) UITextField *usernameTextField;
@property (nonatomic, strong) UITextField *passwordTextField;
@property (nonatomic, strong) UITextField *passwordConfirmationTextField;

@property (nonatomic, weak) UIAlertAction *loginAction;

@end

#pragma mark -

@implementation OUIPasswordAlert

+ (NSMutableSet *)_visibleAlerts;
{
    static NSMutableSet *_alerts = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _alerts = [[NSMutableSet alloc] init];
    });
    return _alerts;
}

- (id)initWithProtectionSpace:(NSURLProtectionSpace *)protectionSpace title:(NSString *)title options:(OUIPasswordAlertOptions)options;
{
    self = [super init];
    if (!self)
        return nil;

    _protectionSpace = [protectionSpace copy];
    _title = [title copy];
    _options = options;

    if ([NSString isEmptyString:_title]) {
        NSString *name = [protectionSpace realm];
        if ([NSString isEmptyString:name]) {
            name = [protectionSpace host];
        }
    
        _title = [name copy];
    }
    
    BOOL showUsername = (_options & OUIPasswordAlertOptionShowUsername) != 0;
    BOOL allowEditingUsername = (_options & OUIPasswordAlertOptionAllowsEditingUsername) != 0;

    _alertController = [UIAlertController alertControllerWithTitle:_title message:self.message preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    
    // Username field
    if (showUsername && allowEditingUsername) {
        [_alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            weakSelf.usernameTextField = textField;
            weakSelf.usernameTextField.placeholder = NSLocalizedStringFromTableInBundle(@"username", @"OmniUI", OMNI_BUNDLE, @"placeholder text - username field of login/password prompt");
        }];
    }
    
    // Password field
    [_alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        [weakSelf configurePasswordTextField:textField forConfirmation:NO];
    }];
    
    // Confirmation field
    if (options & OUIPasswordAlertOptionRequiresPasswordConfirmation) {
        [_alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            [weakSelf configurePasswordTextField:textField forConfirmation:YES];
        }];
    }
    
    // Buttons
    NSString *cancelButtonTitle = NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title - password/passphrase prompt");
    NSString *logInButtonTitle = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"button title - password/passphrase prompt");
    
    // See discussion around dismiss timing in -_didDismissWithAction:.
    [_alertController addAction:[UIAlertAction actionWithTitle:cancelButtonTitle style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self _didDismissWithAction:OUIPasswordAlertActionCancel];
    }]];
    
    self.loginAction = [UIAlertAction actionWithTitle:logInButtonTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self _didDismissWithAction:OUIPasswordAlertActionLogIn];
    }];
    [_alertController addAction:self.loginAction];

    return self;
}

- (void)setTitle:(NSString *)title;
{
    if (_title != title) {
        _title = [title copy];
        self.alertController.title = _title;
    }
}

- (void)setMessage:(NSString *)message;
{
    if (![_message isEqualToString:message]) {
        _message = [message copy];
        if ((_options & OUIPasswordAlertOptionShowUsername) == 0) {
            self.alertController.message = message;
        }
    }
}

@synthesize delegate = _weak_delegate;
@synthesize finished = _finished_callback;

- (NSString *)username;
{
    if (self.usernameTextField == nil)
        return _username;

    return self.usernameTextField.text;
}

- (void)setUsername:(NSString *)username;
{
    BOOL showUsername = (_options & OUIPasswordAlertOptionShowUsername) != 0;
    
    if (showUsername && self.usernameTextField == nil) {
        self.alertController.message = username;
    }

    self.usernameTextField.text = username;
    
    if (_username != username) {
        _username = [username copy];
    }
}

- (NSString *)password;
{
    if ([self isUsingObfuscatedPasswordPlaceholder]) {
        return nil;
    }
    
    BOOL requiresConfirmation = (_options & OUIPasswordAlertOptionRequiresPasswordConfirmation);
    BOOL passwordsMatch = [self.passwordTextField.text isEqualToString:self.passwordConfirmationTextField.text];
    if (requiresConfirmation && !passwordsMatch) {
        return nil;
    }
    
    if ([self.passwordTextField.text length] < self.minimumPasswordLength) {
        return nil;
    }
    
    return self.passwordTextField.text;
}

- (void)setPassword:(NSString *)password;
{
    // Previously we disabled support for the obfuscated password placholder due to:
    //
    //     rdar://problem/14515061 - Programmatically set text for field in secure style UIAlertView isn't drawn
    //     rdar://problem/14517882 - Regression: UITextField in secure mode drops input when delegate changes text value
    //
    // This is fixed on iOS 9.0 and later, so we've removed the workaround (where we specifically passed through nil if password was isEqualToString:OUIPasswordAlertObfuscatedPasswordPlaceholder).

    self.passwordTextField.text = password;
    self.passwordConfirmationTextField.text = password;
    OBPOSTCONDITION([self.password isEqualToString:password]);
}

- (BOOL)isUsingObfuscatedPasswordPlaceholder;
{
    return [self.passwordTextField.text isEqualToString:OUIPasswordAlertObfuscatedPasswordPlaceholder];
}

- (void)showFromController:(UIViewController *)controller;
{
    OBPRECONDITION(self.delegate || _finished_callback); // Otherwise there's no point
    [[OUIPasswordAlert _visibleAlerts] addObject:self]; // we hold a reference to ourselves until -_didDismissWithAction:
    [controller presentViewController:self.alertController animated:YES completion:nil];
}

- (UIColor *)tintColor;
{
    return [[self.alertController view] tintColor];
}

- (void)setTintColor:(UIColor *)tintColor;
{
    [[self.alertController view] setTintColor:tintColor];
}

- (void)setMinimumPasswordLength:(NSUInteger)minimumPasswordLength;
{
    _minimumPasswordLength = minimumPasswordLength;
    
    [self setNeedsLoginActionStateUpdate];
}

#pragma mark Internal

- (BOOL)canLogIn;
{
    // self.password returns nil if the obfuscated placeholder is in place, but that shouldn't prevent a login
    return (self.password != nil) || [self isUsingObfuscatedPasswordPlaceholder];
}

- (BOOL)isDismissed;
{
    return _flags.dismissed;
}

- (void)configurePasswordTextField:(UITextField *)textField forConfirmation:(BOOL)forConfirmation;
{
    NSString *placeholder;
    
    if (forConfirmation) {
        self.passwordConfirmationTextField = textField;
        placeholder = NSLocalizedStringFromTableInBundle(@"confirm", @"OmniUI", OMNI_BUNDLE, @"placeholder text - password/passphrase confirmation field in prompt");
    } else {
        self.passwordTextField = textField;
        placeholder = NSLocalizedStringFromTableInBundle(@"password", @"OmniUI", OMNI_BUNDLE, @"placeholder text - password/passphrase field of login/password prompt");
    }
    
    OBASSERT(textField.delegate == nil);
    textField.delegate = self;
    textField.secureTextEntry = YES;
    textField.placeholder = placeholder;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textFieldTextDidChange:) name:UITextFieldTextDidChangeNotification object:textField];
}

- (void)setNeedsLoginActionStateUpdate;
{
    if (_flags.needsLoginActionStateUpdate) {
        return;
    }
    _flags.needsLoginActionStateUpdate = YES;
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        self.loginAction.enabled = [self canLogIn];
        _flags.needsLoginActionStateUpdate = NO;
    }];
}

- (void)dismissWithAction:(OUIPasswordAlertAction)action;
{
    OBPRECONDITION(![self isDismissed]);
    [self.alertController dismissViewControllerAnimated:YES completion:^{
        [self _didDismissWithAction:action];
    }];
}

#pragma mark -

- (void)textFieldTextDidChange:(NSNotification *)notification;
{
    if (notification.object == self.passwordTextField || notification.object == self.passwordConfirmationTextField) {
        [self setNeedsLoginActionStateUpdate];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField;
{
    OBPRECONDITION(textField == self.passwordTextField || textField == self.passwordConfirmationTextField);

    void (^dismiss)(void) = ^{
        // See discussion around alert dismissal in -_didDismissWithAction:.
        if (![self isDismissed]) {
            [self dismissWithAction:OUIPasswordAlertActionLogIn];
        }
    };
    
    if (_options & OUIPasswordAlertOptionRequiresPasswordConfirmation) {
        if (textField == self.passwordConfirmationTextField && [self canLogIn]) {
            dismiss();
        } else if (textField == self.passwordTextField) {
            [self.passwordConfirmationTextField becomeFirstResponder];
        }
    } else {
        if (textField == self.passwordTextField && [self canLogIn]) {
            dismiss();
        }
    }
    
    return NO;
}

#pragma mark -
#pragma mark Private

- (void)_didDismissWithAction:(OUIPasswordAlertAction)action;
{
    // The dismiss behavior around UIAlertController is a little inconsistent:
    //   * When pressing a button added by a UIAlertAction, the controller will dismiss itself, then call the handler (contradicting the documentation: rdar://problem/17611214)
    //   * When pressing Return in a text field added to the controller, the delegate is responsible for dismissing the controller.
    // Either way, we want this method to get called after the alert controller is already dismissed, but before it is released and gone. Assert that we haven't set our flag yet, and that the alert controller exists but is not being presented.
    
    OBPRECONDITION(!_flags.dismissed);
    OBPRECONDITION(self.alertController != nil);
    OBPRECONDITION([self.alertController presentingViewController] == nil);
    OBASSERT_IF(action == OUIPasswordAlertActionLogIn, [self canLogIn]);
    
    _flags.dismissed = 1;

    if (_finished_callback) {
        _finished_callback(self, action);
        _finished_callback = nil;
    }
    [self.delegate passwordAlert:self didDismissWithAction:action];

    [[OUIPasswordAlert _visibleAlerts] removeObject:self]; // balance the retain in -show
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextFieldTextDidChangeNotification object:nil];
}

@end
