//
//  OUILongPressGestureRecognizer.m
//  GesturePlayground
//
//  Created by Robin Stewart on 7/26/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "OUILongPressGestureRecognizer.h"


@implementation OUILongPressGestureRecognizer

@synthesize hysteresisDistance, overcameHysteresis;

- (id)initWithTarget:(id)target action:(SEL)action;
{
    if (!(self = [super initWithTarget:target action:action]))
        return nil;
    
    // Defaults
    self.hysteresisDistance = 10;  // pixels
    overcameHysteresis = NO;
    
    return self;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesBegan:touches withEvent:event];
    
    overcameHysteresis = NO;
    firstTouchPoint = [self locationInView:self.view.window];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesMoved:touches withEvent:event];
    
    if (!overcameHysteresis) {
        CGPoint touchPoint = [self locationInView:self.view.window];
        CGFloat distanceMoved = hypotf(touchPoint.x - firstTouchPoint.x, touchPoint.y - firstTouchPoint.y);
        if (distanceMoved > self.hysteresisDistance) {
            overcameHysteresis = YES;
        }
    }
    
    lastTouchPoint = [self locationInView:self.view.window];
}


#pragma mark -
#pragma mark Class methods

- (void)resetHysteresis;
{
    overcameHysteresis = NO;
    firstTouchPoint = lastTouchPoint;
}


@end
