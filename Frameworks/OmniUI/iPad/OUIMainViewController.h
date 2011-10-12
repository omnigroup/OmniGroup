// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIViewController.h>

@class UINavigationController;

typedef void (^OUIMainViewControllerGetAnimationRegion)(UIView **outView, CGRect *outRect);

@interface OUIMainViewController : OUIViewController
{
@private
    CGFloat _lastKeyboardHeight;
    UIViewController *_innerViewController;
    BOOL _resizesToAvoidKeyboard;
}

@property(nonatomic,readonly) CGFloat lastKeyboardHeight;

- (void)setToolbarHidden:(BOOL)hidden;
- (void)resetToolbarFromMainViewController;

//- (void)willAnimateToInnerViewController:(UIViewController *)viewController; // Pass nil if you don't know what view controller, just that *some* animation will take place soon
@property(nonatomic,retain) UIViewController *innerViewController;
- (void)setInnerViewController:(UIViewController *)viewController animated:(BOOL)animated
                    fromRegion:(OUIMainViewControllerGetAnimationRegion)fromRegion
                      toRegion:(OUIMainViewControllerGetAnimationRegion)toRegion
              transitionAction:(void (^)(void))transitionAction;
- (void)setInnerViewController:(UIViewController *)viewController animated:(BOOL)animated fromView:(UIView *)fromView toView:(UIView *)toView;

@property(nonatomic,assign) BOOL resizesToAvoidKeyboard;

@end

@interface UIViewController (OUIMainViewControllerExtensions)
- (UIToolbar *)toolbarForMainViewController;
@property(readonly) BOOL isEditingViewController;
@end

extern NSString * const OUIMainViewControllerResizedForKeyboard;
extern NSString * const OUIMainViewControllerResizedForKeyboardVisibilityKey; // user data key; Boolean NSNumber value
extern NSString * const OUIMainViewControllerResizedForKeyboardOriginalUserInfoKey; // user data key; original userInfo dictionary from the keyboard will/did show/hide notification
