// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUILongPressGestureRecognizer.h>

RCS_ID("$Id$")

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
