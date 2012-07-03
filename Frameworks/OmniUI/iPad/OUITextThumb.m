// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUITextThumb.h"

#import <OmniQuartz/OQDrawing.h>
#import <QuartzCore/QuartzCore.h>
#import <OmniBase/rcsid.h>
#import <OmniUI/OUIDragGestureRecognizer.h>

#import "OUIEditableFrame-Internal.h"

#define THUMB_TOP_GAP (-2)     // The gap between the thumb image and the caret bar (pixels)
#define THUMB_BOT_GAP ( 0)     // Same, for the end-thumb
#define THUMB_TOUCH_RADIUS 35  // How many pixels from the ring should we be sensitive to touches?

//#define DEBUG_THUMB_GRABBY

RCS_ID("$Id$");

@interface OUITextThumb () <UIGestureRecognizerDelegate>
@end

@implementation OUITextThumb
{
    OUIDragGestureRecognizer *_touchRecognizer;
}

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
    
    // This recognizer handles long-press to unconditionally show the loupe and dragging to adjust the handle.
    // We could probably make this handle taps too, but that would complicate the code w/o any significant savings.
    OUIDragGestureRecognizer *dragRecognizer = [[OUIDragGestureRecognizer alloc] initWithTarget:self action:@selector(_dragged:)];
    dragRecognizer.holdDuration = 0.5; // fire if held long enough, even if we didn't start dragging. taken from UILongPressGestureRecognizer.h
    dragRecognizer.numberOfTouchesRequired = 1;
    dragRecognizer.delaysTouchesBegan = YES;
    dragRecognizer.enabled = NO; // Will be enabled & disabled in our -setHidden: implementation
    dragRecognizer.delegate = self;
    [self addGestureRecognizer:dragRecognizer];
    [dragRecognizer release];

    // A tap on a thumb should transition from range selection to caret selection
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tapped:)];
    tapRecognizer.enabled = NO; // Will be enabled & disabled in our -setHidden: implementation
    tapRecognizer.delegate = self;
    [self addGestureRecognizer:tapRecognizer];
    [tapRecognizer release];

    // Add *another* recognizer that just tells us immediately when we are being touched and let this run concurrently with the other two. This will let us hide the system menu before the system automatically does it so that our workarounds in OUIEditMenuController have a chance.
    _touchRecognizer = [[OUIDragGestureRecognizer alloc] initWithTarget:self action:@selector(_touched:)];
    _touchRecognizer.holdDuration = 0.0001; // Zero means it won't auto-start, but we want a short delay to be effectively immediately. We are competing with the timer in OUIEditMenuController for re-showing the menu after the system has finished hiding one (currently 0.1s). Terrible.
    _touchRecognizer.numberOfTouchesRequired = 1;
    _touchRecognizer.enabled = NO; // Will be enabled & disabled in our -setHidden: implementation
    _touchRecognizer.delegate = self;
    [self addGestureRecognizer:_touchRecognizer];

    return self;
}

- (void)dealloc;
{
    _touchRecognizer.delegate = nil;
    [_touchRecognizer release];
    _touchRecognizer = nil;
    
    [super dealloc];
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

#pragma mark - UIView subclass

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

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer;
{
    if (gestureRecognizer == _touchRecognizer || otherGestureRecognizer == _touchRecognizer)
        return YES;
    
    return NO;
}

#pragma mark - Private

- (void)_tapped:(UITapGestureRecognizer *)gestureRecognizer;
{
    OBPRECONDITION(nonretained_editor);
    
    OUIEditableFrame *editor = nonretained_editor;
    [editor thumbTapped:self recognizer:gestureRecognizer];
}

- (void)_dragged:(OUIDragGestureRecognizer *)recognizer;
{
    OBPRECONDITION(nonretained_editor);
    
    OUIEditableFrame *editor = nonretained_editor;
    UIGestureRecognizerState st = recognizer.state;
 
    if (st == UIGestureRecognizerStateBegan) {
        /* The point below is the center of the caret rectangle we draw. We want to use that rather than the baseline point or the thumb point to allow the maximum finger slop before the text view selects a different line. */
        touchdownPoint = [self convertPoint:(CGPoint){0, - ascent/2} toView:editor];
        [editor thumbDragBegan:self];
    }

    if (st == UIGestureRecognizerStateEnded || st == UIGestureRecognizerStateCancelled) {
        [editor thumbDragEnded:self normally:(st == UIGestureRecognizerStateEnded? YES:NO)];
        touchdownPoint = (CGPoint){ NAN, NAN };
    } else {
        // We send 'moved' on either a moved or a began, which is what we want. A long press on a handle should show the loupe, not wait for the first drag (though we could maybe rename this method to be less confusing for this change in behavior).
        CGPoint delta = [recognizer cumulativeOffsetInView:editor];
        [editor thumbDragMoved:self targetPosition:(CGPoint){ touchdownPoint.x + delta.x, touchdownPoint.y + delta.y }];
    }
}

- (void)_touched:(OUIDragGestureRecognizer *)recognizer;
{
    OBPRECONDITION(nonretained_editor);
    
    OUIEditableFrame *editor = nonretained_editor;
    UIGestureRecognizerState st = recognizer.state;

    if (st == UIGestureRecognizerStateBegan)
        [editor thumbTouchBegan:self];
    else if (st == UIGestureRecognizerStateEnded || st == UIGestureRecognizerStateCancelled)
        [editor thumbTouchEnded:self];
}

@end


