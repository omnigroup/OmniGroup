// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class OUIMenuOption;

// If a menu option wants to present a new view controller of its own, it will likely want to know where the menu was presented from. But, by the time the action is invoked, the menu itself will have been dismissed.
typedef void (^OUIMenuOptionAction)(OUIMenuOption *option, UIViewController *presentingViewController);
typedef BOOL (^OUIMenuOptionValidatorAction)(OUIMenuOption *option);

@interface OUIMenuOption : NSObject

+ (instancetype)optionWithFirstResponderSelector:(SEL)selector title:(NSString *)title image:(nullable UIImage *)image;

+ (instancetype)optionWithTitle:(NSString *)title image:(nullable UIImage *)image action:(nullable OUIMenuOptionAction)action;
+ (instancetype)optionWithTitle:(NSString *)title action:(nullable OUIMenuOptionAction)action;
+ (instancetype)optionWithTitle:(NSString *)title action:(nullable OUIMenuOptionAction)action validator:(nullable OUIMenuOptionValidatorAction)validator;

+ (instancetype)separator;
+ (instancetype)separatorWithTitle:(NSString *)title;

- initWithTitle:(NSString *)title image:(nullable UIImage *)image options:(nullable NSArray <OUIMenuOption *> *)options destructive:(BOOL)destructive action:(nullable OUIMenuOptionAction)action validator:(nullable OUIMenuOptionValidatorAction)validator;
- initWithTitle:(NSString *)title image:(nullable UIImage *)image options:(nullable NSArray <OUIMenuOption *> *)options destructive:(BOOL)destructive action:(nullable OUIMenuOptionAction)action;
- initWithTitle:(NSString *)title image:(nullable UIImage *)image action:(nullable OUIMenuOptionAction)action;

@property(nonatomic, readonly, getter=isSeparator) BOOL separator;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, strong, nullable) UIImage *image;
@property(nonatomic, readonly, nullable) OUIMenuOptionAction action;
@property(nonatomic, readonly, nullable) OUIMenuOptionValidatorAction validator;
@property(nonatomic, strong) UIView *attentionDotView;

/*!
 @discussion An option is considered enabled if it does not have a validator or if it's validator action returns YES. If a validator action is set, it will be called each time isEnabled is called.
 */
@property (nonatomic, readonly) BOOL isEnabled;
@property(nonatomic) BOOL destructive;
@property(nonatomic, readonly, nullable) NSArray <OUIMenuOption *> *options; // Child options
@property(nonatomic) NSUInteger indentationLevel;

@end

NS_ASSUME_NONNULL_END
