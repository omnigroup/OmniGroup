// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

/*
 A scroll notifier is a class that agrees to send notifications when an associated scroll view starts and stops scrolling. This is useful for deep subviews that need to change their display while scrolling. The subview can implement OUIScrollNotifierDelegate and register to receive callbacks for all UIScrollViews above it in the view hierarchy using:
 
        isRegisteredForScrollNotifications = OUIRegisterForScrollNotificationsAboveView(self);
 
 Registration is typically done in the subview's didMoveToSuperview method. The registration function unregisters any old registrations before creating the new ones. If the subview has no superview, then the registration function will still unregister the old registration and will return NO.
 
 For safety, the subview should unregister for callbacks in its dealloc method using:
 
        OUIUnregisterForScrollNotifications(self);
 
 Before this call, the subview may want to OBASSERT(!isRegisteredForScrollNotifications).

 The notifier needs to implement the UIScrollViewDelegate methods that are redundantly specified in the UIScrollNotifier protocol, calling OUIPostScrollingWillBeginNotification or OUIPostScrollingDidEndNotification as necessary. OUIMinimalScrollNotifierImplementation defines, uh, a minimall implementation of OUIScrollNotifier. Use cases where a UIScrollView otherwise needs no delegate can use an instance of that.

 N.B., applications that manually adjust scroll views may need to post notifications from additional places. A typical example is the case where two sibling scroll views are synchronized. Suppose a scrolling gesture on the left-hand view is communicated to the right-hand view so they scroll together. A subview of the right-hand view wouldn't have registered for notifications on the left-hand view. In this case, when the controller for the right-hand view learns that its view needs to scroll, it will have to post the scroll notification.
 
 At this time programmatically calling scrollRectToVisible: (and possibly other such API) does _not_ trigger the delegate callbacks, so the notifications are not effective.
*/

@protocol OUIScrollNotifierDelegate;

void _OUIRegisterForScrollNotifications(UIView<OUIScrollNotifierDelegate> *toView, UIScrollView *fromView);

extern BOOL OUIRegisterForScrollNotificationsAboveView(UIView<OUIScrollNotifierDelegate> *view); 
    // returns YES iff any ancestor scroll views were found for which to register
extern void OUIUnregisterForScrollNotifications(UIView<OUIScrollNotifierDelegate> *view);

extern void OUIPostScrollingWillBeginNotification(UIScrollView *scrollView);
extern void OUIPostScrollingDidEndNotification(UIScrollView *scrollView);

@protocol OUIScrollNotifier <UIScrollViewDelegate,NSObject>
// Except with great contortions, a class must implement UIScrollViewDelegate to successfully act as a scroll notifier. The methods of UIScrollViewDelegate are all optional, but the delegate must implement all of the methods below in order to send the appropriate notifications. So, declaring the methods here acts as a static guard against one of the ways to screw up the implementation.
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView;
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate;
- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView;
- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView;
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;
@end

@protocol OUIScrollNotifierDelegate
- (void)ancestorScrollViewWillBeginScrolling;
- (void)ancestorScrollViewDidEndScrolling;
@end

extern NSString *const OUIScrollingWillBeginNotification;
extern NSString *const OUIScrollingDidEndNotification;
