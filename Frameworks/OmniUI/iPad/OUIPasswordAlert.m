// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIPasswordAlert.h>

#import <OmniFoundation/OFVersionNumber.h>

RCS_ID("$Id$");

NSString * const OUIPasswordAlertObfuscatedPasswordPlaceholder = @"********";

@interface OUIPasswordAlert () <UITextFieldDelegate> {
  @private
    NSString *_username;
    NSString *_password;
    NSUInteger _options;
    UIAlertController *_alertController;
    
    struct {
        NSUInteger dismissed:1;
    } _flags;
}

@property (nonatomic, strong) UITextField *usernameTextField;
@property (nonatomic, strong) UITextField *passwordTextField;

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

- (id)initWithProtectionSpace:(NSURLProtectionSpace *)protectionSpace title:(NSString *)title options:(NSUInteger)options;
{
    self = [super init];
    if (!self)
        return nil;

    _protectionSpace = [protectionSpace copy];
    _title = [title copy];
    _options = options;

    if ([NSString isEmptyString:_title]) {
        _title = nil;

        NSString *name = [protectionSpace realm];
        if ([NSString isEmptyString:name])
            name = [protectionSpace host];
    
        _title = [name copy];
    }
    
    BOOL showUsername = (_options & OUIPasswordAlertOptionShowUsername) != 0;
    BOOL allowEditingUsername = (_options & OUIPasswordAlertOptionAllowsEditingUsername) != 0;

    _alertController = [UIAlertController alertControllerWithTitle:_title message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    
    // Username field
    if (showUsername && allowEditingUsername) {
        [_alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            weakSelf.usernameTextField = textField;
            weakSelf.usernameTextField.placeholder = NSLocalizedStringFromTableInBundle(@"username", @"OmniUI", OMNI_BUNDLE, @"placeholder text");
        }];
    }
    
    // Password field
    [_alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        weakSelf.passwordTextField = textField;
        OBASSERT(weakSelf.passwordTextField.delegate == nil);
        weakSelf.passwordTextField.delegate = weakSelf;
        weakSelf.passwordTextField.secureTextEntry = YES;
        weakSelf.passwordTextField.placeholder = NSLocalizedStringFromTableInBundle(@"password", @"OmniUI", OMNI_BUNDLE, @"placeholder text");
    }];
    
    // Buttons
    
    NSString *cancelButtonTitle = NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title");
    NSString *logInButtonTitle = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"button title");
    
    // See discussion around dismiss timing in -_didDismissWithAction:.
    [_alertController addAction:[UIAlertAction actionWithTitle:cancelButtonTitle style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self _didDismissWithAction:OUIPasswordAlertActionCancel];
    }]];
    [_alertController addAction:[UIAlertAction actionWithTitle:logInButtonTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self _didDismissWithAction:OUIPasswordAlertActionLogIn];
    }]];

    return self;
}

- (void)setTitle:(NSString *)title;
{
    if (_title != title) {
        _title = [title copy];
        _alertController.title = _title;
    }
}

@synthesize delegate = _weak_delegate;

- (NSString *)username;
{
    if (self.usernameTextField == nil)
        return _username;

    return self.usernameTextField.text;
}

- (void)setUsername:(NSString *)username;
{
    BOOL showUsername = (_options & OUIPasswordAlertOptionShowUsername) != 0;
    
    if (showUsername && self.usernameTextField == nil)
        _alertController.message = username;

    self.usernameTextField.text = username;
    
    if (_username != username) {
        _username = [username copy];
    }
}

- (NSString *)password;
{
    if ([self isUsingObfuscatedPasswordPlaceholder])
        return nil;
    
    return self.passwordTextField.text;
}

- (void)setPassword:(NSString *)password;
{
    // OUIPasswordAlert has support for a placeholder password (to indicate that you've previously typed a value, and simply pressing return will retry that value. If a client sets the password to OUIPasswordAlertObfuscatedPasswordPlaceholder, we display a placeholder, and clear it when the first character is typed.
    //
    // This is currently disabled when running on iOS 7 due to 2 bugs:
    //
    // rdar://problem/14515061 - Programmatically set text for field in secure style UIAlertView isn't drawn
    // rdar://problem/14517882 - Regression: UITextField in secure mode drops input when delegate changes text value
    //
    // The second is more serious, because it drops the first character after you've typed the second, and you probably won't have noticed it did that.
    
    OBFinishPortingLater("Recheck whether the password field needs this hack in iOS 8");

    if ([password isEqualToString:OUIPasswordAlertObfuscatedPasswordPlaceholder]) {
        self.passwordTextField.text = nil;
        return;
    }

    self.passwordTextField.text = password;
}

- (BOOL)isUsingObfuscatedPasswordPlaceholder;
{
    return [self.passwordTextField.text isEqualToString:OUIPasswordAlertObfuscatedPasswordPlaceholder];
}

- (void)showFromController:(UIViewController *)controller;
{
    [[OUIPasswordAlert _visibleAlerts] addObject:self]; // we hold a reference to ourselves until -_didDismissWithAction:
    [controller presentViewController:_alertController animated:YES completion:nil];
}

- (UIColor *)tintColor;
{
    return [[_alertController view] tintColor];
}

- (void)setTintColor:(UIColor *)tintColor;
{
    [[_alertController view] setTintColor:tintColor];
}

#pragma mark -

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
    OBPRECONDITION(textField == self.passwordTextField);

    if ([self isUsingObfuscatedPasswordPlaceholder]) {
        OBASSERT_NOT_REACHED("We shouldn't be taking this code path on iOS 7; see comment in -setPassword:.");
        return YES;
    }
    
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField;
{
    OBPRECONDITION(textField == self.passwordTextField);

    if (textField == self.passwordTextField && ![NSString isEmptyString:self.passwordTextField.text]) {
        
        // See discussion around alert dismissal in -_didDismissWithAction:.
        if (!_flags.dismissed) {
            [_alertController dismissViewControllerAnimated:YES completion:^{
                [self _didDismissWithAction:OUIPasswordAlertActionLogIn];
            }];
        }

        return NO;
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
    OBPRECONDITION(_alertController);
    OBPRECONDITION([_alertController presentingViewController] == nil);
    
    _flags.dismissed = 1;

    [self.delegate passwordAlert:self didDismissWithAction:action];

    [[OUIPasswordAlert _visibleAlerts] removeObject:self]; // balance the retain in -show
}

@end
