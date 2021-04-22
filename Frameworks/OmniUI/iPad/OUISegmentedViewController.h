// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIViewController.h>
#import <UIKit/UINavigationController.h>

@interface OUISegmentedViewController : UIViewController <UIBarPositioningDelegate>

- (void)oui_invalidate;

@property (nonatomic, copy, nullable) NSArray<UIViewController *> *viewControllers;

@property(nonatomic, assign, nullable) UIViewController *selectedViewController;
@property(nonatomic) NSUInteger selectedIndex;

/*!
 @discussion This is used to set the rightBarButtonItem in the navigationItem. Please do not use the navigation item directly. OUISegmentedViewController owns the titleView and the leftBarButtonItem and will clobber anything you set them to. This is why we provide the rightBarButtonItem property for you to use.
 */
@property (nonatomic, strong, nullable) UIBarButtonItem *leftBarButtonItem;

- (CGFloat)topLayoutLength;
- (void)setShouldShowDismissButton:(BOOL)shouldShow;
- (void)temporarilyHideDismissButton:(BOOL)hide;

// Redeclared from UINavigationControllerDelegate. Subclasses should call super if overriding.
- (void)navigationController:(nonnull UINavigationController *)navigationController willShowViewController:(nonnull UIViewController *)viewController animated:(BOOL)animated NS_REQUIRES_SUPER;

@end

@interface OUISegmentItem : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *title;
@property (nonatomic, strong, readonly, nullable) UIImage *image;

// You must use either -initWithTitle: or -initWithImage:
- (_Null_unspecified instancetype)init NS_UNAVAILABLE;
- (_Nonnull instancetype)initWithTitle:(nonnull NSString *)title NS_DESIGNATED_INITIALIZER;
- (_Nonnull instancetype)initWithImage:(nonnull UIImage *)image NS_DESIGNATED_INITIALIZER;

@end

@interface UIViewController (OUISegmentedViewControllerExtras)

@property (nonatomic, readonly, nullable) OUISegmentedViewController *segmentedViewController;
@property (nonatomic, readonly) BOOL wantsHiddenNavigationBar;

// If this returns YES, the top of the view will be pinned to the bottom of the segmented control.
// Returns NO by default, but YES in UINavigationController.
@property (nonatomic, readonly) BOOL shouldAvoidSegmentedNavigationBar;

@property (nonatomic, readonly, nullable) OUISegmentItem *segmentItem;

@end

@interface UINavigationController (OUISegmentedViewControllerExtras)

@property (nonatomic, readonly, nullable) OUISegmentItem *segmentItem;

@end
