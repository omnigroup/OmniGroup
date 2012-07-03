// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIEmptyPaddingInspectorSlice.h>

RCS_ID("$Id$")

// Custom view necessary to avoid assertions about not knowing what sort of auto-padding to do.
@interface OUIEmptyPaddingInspectorSliceView : UIView
@end
@implementation OUIEmptyPaddingInspectorSliceView
@end

@implementation OUIEmptyPaddingInspectorSlice

#pragma mark - UIViewController subclass

- (void)loadView;
{
    UIView *view = [[OUIEmptyPaddingInspectorSliceView alloc] initWithFrame:CGRectZero];
    view.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    self.view = view;
    [view release];
}

#pragma mark - OUIInspectorSlice subclass

- (CGFloat)minimumHeightForWidth:(CGFloat)width;
{
    return 0;
}

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    // Show up no matter what
    return YES;
}

@end
