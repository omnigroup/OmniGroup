// Copyright 2010-2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>
#import <OmniUI/OUIWrappingViewController.h>
#import <OmniUI/OUIMenuOption.h>

@class OUIMenuController, OUIMenuOption;

typedef NS_ENUM(NSUInteger, OUIMenuControllerOptionInvocationAction) {
    OUIMenuControllerOptionInvocationActionDismiss,
    OUIMenuControllerOptionInvocationActionReload,
};

@interface OUIMenuController : OUIWrappingViewController

@property(nonatomic,copy) NSArray *topOptions;
@property(nonatomic,copy) void (^didFinish)(void);

@property(nonatomic,copy) UIColor *tintColor;
@property(nonatomic,assign) BOOL sizesToOptionWidth;
@property(nonatomic,assign) NSTextAlignment textAlignment;
@property(nonatomic,assign) BOOL showsDividersBetweenOptions; // Defaults to YES.

@property(nonatomic,assign) OUIMenuControllerOptionInvocationAction optionInvocationAction; // OUIMenuControllerOptionInvocationActionDismiss by default

// Called by OUIMenuOptionsController
- (void)dismissAndInvokeOption:(OUIMenuOption *)option;

@end
