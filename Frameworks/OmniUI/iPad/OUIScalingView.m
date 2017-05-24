// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
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
    self->_scaleEnabled = YES;
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

// If this view is within a OUIScalingScrollView, then this property should be considered read-only and the scale should be adjusted via its methods.
- (void)setScale:(CGFloat)scale;
{
    if (self.scaleEnabled == NO) {
        return;
    }
    
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

// UIView is flipped, but some subclasses want unflipped coordinates. Both this and scale matter when building the transform from on screen coordiantes (view frame geometry and touch positions) to CoreGraphics rendering coordinates (inside the view).
- (BOOL)wantsUnflippedCoordinateSystem;
{
    return NO;
}

- (CGPoint)viewPointForTouchPoint:(CGPoint)point;
{
    return point;
    // TODO: delete this method, stop using it anywhere. adjustScaleTo: handles the scaling, so by the time we're processing a touch, the touch point's locationInView IS the view point.

}

- (CGPoint)viewPointForTouch:(UITouch *)touch;
{
    return [self viewPointForTouchPoint:[touch locationInView:self]];
}

- (CGAffineTransform)transformFromViewSpaceToUnscaledSpace
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

- (CGRect)convertRectFromViewSpaceToUnscaledSpace:(CGRect)rect;
{
    CGAffineTransform xform = [self transformFromViewSpaceToUnscaledSpace];
    return CGRectApplyAffineTransform(rect, CGAffineTransformInvert(xform));
}

- (CGRect)convertRectFromUnscaledSpaceToViewSpace:(CGRect)rect;
{
    CGAffineTransform xform = [self transformFromViewSpaceToUnscaledSpace];
    return CGRectApplyAffineTransform(rect, xform);
}

- (CGPoint)convertPointFromViewSpaceToUnscaledSpace:(CGPoint)point;
{
    CGAffineTransform xform = [self transformFromViewSpaceToUnscaledSpace];
    return CGPointApplyAffineTransform(point, CGAffineTransformInvert(xform));
}

- (CGPoint)convertPointFromUnscaledSpaceToViewSpace:(CGPoint)point;
{
    CGAffineTransform xform = [self transformFromViewSpaceToUnscaledSpace];
    return CGPointApplyAffineTransform(point, xform);
}

- (void)establishTransformFromViewSpaceToUnscaledSpace:(CGContextRef)ctx;
{
    CGContextConcatCTM(ctx, [self transformFromViewSpaceToUnscaledSpace]);
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

#pragma mark UIView subclass

- (void)drawRect:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx); // for subclasses that draw unscaled content atop the scaled content (like the border in OO/iPad text cells).
    {
        [self establishTransformFromViewSpaceToUnscaledSpace:ctx];
        [self drawScaledContent:rect];
    }
    CGContextRestoreGState(ctx);
}

@end
