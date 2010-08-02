// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIGestureRecognizerSubclass.h>


@interface OUILongPressGestureRecognizer : UILongPressGestureRecognizer
{
@private
    CGFloat hysteresisDistance;
    BOOL overcameHysteresis;
    
    CGPoint firstTouchPoint;
    CGPoint lastTouchPoint;
}

@property (nonatomic) CGFloat hysteresisDistance;
@property (readonly, nonatomic) BOOL overcameHysteresis;

- (void)resetHysteresis;

@end
