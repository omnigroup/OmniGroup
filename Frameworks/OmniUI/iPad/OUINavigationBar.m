// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUINavigationBar.h>

RCS_ID("$Id$")

NSString *OUINavigationBarHeightChangedNotification = @"OUINavigationBarHeightChangedNotification";

@implementation OUINavigationBar

- (void)layoutSubviews;
{
    [super layoutSubviews];
    
    for (UIView *subview in [self subviews]) {
        CGRect subviewFrame = subview.frame;
        if (CGRectGetHeight(subviewFrame) >= 39.0) {
            // background view that resizes to our whole height, hidden so our new nav bar view shows instead
            subview.hidden = YES;
        }
    }
}

- (void)setFrame:(CGRect)frame;
{
    [super setFrame:frame];
    [[NSNotificationCenter defaultCenter] postNotificationName:OUINavigationBarHeightChangedNotification object:self];
}

- (void)setCenter:(CGPoint)center;
{
    [super setCenter:center];
    [[NSNotificationCenter defaultCenter] postNotificationName:OUINavigationBarHeightChangedNotification object:self];
}

@end
