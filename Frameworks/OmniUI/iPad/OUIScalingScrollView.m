// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIScalingScrollView.h>

#import <OmniUI/OUITiledScalingView.h>
#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$");

@interface OUIScalingScrollView ()

@property (nonatomic) BOOL haveDoneInitialInsetAdjustment;

@end

@implementation OUIScalingScrollView

static id _commonInit(OUIScalingScrollView *self)
{
    self->_allowedEffectiveScaleExtent = OFExtentMake(1, 8);
    self->_centerContent = YES;
    
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

// Caller should call -sizeInitialViewSizeFromUnscaledContentSize on us after setting this.
@synthesize allowedEffectiveScaleExtent = _allowedEffectiveScaleExtent;

// Need to explicitly declare this @dynamic since the superclass, not this implementation, is responsible for synthesizing it
@dynamic delegate;

static OUIScalingView *_scalingView(OUIScalingScrollView *self)
{
    OUIScalingView *view = (OUIScalingView *)[self.delegate viewForZoomingInScrollView:self];
    OBASSERT(view);
    OBASSERT([view isKindOfClass:[OUIScalingView class]]);
    return view;
}

- (void)setBounds:(CGRect)bounds {
    CGRect oldBounds = self.bounds;
    
    OBASSERT(!isnan(bounds.origin.x) && !isnan(bounds.origin.y) && !isnan(bounds.size.width) && !isnan(bounds.size.height), "Attempted to set non-numerical value to bounds");
    if (isnan(bounds.origin.x)) {
        bounds.origin.x = oldBounds.origin.x;
    }
    if (isnan(bounds.origin.y == NAN)) {
        bounds.origin.y = oldBounds.origin.y;
    }
    if (isnan(bounds.size.width == NAN)) {
        bounds.size.width = oldBounds.size.width;
    }
    if (isnan(bounds.size.height == NAN)) {
        bounds.size.height = oldBounds.size.height;
    }
    
    [super setBounds:bounds];
    if (!CGSizeEqualToSize(oldBounds.size, self.bounds.size) && [self.delegate respondsToSelector:@selector(scrollViewDidChangeFrame)]) {
        [self.delegate scrollViewDidChangeFrame];
    }
}

- (CGFloat)fullScreenScaleForUnscaledContentSize:(CGSize)unscaledContentSize;
{
    if (unscaledContentSize.width == 0 || unscaledContentSize.height == 0) {
        return 1;
    }
    
    CGRect scrollBounds = [self.delegate scalingScrollViewContentViewFullScreenBounds:self];

    CGFloat fitXScale = CGRectGetWidth(scrollBounds) / unscaledContentSize.width;
    CGFloat fitYScale = CGRectGetHeight(scrollBounds) / unscaledContentSize.height;
    CGFloat fullScreenScale = MIN(fitXScale, fitYScale); // the maximum size that won't make us scrollable.
    
    return fullScreenScale;
}

- (void)adjustScaleTo:(CGFloat)effectiveScale unscaledContentSize:(CGSize)unscaledContentSize;
{
    if (unscaledContentSize.height <= 0 || unscaledContentSize.width <= 0 || effectiveScale <= 0) {
        OBASSERT_NOT_REACHED(@"unscaledContentSize must be positive and non-zero in both dimensions and effectiveScale must be greater than zero");
        return;
    }
    
    OUIScalingView *view = _scalingView(self);
    if (!view || view.scaleEnabled == NO)
        return;
    
    CGSize oldScrollBuffer = self.scrollBufferSize;
    CGSize preferredScrollBufferSize = [self preferredScrollBufferSizeForScale:effectiveScale];

    if (view.scale == effectiveScale && CGSizeEqualToSize(oldScrollBuffer, preferredScrollBufferSize)) {
        // early out if we're not changing anything
        return;
    }

    _scrollBufferSize = preferredScrollBufferSize;

    view.scale = effectiveScale;
    
    // The scroll view has futzed with our transform to make us look bigger, but we're going to do this by fixing our frame/bounds.
    view.transform = CGAffineTransformIdentity;
    
    // Build the new frame based on an integral scaling of the canvas size and make the bounds match. Thus the view is 1-1 pixel resolution.
    CGSize viewportBufferSize = preferredScrollBufferSize;
    // Buffer needs to be added to each edge, so * 2
    CGSize fullSize = CGSizeMake(effectiveScale * unscaledContentSize.width + 2 * viewportBufferSize.width,
                                 effectiveScale * unscaledContentSize.height + 2 * viewportBufferSize.height);
    CGRect scaledContentSize = CGRectIntegral(CGRectMake(0, 0, fullSize.width, fullSize.height));
    view.frame = scaledContentSize;
    view.bounds = scaledContentSize;
    
    // Need to reset the min/max zoom to be factors of our current scale.  The minimum scale allowed needs to be sufficient to fit the whole graph on screen.  Then, allow zooming up to at least 4x that size or 4x the canvas size, whatever is larger.
    CGFloat minimumZoom = MIN(OFExtentMin(_allowedEffectiveScaleExtent), [self fullScreenScaleForUnscaledContentSize:unscaledContentSize]);
    CGFloat maximumZoom = OFExtentMax(_allowedEffectiveScaleExtent);

    BOOL isTiled = [view isKindOfClass:[OUITiledScalingView class]];
    if (!isTiled) {
        // If we are one big view, we need to limit our scale based on estimated VM size.
        
        // Limit the maximum zoom size (for now) based on the pixel count we'll cover.  Assume each pixel in the view backing store is 4 bytes. Limit to 16MB of video memory (other backing stores, animating between two zoom levels will temporarily double this). This does mean that if you have a large canvas, we might not even allow you to reach 100%. Better than crashing.
        CGFloat maxVideoMemory = 16*1024*1024;
        CGFloat canvasVideoUsage = 4 * unscaledContentSize.width * unscaledContentSize.height;
        maximumZoom = MIN(maximumZoom, sqrt(maxVideoMemory / canvasVideoUsage));
    }
        
    // Bummer. Large canvas?
    if (minimumZoom > maximumZoom)
        minimumZoom = maximumZoom;
    
    CGFloat minFactor = minimumZoom/effectiveScale;
    CGFloat maxFactor = maximumZoom/effectiveScale;
    
    self.minimumZoomScale = minFactor;
    self.maximumZoomScale = maxFactor;
    
    if (isTiled)
        [(OUITiledScalingView *)view tileVisibleRect];
    
    CGSize viewSize = view.frame.size;
    self.contentSize = viewSize;// this has the side effect of scrolling back to origin of scrollview

    [self adjustContentInsetAnimated:NO];  // this has the side effect of scrolling back to origin of scrollview
    
    // UIScrollView will show scrollers if we have the same (or maybe it is nearly the same) size but aren't really scrollable.  See <bug://bugs/60077> (weird scroller issues in landscape mode)
    CGSize scrollSize = self.bounds.size;
    self.showsHorizontalScrollIndicator = scrollSize.width < viewSize.width;
    self.showsVerticalScrollIndicator = scrollSize.height < viewSize.height;
    
    [view scaleChanged];
}

// Might want buffer for a scale that's about to be set, not our current one
- (CGSize)preferredScrollBufferSizeForScale:(CGFloat)scale
{
    CGSize viewportBufferSize = CGSizeZero;
    
    NSObject<OUIVisibleBoundsDelegate> *boundsDelegate = _scalingView(self).visibleBoundsDelegate;
    if (boundsDelegate != nil) {
        viewportBufferSize = [boundsDelegate sizeOfViewport];
    } else {
        OBASSERT_NOT_REACHED(@"scrollview expects a bounds delegate to be able to calculate scrollbuffer");
    }
    CGFloat percentage = self.delegate.scrollBufferAsPercentOfViewportSize;
    viewportBufferSize.width *= percentage;
    viewportBufferSize.height *= percentage;
    return viewportBufferSize;
}

- (void)adjustContentInsetAnimated:(BOOL)animated;
{
    OUIScalingView *view = _scalingView(self);
    if (!view || !_centerContent)
        return;
    
    //NSLog(@"adjustContentInset");
    
    // If the contained view has a size smaller than the scroll view, it will get pinned to the upper left if there are no content insets.
    CGSize viewSize = view.frame.size;
    CGSize scrollSize = self.bounds.size;
    
    CGFloat xSpace = MAX(0, scrollSize.width - viewSize.width);
    CGFloat ySpace = MAX(0, scrollSize.height - viewSize.height);
    
    UIEdgeInsets totalInsets = UIEdgeInsetsMake(ySpace/2, xSpace/2, ySpace/2, xSpace/2);  // natural insets to center the canvas
    totalInsets.left = fmax(totalInsets.left, self.minimumInsets.left);
    totalInsets.right = fmax(totalInsets.right, self.minimumInsets.right);

    if (ySpace > self.minimumInsets.top + self.minimumInsets.bottom) {
        // need more top or bottom insets
        totalInsets.top = fmax(totalInsets.top, self.minimumInsets.top);
        totalInsets.bottom = fmax(totalInsets.bottom, self.minimumInsets.bottom);
    } else {
        // all the needed space is accounted for.  don't try to divide it evenly because that may not be correct (toolbars are shorter than nav bars).
        totalInsets.top = self.minimumInsets.top;
        totalInsets.bottom = self.minimumInsets.bottom;
    }
    
    totalInsets.bottom = fmax(totalInsets.bottom, self.temporaryBottomInset);
    
    if (UIEdgeInsetsEqualToEdgeInsets(self.contentInset, totalInsets))
        return;
    
    if (animated) {
        [UIView animateWithDuration:0.4 animations:^{
            self.contentInset = totalInsets;
        }];
    } else {
        self.contentInset = totalInsets;
    }
}

#pragma mark -
#pragma mark UIView subclass

- (void)layoutSubviews;
{
    if (!_haveDoneInitialInsetAdjustment) {
        [self adjustContentInsetAnimated:NO];
        _haveDoneInitialInsetAdjustment = YES;
    }
}

@end
