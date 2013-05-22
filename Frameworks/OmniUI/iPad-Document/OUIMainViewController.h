// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIViewController.h>

@class UINavigationController;

typedef UIView *(^OUIMainViewControllerGetAnimationRegion)(CGRect *outRect);

@interface OUIMainViewController : OUIViewController

@property(nonatomic,readonly) CGFloat lastKeyboardHeight;

- (void)setToolbarHidden:(BOOL)hidden;
- (void)resetToolbarFromMainViewController;

//- (void)willAnimateToInnerViewController:(UIViewController *)viewController; // Pass nil if you don't know what view controller, just that *some* animation will take place soon
@property(nonatomic,retain) UIViewController *innerViewController;
- (void)setInnerViewController:(UIViewController *)viewController animated:(BOOL)animated
                    fromRegion:(OUIMainViewControllerGetAnimationRegion)fromRegion
                      toRegion:(OUIMainViewControllerGetAnimationRegion)toRegion
              transitionAction:(void (^)(void))transitionAction
              completionAction:(void (^)(void))completionAction;
- (void)setInnerViewController:(UIViewController *)viewController animated:(BOOL)animated fromView:(UIView *)fromView toView:(UIView *)toView;

@property(nonatomic,assign) BOOL resizesToAvoidKeyboard;

// Maintains a local counter and disables interaction on just this view controller's view and subviews (not the whole app)
- (void)beginIgnoringInteractionEvents;
- (void)endIgnoringInteractionEvents;

@end

@interface UIViewController (OUIMainViewControllerExtensions)
@property(readonly) UIToolbar *toolbarForMainViewController;
@property(readonly) BOOL isEditingViewController;
@property(readonly) UIColor *activityIndicatorColorForMainViewController;
@end

// This is posted after the main view controller resizes itself to avoid the keyboard. If you want to match the animation of the keyboard (assuming the software keyboard is on) you should ensure your view is marked as needing display or otherwise sets up animation in its handling of this notification. NOTE: If a hardware keyboard is being used, it sends no show/hide/resize animation when a text input client becomes or resigns first responder. So, you cannot depend on these being sent as your signal for any editing starting/ending.
extern NSString * const OUIMainViewControllerDidBeginResizingForKeyboard;

// This is posted after the keyboard resizing animation is finished. See the note above about hardware keyboards.
extern NSString * const OUIMainViewControllerDidFinishResizingForKeyboard;

// The original user data key from the keyboard will/did change frame notification. This can be used to get the animation duration/curve (though in the default case, OUIMainViewController will already have set up an animation context with the proper values applied).
extern NSString * const OUIMainViewControllerResizedForKeyboardOriginalUserInfoKey;
