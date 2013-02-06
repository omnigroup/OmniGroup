// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPreviewView.h>

#import <OmniUIDocument/OUIDocumentPreview.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUIDrawing.h>
#import <OmniQuartz/CALayer-OQExtensions.h>
#import <OmniQuartz/OQDrawing.h>

#import "OUIDocumentParameters.h"

RCS_ID("$Id$");

@interface OUIDocumentPreviewImageLayer : CALayer
@end
@implementation OUIDocumentPreviewImageLayer

- (id<CAAction>)actionForKey:(NSString *)event;
{
    id <CAAction> action;
    
    if ([event isEqualToString:@"bounds"] ||
        [event isEqualToString:@"position"] ||
        // Let the shadow path resize -- we don't care to animate the color, so don't. Probabliy don't need to animate the opacity either.
        [event isEqualToString:@"shadowPath"] ||
        [event isEqualToString:@"shadowOpacity"]) {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:event];
        animation.fromValue = [self valueForKey:event];
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        animation.fillMode = kCAFillModeBoth;
        
        action = animation;
    } else
        action = [super actionForKey:event];
    
    //NSLog(@"-actionForKey:%@ -> %@", event, action);
    return action;
}

// This significantly lowers the time needed to build the animation images for OUIMainViewController when entering/leaving the document picker. kCGInterpolationNone might be overkill -- can see the aliasing change if you know to look for it.
- (void)renderInContext:(CGContextRef)ctx;
{
    CGImageRef contents = (__bridge CGImageRef)self.contents;
    if (contents == NULL)
        return;
    if (CFGetTypeID(contents) != CGImageGetTypeID()) {
        OBASSERT_NOT_REACHED("contents isn't an image");
        [super renderInContext:ctx];
        return;
    }
    
    CGContextSaveGState(ctx);
    {
        CGColorRef shadowColor = self.shadowColor;
        if (shadowColor) {
            // We assume shadowPath is just our bounds...
            
            CGFloat shadowRadius = self.shadowRadius;
            CGSize shadowOffset = self.shadowOffset;
            
            OBASSERT(self.shadowOpacity == 1); // Not sure how CALayer would render this other than to pre-multiply it into the shadow color...
            
            CGContextSetShadowWithColor(ctx, shadowOffset, shadowRadius, shadowColor);
        }
        
        CGRect bounds = self.bounds;
        
        CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
        OQFlipVerticallyInRect(ctx, bounds);
        CGContextDrawImage(ctx, bounds, contents);
    }
    CGContextRestoreGState(ctx);
}

@end

@implementation OUIDocumentPreviewView
{
    NSMutableArray *_previews;
    
    BOOL _landscape;
    BOOL _group;
    BOOL _needsAntialiasingBorder;
    BOOL _selected;
    BOOL _draggingSource;
    BOOL _highlighted;
    BOOL _downloadRequested;
    BOOL _downloading;
    
    NSTimeInterval _animationDuration;
    UIViewAnimationCurve _animationCurve;

    CALayer *_selectionLayer;
    OUIDocumentPreviewImageLayer *_imageLayer;
    UIImageView *_statusImageView;
    UIProgressView *_transferProgressView;
}

static id _commonInit(OUIDocumentPreviewView *self)
{    
    self->_imageLayer = [[OUIDocumentPreviewImageLayer alloc] init];
    self->_imageLayer.opaque = YES;
    
    [self.layer addSublayer:self->_imageLayer];
    
    return self;
}

/*
 
 The edgeAntialiasingMask property on CALayer is pretty useless for our needs -- we aren't butting two objects together and it doesn't do edge coverage right (it seems).
 
 Instead, if we have the wiggle-edit animation going, we set shouldRasterize=YES on *our* layer. CALayer attempts to find the smallest rectangle that will enclose the drawing when it flattens the bitmap. Because we have a shadow, this rect extends 1px-ish outside the preview image layer (which has the most visible edge) and we get interior-style linear texture lookup.
 
 When we are selected, though, we don't have a shadow, but we *do* have a sublayer for the border that extends outside the bounds of the image, and the preview image has some exterior alpha. Again, this makes the flattened rasterized image have transparent pixels on the border and do linear texture lookup on the interior.
 
 Another (terrible) hack that we don't use here is to set a mostly transparent background color on this superview. If it is too transparent, CALayer will ignore us for the purposes of computing the size of the area to rasterisze. Another possible trick, that I haven't tried, would be to set a 1x1 transparent image as our content (or nil if we don't want to be rasterized). This seems like it would be less prone to implementation changes in computing how transparent is "too transparent" to include in the rasterization.
 */

static void _updateShouldRasterize(OUIDocumentPreviewView *self)
{
    BOOL shouldRasterize = self->_needsAntialiasingBorder;
    self.layer.shouldRasterize = shouldRasterize;
    self.layer.rasterizationScale = [[UIScreen mainScreen] scale];
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
    for (OUIDocumentPreview *preview in _previews)
        [preview decrementDisplayCount];
}

@synthesize landscape = _landscape;
- (void)setLandscape:(BOOL)landscape;
{
    if (_landscape == landscape)
        return;
    
    _landscape = landscape;
    
    [self.superview setNeedsLayout]; // -previewRectInFrame: changes based on the orientation
    [self setNeedsLayout];
}

@synthesize group = _group;
- (void)setGroup:(BOOL)group;
{
    if (_group == group)
        return;
    
    _group = group;
    [self setNeedsLayout];
}

// See commentary by _updateShouldRasterize() for how edge antialiasing works.
@synthesize needsAntialiasingBorder = _needsAntialiasingBorder;
- (void)setNeedsAntialiasingBorder:(BOOL)needsAntialiasingBorder;
{
    if (_needsAntialiasingBorder == needsAntialiasingBorder)
        return;
    
    _needsAntialiasingBorder = needsAntialiasingBorder;
    
    _updateShouldRasterize(self);
    [self setNeedsLayout];
}

@synthesize selected = _selected;
- (void)setSelected:(BOOL)selected;
{
    if (_selected == selected)
        return;
    
    _selected = selected;
    
    if (_selected && !_selectionLayer) {
        OUIWithoutAnimating(^{
            _selectionLayer = [[CALayer alloc] init];
            _selectionLayer.name = @"selection";
            
            UIImage *image = [UIImage imageNamed:@"OUIDocumentPreviewViewSelectedBorder.png"];
            CGSize imageSize = image.size;
            
            _selectionLayer.contents = (id)[image CGImage];
            _selectionLayer.contentsScale = [image scale];
            _selectionLayer.contentsCenter = CGRectMake(kOUIDocumentPreviewViewBorderEdgeInsets.left/imageSize.width,
                                                        kOUIDocumentPreviewViewBorderEdgeInsets.top/imageSize.height,
                                                        (imageSize.width-kOUIDocumentPreviewViewBorderEdgeInsets.left-kOUIDocumentPreviewViewBorderEdgeInsets.right)/imageSize.width,
                                                        (imageSize.height-kOUIDocumentPreviewViewBorderEdgeInsets.top-kOUIDocumentPreviewViewBorderEdgeInsets.bottom)/imageSize.height);
        });
        
        [self.layer insertSublayer:_selectionLayer below:_imageLayer];
    } else if (!_selected && _selectionLayer) {
        [_selectionLayer removeFromSuperlayer];
        _selectionLayer = nil;
    }
    
    [self.superview setNeedsLayout]; // -previewRectInFrame: changes based on the selection state
    [self setNeedsLayout];
}

@synthesize draggingSource = _draggingSource;
- (void)setDraggingSource:(BOOL)draggingSource;
{
    if (_draggingSource == draggingSource)
        return;
    
    _draggingSource = draggingSource;
    
    [self setNeedsLayout];
}

@synthesize highlighted = _highlighted;
- (void)setHighlighted:(BOOL)highlighted;
{
    if (_highlighted == highlighted)
        return;
    
    _highlighted = highlighted;
    
    [self setNeedsLayout];
}

@synthesize previews = _previews;

- (void)addPreview:(OUIDocumentPreview *)preview;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(preview);
    OBPRECONDITION(!_previews || [_previews indexOfObjectIdenticalTo:preview] == NSNotFound);
        
    if (!_previews)
        _previews = [[NSMutableArray alloc] init];
    
    // Files should only have one preview. We might hold onto one while refreshing, though.
    if (!_group) {
        for (OUIDocumentPreview *preview in _previews)
            [preview decrementDisplayCount];
        [_previews removeAllObjects];
    }
    
    [preview incrementDisplayCount];
    [_previews addObject:preview];
    
    DEBUG_PREVIEW_DISPLAY(@"%p addPreview: %@", self, [(id)preview shortDescription]);

    // Our frame gets set by our superview based on our preview size
    [self.superview setNeedsLayout];
    [self setNeedsLayout];
}

- (void)discardPreviews;
{
    OBPRECONDITION([NSThread isMainThread]);

    if ([_previews count] == 0)
        return;
    
    DEBUG_PREVIEW_DISPLAY(@"%p discardPreviews", self);

    for (OUIDocumentPreview *preview in _previews)
        [preview decrementDisplayCount];
    [_previews removeAllObjects];
}

#define kOUIDocumentPreviewViewNormalShadowInsets UIEdgeInsetsMake(ceil(kOUIDocumentPreviewViewNormalShadowBlur)/*top*/, ceil(kOUIDocumentPreviewViewNormalShadowBlur)/*left*/, ceil(kOUIDocumentPreviewViewNormalShadowBlur + 1)/*bottom*/, ceil(kOUIDocumentPreviewViewNormalShadowBlur)/*right*/)

- (UIEdgeInsets)_edgeInsets;
{
    UIEdgeInsets insets;
    
    if (_selected) {
        // Room for the selection border image
        insets = kOUIDocumentPreviewViewBorderEdgeInsets;
    } else if (_draggingSource) {
        // No shadow
        insets = UIEdgeInsetsZero;
    } else {
        // Normal shadow
        insets = kOUIDocumentPreviewViewNormalShadowInsets;
    }
    
    return insets;
}

// Could use -sizeThatFits:, but that would require the caller to center the size... just as easy to define our own API
- (CGRect)previewRectInFrame:(CGRect)frame;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_group) {
        return CGRectInset(frame, 16, 16); // ... or something
    } else {
        OUIDocumentPreview *preview = [_previews lastObject];

        CGSize previewSize;
        if (preview && preview.type == OUIDocumentPreviewTypeRegular) {
            previewSize = preview.size;
            
            CGFloat scale = [OUIDocumentPreview previewImageScale];
            previewSize.width = floor(previewSize.width / scale);
            previewSize.height = floor(previewSize.height / scale);
        } else
            previewSize = [OUIDocumentPreview maximumPreviewSizeForLandscape:_landscape];
        
        CGRect previewFrame;
        previewFrame.origin.x = floor(CGRectGetMidX(frame) - previewSize.width / 2);
        previewFrame.origin.y = floor(CGRectGetMidY(frame) - previewSize.height / 2);
        previewFrame.size = previewSize;
        
        return OUIEdgeInsetsOutsetRect(previewFrame, [self _edgeInsets]);
    }
}

// This version allows the preview to scale up. It would be good to unify this with the other version
- (CGRect)fitPreviewRectInFrame:(CGRect)frame;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_group) {
        return CGRectInset(frame, 16, 16); // ... or something
    } else {
        OUIDocumentPreview *preview = [_previews lastObject];
        
        CGSize previewSize;
        if (preview && preview.type == OUIDocumentPreviewTypeRegular) {
            previewSize = preview.size;
        } else
            previewSize = [OUIDocumentPreview maximumPreviewSizeForLandscape:_landscape];

        CGRect previewFrame = OQCenterAndFitIntegralRectInRectWithSameAspectRatioAsSize(frame, previewSize);
        
        return OUIEdgeInsetsOutsetRect(previewFrame, [self _edgeInsets]);
    }
}

- (CGRect)imageBounds;
{
    return UIEdgeInsetsInsetRect(self.bounds, [self _edgeInsets]);
}

@synthesize animationDuration = _animationDuration;
@synthesize animationCurve = _animationCurve;

- (UIImage *)statusImage;
{
    return _statusImageView.image;
}
- (void)setStatusImage:(UIImage *)image;
{
    if (self.statusImage == image)
        return;

    if (image) {
        if (!_statusImageView) {
            _statusImageView = [[UIImageView alloc] initWithImage:nil];
            [self addSubview:_statusImageView];
        }
        _statusImageView.image = image;
    } else {
        if (_statusImageView) {
            [_statusImageView removeFromSuperview];
            _statusImageView = nil;
        }
    }
    
    _updateShouldRasterize(self);
    [self setNeedsLayout];
}

@synthesize downloadRequested = _downloadRequested;
- (void)setDownloadRequested:(BOOL)downloadRequested;
{
    if (_downloadRequested == downloadRequested)
        return;
    
    _downloadRequested = downloadRequested;

    [self setNeedsLayout];
}

@synthesize downloading = _downloading;
- (void)setDownloading:(BOOL)downloading;
{
    if (_downloading == downloading)
        return;
    
    _downloading = downloading;
    
    [self setNeedsLayout];
}

- (BOOL)showsProgress;
{
    return _transferProgressView != nil;
}
- (void)setShowsProgress:(BOOL)showsProgress;
{
    if (showsProgress) {
        if (_transferProgressView)
            return;
        _transferProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        [self addSubview:self->_transferProgressView];
    } else {
        if (_transferProgressView) {
            [_transferProgressView removeFromSuperview];
            _transferProgressView = nil;
        }
    }
    
    _updateShouldRasterize(self);
    [self setNeedsLayout];
}

- (double)progress;
{
    if (_transferProgressView)
        return _transferProgressView.progress;
    return 0.0;
}
- (void)setProgress:(double)progress;
{
    OBPRECONDITION(_transferProgressView || progress == 0.0 || progress == 1.0);
    
    _transferProgressView.progress = progress;
}

#pragma mark -
#pragma mark UIView (OUIExtensions)

- (UIImage *)snapshotImage;
{
    if (_group) {
        OBFinishPortingLater("Want a special case for this?");
    } else if (!_draggingSource) {
        // If we have one, return the image we already have for the document picker open/close animation.
        // Note: this may have a tiny glitch due to the 1px inset to avoid edge aliasing issues.
        OBASSERT([_previews count] <= 1);
        OUIDocumentPreview *preview = [_previews lastObject];
        
        if (preview.type == OUIDocumentPreviewTypeRegular) {
            OBASSERT(preview.image);
            return [UIImage imageWithCGImage:preview.image];
        }
    }
    
    return [super snapshotImage];
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
    CGRect bounds = self.bounds;
    if (CGRectEqualToRect(bounds, CGRectZero))
        return; // Not configured yet.
    
    CGRect previewFrame = UIEdgeInsetsInsetRect(bounds, [self _edgeInsets]);
    
    // We do need this to animate when entering/leaving rename mode in the document picker.
    //NSLog(@"%p animations UI:%d CA:%d %@", self, [UIView areAnimationsEnabled], ![CATransaction disableActions], NSStringFromCGRect(previewFrame));
    OUIWithAppropriateLayerAnimations(^{
        _imageLayer.frame = previewFrame;
    });

    // Image
    if (_group) {
        // Want to add multiple image layers? Want to force the caller to pre-composite a 3x3 grid of preview images?        
        OBASSERT(self.superview.hidden);
    } else {
        _imageLayer.contents = (id)[(OUIDocumentPreview *)[_previews lastObject] image];
    }
    
    // Highlighting (image alpha)
    {
        CGFloat alpha = 1;
        
        if (_highlighted || _downloadRequested)
            alpha = 0.5;
        
        _imageLayer.opacity = alpha;
    }
    
    // Shadow
    if (_selected || _draggingSource) {
        // No shadow
        OUIWithAppropriateLayerAnimations(^{
            _imageLayer.shadowPath = NULL;
            _imageLayer.shadowColor = NULL;
            _imageLayer.shadowOpacity = 0;
        });
    } else {
        OUIWithAppropriateLayerAnimations(^{
            CGPathRef path = CGPathCreateWithRect(CGRectMake(0, 0, previewFrame.size.width, previewFrame.size.height), NULL/*transform*/);
            _imageLayer.shadowPath = path;
            CFRelease(path);
            
            _imageLayer.shadowOpacity = 1;
            _imageLayer.shadowRadius = kOUIDocumentPreviewViewNormalShadowBlur;
            _imageLayer.shadowOffset = CGSizeMake(0, 1);
            _imageLayer.shadowColor = [OQMakeUIColor(kOUIDocumentPreviewViewNormalShadowColor) CGColor];
        });
    }

    // Selection
    if (_selectionLayer) {
        OUIWithoutLayersAnimating(^{
            _selectionLayer.frame = OUIEdgeInsetsOutsetRect(previewFrame, kOUIDocumentPreviewViewBorderEdgeInsets);
        });
    }
    
    if (_statusImageView) {
        UIImage *statusImage = _statusImageView.image;
        if (statusImage) {
            CGSize statusImageSize = statusImage.size;
            CGRect statusFrame = CGRectMake(CGRectGetMaxX(previewFrame) - statusImageSize.width, CGRectGetMinY(previewFrame), statusImageSize.width, statusImageSize.height);
            OB_UNUSED_VALUE(statusFrame); // http://llvm.org/bugs/show_bug.cgi?id=11576 Use in block doesn't count as use to prevent dead store warning
            
            OUIWithoutAnimating(^{
                _statusImageView.frame = statusFrame;
            });
        }
    }

    if (_transferProgressView) {
        OUIWithoutAnimating(^{
            CGRect previewFrameInsetForProgress = CGRectInset(previewFrame, 16, 16);
            CGRect progressFrame = previewFrameInsetForProgress;
            
            progressFrame.size.height = [_transferProgressView sizeThatFits:progressFrame.size].height;
            progressFrame.origin.y = CGRectGetMaxY(previewFrameInsetForProgress) - progressFrame.size.height;
            
            _transferProgressView.frame = progressFrame;
        });
    }
}

@end

