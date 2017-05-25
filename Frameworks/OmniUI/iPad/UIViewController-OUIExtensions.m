// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIViewController-OUIExtensions.h>

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
    if (self.parentViewController == nil) {
        return self;
    }
    
    return [self.parentViewController mostDistantAncestorViewController];
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

@end
