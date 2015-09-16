// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

typedef NS_OPTIONS(NSUInteger, OUIViewControllerDescendantType) {
    OUIViewControllerDescendantTypeChild = 1 << 0,
    OUIViewControllerDescendantTypePresented = 1 << 1
};

#define OUIViewControllerDescendantTypeNone 0
#define OUIViewControllerDescendantTypeAny (OUIViewControllerDescendantTypeChild | OUIViewControllerDescendantTypePresented)

typedef enum {
    OUIViewControllerVisibilityHidden,
    OUIViewControllerVisibilityAppearing,
    OUIViewControllerVisibilityVisible,
    OUIViewControllerVisibilityDisappearing,
} OUIViewControllerVisibility;

@interface UIViewController (OUIExtensions)

/**
 Checks whether the receiver is a descendant of another UIViewController, either through parent-child containment relationships or presentation relationships. When searching the view controller hierarchy, potential relationships will be checked in the order defined in the OUIViewControllerDescendantType enum.
 
 @param descendantType The kind of relationship(s) to check; the method will only return YES if otherVC can be reached by traversing only relationships of the given type(s)
 @param otherVC The potential parent view controller
 @return YES if otherVC can be reached from the receiver through the given kinds of view controller relationships; NO otherwise
 */
- (BOOL)isDescendant:(OUIViewControllerDescendantType)descendantType ofViewController:(UIViewController *)otherVC;

- (BOOL)isChildViewController:(UIViewController *)child;

@property(readonly,nonatomic) OUIViewControllerVisibility visibility;

#if defined(DEBUG)
/// Returns a list of this view controller and all its children recursively, one per line, indented to show hierarchy. Analogous to -[UIView recursiveDescription].
- (NSString *)recursiveDescription;
#endif

#ifdef DEBUG
- (void)expectDeallocationOfControllerTreeSoon;
#endif

@end
