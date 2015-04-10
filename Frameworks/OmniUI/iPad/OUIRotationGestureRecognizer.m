// Copyright 2011-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <OmniUI/OUIRotationGestureRecognizer.h>

#import <UIKit/UIGestureRecognizerSubclass.h>

RCS_ID("$Id$");

static inline CGFloat _angleBetweenPointsInDegrees(CGPoint pointOne, CGPoint pointTwo)
{
    CGFloat radians = (CGFloat)atan2(pointOne.y - pointTwo.y, pointOne.x - pointTwo.x);
    return (CGFloat)fmod(fmod(radians * 360.0f / (2.0f * M_PI), 360.0f) + 360.0f, 360.0f);
}

//#define DEBUG_RotationGesture 1
#ifdef DEBUG_RotationGesture
static void _logTouchDescription(UITouch *aTouch)
{
    // -description works but prints out a lot of extra stuff
    NSLog(@"    <%@ %p>: gestures", [aTouch class], aTouch);
    for (UIGestureRecognizer *aGesture in [aTouch gestureRecognizers])
        NSLog(@"        <%@ %p>", [aGesture class], aGesture);
}
#endif

@implementation OUIRotationGestureRecognizer

- (id)initWithTarget:(id)target action:(SEL)action;
{
    if (!(self = [super initWithTarget:target action:action]))
        return nil;
    
    // Defaults
    _hysteresisAngle = 15;  
    _overcameHysteresis = NO;
    _rotation = 0;
    
    self.numberOfTouchesRequired = 2;
    
    return self;
}

#pragma mark -
#pragma mark UIGestureRecognizer subclass

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesBegan:touches withEvent:event];
    
#ifdef DEBUG_RotationGesture
    NSLog(@"%s (state = %li, capture touches = %lu, input = %lu)", __FUNCTION__, self.state, [_capturedTouches count], [touches count]);
#endif
    
    if (self.state != UIGestureRecognizerStatePossible)
        return;
    
    // Update the likelihood
    if ([_capturedTouches count] == 1) {
        // updating _centerTouchPoint so that -locationInView returns a valid value
        UITouch *firstTouch = [_capturedTouches objectAtIndex:0];
        _centerTouchPoint = [firstTouch locationInView:self.view];
        
        self.likelihood = 0.1;
        
        return;
    }
    
    UITouch *firstTouch = [_capturedTouches objectAtIndex:0];
    CGPoint firstTouchPoint = [firstTouch locationInView:self.view];
    UITouch *secondTouch = [_capturedTouches objectAtIndex:1];
    CGPoint secondTouchPoint = [secondTouch locationInView:self.view];
    
    _centerTouchPoint = CGPointMake((firstTouchPoint.x + secondTouchPoint.x)/2, (firstTouchPoint.y + secondTouchPoint.y)/2);
    
    self.likelihood = 0.2;
    
#ifdef DEBUG_RotationGesture
    NSLog(@"    first touch");
    _logTouchDescription(firstTouch);
    NSLog(@"    second touch");
    _logTouchDescription(secondTouch);
#endif
    
    _startAngle = _angleBetweenPointsInDegrees(firstTouchPoint, secondTouchPoint);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
{
#ifdef DEBUG_RotationGesture
    NSLog(@"%s (state = %li)", __FUNCTION__, self.state);
#endif
    
    [super touchesMoved:touches withEvent:event];
    
    CGFloat finishAngle = 0;
    if ([_capturedTouches count] == 0) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    } else if ([_capturedTouches count] == 1) {
        UITouch *onlyTouch = [_capturedTouches anyObject];
        CGPoint onlyTouchPoint = [onlyTouch locationInView:self.view];
        
        finishAngle = _angleBetweenPointsInDegrees(onlyTouchPoint, _centerTouchPoint);
    } else {
        UITouch *firstTouch = [_capturedTouches objectAtIndex:0];
        CGPoint firstTouchPoint = [firstTouch locationInView:self.view];
        UITouch *secondTouch = [_capturedTouches objectAtIndex:1];
        CGPoint secondTouchPoint = [secondTouch locationInView:self.view];
        
        _centerTouchPoint = CGPointMake((firstTouchPoint.x + secondTouchPoint.x)/2, (firstTouchPoint.y + secondTouchPoint.y)/2);
        
        finishAngle = _angleBetweenPointsInDegrees(firstTouchPoint, secondTouchPoint);
    }
    
    if (!_overcameHysteresis && self.state == UIGestureRecognizerStatePossible /* holdTimer has not fired */) {
        if (fabs(_startAngle - finishAngle) < _hysteresisAngle)
            return;
        
        _overcameHysteresis = YES;
    }
    
    _rotation = finishAngle - _startAngle;
    
    if (self.state == UIGestureRecognizerStatePossible) {
        self.likelihood = 1;
        
        self.state = UIGestureRecognizerStateBegan;
    } else if (self.state == UIGestureRecognizerStateBegan || self.state == UIGestureRecognizerStateChanged) {
        self.state = UIGestureRecognizerStateChanged;
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesEnded:touches withEvent:event];
    
    for (UITouch *touch in touches)
        [_capturedTouches removeObjectIdenticalTo:touch];
    
#ifdef DEBUG_RotationGesture
    NSLog(@"%s (state = %li, capture touches = %lu, input = %lu)", __FUNCTION__, self.state, [_capturedTouches count], [touches count]);
    for (UITouch *aTouch in _capturedTouches)
        _logTouchDescription(aTouch);
#endif
    
    // If a finger is still down, don't end the gesture
    if ([_capturedTouches count])
        return;
    
    self.state = UIGestureRecognizerStateEnded;  // same as UIGestureRecognizerStateRecognized
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
{
#ifdef DEBUG_RotationGesture
    NSLog(@"%s", __FUNCTION__);
#endif
    
    [super touchesCancelled:touches withEvent:event];
    
    for (UITouch *touch in touches)
        [_capturedTouches removeObjectIdenticalTo:touch];
    
    self.state = UIGestureRecognizerStateCancelled;
}

- (void)reset;
{
    [super reset];
    
    _overcameHysteresis = NO;
    _rotation = 0;
    
    [_capturedTouches removeAllObjects];
}

- (CGPoint)locationInView:(UIView*)view;
{
    return [self.view convertPoint:_centerTouchPoint toView:view];
}

@synthesize rotation= _rotation;

@end
