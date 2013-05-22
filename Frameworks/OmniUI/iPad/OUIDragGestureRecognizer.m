// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDragGestureRecognizer.h>

#import <UIKit/UIGestureRecognizerSubclass.h>

RCS_ID("$Id$");

@implementation OUIDragGestureRecognizer

- (id)initWithTarget:(id)target action:(SEL)action;
{
    if (!(self = [super initWithTarget:target action:action]))
        return nil;
    
    // Defaults
    self.hysteresisDistance = 9;  // In pixels.  9 pixels is the empirically-determined value that always beats out the scrollview's pan gesture recognizers.
    overcameHysteresis = NO;
    self.numberOfTouchesRequired = 1;
    requiresHoldToComplete = NO;
    
    return self;
}

#pragma mark -
#pragma mark UIGestureRecognizer subclass

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesBegan:touches withEvent:event];
    
    if (self.state != UIGestureRecognizerStatePossible)
        return;
    
    overcameHysteresis = NO;
    firstTouchPoint = latestTouchPoint = [self locationInView:self.view.window];
    
    self.likelihood = 0.1;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesMoved:touches withEvent:event];
    OBASSERT([touches count] == 1);
    OBASSERT([touches anyObject] == [_capturedTouches anyObject]);
    
    // If we don't do this, the event system will send out multiple action messages with UIGestureRecognizerStateBegan:
    if (self.state == UIGestureRecognizerStateBegan) {
        self.state = UIGestureRecognizerStateChanged;
    }
    
    latestTouchPoint = [self locationInView:self.view.window];
    
    if (!overcameHysteresis) {
        CGFloat distanceMoved = hypotf(latestTouchPoint.x - firstTouchPoint.x, latestTouchPoint.y - firstTouchPoint.y);
        if (distanceMoved < self.hysteresisDistance)
            return;
        
        overcameHysteresis = YES;
    }
    
    if (requiresHoldToComplete && !self.completedHold) {
        self.likelihood = 0;
        self.state = UIGestureRecognizerStateFailed;
    }
    
    if (self.state == UIGestureRecognizerStatePossible) {
        self.likelihood = 1;
        self.state = UIGestureRecognizerStateBegan;
    }
    else if (self.state == UIGestureRecognizerStateBegan || self.state == UIGestureRecognizerStateChanged) {
        self.state = UIGestureRecognizerStateChanged;
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesEnded:touches withEvent:event];
    OBASSERT([touches count] == 1);
    OBASSERT([touches anyObject] == [_capturedTouches anyObject]);
    
    if (!overcameHysteresis) {
        wasATap = YES;  // This can be checked in a delegate implementation of -gestureRecognizerShouldBegin:
    }
    
    self.state = UIGestureRecognizerStateEnded;  // same as UIGestureRecognizerStateRecognized
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesCancelled:touches withEvent:event];
    OBASSERT([touches count] == 1);
    OBASSERT([touches anyObject] == [_capturedTouches anyObject]);
    
    self.state = UIGestureRecognizerStateCancelled;
}

- (void)reset;
{
    [super reset];
    
    wasATap = NO;
}


#pragma mark -
#pragma mark Class methods

@synthesize hysteresisDistance, overcameHysteresis, requiresHoldToComplete, wasATap;

- (BOOL)touchIsDown;
{
    return [_capturedTouches anyObject] != nil && self.state != UIGestureRecognizerStateFailed;
}

- (void)resetHysteresis;
{
    //NSLog(@"resetHysteresis");
    overcameHysteresis = NO;
    firstTouchPoint = latestTouchPoint;
}

- (CGPoint)touchBeganPoint;
{
    return [self firstTouchPointInView:self.view];
}

- (CGPoint)firstTouchPointInView:(UIView *)view;
{
    if (!view)
        view = self.view;
    
    UIWindow *window = self.view.window;
    return [view convertPoint:firstTouchPoint fromView:window];
}

- (CGPoint)cumulativeOffsetInView:(UIView *)view;
{
    UIWindow *window = self.view.window;
    
    CGPoint startPoint = [view convertPoint:firstTouchPoint fromView:window];
    CGPoint endPoint = [view convertPoint:latestTouchPoint fromView:window];
    
    return CGPointMake(endPoint.x - startPoint.x, endPoint.y - startPoint.y);
}

@end
