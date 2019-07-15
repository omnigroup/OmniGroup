// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUILoupeOverlay.h>

#import <OmniUI/OUIScalingView.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OUILoupeOverlay
{
    OUILoupeMode _mode;           // What kind of loupe we're displaying
    CGPoint _touchPoint;          // The point (in our subject view's bounds coordinates) to display
    CGFloat _scale;               // How much to magnify the subject view
    __weak OUIScalingView <OUILoupeOverlaySubject> *_weak_subjectView;  // If not set, self.superview is used for the subject of display
    
    // These are updated based on the mode
    UIImage *loupeFrameImage;   // The border image to draw around the zoomed view region
    CGRect loupeFramePosition;  // The frame of the above image, expressed with (0,0) at the (unmagnified) touch point
    CGPathRef loupeClipPath;    // The clip-path into which to draw the zoomed view region, in our bounds coordinate system
    CGPoint loupeTouchPoint;    // The point in our bounds coordinate system at which (magnified) _touchPoint should be made to draw
    UIImage *loupeTabImage;     // Additional image to draw, may be nil
    CGPoint loupeTabPosition;   // The offset of loupeTabImage w.r.t. the origin of loupeFrameImage
}

#define OUILoupeDismissedTransform (CGAffineTransform){ 0.0625, 0, 0, 0.25, 0, 0 };

// These are relevant dimensions of the images we use for the rectangular loupe.
// (We used to try to base everything off the image dimensions, but we do a bunch of stretching and tweaking now.)
#define RectLoupeSideCapWidth    15       // Side cap width, for stretching.
#define RectLoupeTopCapHeight    22       // Top cap width, for stretching.
#define RectLoupeSideInset        5       // Distance from image sides to the clippath we should use for the content.
#define RectLoupeTopInset         2       // Distance from image top to the clippath
#define RectLoupeBottomInset     20       // Distance from image bottom to the clippath
#define RectLoupeSideArrowStandoff  15    // How close the edge of the arrow image is allowed to get to the side of the frame image

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
    if (loupeClipPath)
        CFRelease(loupeClipPath);
}

@synthesize subjectView = _weak_subjectView;

/* Set the touch point, which is in the subject view's bounds coordinate system */
- (void)setTouchPoint:(CGPoint)touchPoint;
{
    OUIScalingView <OUILoupeOverlaySubject> *subjectView = _weak_subjectView;
    
    _touchPoint = touchPoint;
    CGPoint indicatedPoint = touchPoint; // Same, for now
    
    if (_mode == OUILoupeOverlayNone) {
        /* The "none" mode is special-cased because we don't want to clear out the old image and frame while dismissing the loupe. So the loupeFramePosition values probably refer to a previous mode's geometry here. */
        
        CGPoint centerPoint = touchPoint;
        if (subjectView)
            centerPoint = [subjectView convertPoint:centerPoint toView:[self superview]];
        
        self.center = centerPoint;
    } else {
        CGRect newFrame;
        
        if (_mode == OUILoupeOverlayRectangle)
            loupeFramePosition.origin.x = loupeTouchPoint.x;
        
        newFrame.origin.x = round(indicatedPoint.x - loupeFramePosition.origin.x);
        newFrame.origin.y = round(indicatedPoint.y - loupeFramePosition.origin.y);
        newFrame.size = loupeFramePosition.size;
        
        /* The "rectangle" mode is slightly flexible */
        if (_mode == OUILoupeOverlayRectangle) {
            CGRect allowedFrame = CGRectInset([[self superview] bounds], -4, -2);
            if (subjectView)
                allowedFrame = [subjectView convertRect:allowedFrame fromView:[self superview]];
            
            if (loupeTabImage) {
                CGSize loupeTabSize = loupeTabImage.size;
                CGFloat tabHalfWidth = floor(loupeTabSize.width / 2);
                
                if (newFrame.origin.x < allowedFrame.origin.x) {
                    loupeFramePosition.origin.x = MAX(indicatedPoint.x - allowedFrame.origin.x,
                                                      RectLoupeSideArrowStandoff + tabHalfWidth);
                } else if (CGRectGetMaxX(newFrame) > CGRectGetMaxX(allowedFrame)) {
                    loupeFramePosition.origin.x = MIN(indicatedPoint.x + newFrame.size.width - CGRectGetMaxX(allowedFrame),
                                                      newFrame.size.width - RectLoupeSideArrowStandoff - loupeTabSize.width + tabHalfWidth);
                }
                
                newFrame.origin.x = round(indicatedPoint.x - loupeFramePosition.origin.x);
                newFrame.origin.y = round(indicatedPoint.y - loupeFramePosition.origin.y);
                loupeTabPosition.x = loupeFramePosition.origin.x - tabHalfWidth;
            }
        }

        if (subjectView)
            newFrame = [(OUIScalingView *)subjectView convertRect:newFrame toView:[self superview]];
        
        self.frame = newFrame;
    }

    // Need to redisplay because our contents depend on the touch point
    [self setNeedsDisplay];
}

@synthesize touchPoint = _touchPoint;

/* Set the mode of the loupe */
- (void)setMode:(OUILoupeMode)newMode
{
    if (newMode == _mode)
        return;
    
    OUIScalingView <OUILoupeOverlaySubject> *subjectView = _weak_subjectView;

    [self willChangeValueForKey:@"mode"];

    Class animatorClass = [self class];
    BOOL wereAnimationsEnabled = [animatorClass areAnimationsEnabled];

    OUILoupeMode oldMode = _mode;
    
    if (oldMode == OUILoupeOverlayNone) {
        // We're bringing the loupe onscreen
        // Make sure it's in front of everything else
        [self.superview bringSubviewToFront:self];
        
        // And make sure it animates from the current location, instead of the previous location
        [animatorClass setAnimationsEnabled:NO];
        [animatorClass animateWithDuration:0.2 animations:^{
            CGPoint centerPoint = _touchPoint;
            if (subjectView)
                centerPoint = [(OUIScalingView *)subjectView convertPoint:centerPoint toView:[self superview]];
            self.center = centerPoint;
            self.transform = OUILoupeDismissedTransform;
            self.alpha = 1;
        }];
    }

    _mode = newMode;
    [self didChangeValueForKey:@"mode"];

    // Adjust location for new size, touch point, whatever might have changed
    [self setTouchPoint:_touchPoint];

    [animatorClass setAnimationsEnabled:YES];
    [animatorClass animateWithDuration:0.2 delay:0 options:(_mode == OUILoupeOverlayNone)? UIViewAnimationOptionBeginFromCurrentState : kNilOptions animations:^{
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
                loupeFrameImage = nil;
            }
            if (loupeTabImage) {
                loupeTabImage = nil;
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
                    loupeFrameImage = [UIImage imageNamed:@"OUITextSelectionOverlay.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
                    CGSize loupeImageSize = [loupeFrameImage size];

                    CGMutablePathRef ring = CGPathCreateMutable();
                    CGPathAddEllipseInRect(ring, NULL, CGRectInset((CGRect){{0, 0}, loupeImageSize}, 6, 6));
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
                    UIImage *plainImage = [UIImage imageNamed:@"OUIRectangularOverlayFrame.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
                    loupeFrameImage = [plainImage stretchableImageWithLeftCapWidth:RectLoupeSideCapWidth
                                                                      topCapHeight:RectLoupeTopCapHeight];
                    if (!loupeTabImage)
                        loupeTabImage = [UIImage imageNamed:@"OUIRectangularOverlayArrow.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
                    CGSize loupeImageSize;
                    loupeImageSize = [plainImage size];
                    loupeImageSize.width = 207;
#if 0
                    // We can make the loupe taller or wider by stretching it here
                    loupeImageSize.height += 78.0f;
#endif
                    CGRect contour = (CGRect){ {RectLoupeSideInset, RectLoupeTopInset},
                        { loupeImageSize.width - 2*RectLoupeSideInset,
                            loupeImageSize.height - (RectLoupeTopInset+RectLoupeBottomInset) } };
                    // This should form a rounded rect within the image
                    CGMutablePathRef ring = CGPathCreateMutable();
                    OQAddRoundedRect(ring, contour, 6.0f);
                    loupeClipPath = CGPathCreateCopy(ring);
                    CFRelease(ring);
                    loupeTouchPoint.x = CGRectGetMidX(contour);
                    loupeTouchPoint.y = CGRectGetMidY(contour);
                    loupeFramePosition.size = loupeImageSize;
                    loupeFramePosition.origin.x = loupeTouchPoint.x;
                    loupeFramePosition.origin.y = loupeImageSize.height + 20;
                    if (loupeTabImage) {
                        CGSize tabSize = [loupeTabImage size];
                        loupeTabPosition.x = loupeTouchPoint.x - floor(tabSize.width / 2);
                        loupeTabPosition.y = loupeImageSize.height - tabSize.height;
                    }
                    break;
                }
            }

            self.alpha = 1;

            if (oldMode == OUILoupeOverlayNone)
                [animatorClass setAnimationsEnabled:NO];
            self.bounds = (CGRect){ .origin = { 0,0 }, .size = loupeFramePosition.size };
        }
    } completion:^(BOOL finished) {
        [animatorClass setAnimationsEnabled:wereAnimationsEnabled];
    }];
}

@synthesize mode = _mode;

/* Scaling factor applied to the view as seen through the loupe */
@synthesize scale = _scale;

#pragma mark UIView methods

- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    OUIScalingView <OUILoupeOverlaySubject> *subject = _weak_subjectView;
    if (!subject)
        subject = (OUIScalingView <OUILoupeOverlaySubject> *)self.superview;

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
        
        CGAffineTransform subjectTransform = [subject transformFromViewSpaceToUnscaledSpace];
        CGAffineTransform loupeTransform;
        loupeTransform.a = _scale;
        loupeTransform.b = 0;
        loupeTransform.c = 0;
        loupeTransform.d = _scale;
        loupeTransform.tx = round(loupeTouchPoint.x - _touchPoint.x * loupeTransform.a);
        loupeTransform.ty = round(loupeTouchPoint.y - _touchPoint.y * loupeTransform.d);
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
            
            
#if 0 && defined(DEBUG)
            // Fill the content area with red to help make sure the opaque edge of the loupe image will cover the edge of the clip path
            CGContextSaveGState(ctx);
            [[UIColor redColor] set];
            CGContextFillRect(ctx, drawRect);
            CGContextRestoreGState(ctx);
#else
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
            
            if ([subject respondsToSelector:@selector(drawScaledContentForLoupe:)])
                [subject drawScaledContentForLoupe:[subject convertRectFromUnscaledSpaceToViewSpace:drawRect]];
            else
                [subject drawScaledContent:[subject convertRectFromUnscaledSpaceToViewSpace:drawRect]];
#endif
        }
    }
    CGContextRestoreGState(ctx);

    /* Draw the border image */
    if (loupeFrameImage)
        [loupeFrameImage drawInRect:bounds];
    if (loupeTabImage) {
        [loupeTabImage drawAtPoint:(CGPoint){ bounds.origin.x + loupeTabPosition.x,
                                              bounds.origin.y + loupeTabPosition.y }
                         blendMode:kCGBlendModeCopy alpha:1.0];
    }

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
