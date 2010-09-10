// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUILongPressGestureRecognizer.h>

RCS_ID("$Id$")

@implementation OUILongPressGestureRecognizer

@synthesize hysteresisDistance, overcameHysteresis, latestTimestamp;

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
    
    latestTimestamp = [[touches anyObject] timestamp];
    
    if (!beginTimestamp) {
        beginTimestamp = CFAbsoluteTimeGetCurrent();
    }
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
    
    latestTimestamp = [[touches anyObject] timestamp];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesEnded:touches withEvent:event];
    
    endTimestamp = CFAbsoluteTimeGetCurrent();
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
{
    [super touchesCancelled:touches withEvent:event];
    
    endTimestamp = CFAbsoluteTimeGetCurrent();
}

- (void)reset;
{
    [super reset];
    
    beginTimestamp = 0;
}


#pragma mark -
#pragma mark Class methods

- (NSTimeInterval)gestureDuration;
{
    return endTimestamp - beginTimestamp;
}

- (void)resetHysteresis;
{
    overcameHysteresis = NO;
    firstTouchPoint = lastTouchPoint;
}

- (CGPoint)cumulativeOffsetInView:(UIView *)view;
{
    UIWindow *window = self.view.window;
    
    CGPoint startPoint = [view convertPoint:firstTouchPoint fromView:window];
    CGPoint endPoint = [view convertPoint:lastTouchPoint fromView:window];
    
    return CGPointMake(endPoint.x - startPoint.x, endPoint.y - startPoint.y);
}

@end
