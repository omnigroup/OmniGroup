// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIViewController-OUIExtensions.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OmniUI-Swift.h>

#if defined(DEBUG)
#import <OmniFoundation/NSString-OFExtensions.h>
#endif

RCS_ID("$Id$");

@implementation UIViewController (OUIExtensions)

- (BOOL)isDescendant:(OUIViewControllerDescendantType)descendantType ofViewController:(UIViewController *)otherVC;
{
    if ([self isEqual:otherVC])
        return YES;
    
    if (descendantType & OUIViewControllerDescendantTypeChild) {
        if ([self.parentViewController isDescendant:descendantType ofViewController:otherVC])
            return YES;
    }
    
    if (descendantType & OUIViewControllerDescendantTypePresented) {
        if ([self.presentingViewController isDescendant:descendantType ofViewController:otherVC])
            return YES;
    }
    
    return NO;
}

- (UIViewController *)mostDistantAncestorViewController {
    UIViewController *parentViewController = self.parentViewController;
    if (parentViewController == nil) {
        return self;
    }
    
    return [parentViewController mostDistantAncestorViewController];
}

- (BOOL)isChildViewController:(UIViewController *)child;
{
    return [self.childViewControllers indexOfObjectIdenticalTo:child] != NSNotFound;
}

- (OUIViewControllerVisibility)visibility;
{
    if (self.isBeingPresented || self.isMovingToParentViewController) {
        return OUIViewControllerVisibilityAppearing;
    }
    else if (self.isBeingDismissed || self.isMovingFromParentViewController) {
        return OUIViewControllerVisibilityDisappearing;
    }
    else if (self.isViewLoaded == YES && self.view.window != nil) {
        return OUIViewControllerVisibilityVisible;
    }
    else {
        return OUIViewControllerVisibilityHidden;
    }
}

#if defined(DEBUG)
- (NSString *)recursiveDescription;
{
    return [self _recursiveDescriptionAtDepth:0];
}

- (NSString *)_recursiveDescriptionAtDepth:(NSUInteger)depth;
{
    NSString *selfDescription = [[NSString spacesOfLength:depth * 4] stringByAppendingString:[self debugDescription]];
    NSArray *childDescriptions = [self.childViewControllers arrayByPerformingBlock:^id(UIViewController *childViewController) {
        return [childViewController _recursiveDescriptionAtDepth:(depth + 1)];
    }];
    return [[@[selfDescription] arrayByAddingObjectsFromArray:childDescriptions] componentsJoinedByString:@"\n"];
}
#endif

- (void)expectDeallocationOfControllerTreeSoon;
{
    if (OBExpectedDeallocationsIsEnabled()) {
        OBExpectDeallocationWithPossibleFailureReason(self, ^NSString *(UIViewController *vc){
            if (vc.parentViewController)
                return @"still has parent view controller";
            return nil;
        });
        for (UIViewController *vc in self.childViewControllers) {
            [vc expectDeallocationOfControllerTreeSoon];
        }
    }
}

- (BOOL)shouldBeDismissedTransitioningToTraitCollection:(UITraitCollection *)traitCollection;
{
    if ([self isKindOfClass:[UIAlertController class]]) {
        return NO;
    }
    return YES;
}

- (UIScene *)_containingSceneAllowingCheckPresentedController:(BOOL)canCheckPresentedController NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    // If the view's in the view hierarchy, it'll have a scene
    if ([self isViewLoaded]) {
        UIScene *scene = self.view.containingScene;
        if (scene != nil) {
            return scene;
        }
    }
    
    // If it's not in the hierarchy, we may have an ancestor who is about to add us as a a child, and they may have a containing scene
    UIViewController *parent = self.parentViewController;
    if (parent != nil) {
        UIScene *scene = parent.containingScene;
        if (scene != nil) {
            return scene;
        }
    }

    // We may have a presenting view controller that can resolve a scene. When it is checking for its containing scene, do not allow it to try to check us (its presented view controller) for our containing scene. Otherwise, we can ping-pong back and forth asking each other for our containing scenes forever.
    UIScene *presentingContainingScene = [self.presentingViewController _containingSceneAllowingCheckPresentedController:NO];
    if (presentingContainingScene != nil) {
        return presentingContainingScene;
    }
    
    if (canCheckPresentedController) {
        // We may have a presented view controller that can resolve a scene
        UIScene *presentedViewControllerContainingScene = self.presentedViewController.containingScene;
        if (presentedViewControllerContainingScene != nil) {
            return presentedViewControllerContainingScene;
        }
    }
    
    // If we're in a compact multipane controller and we're in an off-screen pane, we're not in a view hierarchy at all, but we're still contained within a specific scene.
    UIViewController *mostDistantAncestor = self.mostDistantAncestorViewController;
    OBASSERT(!mostDistantAncestor.isVisible || ![mostDistantAncestor isKindOfClass:[OUIMultipanePresentationWrapperViewController class]], "If we're within in a visible presentation wrapper, we should be presented and able to find our containing scene with an earlier check.");
    
    // Search the connected scenes for one where a compact multipane controller contains us within one of its panes.
    return [[OUIAppController sharedController] mostRecentlyActiveSceneSatisfyingCondition:^BOOL(UIScene * scene) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindow *window = [OUIAppController windowForScene:scene options:OUIWindowForSceneOptionsNone];
            OUIMultiPaneController *controller = [[window rootViewController] _descendantMultiPaneController];
            if (controller == nil) {
                return NO;
            }
            
            for (OUIMultiPane *pane in controller.orderedPanes) {
                if (pane.viewController == mostDistantAncestor) {
                    return YES;
                }
            }
            return NO;
        } else {
            return NO;
        }
    }];
}

- (UIScene *)containingScene NS_EXTENSION_UNAVAILABLE_IOS("Use view controller based solutions where available instead.");
{
    return [self _containingSceneAllowingCheckPresentedController:YES];
}

- (OUIMultiPaneController *)_descendantMultiPaneController
{
    if ([self isKindOfClass:[OUIMultiPaneController class]]) {
        return (OUIMultiPaneController *)self;
    }
    
    for (UIViewController *child in self.childViewControllers) {
        OUIMultiPaneController *controller = [child _descendantMultiPaneController];
        if (controller != nil) {
            return controller;
        }
    }
    
    return nil;
}

@end
