// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

NS_ASSUME_NONNULL_BEGIN

@class OUIPasswordAlertViewController;
@protocol OUIPasswordAlertDelegate;

typedef NS_ENUM(NSUInteger, OUIPasswordAlertAction) {
    OUIPasswordAlertActionCancel = 0,
    OUIPasswordAlertActionLogIn,
};

typedef NS_OPTIONS(NSUInteger, OUIPasswordAlertOptions) {
    OUIPasswordAlertOptionShowUsername = 1 << 0,
    OUIPasswordAlertOptionAllowsEditingUsername = 1 << 1,
    OUIPasswordAlertOptionRequiresPasswordConfirmation = 1 << 2,
};

// This is the placeholder we use when presenting UI with a previously stored password to obfuscate its length
extern NSString * const OUIPasswordAlertObfuscatedPasswordPlaceholder;

@interface OUIPasswordAlert : NSObject

- (id)init NS_UNAVAILABLE;
- (id)initWithProtectionSpace:(NSURLProtectionSpace *)protectionSpace title:(nullable NSString *)title options:(OUIPasswordAlertOptions)options NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) NSString *title;
@property (nonatomic, copy) NSString *message; // Detail text for the presented alert. Overridden by username if the ShowUsername option is set.
@property (nonatomic, readonly) NSURLProtectionSpace *protectionSpace;

@property (nonatomic, weak, nullable) id <OUIPasswordAlertDelegate> delegate;
@property (nonatomic, copy, nullable) void (^finished)(OUIPasswordAlert *, OUIPasswordAlertAction);

@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, copy, nullable) NSString *password;

@property (nonatomic, readonly, getter=isUsingObfuscatedPasswordPlaceholder) BOOL usingObfuscatedPasswordPlaceholder;
@property (nonatomic, assign) NSUInteger minimumPasswordLength;

@property (nonatomic, strong, null_resettable) UIColor *tintColor;

- (void)showFromController:(UIViewController *)controller;

@end


@protocol OUIPasswordAlertDelegate <NSObject>

- (void)passwordAlert:(OUIPasswordAlert *)passwordAlert didDismissWithAction:(OUIPasswordAlertAction)action;

@end

NS_ASSUME_NONNULL_END
