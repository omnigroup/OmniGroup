// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIPasswordAlert.h>

#import <OmniFoundation/OFVersionNumber.h>

RCS_ID("$Id$");

NSString * const OUIPasswordAlertObfuscatedPasswordPlaceholder = @"********";

@interface OUIPasswordAlert () <UITextFieldDelegate>
@end

#pragma mark -

@implementation OUIPasswordAlert
{
    NSString *_username;
    NSString *_password;
    NSUInteger _options;
    UIAlertView *_alertView;
    OUIPasswordAlertAction _dismissalAction;
}

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
    UIAlertViewStyle alertViewStyle = UIAlertViewStyleSecureTextInput;
    
    if (showUsername && allowEditingUsername) {
        alertViewStyle = UIAlertViewStyleLoginAndPasswordInput;
    }
    
    NSString *cancelButtonTitle = NSLocalizedStringFromTableInBundle(@"Cancel", @"OmniUI", OMNI_BUNDLE, @"button title");
    NSString *logInButtonTitle = NSLocalizedStringFromTableInBundle(@"OK", @"OmniUI", OMNI_BUNDLE, @"button title");

    _alertView = [[UIAlertView alloc] initWithTitle:_title message:nil delegate:self cancelButtonTitle:cancelButtonTitle otherButtonTitles:logInButtonTitle, nil];
    _alertView.alertViewStyle = alertViewStyle;
    _alertView.delegate = self;
    
    if (alertViewStyle == UIAlertViewStyleLoginAndPasswordInput) {
        self.usernameTextField.placeholder = NSLocalizedStringFromTableInBundle(@"username", @"OmniUI", OMNI_BUNDLE, @"placeholder text");
        self.passwordTextField.placeholder = NSLocalizedStringFromTableInBundle(@"password", @"OmniUI", OMNI_BUNDLE, @"placeholder text");
    } else {
        self.passwordTextField.placeholder = NSLocalizedStringFromTableInBundle(@"password", @"OmniUI", OMNI_BUNDLE, @"placeholder text");
    }

    OBASSERT(self.passwordTextField.delegate == nil);
    if (self.passwordTextField.delegate == nil) {
        self.passwordTextField.delegate = self;
    }

    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_alertView setDelegate:nil];
}

- (void)setTitle:(NSString *)title;
{
    if (_title != title) {
        _title = [title copy];
        _alertView.title = _title;
    }
}

@synthesize delegate = _weak_delegate;

- (NSString *)username;
{
    if (_alertView.alertViewStyle == UIAlertViewStyleSecureTextInput)
        return _username;

    return self.usernameTextField.text;
}

- (void)setUsername:(NSString *)username;
{
    BOOL showUsername = (_options & OUIPasswordAlertOptionShowUsername) != 0;
    
    if (showUsername && _alertView.alertViewStyle == UIAlertViewStyleSecureTextInput)
        _alertView.message = username;

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
    
    if ([password isEqualToString:OUIPasswordAlertObfuscatedPasswordPlaceholder] && [OFVersionNumber isOperatingSystemiOS7OrLater]) {
        self.passwordTextField.text = nil;
        return;
    }

    self.passwordTextField.text = password;
}

- (BOOL)isUsingObfuscatedPasswordPlaceholder;
{
    return [self.passwordTextField.text isEqualToString:OUIPasswordAlertObfuscatedPasswordPlaceholder];
}

- (UITextField *)usernameTextField
{
    if (_alertView.alertViewStyle == UIAlertViewStyleLoginAndPasswordInput) 
        return [_alertView textFieldAtIndex:0];

    return nil;
}

- (UITextField *)passwordTextField
{
    if (_alertView.alertViewStyle == UIAlertViewStyleLoginAndPasswordInput) 
        return [_alertView textFieldAtIndex:1];

    return [_alertView textFieldAtIndex:0];
}

- (void)show;
{
    [[OUIPasswordAlert _visibleAlerts] addObject:self]; // we hold a reference to ourselves until -_dismissWithAction
    [_alertView show];
}   

#pragma mark -

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex;
{
    OUIPasswordAlertAction action = [_alertView cancelButtonIndex] == buttonIndex ? OUIPasswordAlertActionCancel : OUIPasswordAlertActionLogIn;
    [self _dismissWithAction:action];
}

- (BOOL)alertViewShouldEnableFirstOtherButton:(UIAlertView *)alertView;
{
    BOOL hasPassword = [self isUsingObfuscatedPasswordPlaceholder] || [self.password length] > 0;
    
    if (alertView.alertViewStyle == UIAlertViewStyleSecureTextInput) {
        return hasPassword;
    } else if (alertView.alertViewStyle == UIAlertViewStyleLoginAndPasswordInput) {
        return [self.username length] > 0 && hasPassword;
    }
    
    return YES;
}

#pragma mark -

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
{
    OBPRECONDITION(textField == self.passwordTextField);

    if ([self isUsingObfuscatedPasswordPlaceholder]) {
        if ([OFVersionNumber isOperatingSystemiOS7OrLater]) {
            OBASSERT_NOT_REACHED("We shouldn't be taking this code path on iOS 7; see comment in -setPassword:.");
            return YES;
        }
        
        textField.text = string;
        return NO;
    }
    
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField;
{
    OBPRECONDITION(textField == self.passwordTextField);

    if (textField == self.passwordTextField && ![NSString isEmptyString:self.passwordTextField.text]) {
        [_alertView dismissWithClickedButtonIndex:1 animated:YES];
        return NO;
    }
    
    return NO;
}

#pragma mark -
#pragma mark Private

- (void)_dismissWithAction:(OUIPasswordAlertAction)action;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];

    _dismissalAction = action;
    [self.delegate passwordAlert:self didDismissWithAction:action];

    [[OUIPasswordAlert _visibleAlerts] removeObject:self]; // balance the retain in -show
}

- (void)_applicationDidEnterBackground:(NSNotification *)notification;
{
#define DISMISS_ON_ENTER_BACKGROUND 0

#if DISMISS_ON_ENTER_BACKGROUND
    [self dismissWithAction:PasswordAlertActionCancel];
#endif    
}

@end



