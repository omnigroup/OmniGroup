// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

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
    OAPassphrasePromptOfferHintText           = 1 << 4,
    OAPassphrasePromptWithoutIcon             = 1 << 5,
    OAPassphrasePromptWithAuxiliaryButton     = 1 << 6,
};

@class OAPassphrasePrompt;

typedef BOOL (^OAPassphrasePromptAcceptActionBlock)(OAPassphrasePrompt *prompt, NSModalResponse action);
typedef BOOL (^OAPassphrasePromptValidationBlock)(OAPassphrasePrompt *prompt, NSModalResponse proposedAction);

@interface OAPassphrasePrompt : NSWindowController

- (id)initWithOptions:(OAPassphrasePromptOptions)options;

// These properties are available for configuring the panel
@property (nonatomic, strong, readonly) NSTextField *titleField;
@property (nonatomic, strong, readonly, nullable) NSImageView *iconView;
@property (nonatomic, strong, readonly, nullable) NSTextField *userLabelField; // In case you want to change it to "Account Name:" or something
@property (nonatomic, strong, readonly) NSTextField *passwordLabelField;
@property (nonatomic, strong, readonly, nullable) NSTextField *confirmPasswordLabelField;

// By default, the panel shows only OK and Cancel.
// Callers can customize the title, key equivalent, and tag of these buttons (the tag becomes the modal response return code: by default NSModalResponseOK and NSModalResponseCancel).
@property (nonatomic, strong, readonly) NSButton *OKButton;
@property (nonatomic, strong, readonly) NSButton *cancelButton;
@property (nonatomic, strong, readonly, nullable) NSButton *auxiliaryButton;  // Only if OAPassphrasePromptWithAuxiliaryButton is set

/// The username or account name entered by the user. Read-write.
@property (nonatomic, copy, nullable) NSString *user;

/// The password entered by the user. May be nil if usingObfuscatedPasswordPlaceholder is YES.
@property (nonatomic, copy, nullable, readonly) NSString *password;

/// Set this to YES to show "*****" in the password field indicating we already have a password (possibly not a password whose value we can directly access). If the user edits the password field, this will change to NO, and you can fetch the user-entered password using the password property.
@property (nonatomic) BOOL usingObfuscatedPasswordPlaceholder;

/// Set this to non-nil to provide password hint text which can be revealed by the user.
@property (nonatomic, copy, nullable) NSString *hint;

@property (nonatomic) NSUInteger minimumPasswordLength;

/// The state of the remember-in-keychain checkbox (or NO if the ShowKeychain option wasn't given).
@property (nonatomic) BOOL rememberInKeychain;

@property (nonatomic, copy, readwrite) OAPassphrasePromptAcceptActionBlock acceptActionBlock;
@property (nonatomic, copy, readwrite) OAPassphrasePromptValidationBlock validationBlock;

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
