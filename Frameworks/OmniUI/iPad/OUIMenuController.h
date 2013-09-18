// Copyright 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>
#import <OmniUI/OUIMenuOption.h>

@class OUIMenuController, OUIMenuOption;

typedef NS_ENUM(NSUInteger, OUIMenuControllerOptionInvocationAction) {
    OUIMenuControllerOptionInvocationActionDismiss,
    OUIMenuControllerOptionInvocationActionReload,
};

@protocol OUIMenuControllerDelegate <NSObject>
- (NSArray *)menuControllerOptions:(OUIMenuController *)menu;
@end

@interface OUIMenuController : NSObject

+ (void)showPromptFromSender:(id)sender title:(NSString *)title destructive:(BOOL)destructive action:(OUIMenuOptionAction)action;
+ (void)showPromptFromSender:(id)sender title:(NSString *)title tintColor:(UIColor *)tintColor action:(OUIMenuOptionAction)action;

- initWithDelegate:(id <OUIMenuControllerDelegate>)delegate;
- initWithOptions:(NSArray *)options;

@property(nonatomic,copy) void (^didFinish)(void);

@property(nonatomic,retain) UIColor *tintColor;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,assign) BOOL sizesToOptionWidth;
@property(nonatomic,assign) NSTextAlignment textAlignment;
@property(nonatomic,assign) BOOL showsDividersBetweenOptions; // Defaults to YES.
@property(nonatomic,assign) BOOL padTopAndBottom; // Adds some padding before the first option and after the last option to make the spacing look the same as the spacing between options.

@property(nonatomic,assign) OUIMenuControllerOptionInvocationAction optionInvocationAction; // OUIMenuControllerOptionInvocationActionDismiss by default

// Valid sender classes are UIBarButtonItem and UIView.
- (void)showMenuFromSender:(id)sender;
- (void)dismissMenuAnimated:(BOOL)animated;

@property(nonatomic,readonly) BOOL visible;

// Called by OUIMenuOptionsController
- (void)didInvokeOption:(OUIMenuOption *)option;

@end
