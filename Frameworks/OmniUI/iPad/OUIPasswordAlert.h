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

typedef enum {
    OUIPasswordAlertActionCancel,
    OUIPasswordAlertActionLogIn
} OUIPasswordAlertAction;

typedef enum {
    OUIPasswordAlertOptionShowUsername = 0x01,
    OUIPasswordAlertOptionAllowsEditingUsername = 0x02
} OUIPasswordAlertOptions;

// This is the placeholder we use when presenting UI with a previously stored password to obfuscate its length
extern NSString * const OUIPasswordAlertObfuscatedPasswordPlaceholder;

@interface OUIPasswordAlert : NSObject

- (id)init NS_UNAVAILABLE;
- (id)initWithProtectionSpace:(NSURLProtectionSpace *)protectionSpace title:(nullable NSString *)title options:(NSUInteger)options NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) NSURLProtectionSpace *protectionSpace;

@property (nonatomic, weak, nullable) id <OUIPasswordAlertDelegate> delegate;
@property (nonatomic, copy, nullable) void (^finished)(OUIPasswordAlert *, OUIPasswordAlertAction);

@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, copy, nullable) NSString *password;

@property (nonatomic, readonly, getter=isUsingObfuscatedPasswordPlaceholder) BOOL usingObfuscatedPasswordPlaceholder;

@property (nonatomic, strong, null_resettable) UIColor *tintColor;

- (void)showFromController:(UIViewController *)controller;

@end


@protocol OUIPasswordAlertDelegate <NSObject>

- (void)passwordAlert:(OUIPasswordAlert *)passwordAlert didDismissWithAction:(OUIPasswordAlertAction)action;

@end

NS_ASSUME_NONNULL_END
