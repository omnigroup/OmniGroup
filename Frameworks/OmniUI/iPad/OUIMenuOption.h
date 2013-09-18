// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

typedef void (^OUIMenuOptionAction)(void);

@interface OUIMenuOption : NSObject

+ (instancetype)optionWithFirstResponderSelector:(SEL)selector title:(NSString *)title image:(UIImage *)image;

+ (instancetype)optionWithTitle:(NSString *)title image:(UIImage *)image action:(OUIMenuOptionAction)action;
+ (instancetype)optionWithTitle:(NSString *)title action:(OUIMenuOptionAction)action;

- initWithTitle:(NSString *)title image:(UIImage *)image options:(NSArray *)options destructive:(BOOL)destructive action:(OUIMenuOptionAction)action;
- initWithTitle:(NSString *)title image:(UIImage *)image action:(OUIMenuOptionAction)action;

@property(nonatomic, readonly) NSString *title;
@property(nonatomic, readonly) UIImage *image;
@property(nonatomic, readonly) OUIMenuOptionAction action;
@property(nonatomic, readonly) BOOL destructive;
@property(nonatomic, readonly) NSArray *options; // Child options
@property(nonatomic) NSUInteger indentationLevel;

@end
