// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentProxyView.h>

#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUILoadedImage.h>
#ifdef OMNI_ASSERTIONS_ON
#import <OmniUI/OUIDocumentPickerView.h>
#endif
#import <OmniQuartz/OQDrawing.h>
#import "OUIDocumentPDFPreview.h"
#import "OUIDocumentImagePreview.h"


RCS_ID("$Id$");

#define SHOW_SELECTION 1

#if 0 && defined(DEBUG)
    #define PREVIEW_DEBUG(format, ...) NSLog(@"PREVIEW VIEW: %p " format, self, ## __VA_ARGS__)
#else
    #define PREVIEW_DEBUG(format, ...)
#endif

@interface OUIDocumentProxyView (/*Private*/)
#if SHOW_SELECTION
- (void)_updateSelectionViewColor;
#endif
@end

@implementation OUIDocumentProxyView

static CGGradientRef LightingGradient = NULL;

static struct {
    OUILoadedImage topLeft;
    OUILoadedImage top;
    OUILoadedImage topRight;
    OUILoadedImage left;
    OUILoadedImage middle;
    OUILoadedImage right;
    OUILoadedImage bottomLeft;
    OUILoadedImage bottom;
    OUILoadedImage bottomRight;
} BorderImages;

+ (void)initialize;
{
    OBINITIALIZE;
    
    id topColor = (id)[[UIColor colorWithWhite:1.0 alpha:.3] CGColor];
    id bottomColor = (id)[[UIColor colorWithWhite:0.0 alpha:.15] CGColor];
    CGColorSpaceRef graySpace = CGColorSpaceCreateDeviceGray();
    LightingGradient = CGGradientCreateWithColors(graySpace, (CFArrayRef)[NSArray arrayWithObjects:bottomColor, topColor, nil], NULL);
    CFRelease(graySpace);

    OUILoadImage(@"OUIPreviewBackgroundBottom.png", &BorderImages.bottom);
    OUILoadImage(@"OUIPreviewBackgroundBottomLeft.png", &BorderImages.bottomLeft);
    OUILoadImage(@"OUIPreviewBackgroundBottomRight.png", &BorderImages.bottomRight);
    OUILoadImage(@"OUIPreviewBackgroundLeft.png", &BorderImages.left);
    OUILoadImage(@"OUIPreviewBackgroundRight.png", &BorderImages.right);
    OUILoadImage(@"OUIPreviewBackgroundTile.png", &BorderImages.middle);
    OUILoadImage(@"OUIPreviewBackgroundTop.png", &BorderImages.top);
    OUILoadImage(@"OUIPreviewBackgroundTopLeft.png", &BorderImages.topLeft);
    OUILoadImage(@"OUIPreviewBackgroundTopRight.png", &BorderImages.topRight);
}

static UIImage *PlaceholderPreviewImage = nil;
+ (void)setPlaceholderPreviewImage:(UIImage *)placeholderPreviewImage;
{
    [PlaceholderPreviewImage release];
    PlaceholderPreviewImage = [placeholderPreviewImage retain];
}

+ (UIImage *)placeholderPreviewImage;
{
    if (!PlaceholderPreviewImage) {
        static BOOL triedDefault = NO;
        if (!triedDefault) {
            triedDefault = YES;
            PlaceholderPreviewImage = [[UIImage imageNamed:@"DocumentPreviewPlaceholder.png"] retain];
        }
    }
    
    OBASSERT(PlaceholderPreviewImage);
    return PlaceholderPreviewImage;
}

static id _commonInit(OUIDocumentProxyView *self)
{
    CALayer *layer = self.layer;
    layer.edgeAntialiasingMask = 0; // See drawing code below.
    layer.needsDisplayOnBoundsChange = YES;
    
    // EXTREMELY SLOW. We'll cache the shadows inside the layer content when drawing it.
    //layer.shadowOpacity = 0.5;
    
    [self.layer setNeedsDisplay];
    
#if SHOW_SELECTION
    self->_selectionGrayView = [[UIView alloc] init];
    self->_selectionGrayView.layer.needsDisplayOnBoundsChange = NO;
    self->_selectionGrayView.userInteractionEnabled = NO;
    [self _updateSelectionViewColor];
    [self addSubview:self->_selectionGrayView];
#endif

    self->_shadowEdgeViews = [OUIViewAddShadowEdges(self) copy];

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
    [_selectionGrayView release];
    
    [_shadowEdgeViews release];
    
    [_preview release];
    [super dealloc];
}

@synthesize selected = _selected;
- (void)setSelected:(BOOL)selected;
{
    if (_selected == selected)
        return;
    
    _selected = selected;
#if SHOW_SELECTION
    [self _updateSelectionViewColor];
#endif
}

@synthesize preview = _preview;
- (void)setPreview:(id <OUIDocumentPreview>)preview;
{
    [_preview release];
    _preview = [preview retain];
    
    PREVIEW_DEBUG(@"_preview now %@, size %@, image %@, layer %@", [(id)_preview shortDescription], NSStringFromCGSize(_preview.originalViewSize), _preview.cachedImage, self.layer);
    
    // Our selection layer gets its rect based on the preview
    [self setNeedsLayout];

    [self.layer setNeedsDisplay];
}

static CGAffineTransform _getTargetTransform(id <OUIDocumentPreview> preview, CGRect bounds)
{    
    if (preview)
        return [preview transformForTargetRect:bounds];
    return CGAffineTransformIdentity;
}

static CGRect _paperRect(id <OUIDocumentPreview> preview, CGRect bounds)
{
    return preview ? preview.untransformedPageRect : bounds;
}

- (NSArray *)shadowEdgeViews;
{
    return _shadowEdgeViews;
}

#pragma mark -
#pragma mark UIView subclass

#ifdef OMNI_ASSERTIONS_ON
- (void)setFrame:(CGRect)frame;
{
    OBPRECONDITION(CGRectEqualToRect(frame, CGRectIntegral(frame)));
    [super setFrame:frame];
}
#endif

- (void)layoutSubviews;
{
    OUIViewLayoutShadowEdges(self, _shadowEdgeViews, YES/*flip*/);

#if SHOW_SELECTION
    _selectionGrayView.frame = self.bounds;
#endif
}

#pragma mark -
#pragma mark CALayer delegate

void OUIDocumentProxyDrawPreview(CGContextRef ctx, OUIDocumentPDFPreview *pdfPreview, CGRect bounds)
{
    //NSLog(@"draw preview %@ in %@", pdfPreview, NSStringFromCGRect(bounds));
    
    /*
     PERFORMANCE NOTE: a pdfPreview of nil means that we are getting called from the main thread to render live into a view that doesn't have a preview loaded yet. We must be very fast in this case.
     */

    CGAffineTransform xform = _getTargetTransform(pdfPreview, bounds);
    CGRect paperRect = _paperRect(pdfPreview, bounds);
    CGRect transformedTarget = CGRectApplyAffineTransform(paperRect, xform);

    // A white piece of paper and shadow, then the PDF atop the paper.
    CGContextSaveGState(ctx);
    {
        //[[UIColor redColor] set];
        //CGContextStrokeRect(ctx, CGRectInset(layer.bounds, 0.5, 0.5));
        
        CGContextConcatCTM(ctx, xform); // size the page to the target rect we wanted
        
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
        
        // Newer OGS builds emit transparent backgrounds.  Make sure our preview appear atop something.
        CGFloat alpha = pdfPreview != nil ? 1.0 : 0.2;
        CGFloat whiteComponents[] = {1.0, alpha};
        CGColorRef white = CGColorCreate(colorSpace, whiteComponents);
        CGContextSetFillColorWithColor(ctx, white);
        CGColorRelease(white);
        
        CGColorSpaceRelease(colorSpace);
        
        CGContextFillRect(ctx, paperRect);
        
        if (pdfPreview) {
            // the PDF is happy to draw outside its page rect.
            CGContextAddRect(ctx, paperRect);
            CGContextClip(ctx);
            
            [pdfPreview drawInTransformedContext:ctx];
        }
    }
    CGContextRestoreGState(ctx);

    if (!pdfPreview && PlaceholderPreviewImage) {
        CGContextSaveGState(ctx);
        {
            CGSize imageSize = [PlaceholderPreviewImage size];
            CGContextTranslateCTM(ctx, CGRectGetMidX(bounds), CGRectGetMidY(bounds));
            CGContextScaleCTM(ctx, 1, -1);
            CGContextTranslateCTM(ctx, -bounds.origin.x - imageSize.width/2, -bounds.origin.y - imageSize.height/2);
            CGContextDrawImage(ctx, CGRectMake(0, 0, imageSize.width, imageSize.height), [PlaceholderPreviewImage CGImage]);
        }
        CGContextRestoreGState(ctx);
        return;
    }

    // The rest of this is fancy stuff that is only applicable for the background thread
    if (!pdfPreview)
	return;
    
    
    // Now, compute the transformed target and draw atop it.
    
    CGContextSaveGState(ctx);
    {
        // Lighting gradient atop the preview; we don't bother flipping the coordinate system here, but just swapped the colors.
        CGContextAddRect(ctx, transformedTarget);
        CGContextClip(ctx);
        CGContextDrawLinearGradient(ctx, LightingGradient, transformedTarget.origin, CGPointMake(transformedTarget.origin.x, CGRectGetMaxY(transformedTarget)), 0);
    }
    CGContextRestoreGState(ctx);
    
    // Paper texture.
    CGContextSaveGState(ctx);
    {        
        CGRect remainder;
        
        CGRect topLeft, top, topRight;
        CGRectDivide(transformedTarget, &top, &remainder, BorderImages.top.size.height, CGRectMaxYEdge);
        CGRectDivide(top, &topLeft, &top, BorderImages.topLeft.size.width, CGRectMinXEdge);
        CGRectDivide(top, &topRight, &top, BorderImages.topLeft.size.width, CGRectMaxXEdge);
        CGContextDrawImage(ctx, topLeft, [BorderImages.topLeft.image CGImage]);
        CGContextDrawImage(ctx, top, [BorderImages.top.image CGImage]);
        CGContextDrawImage(ctx, topRight, [BorderImages.topRight.image CGImage]);
        
        CGRect bottomLeft, bottom, bottomRight;
        CGRectDivide(remainder, &bottom, &remainder, BorderImages.bottom.size.height, CGRectMinYEdge);
        CGRectDivide(bottom, &bottomLeft, &bottom, BorderImages.bottomLeft.size.width, CGRectMinXEdge);
        CGRectDivide(bottom, &bottomRight, &bottom, BorderImages.bottomLeft.size.width, CGRectMaxXEdge);
        CGContextDrawImage(ctx, bottomLeft, [BorderImages.bottomLeft.image CGImage]);
        CGContextDrawImage(ctx, bottom, [BorderImages.bottom.image CGImage]);
        CGContextDrawImage(ctx, bottomRight, [BorderImages.bottomRight.image CGImage]);
        
        CGRect left, right;
        CGRectDivide(remainder, &left, &remainder, BorderImages.left.size.width, CGRectMinXEdge);
        CGRectDivide(remainder, &right, &remainder, BorderImages.right.size.width, CGRectMaxXEdge);
        CGContextDrawImage(ctx, left, [BorderImages.left.image CGImage]);
        CGContextDrawImage(ctx, right, [BorderImages.right.image CGImage]);
        
        // Rest is tiled middle. The edges are just gray and we want the full page covered with this tile to get texture into the edges/corners
        // The CG tiling fills the clip rect by scaling the image to the specified rect.
        CGContextAddRect(ctx, transformedTarget);
        CGContextClip(ctx);
        CGContextDrawTiledImage(ctx, CGRectMake(0, 0, BorderImages.middle.size.width, BorderImages.middle.size.height), [BorderImages.middle.image CGImage]);
    }
    CGContextRestoreGState(ctx);
}

- (void)displayLayer:(CALayer *)layer;
{
    if (!_preview) {
        _preview = [[OUIDocumentImagePreview alloc] initWithImage:[[self class] placeholderPreviewImage]];
        PREVIEW_DEBUG(@"using canned preview %@", _preview);
    }

    UIImage *image = _preview.cachedImage;
    CGImageRef imageRef = [image CGImage];

    // DO NOT animate the content changing. We want this to participate in UIView animations, not CA.
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanFalse forKey:(id)kCATransactionDisableActions];
    {
        // This is for the benefit of the static preview, which is a fixed size.  The other previews are built to match the right size.
        if ([_preview isKindOfClass:[OUIDocumentImagePreview class]])
            layer.contentsGravity = kCAGravityCenter;
        else
            layer.contentsGravity = kCAGravityResizeAspectFill;
        
        layer.contents = (id)imageRef;
    }
    [CATransaction commit];
}

#pragma mark -
#pragma mark UIView (OUIExtensions)

- (UIImage *)snapshotImage;
{
    UIImage *image = _preview.cachedImage;
    if (image)
        return image;
    return [super snapshotImage];
}

#pragma mark -
#pragma mark Private

#if SHOW_SELECTION
- (void)_updateSelectionViewColor;
{
    CGFloat selectionColorAlpha = _selected ? 0 : 0.33;
    [UIView beginAnimations:@"selection color" context:NULL];
    _selectionGrayView.backgroundColor = [UIColor colorWithWhite:0 alpha:selectionColorAlpha];
    [UIView commitAnimations];
}
#endif


@end

