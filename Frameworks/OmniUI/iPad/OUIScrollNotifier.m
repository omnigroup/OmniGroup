// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniUI/OUIScrollNotifier.h>

#import <OmniUI/UIView-OUIExtensions.h>

#import <UIKit/UIScrollView.h>

RCS_ID("$Id$");

NSString * const OUIScrollingWillBeginNotification = @"OUIScrollingWillBeginNotification";
NSString * const OUIScrollingDidEndNotification = @"OUIScrollingDidEndNotification";

#if 0 && defined(DEBUG_curt)
    #define DEBUG_SCROLL(format, ...) NSLog(@"SCROLL: " format, ## __VA_ARGS__)
#else
    #define DEBUG_SCROLL(format, ...)
#endif

void _OUIRegisterForScrollNotifications(UIView<OUIScrollNotifierDelegate> *toView, UIScrollView *fromView)
{
    // If an app is using a view that requires scrolling notifications, than make sure the scroll view is being monitored correctly.
    id<UIScrollViewDelegate> delegate = fromView.delegate;
    OBASSERT_NOTNULL(delegate);
    OBASSERT([delegate conformsToProtocol:@protocol(OUIScrollNotifier)]);
    
    DEBUG_SCROLL(@"Registering for notifications for %@-%p, with delegate %@-%p", [fromView class], fromView, [delegate class], delegate);
    [[NSNotificationCenter defaultCenter] addObserver:toView selector:@selector(ancestorScrollViewWillBeginScrolling) name:OUIScrollingWillBeginNotification object:fromView];
    [[NSNotificationCenter defaultCenter] addObserver:toView selector:@selector(ancestorScrollViewDidEndScrolling) name:OUIScrollingDidEndNotification object:fromView];
}

BOOL OUIRegisterForScrollNotificationsAboveView(UIView<OUIScrollNotifierDelegate> *view)
{
    DEBUG_SCROLL(@"%s", __func__);
    
    // Unregister from old notifications
    OUIUnregisterForScrollNotifications(view);

    BOOL foundAnAncestorScrollView = NO;
    UIScrollView *ancestorScrollView = [view.superview enclosingViewOfClass:[UIScrollView class]];
    while (ancestorScrollView) {
        foundAnAncestorScrollView = YES;
        _OUIRegisterForScrollNotifications(view, ancestorScrollView);
        ancestorScrollView = [ancestorScrollView.superview enclosingViewOfClass:[UIScrollView class]];
    }
    
    return foundAnAncestorScrollView;
}

void OUIUnregisterForScrollNotifications(UIView<OUIScrollNotifierDelegate> *view)
{
    DEBUG_SCROLL(@"%s", __func__);
    [[NSNotificationCenter defaultCenter] removeObserver:view name:OUIScrollingWillBeginNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:view name:OUIScrollingDidEndNotification object:nil];
}

void OUIPostScrollingWillBeginNotification(UIScrollView *scrollView)
{
    DEBUG_SCROLL(@"%s", __func__);
    DEBUG_SCROLL(@"Posting notification for %@ %p", [scrollView class], scrollView);
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIScrollingWillBeginNotification object:scrollView];
}

void OUIPostScrollingDidEndNotification(UIScrollView *scrollView)
{
    DEBUG_SCROLL(@"%s", __func__);
    DEBUG_SCROLL(@"Posting notification for %@ %p", [scrollView class], scrollView);
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIScrollingDidEndNotification object:scrollView];
}

