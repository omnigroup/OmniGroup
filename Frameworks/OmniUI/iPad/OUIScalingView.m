// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIScalingView.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

RCS_ID("$Id$");

@implementation OUIScalingView

static id _commonInit(OUIScalingView *self)
{
    self.layer.needsDisplayOnBoundsChange = YES;
    self->_scale = 1;
    return self;
}

- initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- (void)dealloc;
{
    [_shadowEdgeViews release];
    
    [super dealloc];
}

// DO NOT set this directly for now. Only should be mucked with via GraphViewController and its UIScrollView (or code needs rearranging to support direct mucking)
@synthesize scale = _scale;
- (void)setScale:(CGFloat)scale;
{
    OBPRECONDITION(scale > 0);
    if (_scale == scale)
        return;
    
    _scale = scale;
    [self setNeedsDisplay];
}

- (void)scaleChanged;
{
    // for subclasses
}

- (void)scrollPositionChanged;
{
    // for subclasses
}

@synthesize rotating = _rotating;

// UIView is flipped, but some subclasses want unflipped coordinates. Both this and scale matter when building the transform from on screen coordiantes (view frame geometry and touch positions) to CoreGraphics rendering coordinates (inside the view).
- (BOOL)wantsUnflippedCoordinateSystem;
{
    return NO;
}

- (CGPoint)viewPointForTouchPoint:(CGPoint)point;
{
    OBPRECONDITION(_scale > 0);
    
    CGRect bounds = self.bounds;
    OBASSERT(CGPointEqualToPoint(bounds.origin, CGPointZero)); // Don't bother with this ever so slightly more complicated transform unless we need to.
    
    // Account for our flip and scale.
    CGPoint result;
    result.x = point.x / _scale;
    
    if (self.wantsUnflippedCoordinateSystem) {
        result.y = (bounds.size.height - point.y) / _scale;
    } else {
        result.y = point.y / _scale;
    }
    
    return result;
}

- (CGPoint)viewPointForTouch:(UITouch *)touch;
{
    return [self viewPointForTouchPoint:[touch locationInView:self]];
}

- (CGAffineTransform)transformToRenderingSpace;
{
    CGRect bounds = self.bounds;
    
    // UIView is flipped (Y increases downwards), but we want non-flipped (Y increases upwards), and UIView is always in device pixel space while we want to render in our scaled "view" space for RSDataMapper.
    
    if(self.wantsUnflippedCoordinateSystem)
        return (CGAffineTransform){
            _scale, 0, 0, -_scale,
            bounds.origin.x, bounds.origin.y + bounds.size.height
        };
    else
        return (CGAffineTransform){
            _scale, 0, 0, _scale,
            bounds.origin.x, bounds.origin.y
        };
}

- (CGAffineTransform)transformFromRenderingSpace;
{
    CGRect bounds = self.bounds;
    CGFloat invscale = 1 / _scale;
    
    // This returns the inverse transform from -transformToRenderingSpace.
    // (You could equivalently use CGAffineTransformInvert() on the transform returned by -transformToRenderingSpace, but this should be faster and more accurate)
        
    if (self.wantsUnflippedCoordinateSystem)
        return (CGAffineTransform){
            invscale, 0, 0, -invscale,
            -1 * invscale * bounds.origin.x, invscale * ( bounds.size.height + bounds.origin.y )
        };
    else
        return (CGAffineTransform){
            invscale, 0, 0, invscale,
            -1 * invscale * bounds.origin.x, -1 * invscale * bounds.origin.y
        };
}

- (CGRect)convertRectFromRenderingSpace:(CGRect)rect;
{
    CGAffineTransform xform = [self transformToRenderingSpace];
    return CGRectApplyAffineTransform(rect, CGAffineTransformInvert(xform));
}

- (CGRect)convertRectToRenderingSpace:(CGRect)rect;
{
    CGAffineTransform xform = [self transformToRenderingSpace];
    return CGRectApplyAffineTransform(rect, xform);
}

- (CGPoint)convertPointFromRenderingSpace:(CGPoint)point;
{
    CGAffineTransform xform = [self transformToRenderingSpace];
    return CGPointApplyAffineTransform(point, CGAffineTransformInvert(xform));
}

- (CGPoint)convertPointToRenderingSpace:(CGPoint)point;
{
    CGAffineTransform xform = [self transformToRenderingSpace];
    return CGPointApplyAffineTransform(point, xform);
}

- (void)establishTransformToRenderingSpace:(CGContextRef)ctx;
{
    CGContextConcatCTM(ctx, [self transformToRenderingSpace]);
}

- (CGRect)viewRectWithCenter:(CGPoint)center size:(CGSize)size;
{
    CGPoint newCenter = [self convertPointToRenderingSpace:center];
    CGRect frame = CGRectMake(newCenter.x - size.width / 2, newCenter.y - size.height / 2, size.width, size.height);
    return CGRectIntegral(frame);
}

- (void)drawScaledContent:(CGRect)rect;
{
    // For subclasses
    // Note that rect does not currently hold a useful rectangle
}

- (NSData *)pdfData;
{
    CGRect bounds = self.bounds;
    NSMutableData *data = [NSMutableData data];
    
    NSMutableDictionary *documentInfo = [NSMutableDictionary dictionary];
    NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleNameKey];
    if (appName)
        [documentInfo setObject:appName forKey:(id)kCGPDFContextCreator];
    
#if 0 // GraphView doesn't have the title -- pass it in
    if (_url) {
        NSString *name = [[[[_url absoluteURL] path] lastPathComponent] stringByDeletingPathExtension]
        [documentInfo setObject:name forKey:kCGPDFContextTitle];
    }
#endif
    // other keys we might want to add
    // kCGPDFContextAuthor - string
    // kCGPDFContextSubject -- string
    // kCGPDFContextKeywords -- string or array of strings
    UIGraphicsBeginPDFContextToData(data, bounds, documentInfo);
    {
        UIGraphicsBeginPDFPage();
        [self drawRect:bounds];
    }
    UIGraphicsEndPDFContext();
    return data;
}

@synthesize wantsShadowEdges = _wantsShadowEdges;

- (void)updateShadowEdgeViews;
{
    if (!self.wantsShadowEdges)
        return;
    
    if (!_shadowEdgeViews)
        _shadowEdgeViews = [OUIViewAddShadowEdges(self) copy];
    OUIViewLayoutShadowEdges(self, _shadowEdgeViews, YES/*flipped*/);
}

- (void)setShadowEdgeViewVisibility:(BOOL)visible;
{
    if (!self.wantsShadowEdges)
        return;
    
    if (visible) {
        for (UIView *view in _shadowEdgeViews) {
            [self addSubview:view];
        }
    }
    else {
        [_shadowEdgeViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    }
}

#pragma mark UIView subclass

- (void)drawRect:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [self establishTransformToRenderingSpace:ctx];
    [self drawScaledContent:rect];
}

- (void)layoutSubviews;
{
    if (self.wantsShadowEdges) {
        [self updateShadowEdgeViews];
    }
}

@end
