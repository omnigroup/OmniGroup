// Copyright 2010-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

NS_ASSUME_NONNULL_BEGIN

@protocol OUIPasswordAlertDelegate;

typedef NS_ENUM(NSUInteger, OUIPasswordAlertAction) {
    OUIPasswordAlertActionCancel = 0,
    OUIPasswordAlertActionLogIn,
    OUIPasswordAlertActionHelp,
};

typedef NS_OPTIONS(NSUInteger, OUIPasswordAlertOptions) {
    OUIPasswordAlertOptionShowUsername = 1 << 0,
    OUIPasswordAlertOptionAllowsEditingUsername = 1 << 1,
    OUIPasswordAlertOptionRequiresPasswordConfirmation = 1 << 2,
    OUIPasswordAlertOptionSuppressPasswordAutofill = 1 << 3, // attempt to disable iOS 12-style password autofill & strong password suggestion
};

// This is the placeholder we use when presenting UI with a previously stored password to obfuscate its length
extern NSString * const OUIPasswordAlertObfuscatedPasswordPlaceholder;

@interface OUIPasswordAlert : NSObject

- (id)init NS_UNAVAILABLE;
- (id)initWithTitle:(nullable NSString *)title options:(OUIPasswordAlertOptions)options;
- (id)initWithProtectionSpace:(nullable NSURLProtectionSpace *)protectionSpace title:(nullable NSString *)title options:(OUIPasswordAlertOptions)options NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) NSString *title;
@property (nonatomic, copy) NSString *message; // Detail text for the presented alert. Overridden by username if the ShowUsername option is set.
@property (nonatomic, readonly, nullable) NSURLProtectionSpace *protectionSpace; // Completely unused by this class, but used by the OUIOnePasswordAlert subclass.

@property (nonatomic, weak, nullable) id <OUIPasswordAlertDelegate> delegate;
@property (nonatomic, copy, nullable) void (^finished)(OUIPasswordAlert *, OUIPasswordAlertAction);

@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, copy, nullable) NSString *password;

// Shown in addition to the username or message. A newline is added between the preceding string and the error message.
@property (nonatomic, copy, nullable) NSString *errorMessage;

@property (nonatomic, readonly, getter=isUsingObfuscatedPasswordPlaceholder) BOOL usingObfuscatedPasswordPlaceholder;
@property (nonatomic, assign) NSUInteger minimumPasswordLength;

@property (nonatomic, strong, null_resettable) UIColor *tintColor;

@property (nonatomic, copy, nullable) NSURL *helpURL NS_EXTENSION_UNAVAILABLE_IOS("Cannot open help in a browser from app extensions");

- (void)showFromController:(UIViewController *)controller;
- (void)enqueuePasswordAlertPresentationForAnyForegroundScene NS_SWIFT_NAME(enqueuePasswordAlertPresentationForForegroundScene());

@end


@protocol OUIPasswordAlertDelegate <NSObject>

- (void)passwordAlert:(OUIPasswordAlert *)passwordAlert didDismissWithAction:(OUIPasswordAlertAction)action;

@end

NS_ASSUME_NONNULL_END
