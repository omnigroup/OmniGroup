// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIViewController.h>

typedef NS_OPTIONS(NSUInteger, OUIViewControllerDescendantType) {
    OUIViewControllerDescendantTypeChild = 1 << 0,
    OUIViewControllerDescendantTypePresented = 1 << 1
};

#define OUIViewControllerDescendantTypeNone 0
#define OUIViewControllerDescendantTypeAny (OUIViewControllerDescendantTypeChild | OUIViewControllerDescendantTypePresented)

typedef NS_ENUM(NSUInteger, OUIViewControllerVisibility) {
    OUIViewControllerVisibilityHidden,
    OUIViewControllerVisibilityAppearing,
    OUIViewControllerVisibilityVisible,
    OUIViewControllerVisibilityDisappearing,
};

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (OUIExtensions)

/**
 Checks whether the receiver is a descendant of another UIViewController, either through parent-child containment relationships or presentation relationships. When searching the view controller hierarchy, potential relationships will be checked in the order defined in the OUIViewControllerDescendantType enum.
 
 @param descendantType The kind of relationship(s) to check; the method will only return YES if otherVC can be reached by traversing only relationships of the given type(s)
 @param otherVC The potential parent view controller
 @return YES if otherVC can be reached from the receiver through the given kinds of view controller relationships; NO otherwise
 */
- (BOOL)isDescendant:(OUIViewControllerDescendantType)descendantType ofViewController:(nullable UIViewController *)otherVC;

- (BOOL)isChildViewController:(nullable UIViewController *)child;

@property (readonly, nonatomic, nullable) UIScene *containingScene NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");

/**
 Walks the -[UIViewController parentViewController] chain to find the most distant ancestor view controller.

 @return Returns the first view controller in the -[UIViewController parentViewController] chain whos parent is nil.
 */
- (nullable UIViewController *)mostDistantAncestorViewController;

@property(readonly,nonatomic) OUIViewControllerVisibility visibility;

#if defined(DEBUG)
/// Returns a list of this view controller and all its children recursively, one per line, indented to show hierarchy. Analogous to -[UIView recursiveDescription].
- (NSString *)recursiveDescription;
#endif

/**
 A common practice is for view controllers to dismiss their presented view controller on trait collection change. This method allows presented view controllers to decide for themselves whether they should be dismissed. This is intended to be called by a view controller that may have a presented view controller during willTransitionToTraitCollection:withTransitionCoordinator:. The transitioning view controller will call this on its presentedViewController. Default returns YES;
 
 @return Returns whether the receiver should be dismissed (assuming it is presented) should the application transition to the passed in trait collection
 */
- (BOOL)shouldBeDismissedTransitioningToTraitCollection:(UITraitCollection *)traitCollection;

- (void)expectDeallocationOfControllerTreeSoon;

@end

NS_ASSUME_NONNULL_END
