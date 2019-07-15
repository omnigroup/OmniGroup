// Copyright 2011-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIGestureRecognizer.h>

@protocol OUIGestureDelegate
@optional
- (void)gesture:(UIGestureRecognizer *)recognizer likelihoodDidChange:(CGFloat)likelihood;
@end


@interface OUIGestureRecognizer : UIGestureRecognizer {
@protected
    NSTimer *_holdTimer;
    BOOL _completedHold;
    NSMutableArray *_capturedTouches;
    NSUInteger _numberOfTouchesRequired;
@private
    CGFloat _likelihood;
    NSTimeInterval _holdDuration;
    
    NSTimeInterval _beginTimestampReference;  // measured since "reference date"
    NSTimeInterval _beginTimestamp;  // the rest are measured since system startup time
    NSTimeInterval _endTimestamp;
    NSTimeInterval _latestTimestamp;
    NSTimeInterval _previousTimestamp;
}

- (void)startHoldTimer;
- (void)holdTimerFired:(NSTimer *)theTimer;

@property (readwrite,nonatomic) CGFloat likelihood;
@property (readwrite,nonatomic) NSTimeInterval holdDuration;  // Seconds after which the drag gesture will begin, even if the touch has not overcome hysteresis
@property (readonly,nonatomic) BOOL completedHold;

@property (readonly, nonatomic) NSTimeInterval latestTimestamp;  // Provides precise timing suitable for use in stroke recognition algorithms
@property (readonly, nonatomic) NSTimeInterval durationSinceGestureBegan; // Length of time between start of gesture and now.
@property (readonly, nonatomic) NSTimeInterval gestureDuration;  // The length of time the gesture has been in progress (in seconds).
@property (readonly, nonatomic) CGFloat velocity;  // Measured in pixels per second

@property (readwrite,nonatomic) NSUInteger numberOfTouchesRequired;    // Extra touches while in state possible cause the gesture recognizer to fail; If we've already begun, ignores extra touches. Defaults to 1.

@end
