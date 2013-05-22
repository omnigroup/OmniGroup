// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITapGestureRecognizer.h>

#import <UIKit/UIGestureRecognizerSubclass.h>

RCS_ID("$Id$")

#if 0 && defined(DEBUG)
#define DEBUG_TAP_GESTURE_REC(format, ...) NSLog(@"TAP_GESTURE_REC: " format, ## __VA_ARGS__)
#define IS_DEBUGGING_TAP_GESTURE_REC
#else
#define DEBUG_TAP_GESTURE_REC(format, ...)
#endif

@implementation OUITapGestureRecognizer

#ifdef IS_DEBUGGING_TAP_GESTURE_REC
static void LogGestureState(const char *functionName, UIGestureRecognizerState state) {
    NSString *stateName;
    switch (state) {
        case UIGestureRecognizerStateBegan:
            stateName = @"began";
            break;
        case UIGestureRecognizerStateCancelled:
            stateName = @"cancelled";
            break;
        case UIGestureRecognizerStateEnded:
            stateName = @"ended/recognized";
            break;
        case UIGestureRecognizerStateFailed:
            stateName = @"failed";
            break;
        case UIGestureRecognizerStatePossible:
            stateName = @"possible";
            break;
        case UIGestureRecognizerStateChanged:
            stateName = @"changed";
            break;
        default:
            stateName = @"huh?";
    }
    DEBUG_TAP_GESTURE_REC(@"In %s with state: %@", functionName, stateName);
}
#else
#define LogGestureState(functionName, state)
#endif

- (id)initWithTarget:(id)target action:(SEL)action;
{
    if (!(self = [super initWithTarget:target action:action]))
        return nil;
    
    self.numberOfTouchesRequired = 1;
    _allowableMovement = 10;    // taken from UILongPressGestureRecognizer.h
    _firstTouchPoint = CGPointZero;
    
    return self;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
{
    LogGestureState(__func__, self.state);
    [super touchesBegan:touches withEvent:event];
    
    if (self.state != UIGestureRecognizerStatePossible)
        return;
    
    UITouch *firstTouch = [_capturedTouches anyObject];
    _firstTouchPoint = [firstTouch locationInView:self.view];
    _previousFirstTouchPoint = CGPointZero;
    _cachingPreviousFirstTouchPoint = NO;
    
    self.likelihood = 0.1;
    
    if (!_movementTimer)
        // 0.065 is an arbitrary value that seems to correspond to when 'movement' gestures - such as UIPanGestureRecognizer and UISwipeGestureRecognizer - will fail to recognize due to the touch/event being a 'stationary' one
        _movementTimer = [NSTimer scheduledTimerWithTimeInterval:0.065 target:self selector:@selector(movementTimerFired:) userInfo:nil repeats:NO];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
{
    LogGestureState(__func__, self.state);
    
    [super touchesMoved:touches withEvent:event];
    
    UITouch *firstTouch = [_capturedTouches anyObject];
    CGPoint secondPoint = [firstTouch locationInView:self.view];
    
    CGFloat distance = hypotf(secondPoint.x - _firstTouchPoint.x, secondPoint.y - _firstTouchPoint.y);
    if (distance > _allowableMovement) {
        self.state = UIGestureRecognizerStateFailed;
        self.likelihood = 0.0f;
        
        if (_movementTimer) {
            [_movementTimer invalidate];
            _movementTimer = nil;
        }
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
{
    LogGestureState(__func__, self.state);
    if (self.state == UIGestureRecognizerStatePossible)
        self.likelihood = 1.0f;
    else
        self.likelihood = 0.0f;
    
    [super touchesEnded:touches withEvent:event];
    
    if (_movementTimer) {
        [_movementTimer invalidate];
        _movementTimer = nil;
    }
    
    if (self.state == UIGestureRecognizerStatePossible)
        self.state = UIGestureRecognizerStateEnded;
    else
        self.state = UIGestureRecognizerStateFailed;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
{
    LogGestureState(__func__, self.state);
    self.likelihood = 0.0f;
    [super touchesCancelled:touches withEvent:event];
    
    if (_movementTimer) {
        [_movementTimer invalidate];
        _movementTimer = nil;
    }
    
    self.state = UIGestureRecognizerStateFailed;
}

- (CGPoint)locationInView:(UIView *)view;
{
    CGPoint firstTouchPoint;
    if (_cachingPreviousFirstTouchPoint)
        firstTouchPoint = _previousFirstTouchPoint;
    else
        firstTouchPoint = _firstTouchPoint;

    return [self.view convertPoint:firstTouchPoint toView:view];
}

- (void)reset;
{
    LogGestureState(__func__, self.state);
    _previousFirstTouchPoint = _firstTouchPoint;
    _cachingPreviousFirstTouchPoint = YES;
    _firstTouchPoint = CGPointZero;

    [super reset];
    
    if (_movementTimer) {
        [_movementTimer invalidate];
        _movementTimer = nil;
    }
}

- (void)movementTimerFired:(NSTimer *)aTimer;
{
    _movementTimer = nil;
    
    self.likelihood = 0.2f;
}

@end
