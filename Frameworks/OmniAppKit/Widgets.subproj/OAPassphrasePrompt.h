// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSApplication.h>
#import <AppKit/NSImageView.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSWindowController.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, OAPassphrasePromptOptions) {
    OAPassphrasePromptShowUserField           = 1 << 0,
    OAPassphrasePromptEditableUserField       = 1 << 1,
    OAPassphrasePromptConfirmPassword         = 1 << 2,
    OAPassphrasePromptShowKeychainOption      = 1 << 3,
};


@interface OAPassphrasePrompt : NSWindowController

- (id)initWithOptions:(OAPassphrasePromptOptions)options;

// These properties are available for configuring the panel
@property (nonatomic, strong, readonly) NSTextField *titleField;
@property (nonatomic, strong, readonly) NSImageView *iconView;
@property (nonatomic, strong, readonly) NSTextField *userLabelField; // In case you want to change it to "Account Name:" or something

/// The username or account name entered by the user. Read-write.
@property (nonatomic, copy, nullable) NSString *user;

/// The password entered by the user. May be nil if usingObfuscatedPasswordPlaceholder is YES.
@property (nonatomic, copy, nullable, readonly) NSString *password;

/// Set this to YES to show "*****" in the password field indicating we already have a password (possibly not a password whose value we can directly access). If the user edits the password field, this will change to NO, and you can fetch the user-entered password using the password property.
@property (nonatomic) BOOL usingObfuscatedPasswordPlaceholder;

// @property (nonatomic, copy, nullable) NSString *hint;  // TODO

@property (nonatomic) NSUInteger minimumPasswordLength;

// The state of the remember-in-keychain checkbox (or NO if the ShowKeychain option wasn't given).
@property (nonatomic) BOOL rememberInKeychain;

/// An error message to display, or nil to hide the error-text field.
- (void)setErrorMessage:(NSString * __nullable )errorMessage;

- (NSModalResponse)runModal;
- (void)beginSheetModalForWindow:(NSWindow *)parentWindow completionHandler:(void (^)(NSModalResponse returnCode))handler;

// Override points for subclasses

/// Called before the window is shown
- (void)willShow;

/// After any user change, this is called to determine whether the OK button should be enabled
- (BOOL)isValid;

/// This is called when OK or Cancel is clicked; subclasses should call super, or to ignore the click, don't call super
- (void)endModal:(NSModalResponse)rc;

@end

NS_ASSUME_NONNULL_END
