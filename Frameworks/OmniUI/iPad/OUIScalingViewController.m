// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIScalingViewController.h>

#import <OmniUI/OUIScalingView.h>
#import <OmniUI/OUIScalingScrollView.h>
#import <OmniUI/OUIOverlayView.h>
#import <OmniUI/OUITiledScalingView.h>
#import <OmniUI/UIView-OUIExtensions.h>

RCS_ID("$Id$");

@implementation OUIScalingViewController

- (void)dealloc;
{
    _scrollView.delegate = nil;
    [_scrollView release];
    [_zoomOverlay release];
    
    [super dealloc];
}

@synthesize scrollView = _scrollView;

static OUIScalingView *_scalingView(OUIScalingViewController *self)
{
    if (![self isViewLoaded])
        return nil;
    
    OBASSERT(self->_scrollView);
    OUIScalingView *view = (OUIScalingView *)[self->_scrollView.delegate viewForZoomingInScrollView:self->_scrollView];
    OBASSERT(view);
    OBASSERT([view isKindOfClass:[OUIScalingView class]]);
    return view;
}
                             
#if 0
- (void)_logScrollInfo:(NSString *)reason;
{
    OUIScalingView *view = _scalingView(self);
    if (!view)
        return;
    
    NSLog(@"%@:", reason);
    NSLog(@"  view.frame %@", NSStringFromRect(view.frame));
    NSLog(@"  view.bounds %@", NSStringFromRect(view.bounds));
    NSLog(@"  view.transform %@", NSStringFromCGAffineTransform(view.transform));
    NSLog(@"  zoomScale %f", _scrollView.zoomScale);
    NSLog(@"  scrollView.bounds %@", NSStringFromRect(_scrollView.bounds));
    NSLog(@"  scrollView.frame %@", NSStringFromRect(_scrollView.frame));
    NSLog(@"  scrollView.transform %@", NSStringFromCGAffineTransform(_scrollView.transform));
    NSLog(@"  scrollView.minimumZoomScale %f", _scrollView.minimumZoomScale);
    NSLog(@"  scrollView.maximumZoomScale %f", _scrollView.maximumZoomScale);
    NSLog(@"  contentSize = %@", NSStringFromSize(_scrollView.contentSize));
    NSLog(@"  contentInset = %@", NSStringFromUIEdgeInsets(_scrollView.contentInset));
    NSLog(@"  contentOffset = %@", NSStringFromPoint(_scrollView.contentOffset));
}
#endif

- (CGFloat)fullScreenScale;
{
    return [_scrollView fullScreenScaleForCanvasSize:[self canvasSize]];
}

- (CGFloat)snapZoomScale:(CGFloat)scale;
{
    // Check if the zoom scale is close to 100%.
    CGFloat one = 1.0;
    CGFloat diff = fabs(scale - one);
    BOOL snapToOne = (diff/one < OUI_SNAP_TO_ZOOM_PERCENT);
    
    // Check if the zoom scale is close to the full screen scale.
    CGFloat fullScreenScale = [self fullScreenScale];
    diff = fabs(scale - fullScreenScale);
    BOOL snapToFullScreen = (diff/fullScreenScale < OUI_SNAP_TO_ZOOM_PERCENT);
    
    // If the caller passes in a non-positive number, snap to fit the screen
    if (scale <= 0) {
        return fullScreenScale;
    }
    
    // If the zoom scale is near both 100% and fitting the screen, use whichever is smaller.  That way, you never get into a situation where you can't see the whole canvas.
    if (snapToOne && snapToFullScreen) {
        return MIN(one, fullScreenScale);
    }
    
    // Snap to 100%.
    if (snapToOne) {
        return one;
    }
    
    // Snap to fit the screen.
    if (snapToFullScreen) {
        return fullScreenScale;
    }
    
    // No snap
    return scale;
}

- (void)adjustScaleBy:(CGFloat)scale;
{
    if (!_scrollView)
        return; // just bail if UI not loaded yet
    
    OUIScalingView *view = _scalingView(self);
    if (!view)
        return;
    
    // To get unpixelated drawing, when we are scaled up or down, we need to adjust our view to have a 1-1 pixel mapping.  UIScrollView's "scaling" is just scaling our backing store.
    // If we were at 2x scale and we are 2x more scaled now, then we should be 4x!
    [self adjustScaleTo:view.scale * scale];
}

- (void)adjustScaleTo:(CGFloat)effectiveScale;
{
    if (!_scrollView)
        return; // just bail if UI not loaded yet
    
    OUIScalingView *view = _scalingView(self);
    if (!view)
        return;
    
    effectiveScale = [self snapZoomScale:effectiveScale];
    
    CGSize canvasSize = self.canvasSize;
    [_scrollView adjustScaleTo:effectiveScale canvasSize:canvasSize];
    
    _lastScaleWasFullScale = (view.scale == [self fullScreenScale]);
}

- (void)adjustContentInset;
{
    if (!_scrollView)
        return; // just bail if UI not loaded yet

    [_scrollView adjustContentInset];
}

- (void)sizeInitialViewSizeFromCanvasSize;
{
    OUIScalingView *view = _scalingView(self);
    if (!view)
        return;
    
    CGSize canvasSize = self.canvasSize;
    if (CGSizeEqualToSize(canvasSize, CGSizeZero))
        return;
    
    [self adjustScaleTo:-1]; // Scales as large as possible, respecting aspect ratio and the hard maximum scale.
    [self adjustContentInset];
    
//    UIEdgeInsets insets = _scrollView.contentInset;
//    _scrollView.contentOffset
    [_scrollView scrollRectToVisible:view.frame animated:NO];
//    NSLog(@"initial offset = %@, inset %@", NSStringFromPoint(_scrollView.contentOffset), NSStringFromUIEdgeInsets(_scrollView.contentInset));
}

// Subclasses need to return the nominal size of the canvas; the size in CoreGraphics coordinates.
- (CGSize)canvasSize;
{
    return CGSizeZero;
}

- (OFExtent)allowedEffectiveScaleExtent;
{
    return OFExtentMake(1, 8);
}

- (UIGestureRecognizer *)zoomingGestureRecognizer;
// This could break in the future if the architecture of UIScrollView is changed, but it's the only way I know of to get the current centroid of touches from a gesture recognizer that has captured the touch event stream.
{
    UIView *view = _scrollView;
    for (UIGestureRecognizer *gestureRecognizer in [view gestureRecognizers]) {
        if ([gestureRecognizer isKindOfClass:[UIPinchGestureRecognizer class]]) {
            //NSLog(@"GR: %@", gestureRecognizer);
            return gestureRecognizer;
        }
    }
    OBASSERT_NOT_REACHED("Was unable to find a pinch gesture recognizer in the scrollview.");
    return nil;
}

#pragma mark -
#pragma mark UIViewController subclass;

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration;
{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    OUIScalingView *view = _scalingView(self);
    view.rotating = YES;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation;
{
    OUIScalingView *view = _scalingView(self);
    view.rotating = NO;
    
    //OUILogViewTree(view);
    
//    [view setShadowEdgeViewVisibility:NO];
//    
//    [UIView beginAnimations:@"didRotateFromInterfaceOrientation animation" context:NULL];
//    {
//        [UIView setAnimationDelegate:self];
//        [UIView setAnimationDidStopSelector:@selector(zoomAdjustmentAnimationDidStop:finished:context:)];
//        //[UIView setAnimationDuration:1.0];
        
        if (_lastScaleWasFullScale)
            [self sizeInitialViewSizeFromCanvasSize];
        else
            [self adjustContentInset];
//    }
//    [UIView commitAnimations];

    //[self _logScrollInfo:@"did rotate"];

    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
}

#pragma mark -
#pragma mark UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView;
{
    if (!_isZooming) {
        OUIScalingView *view = _scalingView(self);
        
        if ([view isKindOfClass:[OUITiledScalingView class]])
            [(OUITiledScalingView *)view tileVisibleRect];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;      // called when scroll view grinds to a halt
{
    [self adjustContentInset];
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view;
{
    _isZooming = YES;
    
    if (!_zoomOverlay) {
        _zoomOverlay = [[OUIOverlayView alloc] initWithFrame:CGRectZero];
        _zoomOverlay.text = @"Zoom";
    }
    UIView *stableView = scrollView.superview;
    
    // This automatically falls back to something sensible if the gesture recognizer is nil:
    [_zoomOverlay centerAtPositionForGestureRecognizer:[self zoomingGestureRecognizer] inView:stableView];
    
    [_zoomOverlay displayInView:stableView];
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView;
{
    OUIScalingView *view = _scalingView(self);
    if (!view)
        return;
    
    CGFloat effectiveScale = view.scale * scrollView.zoomScale;
    CGFloat snappedScale = [self snapZoomScale:effectiveScale];
    
    NSString *zoomLabel;
    if (snappedScale == [self fullScreenScale]) {
        zoomLabel = NSLocalizedStringFromTableInBundle(@"Fit", @"OmniUI", OMNI_BUNDLE, @"Overlay text when zoomed to fit screen");
    }
    else {
        zoomLabel = [NSString stringWithFormat:@"%d%%", (NSUInteger)rint(snappedScale * 100)];
    }
    
    _zoomOverlay.text = zoomLabel;
    [_zoomOverlay useSuggestedSize];
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(float)scale; // scale between minimum and maximum. called after any 'bounce' animations
{
    [_zoomOverlay hide];
    
    _isZooming = NO;
    
//    [_scalingView(self) setShadowEdgeViewVisibility:NO];
//    [UIView beginAnimations:@"scrollViewDidEndZooming animation" context:NULL];
//    {
//        [UIView setAnimationDelegate:self];
//        [UIView setAnimationDidStopSelector:@selector(zoomAdjustmentAnimationDidStop:finished:context:)];
//        [UIView setAnimationDuration:0.1];
        
        [self adjustScaleBy:scale]; // This will re-tile the view
//    }
//    [UIView commitAnimations];
}

- (void)zoomAdjustmentAnimationDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context;
{
    [_scalingView(self) setShadowEdgeViewVisibility:YES];
}

@end
