// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIGestureRecognizer.h"
#import <UIKit/UIGestureRecognizerSubclass.h>

RCS_ID("$Id$");

@implementation OUIGestureRecognizer

- (id)initWithTarget:(id)target action:(SEL)action;
{
    if (!(self = [super initWithTarget:target action:action]))
        return nil;
    
    _capturedTouches = [[NSMutableArray alloc] init];
    _numberOfTouchesRequired = 1;
    
    // Defaults
    _likelihood = 0;
    
    return self;
}

- (void)dealloc;
{
    [_capturedTouches release];
    
    [super dealloc];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesBegan:touches withEvent:event];
    
    // If we've already begun, ignore extra touches
    if (self.state != UIGestureRecognizerStatePossible) {
        for (UITouch *touch in touches) {
            [self ignoreTouch:touch forEvent:event];
        }
        return;
    }
    
    // If we haven't begun, record the incoming touch(es).
    for (UITouch *touch in touches) {
        [_capturedTouches addObject:touch];
    }
    
    // If too many touches have come in before the timer has fired, then fail.
    if ([_capturedTouches count] > _numberOfTouchesRequired) {
        self.state = UIGestureRecognizerStateFailed;
    } else if ([_capturedTouches count] == _numberOfTouchesRequired) {
        [self startHoldTimer];
    }
    
    // Record timing information.
    _previousTimestamp = _latestTimestamp = [[touches anyObject] timestamp];
    if (!_beginTimestamp) {
        _beginTimestamp = [[_capturedTouches anyObject] timestamp];
        _beginTimestampReference = [NSDate timeIntervalSinceReferenceDate];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesMoved:touches withEvent:event];
    
    _previousTimestamp = _latestTimestamp;
    _latestTimestamp = [[touches anyObject] timestamp];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesEnded:touches withEvent:event];
    
    if (_holdTimer) {
        [_holdTimer invalidate];
        _holdTimer = nil;
    }
    
    _endTimestamp = [[_capturedTouches anyObject] timestamp];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesCancelled:touches withEvent:event];
    
    if (_holdTimer) {
        [_holdTimer invalidate];
        _holdTimer = nil;
    }
    
    _endTimestamp = [[_capturedTouches anyObject] timestamp];
}

- (void)reset;
{
    [super reset];
    
    [_holdTimer invalidate];
    _holdTimer = nil;
    
    self.likelihood = 0;
    _completedHold = NO;
    
    [_capturedTouches removeAllObjects];
    
    _beginTimestamp = 0;
    _beginTimestampReference = 0;
    _endTimestamp = 0;
}

#pragma mark api
- (void)setLikelihood:(CGFloat)newLikelihood;
{
    if (_likelihood == newLikelihood)
        return;
    
    _likelihood = newLikelihood;
    
    id theDelegate = self.delegate;
    if (theDelegate && [theDelegate respondsToSelector:@selector(gesture:likelihoodDidChange:)]) {
        [theDelegate gesture:self likelihoodDidChange:_likelihood];
    }
}

- (void)startHoldTimer;
{
    if (!_holdTimer && _holdDuration > 0) {
        _completedHold = NO;
        _holdTimer = [NSTimer scheduledTimerWithTimeInterval:_holdDuration target:self selector:@selector(holdTimerFired:) userInfo:nil repeats:NO];
    }
}

- (void)holdTimerFired:(NSTimer *)theTimer;
{
    _holdTimer = nil;
    
    if (self.state == UIGestureRecognizerStatePossible) {
        _completedHold = YES;
        self.state = UIGestureRecognizerStateBegan;
        self.likelihood = 1;
    }
}

@synthesize likelihood = _likelihood;
@synthesize holdDuration = _holdDuration;
@synthesize completedHold = _completedHold;
@synthesize numberOfTouchesRequired = _numberOfTouchesRequired;
@synthesize latestTimestamp = _latestTimestamp;

- (NSTimeInterval)durationSinceGestureBegan;
{
    return [NSDate timeIntervalSinceReferenceDate] - _beginTimestampReference;
}

- (NSTimeInterval)gestureDuration;
{
    if (_endTimestamp) {
        return _endTimestamp - _beginTimestamp;
    }
    else {
        UITouch *theTouch = [_capturedTouches anyObject];
        OBASSERT(theTouch);
        // If the main thread is blocked up, a touch could end before -touchesEnded: is called.
        if (theTouch.phase == UITouchPhaseEnded || theTouch.phase == UITouchPhaseCancelled) {
            return [theTouch timestamp] - _beginTimestamp;
        }
        
        // If the touch has not ended yet, calculate the duration from "now" (less precise than using -[UITouch timestamp], but the best we can do since the touch may not have been updated recently, i.e. if the finger is still).
        return [self durationSinceGestureBegan];
    }
}

- (CGFloat)velocity;
{
    UITouch *theTouch = [_capturedTouches anyObject];
    if (!theTouch) {
        return 0;
    }
    
    CGPoint p1 = [theTouch previousLocationInView:nil];
    CGPoint p2 = [theTouch locationInView:nil];
    CGFloat recentDistance = hypot(p1.x - p2.x, p1.y - p2.y);
    
    NSTimeInterval timeElapsed = theTouch.timestamp - _previousTimestamp;
    if (timeElapsed > 0) {
        return recentDistance/timeElapsed;
    }
    
    // Otherwise
    return 0;
}

@end
