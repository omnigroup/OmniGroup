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

RCS_ID("$Id$");

@implementation OUIScalingViewController

- (void)dealloc;
{
    _scrollView.delegate = nil;
    [_scrollView release];
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

- (void)adjustScaleBy:(CGFloat)scale;
{
    if (!_scrollView)
        return; // just bail if UI not loaded yet

    CGSize canvasSize = self.canvasSize;
    [_scrollView adjustScaleBy:scale canvasSize:canvasSize];
}

- (void)adjustScaleTo:(CGFloat)effectiveScale;
{
    if (!_scrollView)
        return; // just bail if UI not loaded yet
    
    CGSize canvasSize = self.canvasSize;
    [_scrollView adjustScaleTo:effectiveScale canvasSize:canvasSize];
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
    
    if (_scrollView.lastScaleWasFullScale)
        [self sizeInitialViewSizeFromCanvasSize];
    else
        [self adjustContentInset];

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
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView;
{
    OUIScalingView *view = _scalingView(self);
    if (!view)
        return;
    
    // TODO: Add all the clamping/snapping as a utility.
    // TODO: Add "Fit Screen" hooks.
    
    CGFloat effectiveScale = view.scale * scrollView.zoomScale;
    NSString *zoomLabel = [NSString stringWithFormat:@"%d%%", (NSUInteger)rint(effectiveScale * 100)];
    
    [OUIOverlayView displayTemporaryOverlayInView:scrollView withString:zoomLabel alignment:OUIOverlayViewAlignmentMidCenter displayInterval:0.5];
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(float)scale; // scale between minimum and maximum. called after any 'bounce' animations
{
    _isZooming = NO;
    [self adjustScaleBy:scale]; // This will re-tile the view
}

@end
