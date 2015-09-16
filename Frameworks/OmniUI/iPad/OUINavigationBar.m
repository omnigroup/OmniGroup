// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
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
            // Here is where we hide our background view so that the accessoryAndBackgroundView which our OUINavigationController will be adding to its view can be the one that shows.  Otherwise, we would see a hairline separator at the bottom of this OUINavigationBar and at the bottom of the (taller, if there is an accessory view) UINavigationBar accessoryAndBackgroundView that will be added beneath us.
            subview.hidden = YES;
        }
    }
}

- (void)setFrame:(CGRect)frame;
{
    if (frame.size.height != self.frame.size.height || frame.origin.y != self.frame.origin.y) {
        [[NSNotificationCenter defaultCenter] postNotificationName:OUINavigationBarHeightChangedNotification object:self];
    }
    [super setFrame:frame];
}

@end
