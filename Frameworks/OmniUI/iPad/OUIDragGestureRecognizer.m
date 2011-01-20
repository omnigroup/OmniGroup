// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDragGestureRecognizer.h>

#import <UIKit/UIGestureRecognizerSubclass.h>

RCS_ID("$Id$");

@interface OUIDragGestureRecognizer (/*Private*/)
@property (readwrite, nonatomic) CGFloat likelihood;  // Re-defined here to be privately writable
@end


@implementation OUIDragGestureRecognizer

- (id)initWithTarget:(id)target action:(SEL)action;
{
    if (!(self = [super initWithTarget:target action:action]))
        return nil;
    
    // Defaults
    self.hysteresisDistance = 9;  // In pixels.  9 pixels is the empirically-determined value that always beats out the scrollview's pan gesture recognizers.
    overcameHysteresis = NO;
    likelihood = 0;
    
    return self;
}

- (void)setLikelihood:(CGFloat)newLikelihood;
{
    if (likelihood == newLikelihood)
        return;
    
    likelihood = newLikelihood;
    
    id theDelegate = self.delegate;
    if (theDelegate && [theDelegate respondsToSelector:@selector(gesture:likelihoodDidChange:)]) {
        [theDelegate gesture:self likelihoodDidChange:likelihood];
    }
}

- (void)longPressTimerFired:(NSTimer *)theTimer;
{
    longPressTimer = nil;
    
    if (oneTouch && self.state == UIGestureRecognizerStatePossible) {
        self.likelihood = 1;
        self.state = UIGestureRecognizerStateBegan;
    }
}

#pragma mark -
#pragma mark UIGestureRecognizer subclass

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesBegan:touches withEvent:event];
    
    if (oneTouch || [touches count] > 1) {
        // Extra touches while in state possible cause the gesture recognizer to fail.
        if (self.state == UIGestureRecognizerStatePossible) {
            self.likelihood = 0;
            self.state = UIGestureRecognizerStateFailed;
        }
        
        // If we've already begun, just ignore extra touches
        else {
            for (UITouch *touch in touches) {
                [self ignoreTouch:touch forEvent:event];
            }
        }
        
        return;
    }
    oneTouch = [touches anyObject];
    
    overcameHysteresis = NO;
    firstTouchPoint = [self locationInView:self.view.window];
    
    previousTimestamp = latestTimestamp = [[touches anyObject] timestamp];
    
    if (!beginTimestamp) {
        beginTimestamp = [NSDate timeIntervalSinceReferenceDate];
        OBASSERT(beginTimestamp > 0); // True after the first instant of Jan 1, 2001.
    }
    
    if (!longPressTimer && self.longPressDuration > 0) {
        longPressTimer = [NSTimer scheduledTimerWithTimeInterval:self.longPressDuration target:self selector:@selector(longPressTimerFired:) userInfo:nil repeats:NO];

    }
    
    self.likelihood = 0.1;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesMoved:touches withEvent:event];
    OBASSERT([touches count] == 1);
    OBASSERT([touches anyObject] == oneTouch);
    
    // If we don't do this, the event system will send out multiple action messages with UIGestureRecognizerStateBegan:
    if (self.state == UIGestureRecognizerStateBegan) {
        self.state = UIGestureRecognizerStateChanged;
    }
    
    latestTouchPoint = [self locationInView:self.view.window];
    previousTimestamp = latestTimestamp;
    latestTimestamp = [[touches anyObject] timestamp];
    
    if (!overcameHysteresis) {
        CGFloat distanceMoved = hypotf(latestTouchPoint.x - firstTouchPoint.x, latestTouchPoint.y - firstTouchPoint.y);
        if (distanceMoved < self.hysteresisDistance)
            return;
        
        overcameHysteresis = YES;
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
    OBASSERT([touches anyObject] == oneTouch);
    
    if (longPressTimer) {
        [longPressTimer invalidate];
        longPressTimer = nil;
    }
    
    endTimestamp = [NSDate timeIntervalSinceReferenceDate];
    
    if (!overcameHysteresis) {
        wasATap = YES;  // This can be checked in a delegate implementation of -gestureRecognizerShouldBegin:
    }
    
    self.state = UIGestureRecognizerStateEnded;  // same as UIGestureRecognizerStateRecognized
    
    oneTouch = nil;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesCancelled:touches withEvent:event];
    OBASSERT([touches count] == 1);
    OBASSERT([touches anyObject] == oneTouch);
    
    if (longPressTimer) {
        [longPressTimer invalidate];
        longPressTimer = nil;
    }
    
    endTimestamp = [NSDate timeIntervalSinceReferenceDate];
    
    self.state = UIGestureRecognizerStateCancelled;
    
    oneTouch = nil;
}

- (void)reset;
{
    [super reset];
    
    [longPressTimer invalidate];
    longPressTimer = nil;
    
    oneTouch = nil;
    wasATap = NO;
    self.likelihood = 0;
    
    beginTimestamp = 0;
    endTimestamp = 0;
}


#pragma mark -
#pragma mark Class methods

@synthesize longPressDuration, completedLongPress, hysteresisDistance, overcameHysteresis, latestTimestamp, wasATap, likelihood;

- (BOOL)completedLongPress;
{
    return self.gestureDuration >= self.longPressDuration;
}

- (BOOL)touchIsDown;
{
    return oneTouch != nil && self.state != UIGestureRecognizerStateFailed;
}

- (NSTimeInterval)gestureDuration;
{
    if (endTimestamp) {
        return endTimestamp - beginTimestamp;
    }
    else {
        return [NSDate timeIntervalSinceReferenceDate] - beginTimestamp;
    }
}

- (void)resetHysteresis;
{
    NSLog(@"resetHysteresis");
    overcameHysteresis = NO;
    firstTouchPoint = latestTouchPoint;
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

- (CGFloat)velocity;
{
    if (!oneTouch) {
        return 0;
    }
    
    CGPoint p1 = [oneTouch previousLocationInView:nil];
    CGPoint p2 = [oneTouch locationInView:nil];
    CGFloat recentDistance = hypot(p1.x - p2.x, p1.y - p2.y);
    
    NSTimeInterval timeElapsed = oneTouch.timestamp - previousTimestamp;
    if (timeElapsed > 0) {
        return recentDistance/timeElapsed;
    }
    
    // Otherwise
    return 0;
}

@end
