// Copyright 2010-2014 The Omni Group. All rights reserved.
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
    else if (self.isViewLoaded == NO) {
        return OUIViewControllerVisibilityHidden;
    }
    else {
        return OUIViewControllerVisibilityVisible;
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

@end
