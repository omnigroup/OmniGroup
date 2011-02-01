// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIRotationGestureRecognizer.h>

#import <UIKit/UIGestureRecognizerSubclass.h>
#import <OmniUI/OUIDragGestureRecognizer.h>

RCS_ID("$Id$");


@implementation OUIRotationGestureRecognizer

- (id)initWithTarget:(id)target action:(SEL)action;
{
    if (!(self = [super initWithTarget:target action:action]))
        return nil;
    
    // Set up
    capturedTouches = [[NSMutableArray alloc] init];
    likelihood = 0;
    
    // Defaults
    //self.hysteresisDistance = 9;  // In pixels.  9 pixels is the empirically-determined value that always beats out the scrollview's pan gesture recognizers.
    //overcameHysteresis = NO;
    longPressDuration = 0.4;
    
    return self;
}

- (void)dealloc;
{
    [capturedTouches release];
    
    [super dealloc];
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
    
    if ([capturedTouches count] == 2 && self.state == UIGestureRecognizerStatePossible) {
        self.likelihood = 1;
        self.state = UIGestureRecognizerStateBegan;
    }
}


#pragma mark -
#pragma mark UIGestureRecognizer subclass

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
        [capturedTouches addObject:touch];
    }
    
    // If too many touches have come in before the timer has fired, then fail.
    if ([capturedTouches count] > 2) {
        self.likelihood = 0;
        self.state = UIGestureRecognizerStateFailed;
        
        return;
    }
    
    // Update the likelihood
    if ([capturedTouches count] == 1) {
        self.likelihood = 0.1;
    }
    
    // If the right number of touches have been captured, start the timer.
    else if ([capturedTouches count] == 2) {
        self.likelihood = 0.2;
        
        if (!longPressTimer) {
            longPressTimer = [NSTimer scheduledTimerWithTimeInterval:self.longPressDuration target:self selector:@selector(longPressTimerFired:) userInfo:nil repeats:NO];
        }
    }
    
//    overcameHysteresis = NO;
//    firstTouchPoint = [self locationInView:self.view.window];
//    
//    previousTimestamp = latestTimestamp = [[touches anyObject] timestamp];
//    
//    if (!beginTimestamp) {
//        beginTimestamp = [oneTouch timestamp];
//        beginTimestampReference = [NSDate timeIntervalSinceReferenceDate];
//    }
    
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesMoved:touches withEvent:event];
    
    // If we don't do this, the event system will send out multiple action messages with UIGestureRecognizerStateBegan:
    if (self.state == UIGestureRecognizerStateBegan) {
        self.state = UIGestureRecognizerStateChanged;
    }
    
    CGPoint midpoint = [self locationInView:self.view.window];
    NSLog(@"%d touches, with midpoint: %@", (int)[capturedTouches count], NSStringFromCGPoint(midpoint));
    
//    latestTouchPoint = [self locationInView:self.view.window];
//    previousTimestamp = latestTimestamp;
//    latestTimestamp = [[touches anyObject] timestamp];
    
//    if (!overcameHysteresis) {
//        CGFloat distanceMoved = hypotf(latestTouchPoint.x - firstTouchPoint.x, latestTouchPoint.y - firstTouchPoint.y);
//        if (distanceMoved < self.hysteresisDistance)
//            return;
//        
//        overcameHysteresis = YES;
//    }
    
    /*if (self.state == UIGestureRecognizerStatePossible) {
        self.likelihood = 1;
        self.state = UIGestureRecognizerStateBegan;
    }
    else*/ if (self.state == UIGestureRecognizerStateBegan || self.state == UIGestureRecognizerStateChanged) {
        self.state = UIGestureRecognizerStateChanged;
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesEnded:touches withEvent:event];
    
    for (UITouch *touch in touches) {
        [capturedTouches removeObjectIdenticalTo:touch];
    }
    
    // If a finger is still down, don't end the gesture
    if ([capturedTouches count]) {
        return;
    }
    
    // When all fingers are lifted, end the gesture
    if (longPressTimer) {
        [longPressTimer invalidate];
        longPressTimer = nil;
    }
    
//    endTimestamp = [oneTouch timestamp];
    
    self.state = UIGestureRecognizerStateEnded;  // same as UIGestureRecognizerStateRecognized
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesCancelled:touches withEvent:event];
    
    for (UITouch *touch in touches) {
        [capturedTouches removeObjectIdenticalTo:touch];
    }
    
    // Go ahead and cancel the gesture if any of the touches are cancelled.
    
    if (longPressTimer) {
        [longPressTimer invalidate];
        longPressTimer = nil;
    }
    
//    endTimestamp = [oneTouch timestamp];
    
    self.state = UIGestureRecognizerStateCancelled;
}

- (void)reset;
{
    [super reset];
    
    [longPressTimer invalidate];
    longPressTimer = nil;
    
    [capturedTouches removeAllObjects];
//    wasATap = NO;
    self.likelihood = 0;
    
//    beginTimestamp = 0;
//    beginTimestampReference = 0;
//    endTimestamp = 0;
//    
//    _completedHold = NO;
}


#pragma mark -
#pragma mark Class methods

@synthesize longPressDuration;
@synthesize likelihood;

@synthesize rotation;
- (CGFloat)rotation;
{
    return 0;
}


@end
