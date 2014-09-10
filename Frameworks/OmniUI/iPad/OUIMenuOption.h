// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

typedef void (^OUIMenuOptionAction)(void);
typedef BOOL (^OUIMenuOptionValidatorAction)(void);

@interface OUIMenuOption : NSObject

+ (instancetype)optionWithFirstResponderSelector:(SEL)selector title:(NSString *)title image:(UIImage *)image;

+ (instancetype)optionWithTitle:(NSString *)title image:(UIImage *)image action:(OUIMenuOptionAction)action;
+ (instancetype)optionWithTitle:(NSString *)title action:(OUIMenuOptionAction)action;
+ (instancetype)optionWithTitle:(NSString *)title action:(OUIMenuOptionAction)action validator:(OUIMenuOptionValidatorAction)validator;

- initWithTitle:(NSString *)title image:(UIImage *)image options:(NSArray *)options destructive:(BOOL)destructive action:(OUIMenuOptionAction)action validator:(OUIMenuOptionValidatorAction)validator;
- initWithTitle:(NSString *)title image:(UIImage *)image options:(NSArray *)options destructive:(BOOL)destructive action:(OUIMenuOptionAction)action;
- initWithTitle:(NSString *)title image:(UIImage *)image action:(OUIMenuOptionAction)action;

@property(nonatomic, readonly) NSString *title;
@property(nonatomic, readonly) UIImage *image;
@property(nonatomic, readonly) OUIMenuOptionAction action;
@property(nonatomic, readonly) OUIMenuOptionValidatorAction validator;
/*!
 @discussion An option is considered enabled if it does not have a validator or if it's validator action returns YES. If a validator action is set, it will be called each time isEnabled is called.
 */
@property (nonatomic, readonly) BOOL isEnabled;
@property(nonatomic, readonly) BOOL destructive;
@property(nonatomic, readonly) NSArray *options; // Child options
@property(nonatomic) NSUInteger indentationLevel;

@end
