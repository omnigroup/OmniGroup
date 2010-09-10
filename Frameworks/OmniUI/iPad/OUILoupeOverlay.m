// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUILoupeOverlay.h"

#import <OmniUI/OUIScalingView.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OUILoupeOverlay

#define OUILoupeDismissedTransform (CGAffineTransform){ 0.0625, 0, 0, 0.25, 0, 0 };

- initWithFrame:(CGRect)frame;
{
    if ((self = [super initWithFrame:frame]) != nil) {
        self.opaque = NO;
        self.backgroundColor = nil;
        self.clearsContextBeforeDrawing = YES;
        self.contentMode = UIViewContentModeScaleAspectFit;

        _mode = OUILoupeOverlayNone;
        _touchPoint = (CGPoint){ 0, 0 };
        _scale = 1.25;
        
        self.alpha = 0;
        self.transform = OUILoupeDismissedTransform;
    }
    return self;
}

- (void)dealloc
{
    [loupeFrameImage release];
    loupeFrameImage = nil;
    if (loupeClipPath) {
        CFRelease(loupeClipPath);
        loupeClipPath = NULL;
    }
    [super dealloc];
}

@synthesize subjectView;

/* Set the touch point, which is in the subject view's bounds coordinate system */
- (void)setTouchPoint:(CGPoint)touchPoint;
{
    if (_mode == OUILoupeOverlayNone) {
        /* The "none" mode is special-cased because we don't want to clear out the old image and frame while dismissing the loupe. So the loupeFramePosition values probably refer to a previous mode's geometry here. */

        CGPoint centerPoint = touchPoint;
        if (subjectView)
            centerPoint = [(OUIScalingView *)subjectView convertPoint:centerPoint toView:[self superview]];
        
        self.center = centerPoint;
    } else {
        CGRect newFrame;
        newFrame.origin.x = round(touchPoint.x - loupeFramePosition.origin.x);
        newFrame.origin.y = round(touchPoint.y - loupeFramePosition.origin.y);
        newFrame.size = loupeFramePosition.size;
        
        if (subjectView)
            newFrame = [(OUIScalingView *)subjectView convertRect:newFrame toView:[self superview]];
        
        self.frame = newFrame;
    }        
        
    _touchPoint = touchPoint;
    
    // Need to redisplay because our contents depend on the touch point
    [self setNeedsDisplay];
}

@synthesize touchPoint = _touchPoint;

/* Set the mode of the loupe */
- (void)setMode:(OUILoupeMode)newMode
{
    if (newMode == _mode)
        return;
    
    [self willChangeValueForKey:@"mode"];
    
    if (_mode == OUILoupeOverlayNone) {
        // We're bringing the loupe onscreen
        // Make sure it's in front of everything else
        [self.superview bringSubviewToFront:self];
    }
    
    [[self class] beginAnimations:@"OUILoupeOverlay" context:NULL];
    [[self class] setAnimationBeginsFromCurrentState: (_mode == OUILoupeOverlayNone)? NO : YES];
    _mode = newMode;
    
    if (newMode == OUILoupeOverlayNone) {
        /* Okay, we actually leave our various mode settings alone when going to mode=none, because we want to keep displaying the last mode's contents as we animate out of existence. */
        
        /* Shrink and fade the loupe */
        self.transform = OUILoupeDismissedTransform;
        
        self.alpha = 0;
    } else {
        if (loupeClipPath) {
            CFRelease(loupeClipPath);
            loupeClipPath = NULL;
        }
        if (loupeFrameImage) {
            [loupeFrameImage release];
            loupeFrameImage = nil;
        }
        
        // Reset any transform applied when we dismissed it
        self.transform = (CGAffineTransform){ 1, 0, 0, 1, 0, 0 };

        switch (newMode) {
            case OUILoupeOverlayNone:
            default:
                loupeFramePosition.origin.x = 0;
                loupeFramePosition.origin.y = 0;
                loupeFramePosition.size.width = 0;
                loupeFramePosition.size.height = 0;
                loupeTouchPoint.x = 0;
                loupeTouchPoint.y = 0;
                self.alpha = 0;
                break;
            case OUILoupeOverlayCircle:
            {
                loupeFrameImage = [[UIImage imageNamed:@"OUITextSelectionOverlay.png"] retain];
                CGMutablePathRef ring = CGPathCreateMutable();
                CGSize loupeImageSize;
                loupeImageSize = [loupeFrameImage size];
                CGPathAddEllipseInRect(ring, NULL, CGRectInset((CGRect){{0, 0}, loupeImageSize}, 4, 4));
                loupeClipPath = CGPathCreateCopy(ring);
                CFRelease(ring);
                loupeFramePosition.size = loupeImageSize;
                loupeFramePosition.origin.x = loupeImageSize.width / 2;
                loupeFramePosition.origin.y = loupeImageSize.height;  // + 30;
                loupeTouchPoint.x = loupeImageSize.width / 2;
                loupeTouchPoint.y = loupeImageSize.height / 2;
                break;
            }
            case OUILoupeOverlayRectangle:
            {
                UIImage *plainImage = [UIImage imageNamed:@"OUIRectangularOverlayFrame.png"];
                loupeFrameImage = [[plainImage stretchableImageWithLeftCapWidth:0 topCapHeight:22] retain];
                CGSize loupeImageSize;
                loupeImageSize = [plainImage size];
                CGRect contour = (CGRect){ {5.0f, 2.0f}, { 197.0f, 36.0f } }; // This should form a rounded rect within the image
#if 0
                // We can make the loupe taller by stretching it here
                loupeImageSize.height += 78.0f;
                contour.size.height += 78.0f;
#endif
                CGMutablePathRef ring = CGPathCreateMutable();
                OQAddRoundedRect(ring, contour, 6.0f);
                loupeClipPath = CGPathCreateCopy(ring);
                CFRelease(ring);
                loupeTouchPoint.x = CGRectGetMidX(contour);
                loupeTouchPoint.y = CGRectGetMidY(contour);
                loupeFramePosition.size = loupeImageSize;
                loupeFramePosition.origin.x = loupeTouchPoint.x;
                loupeFramePosition.origin.y = loupeImageSize.height + 20;
                break;
            }
        }
        
        self.bounds = (CGRect){ .origin = { 0,0 }, .size = loupeFramePosition.size };
        self.alpha = 1;
    }
    
    // Adjust location for new size, touch point, whatever might have changed
    [self setTouchPoint:_touchPoint];
    
    [[self class] commitAnimations];
    
    [self didChangeValueForKey:@"mode"];
}

@synthesize mode = _mode;

/* Scaling factor applied to the view as seen through the loupe */
@synthesize scale = _scale;

#pragma mark UIView methods

- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    OUIScalingView <OUILoupeOverlaySubject> *subject = (subjectView) ? (subjectView) : (OUIScalingView <OUILoupeOverlaySubject> *)(self.superview);

    /* First draw the contents of the subject view */
    CGContextSaveGState(ctx);
    {
        /* Clip to the transparent region of the loupe image */
        if (loupeClipPath) {
            CGContextBeginPath(ctx);
            CGContextAddPath(ctx, loupeClipPath);
            CGContextClip(ctx);
        }
        
        /* We want the touchPoint in the subject view to end up at our loupeTouchPoint point (typically the center of our loupe clip path). */
        
        /* Our _touchPoint ivar is expressed in our subject's bounds coordinate system (usually == our frame coordinate system). */
        
        CGAffineTransform subjectTransform = [subject transformToRenderingSpace];
        CGAffineTransform loupeTransform;
        loupeTransform.a = _scale;
        loupeTransform.b = 0;
        loupeTransform.c = 0;
        loupeTransform.d = _scale;
        loupeTransform.tx = loupeTouchPoint.x - _touchPoint.x * loupeTransform.a;
        loupeTransform.ty = loupeTouchPoint.y - _touchPoint.y * loupeTransform.d;
        loupeTransform = CGAffineTransformConcat(subjectTransform, loupeTransform);
        CGContextConcatCTM(ctx, loupeTransform);

        /* We can't actually make a patterned background work perfectly because of the scaling, but adjusting the pattern phase here will at least keep the background from appearing to skid around when the loupe is moved. */
        CGContextSetPatternPhase(ctx, (CGSize){ loupeTransform.tx, loupeTransform.ty });
        
        /* Compute the rectangle to pass on to the subject view */
        CGRect drawRect;
        if (loupeClipPath) {
            drawRect = CGRectIntersection(bounds, CGPathGetBoundingBox(loupeClipPath));
        } else {
            drawRect = bounds;
        }
        if (!CGRectIsNull(rect))
            drawRect = CGRectIntersection(drawRect, rect);
        // Snap to integer coordinates in our bounds coordinate system, since that's the one in which rasterization is happening
        drawRect = CGRectIntegral(drawRect);
        
        if (!CGRectIsEmpty(drawRect)) {
            // Convert the rect to the coordinate system seen by -drawScaledContent:
            drawRect = CGRectApplyAffineTransform(drawRect, CGAffineTransformInvert(loupeTransform));
            
            if (!subject.opaque) {
                if ([subject respondsToSelector:@selector(drawLoupeOverlayBackgroundInRect:)])
                    [subject drawLoupeOverlayBackgroundInRect:drawRect];
                else {
                    UIColor *backgroundColor = nil;
                    
                    if ([subject respondsToSelector:@selector(loupeOverlayBackgroundColor)])
                        backgroundColor = [subject loupeOverlayBackgroundColor];

                    if (!backgroundColor)
                        backgroundColor = [UIColor whiteColor];
                    
                    [backgroundColor setFill];
                    CGContextFillRect(ctx, drawRect);
                }
            }
            
            [subject drawScaledContent:drawRect];
        }
    }
    CGContextRestoreGState(ctx);

    /* Draw the border image */
    if (loupeFrameImage)
        [loupeFrameImage drawInRect:bounds];

#if 0 && defined(DEBUG_wiml)
    // Debug helper. This redraws the clip path on top of the image to help make sure it is lined up right.
    CGContextBeginPath(ctx);
    CGContextAddPath(ctx, loupeClipPath);
    [[UIColor redColor] setStroke];
    CGContextSetLineWidth(ctx, 1.0);
    CGContextStrokePath(ctx);
    
    // Also note the touch point
    CGPoint tp = [subject convertPoint:_touchPoint toView:self];
    CGContextStrokeEllipseInRect(ctx, (CGRect){{tp.x - 2, tp.y - 2}, { 4, 4 }});
#endif
}

@end
