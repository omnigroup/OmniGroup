// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUITextThumb.h"

#import <OmniUI/OUIEditableFrame.h>

#import <OmniQuartz/OQDrawing.h>
#import <QuartzCore/QuartzCore.h>
#import <OmniBase/rcsid.h>


#define THUMB_TOP_GAP (-2)     // The gap between the thumb image and the caret bar (pixels)
#define THUMB_BOT_GAP ( 0)     // Same, for the end-thumb
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
@synthesize editor = nonretained_editor;

- (void)setCaretRectangle:(CGRect)r;
{
    // Caret rect is supplied in our superview's bounds coordinates
    if (self.superview != nonretained_editor)
        r = [nonretained_editor convertRect:r toView:[self superview]];
    
    // Caret rect is now in our frame coordinates
    CGRect frame = self.frame;
    CGFloat belowCaret;
    
    if (ascent != r.size.height || width != r.size.width) {
        ascent = r.size.height;
        width = r.size.width;
        
        CGRect newBounds;
        
        newBounds.size.width = 2 * THUMB_TOUCH_RADIUS; // Assuming this is the largest length we worry about (else, do some MAX() calls here)
        newBounds.origin.x = - THUMB_TOUCH_RADIUS;
        
        // How far past the end of the caret does the touch radius extend?
        // (This is the same for start and end thumbs - it extends past the bottom or top of the caret respectively)
        CGFloat pastCaret = MAX(0, THUMB_TOUCH_RADIUS - ascent);
        
        // Our height: the touch radius at the knob end of the caret, the ascent, and any touch radius past the other end of the caret
        newBounds.size.height = THUMB_TOUCH_RADIUS + ascent + pastCaret;
        
        // Work out our bounds rect: place Y=0 at the bottom of the caret rect
        // Note we're working in a Y-increases-downwards coordinate system here, so the bottom is at +ascent
        if (isEndThumb) {
            // Thumb dot is below caret rect
            newBounds.origin.y = - ( ascent + pastCaret );
        } else {
            // Thumb dot is above caret rect
            newBounds.origin.y = - ( ascent + THUMB_TOUCH_RADIUS );
        }
        
        newBounds = CGRectIntegral(newBounds);
        
        frame.size = newBounds.size;
        self.bounds = newBounds;
        // NSLog(@"Thumb(%d): caret rect is %@ -> bounds are %@", (int)isEndThumb, NSStringFromCGRect(r), NSStringFromCGRect(newBounds));
        [self setNeedsDisplay];
        
        belowCaret = CGRectGetMinY(newBounds);
    } else {
        belowCaret = CGRectGetMinY(self.bounds);
    }
    
    // Our frame is always in Y-increases-downwards coordinates
    frame.origin.x = r.origin.x - THUMB_TOUCH_RADIUS + round(width / 2);
    frame.origin.y = CGRectGetMaxY(r) + belowCaret;
    
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
#ifdef DEBUG_THUMB_GRABBY
    CGRect viewBounds = self.bounds;
    
    CGContextSetRGBFillColor(cgContext, 1.0, 0.5, 0.5, 0.125);
    CGContextFillRect(cgContext, viewBounds);
    CGContextSetRGBFillColor(cgContext, isEndThumb?1:0, isEndThumb?0:1, 0, 1);
    CGContextFillRect(cgContext, (CGRect){ {viewBounds.origin.x, 0}, {viewBounds.size.width, 1} });
#endif    
    
    CGContextSetAlpha(cgContext, 1.0);
    
    UIImage *thumbImage = [UIImage imageNamed:@"OUITextSelectionHandle.png"];
    
    /* Divide our area into three stacked rectangles: the thumb circle, the vertical caret-like line attached to it, and the small gap between them */
    CGRect thumbRect, caretRect;
    thumbRect.size = [thumbImage size];
    thumbRect.origin.x = - floor(thumbRect.size.width / 2);
    caretRect.size.width = width;
    caretRect.size.height = ascent;
    caretRect.origin.x = - floor(width / 2);
    caretRect.origin.y = - ascent;
    if (isEndThumb) {
        // The knob image is below the caret
        thumbRect.origin.y = 0 + THUMB_BOT_GAP;
    } else {
        // The knob image is above the caret
        thumbRect.origin.y = - ( ascent + thumbRect.size.height ) - THUMB_TOP_GAP;
    }
    
    /* Inset the thumb rect to allow for the portion of the stroke that goes outside the rect */
    
    CGContextSetFillColorWithColor(cgContext, self.editor.selectionColor.CGColor);
    CGContextFillRect(cgContext, caretRect);
    
    
    [thumbImage drawAtPoint:thumbRect.origin];
}

- (CGFloat)distanceFromPoint:(CGPoint)p;
{
    // Not a true distance, we only need something that increases monotonically with distance so we can compare.
    
    // Convert to our bounds coords...
    p = [self convertPoint:p fromView:nonretained_editor];
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
    OUIEditableFrame *editor = nonretained_editor;
    UIGestureRecognizerState st = gestureRecognizer.state;
    CGPoint delta = [gestureRecognizer translationInView:editor];
 
    // UIPanGestureRecognizer seems to be kind of sloppy about its initial offset. Not sure if this'll be a problem in practice but it's noticeable in the simulator. Might need to do our own translation calculations.
    // NSLog(@"pan: %@, delta=%@", gestureRecognizer, NSStringFromCGPoint(delta));
    
    if (st == UIGestureRecognizerStateBegan) {
        /* The point below is the center of the caret rectangle we draw. We want to use that rather than the baseline point or the thumb point to allow the maximum finger slop before the text view selects a different line. */
        touchdownPoint = [self convertPoint:(CGPoint){0, - ascent/2} toView:editor];
        [editor thumbBegan:self];
    }

    /* UIPanGestureRecognizer will return a delta of { -NAN, -NAN } sometimes (if it would be outside the parent view's bounds maybe?). */
    if ((isfinite(delta.x) && isfinite(delta.y)) &&
        (st != UIGestureRecognizerStateBegan || !(delta.x == 0 && delta.y == 0))) {
        [editor thumbMoved:self targetPosition:(CGPoint){ touchdownPoint.x + delta.x, touchdownPoint.y + delta.y }];
    }
    
    if (st == UIGestureRecognizerStateEnded || st == UIGestureRecognizerStateCancelled) {
        [editor thumbEnded:self normally:(st == UIGestureRecognizerStateEnded? YES:NO)];
        touchdownPoint = (CGPoint){ NAN, NAN };
    }
}

@end


