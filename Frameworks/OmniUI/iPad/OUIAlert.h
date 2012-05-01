// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@interface OUIAlert : NSObject

- (id)initWithTitle:(NSString *)title message:(NSString *)message cancelButtonTitle:(NSString *)cancelButtonTitle cancelAction:(void (^)(void))cancelAction;

@property(nonatomic,assign) BOOL shouldCancelWhenApplicationEntersBackground;

- (void)addButtonWithTitle:(NSString *)title action:(void (^)(void))action;

- (void)show;
- (void)cancelAnimated:(BOOL)animated;
- (void)dismissWithClickedButtonIndex:(NSInteger)buttonIndex animated:(BOOL)animated;

@end
