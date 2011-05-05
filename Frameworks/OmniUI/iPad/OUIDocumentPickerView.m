// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentPickerView.h"

RCS_ID("$Id$");

@implementation OUIDocumentPickerView

- (void)dealloc
{
    [_bottomToolbar release];
    [super dealloc];
}

@synthesize bottomToolbar = _bottomToolbar;

@synthesize bottomToolbarHidden = _bottomToolbarHidden;
- (void)setBottomToolbarHidden:(BOOL)bottomToolbarHidden;
{
    [self setBottomToolbarHidden:bottomToolbarHidden animated:NO];
}

- (void)setBottomToolbarHidden:(BOOL)bottomToolbarHidden animated:(BOOL)animated;
{
    if (_bottomToolbarHidden == bottomToolbarHidden)
        return;
    _bottomToolbarHidden = bottomToolbarHidden;
    [self setNeedsLayout];
    
    if (animated) {
        [UIView beginAnimations:nil context:NULL];
        [self layoutIfNeeded];
        [UIView commitAnimations];
    }
}

#pragma mark -
#pragma mark UIView subclass

- (void)layoutSubviews;
{
    OBPRECONDITION(_bottomToolbar);
    
    [super layoutSubviews];
    
    // Show/hide the slider
    CGRect bounds = self.bounds;
    CGRect dummy, toolbarFrame = _bottomToolbar.frame;
    
    CGRectDivide(bounds, &toolbarFrame, &dummy, toolbarFrame.size.height, CGRectMaxYEdge);
    
    if (_bottomToolbarHidden)
        toolbarFrame.origin.y += toolbarFrame.size.height;
    _bottomToolbar.frame = toolbarFrame;
}

@end
