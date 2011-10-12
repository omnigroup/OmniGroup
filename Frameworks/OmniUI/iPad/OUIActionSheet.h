// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIActionSheet.h>

extern NSString * const OUIActionSheetDidDismissNotification;

@interface OUIActionSheet : UIActionSheet

@property (nonatomic, readonly) NSString *identifier;

- (id)initWithIdentifier:(NSString *)identifier;

- (void)addButtonWithTitle:(NSString *)buttonTitle forAction:(void(^)(void))action;
- (void)setDestructiveButtonTitle:(NSString *)destructiveButtonTitle andAction:(void(^)(void))action;
- (void)setCancelButtonTitle:(NSString *)cancelButtonTitle andAction:(void(^)(void))action;

@end
