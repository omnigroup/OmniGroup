// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUITextThumb.h"

#import "OUIEditableFrame.h"

#import <OmniQuartz/OQDrawing.h>
#import <QuartzCore/QuartzCore.h>
#import <OmniBase/rcsid.h>


/*
 We want a large hit area for the thumbs; not just the size of the dot.
 The leading edge thumb is biased towards the top (its touchable area doesn't do below the selection rect it is associated with) and the trailing edge thumb is biased towards the bottom.
*/

#define THUMB_HALFWIDTH 9      // The radius of the thumb circle (pixels)
#define THUMB_GAP 3            // The gap between the thumb circle and the caret bar (pixels)
#define THUMB_RING_WIDTH 2     // The width of the white border of the thumb circle (pixels)

#define THUMB_TOUCH_RADIUS 35  // How many pixels from the ring should we be sensitive to touches?

//#define DEBUG_THUMB_GRABBY

RCS_ID("$Id$");

@implementation OUITextThumb

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    
    self.clearsContextBeforeDrawing = YES;
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.userInteractionEnabled = YES;
    self.hidden = YES;
    
    ascent = -1;
    width = -1;
    
    /* We create a gesture recognizer for the drag gesture */
    UIPanGestureRecognizer *dragMe = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_dragged:)];
    dragMe.minimumNumberOfTouches = 1;
    dragMe.maximumNumberOfTouches = 1;
    dragMe.delaysTouchesBegan = YES;
    dragMe.enabled = NO; // Will be enabled & disabled in our -setHidden: implementation
    
    [self addGestureRecognizer:dragMe];
    [dragMe release];
    
    return self;
}

@synthesize isEndThumb;

- (void)setCaretRectangle:(CGRect)r;
{
    // Caret rect is in our frame coordinates (our superview's bounds coordinates).
    CGRect frame = self.frame;
    CGFloat belowCaret;
    
    if (ascent != r.size.height || width != r.size.width) {
        ascent = r.size.height;
        width = r.size.width;
        
        CGRect newBounds;
        
        newBounds.size.width = 2 * THUMB_TOUCH_RADIUS; // Assuming this is the largest length we worry about (else, do some MAX() calls here)
        newBounds.origin.x = - THUMB_TOUCH_RADIUS;
        
        // How far past the end of the caret does the touch radius extend?
        // (This is the same for start and end thumbs)
        CGFloat pastCaret = ( THUMB_TOUCH_RADIUS - THUMB_GAP - THUMB_HALFWIDTH ) - ascent;
        
        newBounds.size.height = THUMB_TOUCH_RADIUS + THUMB_HALFWIDTH + THUMB_GAP + ascent + MAX(0, pastCaret);
        
        // Work out our bounds rect: place Y=0 at the bottom of the caret rect
        if (isEndThumb) {
            // Thumb dot is below caret rect
            newBounds.origin.y = - (THUMB_TOUCH_RADIUS + THUMB_HALFWIDTH + THUMB_GAP);
        } else {
            // Thumb dot is above caret rect
            newBounds.origin.y = MIN(0, -pastCaret);
        }
        
        newBounds = CGRectIntegral(newBounds);
        
        frame.size = newBounds.size;
        self.bounds = newBounds;
        // NSLog(@"Thumb(%d): caret rect is %@ -> bounds are %@", (int)isEndThumb, NSStringFromCGRect(r), NSStringFromCGRect(newBounds));
        [self setNeedsDisplay];
        
        belowCaret = - (newBounds.origin.y);
    } else {
        belowCaret = - (self.bounds.origin.y);
    }
    
    // We work in Y-increases-upwards coordinates internally, but our frame is always in Y-increases-downwards coordinates
    frame.origin.x = r.origin.x - THUMB_TOUCH_RADIUS + round(width / 2);
    frame.origin.y = r.origin.y + r.size.height + belowCaret - frame.size.height;
    
    // NSLog(@"Thumb(%d): caret rect is %@ -> frame is %@", (int)isEndThumb, NSStringFromCGRect(r), NSStringFromCGRect(frame));
    self.frame = frame;
}

- (BOOL)canBecomeFirstResponder
{
    return NO;
}

- (void)setHidden:(BOOL)newHidden
{
    [super setHidden:newHidden];
    OFForEachInArray([self gestureRecognizers], UIGestureRecognizer *, recognizer, recognizer.enabled = !newHidden);
}

- (void)drawRect:(CGRect)rect;
{
    CGContextRef cgContext = UIGraphicsGetCurrentContext();
    CGRect viewBounds = self.bounds;
    
#ifdef DEBUG_THUMB_GRABBY
    CGContextSetRGBFillColor(cgContext, 1.0, 0.5, 0.5, 0.125);
    CGContextFillRect(cgContext, viewBounds);
#endif    
    
    OQFlipVerticallyInRect(cgContext, viewBounds);
    CGContextSetAlpha(cgContext, 1.0);
    
    /* Divide our area into three stacked rectangles: the thumb circle, the vertical caret-like line attached to it, and the small gap between them */
    CGRect thumbRect, caretRect;
    thumbRect.size.width = 2*THUMB_HALFWIDTH;
    thumbRect.size.height = 2*THUMB_HALFWIDTH;
    thumbRect.origin.x = - THUMB_HALFWIDTH;
    caretRect.size.width = width;
    caretRect.size.height = ascent;
    caretRect.origin.x = - floor(width / 2);
    caretRect.origin.y = 0;
    if (isEndThumb) {
        thumbRect.origin.y = - ( 2*THUMB_HALFWIDTH + THUMB_GAP );
    } else {
        thumbRect.origin.y = ascent + THUMB_GAP;
    }
    
    /* Inset the thumb rect to allow for the portion of the stroke that goes outside the rect */
    
    thumbRect = CGRectInset(thumbRect, THUMB_RING_WIDTH*0.5, THUMB_RING_WIDTH*0.5);
    
    OUIEditableFrame *editor = ((OUIEditableFrame *)self.superview);
    
    /* interestingly, CGColorGetConstantColor() exists on the iphone, but all of the defined values for its argument are __IPHONE_NA. */
    
    CGColorRef gradientColors[2];
    /* [UIColor blackColor] acts as a transparent color when used in a gradient; looks like CGGradientCreateWithColors() is broken and doesn't translate grays into rgbs? RADAR 7884816. */
    static const CGFloat zeroes[4] = { 0, 0, 0, 1 };
    CGColorSpaceRef deviceRGB = CGColorSpaceCreateDeviceRGB();
    CGColorRef actualBlackColor = CGColorCreate(deviceRGB, zeroes);
    gradientColors[0] = [editor.selectionColor colorWithAlphaComponent:1.0].CGColor;
    gradientColors[1] = actualBlackColor;
    CFArrayRef colorPoints = CFArrayCreate(kCFAllocatorDefault, (const void **)gradientColors, 2, &kCFTypeArrayCallBacks);
    CFRelease(actualBlackColor);
    
    CGGradientRef thumbFill = CGGradientCreateWithColors(deviceRGB, colorPoints, NULL);
    
    CFRelease(colorPoints);
    CFRelease(deviceRGB);
    
    CGContextBeginPath(cgContext);
    CGContextAddEllipseInRect(cgContext, thumbRect);
    
    CGContextSaveGState(cgContext);
    CGContextClip(cgContext);
    
    CGFloat midX = thumbRect.origin.x + ( thumbRect.size.width / 2 );
    CGFloat midY = thumbRect.origin.y + ( thumbRect.size.height / 2 );
    CGFloat topMidY = thumbRect.origin.y + ( 3 * thumbRect.size.height / 4 );
    
    CGContextDrawRadialGradient(cgContext, thumbFill,
                                (CGPoint){ midX, topMidY }, 0,
                                (CGPoint){ midX, midY }, thumbRect.size.width * 0.7,
                                kCGGradientDrawsBeforeStartLocation);
    
    CFRelease(thumbFill);
    
    CGContextRestoreGState(cgContext);
    
    CGContextSetStrokeColorWithColor(cgContext, [UIColor whiteColor].CGColor);
    CGContextBeginPath(cgContext);
    CGContextAddEllipseInRect(cgContext, thumbRect);
    CGContextSetLineWidth(cgContext, THUMB_RING_WIDTH);
    CGContextStrokePath(cgContext);
    
    CGContextSetFillColorWithColor(cgContext, editor.selectionColor.CGColor);
    CGContextFillRect(cgContext, caretRect);
}

- (CGFloat)distanceFromPoint:(CGPoint)p;
{
    // Not a true distance, we only need something that increases monotonically with distance so we can compare.
    
    // Convert to our bounds coords...
    p = [self convertPoint:p fromView:[self superview]];
    // ... and to the system we mostly draw in
    CGRect f = self.bounds;
    p.y = (2 * f.origin.y) + f.size.height - p.y;
    
    CGFloat dy;
    
    if (p.y < 0) {
        dy = -p.y;
    } else if (p.y > ascent) {
        dy = ascent - p.y;
    } else {
        dy = 0;
    }

    return ( dy*dy ) + ( p.x * p.x );
}

- (void)_dragged:(UIPanGestureRecognizer *)gestureRecognizer;
{
    OUIEditableFrame *parent = (OUIEditableFrame *)(self.superview);
    UIGestureRecognizerState st = gestureRecognizer.state;
    CGPoint delta = [gestureRecognizer translationInView:parent];
 
    // UIPanGestureRecognizer seems to be kind of sloppy about its initial offset. Not sure if this'll be a problem in practice but it's noticeable in the simulator. Might need to do our own translation calculations.
    // NSLog(@"pan: %@, delta=%@", gestureRecognizer, NSStringFromCGPoint(delta));
    
    if (st == UIGestureRecognizerStateBegan) {
        CGRect myBounds = self.bounds;
        /* The point below is the center of the caret rectangle we draw. We want to use that rather than the baseline point or the thumb point to allow the maximum finger slop before the text view selects a different line. */
        touchdownPoint = [self convertPoint:(CGPoint){0, 2 * myBounds.origin.y + myBounds.size.height - ascent/2} toView:parent];
        [parent thumbBegan:self];
    }

    /* UIPanGestureRecognizer will return a delta of { -NAN, -NAN } sometimes (if it would be outside the parent view's bounds maybe?). */
    if ((isfinite(delta.x) && isfinite(delta.y)) &&
        (st != UIGestureRecognizerStateBegan || !(delta.x == 0 && delta.y == 0))) {
        [parent thumbMoved:self targetPosition:(CGPoint){ touchdownPoint.x + delta.x, touchdownPoint.y + delta.y }];
    }
    
    if (st == UIGestureRecognizerStateEnded || st == UIGestureRecognizerStateCancelled) {
        [parent thumbEnded:self normally:(st == UIGestureRecognizerStateEnded? YES:NO)];
        touchdownPoint = (CGPoint){ NAN, NAN };
    }
}

@end


