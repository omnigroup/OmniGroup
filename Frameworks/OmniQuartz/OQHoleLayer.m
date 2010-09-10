// Copyright 2000-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQHoleLayer.h>

#import <OmniQuartz/CALayer-OQExtensions.h>
#import <OmniQuartz/OQGradient.h>

RCS_ID("$Id$");

@implementation OQHoleLayer

static const CGFloat kShadowRadius = 40.0f;

static void _drawInnerShadow(CGContextRef ctx, CGRect bounds, NSUInteger shadowEdgeMask)
{
#if 0
    CGColorRef white = CGColorCreateGenericRGB(1, 1, 1, 1);
    CGContextSetFillColorWithColor(ctx, white);
    CGContextFillRect(ctx, bounds);
    CGColorRelease(white);
#else
    CGContextClearRect(ctx, bounds);
#endif
    
    CGContextAddRect(ctx, NSInsetRect(bounds, -4*kShadowRadius, -4*kShadowRadius));
    
    // Set up a path outside our bounds so the shadow will be cast into the bounds but no fill.  Push each edge out based on whether we want a shadow on that edge.  If we do, 
    CGRect interiorRect = bounds;
    CGFloat noShadowOutset = 2*kShadowRadius;
    
    if ((shadowEdgeMask & (1<<NSMinXEdge)) == 0) {
        interiorRect.origin.x -= noShadowOutset;
        interiorRect.size.width += noShadowOutset;
    }
    if ((shadowEdgeMask & (1<<NSMinYEdge)) == 0) {
        interiorRect.origin.y -= noShadowOutset;
        interiorRect.size.height += noShadowOutset;
    }
    if ((shadowEdgeMask & (1<<NSMaxXEdge)) == 0) {
        interiorRect.size.width += noShadowOutset;
    }
    if ((shadowEdgeMask & (1<<NSMaxYEdge)) == 0) {
        interiorRect.size.height += noShadowOutset;
    }
    CGContextAddRect(ctx, interiorRect);
    
    CGColorRef shadowColor = CGColorCreateGenericGray(0.0f, 0.8f);
    CGContextSetShadowWithColor(ctx, NSMakeSize(0, 2)/*offset*/, kShadowRadius, shadowColor);
    CFRelease(shadowColor);
    
    CGContextSetFillColorWithColor(ctx, CGColorGetConstantColor(kCGColorWhite));
    CGContextDrawPath(ctx, kCGPathEOFill);
}

static CALayer *_createEdge(OQHoleLayer *self)
{
    CALayer *layer = [[CALayer alloc] init];
    layer.edgeAntialiasingMask = 0;
    layer.needsDisplayOnBoundsChange = NO;
    layer.anchorPoint = CGPointZero;
    layer.opaque = NO;
    [self addSublayer:layer];
    return layer;
}

- initWithGradientExtent:(OFExtent)gradientExtent shadowEdgeMask:(NSUInteger)shadowEdgeMask;
{
    if (!(self = [super init]))
        return nil;
    
    _shadowEdgeMask = shadowEdgeMask;
    
    // The full gray range we'll use if we get (0,1) as an input.
    OFExtent grayRange = OFExtentFromLocations(0.66f, 0.70f);
    
    // 10.6 has a gradient layer, but we don't on 10.5.
    CGFloat minGray = OFExtentValueAtPercentage(grayRange, OFExtentMin(gradientExtent));
    CGFloat maxGray = OFExtentValueAtPercentage(grayRange, OFExtentMax(gradientExtent));
    _gradient = OQCreateVerticalGrayGradient(minGray, maxGray);
    
    self.needsDisplayOnBoundsChange = YES;
    self.anchorPoint = CGPointZero;
    self.edgeAntialiasingMask = 0; // Default to no anti-aliasing

    self.masksToBounds = YES;
    
    // Add four sublayers that we'll size/fill in -layoutSubviews. We need to know how big we are before deciding how to best to render.
    
    // Set up 4 layers with right contentsRect and autosizing flags. add as sublayers.
    _minXEdge = _createEdge(self);
    _maxXEdge = _createEdge(self);
    _minYEdge = _createEdge(self);
    _maxYEdge = _createEdge(self);
    
    return self;
}

- init;
{
    return [self initWithGradientExtent:OFExtentMake(0, 1) shadowEdgeMask:(1<<NSMinXEdge)|(1<<NSMinYEdge)|(1<<NSMaxXEdge)|(1<<NSMaxYEdge)];
}

- (void)dealloc;
{
    if (_gradient)
        CFRelease(_gradient);
    [_minXEdge release];
    [_maxXEdge release];
    [_minYEdge release];
    [_maxYEdge release];
    [super dealloc];
}

- (void)exposeByExpandingFromRect:(CGRect)originalRect toRect:(CGRect)finalRect inLayer:(CALayer *)parentLayer;
{
    OBPRECONDITION(self.superlayer == nil); // we are doing the expose
    OBPRECONDITION(originalRect.size.width == 0 || originalRect.size.height == 0); // should be expanding from nothing on one axis
    OBPRECONDITION(finalRect.size.width > 0 && finalRect.size.height > 0); // to a rect that isn't empty
    OBPRECONDITION(originalRect.size.width == finalRect.size.width || originalRect.size.height == finalRect.size.height); // ... along only one axis
    
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    {
        // Get set up in the *final* (non-empty) size. This will make our set of layers be right.
        self.position = finalRect.origin;
        self.bounds = CGRectMake(0, 0, finalRect.size.width, finalRect.size.height);
        [self layoutSublayers];
        
        // Switch to the empty version; our zero width/height case keeps around some state based on our original size.
        self.position = originalRect.origin;
        self.bounds = CGRectMake(0, 0, originalRect.size.width, originalRect.size.height);
        [self layoutSublayers];
        
        [parentLayer addSublayer:self];
    }
    [CATransaction commit];
    
    // Now, animate to the final frame.
    self.position = finalRect.origin;
    self.bounds = CGRectMake(0, 0, finalRect.size.width, finalRect.size.height);
}

static NSString * const OQHoleLayerRemoveAtEndOfAnimationKey = @"OQHoleLayerRemoveAtEndOfAnimation";

- (void)removeFromSuperlayerAtEndOfAnimation;
{
    // Add an animation that we understand to indicate we should remove ourselves at its end.  The animation itself make sure we say behind the cell that is going opaque above us.
    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"zPosition"];
    anim.fromValue = [NSNumber numberWithFloat:/*OOOutlineViewColumnDragHoleZPosition*/300];
    anim.toValue = [NSNumber numberWithFloat:/*OOOutlineViewColumnDragHoleZPosition*/300];
    anim.removedOnCompletion = NO;
    anim.fillMode = kCAFillModeForwards;
    anim.timingFunction = [CAMediaTimingFunction functionCompatibleWithDefault];
    anim.delegate = self;
    [self addAnimation:anim forKey:OQHoleLayerRemoveAtEndOfAnimationKey];
}

- (void)removeAfterShrinkingToRect:(CGRect)finalRect;
{
    OBPRECONDITION(self.superlayer != nil); // we are doing the remove
    
#ifdef OMNI_ASSERTIONS_ON
    {    
        CGRect originalRect = self.bounds;
        OBPRECONDITION(originalRect.size.width > 0 && originalRect.size.height > 0); // should be hiding non-zero rect
        OBPRECONDITION(finalRect.size.width == 0 || finalRect.size.height == 0); // to a rect that that is thin
        OBPRECONDITION(originalRect.size.width == finalRect.size.width || originalRect.size.height == finalRect.size.height); // ... along only one axis
    }
#endif

    self.position = finalRect.origin;
    self.bounds = CGRectMake(0, 0, finalRect.size.width, finalRect.size.height);

    [self removeFromSuperlayerAtEndOfAnimation];
}

#pragma mark CAAnimation delegate

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag;
{
    OBPRECONDITION(![[[self class] superclass] instancesRespondToSelector:_cmd]);

    if ([self animationForKey:OQHoleLayerRemoveAtEndOfAnimationKey] == anim) {
        // We are likely only retained by our superlayer.
        [[self retain] autorelease];

        [CATransaction begin];
        [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
        [self removeFromSuperlayer];
        [CATransaction commit];

        [self removeAnimationForKey:OQHoleLayerRemoveAtEndOfAnimationKey]; // break the retain cycle; apparently CAAnimation retains its delegate
    } else {
        OBASSERT_NOT_REACHED("Unknown animation finished");
    }
}

#pragma mark CALayer subclass

static CGImageRef _createShadowImageWithSize(CGSize size, NSUInteger shadowEdgeMask)
{
#if 0 // alpha only doesn't seem to work right. it seems like they have an off-by-one error since we get a diagonalized pattern with garbage at the end in this case. Either that, or something is goofy with bytesPerRow in this case (this was with a 70x120 image).
    size_t componentCount = 1;
    CGImageAlphaInfo alphaInfo = kCGImageAlphaOnly;
    CFStringRef colorSpaceName = kCGColorSpaceGenericGray;
#else
    size_t componentCount = 4;
    CGImageAlphaInfo alphaInfo = kCGImageAlphaPremultipliedFirst;
    CFStringRef colorSpaceName = kCGColorSpaceGenericRGB;
#endif
    
    size_t bytesPerRow = componentCount * size.width; // alpha

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(colorSpaceName);
    CGContextRef ctx = CGBitmapContextCreate(NULL, size.width, size.height, 8/*bitsPerComponent*/, bytesPerRow, colorSpace, alphaInfo);
    CGColorSpaceRelease(colorSpace);

    CGRect bounds = CGRectMake(0, 0, size.width, size.height);
    _drawInnerShadow(ctx, bounds, shadowEdgeMask);

    CGContextFlush(ctx);
    
    CGImageRef shadowImage = CGBitmapContextCreateImage(ctx);
    CFRelease(ctx);
    
    return shadowImage;
}

static void _setFrameXExtent(CALayer *layer, OFExtent xExtent)
{
    CGRect frame = layer.frame;
    frame.origin.x = OFExtentMin(xExtent);
    frame.size.width = OFExtentLength(xExtent);
    layer.frame = frame;
}

static void _setFrameYExtent(CALayer *layer, OFExtent yExtent)
{
    CGRect frame = layer.frame;
    frame.origin.y = OFExtentMin(yExtent);
    frame.size.height = OFExtentLength(yExtent);
    layer.frame = frame;
}

- (void)layoutSublayers;
{
    // Update the images on the sublayers if needed.
    // Build a inner-shadow image for our shadow edge layers. This layer stretching approach means that we need to be at least a minimum size.
    // TODO: If we are too small for 4 sublayer approach, build a shadow image that is vertically or horizontally stretchable (along the longer axis) and use a single sublayer.

    CGRect bounds = self.bounds;
    CGFloat edgeLength = 3*kShadowRadius; // Middle square of 3x3 grid won't be used.
    CGFloat oneThird = kShadowRadius/edgeLength;

    if (bounds.size.width < 1 || bounds.size.height < 1) {
        // If we are empty, we won't be seen anyway. More, creating shadow images will fail. This is probably due to us being resized to a zero width/height as part of animating a hole closed.
        
        // _minXEdge gets used if we only have one layer.
        BOOL wasNarrow = _maxXEdge.hidden;
        OBASSERT(!wasNarrow || (_minYEdge.hidden && _maxYEdge.hidden));
        
        if (wasNarrow) {
            _minXEdge.frame = bounds;
        } else {
            if (bounds.size.width < 1) {
                // squish to a narrow width for closing animation
                _setFrameXExtent(_minXEdge, OFExtentZero);
                _setFrameXExtent(_maxXEdge, OFExtentZero);
                _setFrameXExtent(_minYEdge, OFExtentZero);
                _setFrameXExtent(_maxYEdge, OFExtentZero);
            } else {
                // squish to a narrow height for closing animation
                _setFrameYExtent(_minXEdge, OFExtentZero);
                _setFrameYExtent(_maxXEdge, OFExtentZero);
                _setFrameYExtent(_minYEdge, OFExtentZero);
                _setFrameYExtent(_maxYEdge, OFExtentZero);
            }
        }
        
        return;
    }
    
    if (CGRectGetWidth(bounds) >= edgeLength && CGRectGetHeight(bounds) >= edgeLength) {
        // Wide and tall; used four edges with a center area
        CGSize shadowImageSize = CGSizeMake(edgeLength, edgeLength);
        if (!_shadowImage || (CGSizeEqualToSize(_shadowImageSize, shadowImageSize) == NO)) {
            CGImageRelease(_shadowImage);
            _shadowImage = _createShadowImageWithSize(shadowImageSize, _shadowEdgeMask);
            _shadowImageSize = shadowImageSize;
            
            _minXEdge.contents = (id)_shadowImage;
            _minXEdge.contentsRect = CGRectMake(0.0f, 0.0f, oneThird, 1.0f); // full height of side, including corners
            _minXEdge.contentsCenter = CGRectMake(0.0f, oneThird, oneThird, oneThird); // stretch the middle, not the end caps
            _minXEdge.hidden = NO;
            
            _maxXEdge.contents = (id)_shadowImage;
            _maxXEdge.contentsRect = CGRectMake(1.0f - oneThird, 0.0f, oneThird, 1.0f); // full height of side, including corners
            _maxXEdge.contentsCenter = CGRectMake(1.0f - oneThird, oneThird, oneThird, oneThird); // stretch the middle, not the end caps
            _maxXEdge.hidden = NO;
            
            _minYEdge.contents = (id)_shadowImage;
            _minYEdge.contentsRect = CGRectMake(oneThird, 0.0f, oneThird, oneThird);
            _minYEdge.hidden = NO;
            
            _maxYEdge.contents = (id)_shadowImage;
            _maxYEdge.contentsRect = CGRectMake(oneThird, 1.0f - oneThird, oneThird, oneThird);
            _maxYEdge.hidden = NO;
        }

        // Lay out edges
        CGRect slice, remaining = bounds;
        
        CGRectDivide(remaining, &slice, &remaining, kShadowRadius, CGRectMinXEdge);
        _minXEdge.frame = slice;
        
        CGRectDivide(remaining, &slice, &remaining, kShadowRadius, CGRectMaxXEdge);
        _maxXEdge.frame = slice;
        
        CGRectDivide(remaining, &slice, &remaining, kShadowRadius, CGRectMinYEdge);
        _minYEdge.frame = slice;
        
        CGRectDivide(remaining, &slice, &remaining, kShadowRadius, CGRectMaxYEdge);
        _maxYEdge.frame = slice;
    } else if (CGRectGetWidth(bounds) >= edgeLength) {
        // wide and short; just use one layer
        CGSize shadowImageSize = CGSizeMake(edgeLength, CGRectGetHeight(bounds));
        if (!_shadowImage || (CGSizeEqualToSize(_shadowImageSize, shadowImageSize) == NO)) {
            CGImageRelease(_shadowImage);
            _shadowImage = _createShadowImageWithSize(shadowImageSize, _shadowEdgeMask);
            _shadowImageSize = shadowImageSize;
            
            _minXEdge.contents = (id)_shadowImage;
            _minXEdge.contentsRect = CGRectMake(0.0f, 0.0f, 1.0f, 1.0f); // set this back to default in case it was changed from a previous size.
            _minXEdge.contentsCenter = CGRectMake(oneThird, 0.0f, oneThird, 1.0f); // stretch the middle, not the end caps
            _minXEdge.hidden = NO;
            
            _maxXEdge.hidden = YES;
            _minYEdge.hidden = YES;
            _maxYEdge.hidden = YES;
        }
        
        _minXEdge.frame = bounds;
    } else if (CGRectGetHeight(bounds) >= edgeLength) {
        // tall and narrow
        CGSize shadowImageSize = CGSizeMake(CGRectGetWidth(bounds), edgeLength);
        if (!_shadowImage || (CGSizeEqualToSize(_shadowImageSize, shadowImageSize) == NO)) {
            CGImageRelease(_shadowImage);
            _shadowImage = _createShadowImageWithSize(shadowImageSize, _shadowEdgeMask);
            _shadowImageSize = shadowImageSize;
            
            _minXEdge.contents = (id)_shadowImage;
            _minXEdge.contentsRect = CGRectMake(0.0f, 0.0f, 1.0f, 1.0f); // set this back to default in case it was changed from a previous size.
            _minXEdge.contentsCenter = CGRectMake(0.0f, oneThird, 1.0f, oneThird); // stretch the middle, not the end caps
            _minXEdge.hidden = NO;
            
            _maxXEdge.hidden = YES;
            _minYEdge.hidden = YES;
            _maxYEdge.hidden = YES;
        }
        
        _minXEdge.frame = bounds;
    } else {
        // small overall; just use one layer with no stretching
        CGSize shadowImageSize = bounds.size;
        if (!_shadowImage || (CGSizeEqualToSize(_shadowImageSize, shadowImageSize) == NO)) {
            OBFinishPortingLater("This path not tested, but hopefully works");
            
            CGImageRelease(_shadowImage);
            _shadowImage = _createShadowImageWithSize(shadowImageSize, _shadowEdgeMask);
            _shadowImageSize = shadowImageSize;
            
            _minXEdge.contents = (id)_shadowImage;
            _minXEdge.contentsRect = CGRectMake(0.0f, 0.0f, 1.0f, 1.0f); // set this back to default in case it was changed from a previous size.
            _minXEdge.contentsCenter = CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
            _minXEdge.hidden = NO;
            
            _maxXEdge.hidden = YES;
            _minYEdge.hidden = YES;
            _maxYEdge.hidden = YES;
        }
        
        _minXEdge.frame = bounds;
    }
    
}

- (void)display;
{
    NSRect bounds = self.bounds;

    //CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

    CGImageRef gradientImage = OQCreateVerticalGradientImage(_gradient, kCGColorSpaceGenericGray, CGRectGetHeight(bounds), YES/*opaque*/, YES/*flip*/);
    self.contents = (id)gradientImage;
    CGImageRelease(gradientImage);

    //CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    //NSLog(@"hole = %f", end - start);
}

@end
