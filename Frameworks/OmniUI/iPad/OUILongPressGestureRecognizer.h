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
    
    // Points stored in window coordinates
    CGPoint firstTouchPoint;
    CGPoint lastTouchPoint;
    
    NSTimeInterval latestTimestamp;  // measured since system startup time
    
    NSTimeInterval beginTimestamp;  // measured since Jan 1, 2001
    NSTimeInterval endTimestamp;    // "
}

@property (nonatomic) CGFloat hysteresisDistance;
@property (readonly, nonatomic) BOOL overcameHysteresis;

@property (readonly, nonatomic) NSTimeInterval latestTimestamp;  // Provides precise timing suitable for use in stroke recognition algorithms
@property (readonly, nonatomic) NSTimeInterval gestureDuration;  // The length of time the gesture was in progress.  Only valid after the gesture has finished (ended or cancelled).

- (CGPoint)cumulativeOffsetInView:(UIView *)view;

- (void)resetHysteresis;

@end
