// Copyright 2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIMinimalScrollNotifierImplementation.h>

RCS_ID("$Id$");

@implementation OUIMinimalScrollNotifierImplementation

#pragma mark -
#pragma mark UIScrollViewDelegate
#pragma mark OUIScrollNotifier

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView;
{
    OUIPostScrollingWillBeginNotification(scrollView);
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate;
{
    if (!decelerate)
        OUIPostScrollingDidEndNotification(scrollView);
}

- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView;
{
    OUIPostScrollingWillBeginNotification(scrollView); // only post if returning YES
    return YES;
}

- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView;
{
    OUIPostScrollingDidEndNotification(scrollView);
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;
{
    OUIPostScrollingDidEndNotification(scrollView);
}

@end
