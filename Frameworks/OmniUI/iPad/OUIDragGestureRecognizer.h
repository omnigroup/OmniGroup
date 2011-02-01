// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIGestureRecognizer.h>

@protocol OUIDragGestureDelegate
@optional
- (void)gesture:(UIGestureRecognizer *)recognizer likelihoodDidChange:(CGFloat)likelihood;
@end


@interface OUIDragGestureRecognizer : UIGestureRecognizer
{
@private
    CGFloat hysteresisDistance;
    BOOL overcameHysteresis;
    
    // Points stored in window coordinates
    CGPoint firstTouchPoint;
    CGPoint latestTouchPoint;
    
    NSTimeInterval beginTimestampReference;  // measured since "reference date"
    NSTimeInterval beginTimestamp;  // the rest are measured since system startup time
    NSTimeInterval endTimestamp;
    NSTimeInterval latestTimestamp;
    NSTimeInterval previousTimestamp;
    
    NSTimeInterval holdDuration;
    NSTimer *longPressTimer;
    
    UITouch *oneTouch;
    CGFloat likelihood;
    
    BOOL wasATap;
    BOOL _completedHold;
}

// Settings
@property (nonatomic) NSTimeInterval holdDuration;  // Seconds after which the drag gesture will begin, even if the touch has not overcome hysteresis
@property (nonatomic) CGFloat hysteresisDistance;

// Actions
- (void)resetHysteresis;

// Properties
@property (readonly, nonatomic) BOOL wasATap;  // YES if the gesture is ending without overcoming hysteresis.
@property (readonly, nonatomic) BOOL touchIsDown;
@property (readonly, nonatomic) CGFloat likelihood;
@property (readonly, nonatomic) BOOL overcameHysteresis;
@property (readonly, nonatomic) BOOL completedHold;
@property (readonly, nonatomic) CGFloat velocity;

@property (readonly, nonatomic) NSTimeInterval latestTimestamp;  // Provides precise timing suitable for use in stroke recognition algorithms
@property (readonly, nonatomic) NSTimeInterval gestureDuration;  // The length of time the gesture has been in progress (in seconds).

- (CGPoint)touchBeganPoint;  // TODO: Remove (it's here for compatibility with GPMoveGestureRecognizer
- (CGPoint)firstTouchPointInView:(UIView *)view;
- (CGPoint)cumulativeOffsetInView:(UIView *)view;

@end
