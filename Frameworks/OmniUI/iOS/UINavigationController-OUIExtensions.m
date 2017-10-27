// Copyright 2014-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UINavigationController-OUIExtensions.h>

RCS_ID("$Id$")

@implementation UINavigationController (OUIExtensions)


- (CGRect)visibleRectOfContainedView:(UIView*)view;
{
    if (!view || !self.view) {
        return CGRectZero;
    }
    if (CGRectEqualToRect(self.view.bounds, CGRectZero) || CGRectEqualToRect(view.bounds, CGRectZero)) {
        return CGRectZero;
    }
    OBASSERT(view.window == self.view.window, @"trying to compute visible rect of a view that is not in this navigation controller's window");

    // toplayout guide is only giving height of status bar, so we can't rely on that
    CGPoint topLeft = CGPointZero;
    CGPoint topRight = CGPointZero;
    if (self.navigationBarHidden) {
        CGPoint topLeftInMyCoords = CGPointMake(CGRectGetMinX(self.view.bounds), self.view.bounds.origin.y + self.view.safeAreaInsets.top);
        CGPoint topRightInMyCoords = CGPointMake(CGRectGetMaxX(self.view.bounds), self.view.bounds.origin.y + self.view.safeAreaInsets.top);
        topLeft = [self.view convertPoint:topLeftInMyCoords toView:view];
        topRight = [self.view convertPoint:topRightInMyCoords toView:view];
    } else {
        CGPoint topLeftInNavBarSuperCoords = CGPointMake(CGRectGetMinX(self.navigationBar.frame), CGRectGetMaxY(self.navigationBar.frame));
        CGPoint topRightInNavBarSuperCoords = CGPointMake(CGRectGetMaxX(self.navigationBar.frame), CGRectGetMaxY(self.navigationBar.frame));
        topLeft = [self.navigationBar.superview convertPoint:topLeftInNavBarSuperCoords toView:view];
        topRight = [self.navigationBar.superview convertPoint:topRightInNavBarSuperCoords toView:view];
    }
    
    CGPoint bottomLeft = CGPointZero;
    
    if (self.toolbarHidden) {
        bottomLeft = [self.view convertPoint:CGPointMake(CGRectGetMinX(self.view.bounds), CGRectGetMaxY(self.view.bounds)) toView:view];
    } else {
        CGRect toolbarFrame = self.toolbar.frame;
        bottomLeft.x = [self.view convertPoint:CGPointMake(CGRectGetMinX(self.view.bounds), 0) toView:view].x;
        bottomLeft.y = [self.toolbar.superview convertPoint:CGPointMake(0, CGRectGetMinY(toolbarFrame)) toView:view].y;
    }
    
    CGRect visibleRect = CGRectZero;
    visibleRect.origin = topLeft;
    visibleRect.size.width = topRight.x - topLeft.x;
    visibleRect.size.height = bottomLeft.y - topLeft.y;
    visibleRect = CGRectIntersection(view.bounds, visibleRect);
    if (CGSizeEqualToSize(visibleRect.size, CGSizeZero)) {
        visibleRect = CGRectZero;
    }
    return visibleRect;
}

/// Returns CGSizeZero if not currently in a window
- (CGSize)viewportSize;
{
    // best to punt if we don't have a window
    if (!self.view.window) {
        return CGSizeZero;
    }
    
    // toplayout guide is only giving height of status bar, so we can't rely on that
    CGFloat top = 0;
    CGFloat bottom = 0;
    
    if (self.navigationBarHidden) {
        top = [self.view convertPoint:self.view.bounds.origin toView:nil].y;
    } else {
        CGPoint navBarBottomLeft = CGPointMake(self.navigationBar.bounds.origin.x, CGRectGetMaxY(self.navigationBar.bounds));
        top = [self.navigationBar convertPoint:navBarBottomLeft toView:nil].y;
    }
    
    if (self.toolbarHidden) {
        CGPoint selfBottomLeft = CGPointMake(self.view.bounds.origin.x, CGRectGetMaxY(self.view.bounds));
        bottom = [self.view convertPoint:selfBottomLeft toView:nil].y;
    } else {
        CGRect toolbarRect = [self.toolbar convertRect:self.toolbar.bounds toView:nil];
        bottom = toolbarRect.origin.y;
    }
    
    return CGSizeMake(self.view.bounds.size.width, bottom - top);
}

@end
