// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@class UINavigationController;

@interface OUIToolbarViewController : UIViewController
{
@private
    UIToolbar *_toolbar;    
    UIView *_contentView;
    
    UIViewController *_innerViewController;
    BOOL _resizesToAvoidKeyboard;
    BOOL _didStartActivityIndicator;
}

@property(nonatomic,readonly) UIToolbar *toolbar;

- (void)willAnimateToInnerViewController:(UIViewController *)viewController; // Pass nil if you don't know what view controller, just that *some* animation will take place soon
@property(nonatomic,retain) UIViewController *innerViewController;
- (void)setInnerViewController:(UIViewController *)viewController animatingFromView:(UIView *)fromView rect:(CGRect)fromViewRect toView:(UIView *)toView rect:(CGRect)toViewRect;
- (void)setInnerViewController:(UIViewController *)viewController animatingView:(UIView *)fromView toView:(UIView *)toView;

@property(nonatomic,assign) BOOL resizesToAvoidKeyboard;

@end

@interface UIViewController (OUIToolbarViewControllerExtensions)
- (UIView *)prepareToResignInnerToolbarControllerAndReturnParentViewForActivityIndicator:(OUIToolbarViewController *)toolbarViewController;
- (void)willResignInnerToolbarController:(OUIToolbarViewController *)toolbarViewController animated:(BOOL)animated;
- (void)didResignInnerToolbarController:(OUIToolbarViewController *)toolbarViewController;
- (void)willBecomeInnerToolbarController:(OUIToolbarViewController *)toolbarViewController animated:(BOOL)animated;
- (void)didBecomeInnerToolbarController:(OUIToolbarViewController *)toolbarViewController;
@property(readonly) BOOL isEditingViewController;
@end

extern NSString * const OUIToolbarViewControllerResizedForKeyboard;
