// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUILongPressGestureRecognizer.h>

#import <UIKit/UIGestureRecognizerSubclass.h>

RCS_ID("$Id$")

@implementation OUILongPressGestureRecognizer

- (id)initWithTarget:(id)target action:(SEL)action;
{
    if (!(self = [super initWithTarget:target action:action]))
        return nil;
    
    self.holdDuration = 0.5;    // taken from UILongPressGestureRecognizer.h
    self.numberOfTouchesRequired = 1;
    _allowableMovement = 10;    // taken from UILongPressGestureRecognizer.h
    _firstTouchPoint = CGPointZero;
    
    return self;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesBegan:touches withEvent:event];
    
    if (self.state != UIGestureRecognizerStatePossible)
        return;
    
    UITouch *firstTouch = [_capturedTouches anyObject];
    _firstTouchPoint = [firstTouch locationInView:self.view];
    
    self.likelihood = 0.1;
    
    if (!_movementTimer)
        // 0.065 is an arbitrary value that seems to correspond to when 'movement' gestures - such as UIPanGestureRecognizer and UISwipeGestureRecognizer - will fail to recognize due to the touch/event being a 'stationary' one
        _movementTimer = [NSTimer scheduledTimerWithTimeInterval:0.065 target:self selector:@selector(movementTimerFired:) userInfo:nil repeats:NO];        
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesMoved:touches withEvent:event];
    
    if (self.state == UIGestureRecognizerStatePossible /* holdTimer has not fired */) {
        UITouch *firstTouch = [_capturedTouches anyObject];
        CGPoint secondPoint = [firstTouch locationInView:self.view];
        
        CGFloat distance = hypotf(secondPoint.x - _firstTouchPoint.x, secondPoint.y - _firstTouchPoint.y);
        if (distance > _allowableMovement) {
            self.state = UIGestureRecognizerStateCancelled;

            if (_movementTimer) {
                [_movementTimer invalidate];
                _movementTimer = nil;
            }
        }
        
        return;
    }
    
    // holdTimer has fired and we didn't move too far, so we have a match
    if (self.likelihood < 1)
        self.likelihood = 1;
    
    self.state = UIGestureRecognizerStateChanged;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesEnded:touches withEvent:event];
    
    if (_movementTimer) {
        [_movementTimer invalidate];
        _movementTimer = nil;
    }
    
    UIGestureRecognizerState state = self.state;
    if (state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateChanged)
        self.state = UIGestureRecognizerStateEnded;
    else
        self.state = UIGestureRecognizerStateCancelled;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesCancelled:touches withEvent:event];
    
    if (_movementTimer) {
        [_movementTimer invalidate];
        _movementTimer = nil;
    }
    
    self.state = UIGestureRecognizerStateCancelled;
}

- (void)reset;
{
    [super reset];
    
    if (_movementTimer) {
        [_movementTimer invalidate];
        _movementTimer = nil;
    }
}

- (void)movementTimerFired:(NSTimer *)aTimer;
{
    _movementTimer = nil;
    
    self.likelihood = 0.2;
}

@end
