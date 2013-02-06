// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIPasswordAlert.h>

RCS_ID("$Id$");

NSString * const OUIPasswordAlertObfuscatedPasswordPlaceholder = @"********";

@interface OUIPasswordAlert () <UITextFieldDelegate>

- (void)_dismissWithAction:(OUIPasswordAlertAction)action;
- (void)_applicationDidEnterBackground:(NSNotification *)notification;

@end

#pragma mark -

@implementation OUIPasswordAlert

- (id)initWithProtectionSpace:(NSURLProtectionSpace *)protectionSpace title:(NSString *)title options:(NSUInteger)options;
{
    self = [super init];
    if (!self)
        return nil;

    _protectionSpace = [protectionSpace copy];
    _title = [title copy];
    _options = options;

    if ([NSString isEmptyString:_title]) {
        [_title release];
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

    [_title release];
    [_username release];
    [_protectionSpace release];
    
    [_alertView setDelegate:nil];
    [_alertView release];
    
    [super dealloc];
}

- (NSString *)title;
{
    return _title;
}

- (void)setTitle:(NSString *)title;
{
    if (_title != title) {
        [_title release];
        _title = [title copy];
        _alertView.title = _title;
    }
}

@synthesize protectionSpace = _protectionSpace;
@synthesize delegate = _delegate;

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
        [_username release];
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
    [self retain]; // we hold a reference to ourselves until -_dismissWithAction
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

    [self autorelease]; // balance -retain in -show
}

- (void)_applicationDidEnterBackground:(NSNotification *)notification;
{
#define DISMISS_ON_ENTER_BACKGROUND 0

#if DISMISS_ON_ENTER_BACKGROUND
    [self dismissWithAction:PasswordAlertActionCancel];
#endif    
}

@end



