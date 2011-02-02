// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIGestureRecognizer.h>


@interface OUIRotationGestureRecognizer : UIGestureRecognizer
{
@private
    NSMutableArray *capturedTouches;
    CGFloat likelihood;
    
    NSTimer *longPressTimer;
    NSTimeInterval longPressDuration;
}

@property (nonatomic) NSTimeInterval longPressDuration;  // Seconds after which the drag gesture will begin, even if the touch has not overcome hysteresis

@property (nonatomic) CGFloat rotation;
@property (readonly, nonatomic) CGFloat likelihood;

@end
