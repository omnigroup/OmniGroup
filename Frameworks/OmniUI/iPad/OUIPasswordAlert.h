// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class OUIPasswordAlertViewController;
@protocol OUIPasswordAlertDelegate;

typedef enum {
    OUIPasswordAlertActionCancel,
    OUIPasswordAlertActionLogIn
} OUIPasswordAlertAction;

enum {
    OUIPasswordAlertOptionShowUsername = 0x01,
    OUIPasswordAlertOptionAllowsEditingUsername = 0x02
} OUIPasswordAlertOptions;

// This is the placeholder we use when presenting UI with a previously stored password to obfuscate its length
extern NSString * const OUIPasswordAlertObfuscatedPasswordPlaceholder;

@interface OUIPasswordAlert : NSObject {
  @protected
    NSString *_title;
    NSString *_username;
    NSURLProtectionSpace *_protectionSpace;
    NSUInteger _options;
    UIAlertView *_alertView;
    id <OUIPasswordAlertDelegate> _delegate;
    OUIPasswordAlertAction _dismissalAction;
}

// Designated initializer
- (id)initWithProtectionSpace:(NSURLProtectionSpace *)protectionSpace title:(NSString *)title options:(NSUInteger)options;

// Properties
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) NSURLProtectionSpace *protectionSpace;

@property (nonatomic, assign) id <OUIPasswordAlertDelegate> delegate;

@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;

@property (nonatomic, readonly, getter=isUsingObfuscatedPasswordPlaceholder) BOOL usingObfuscatedPasswordPlaceholder;

// API
- (void)show;

@end


@protocol OUIPasswordAlertDelegate <NSObject>

- (void)passwordAlert:(OUIPasswordAlert *)passwordAlert didDismissWithAction:(OUIPasswordAlertAction)action;

@end
