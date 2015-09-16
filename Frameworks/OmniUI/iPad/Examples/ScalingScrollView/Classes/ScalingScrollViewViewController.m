// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ScalingScrollViewViewController.h"

#import "ScalingView.h"
#import "Box.h"

RCS_ID("$Id$")

@interface ScalingScrollViewViewController () <UIGestureRecognizerDelegate>
@end

@implementation ScalingScrollViewViewController
{
    UIPanGestureRecognizer *_dragRecognizer;
    
    Box *_box;
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView;
{
    return _scalingView;
}

#pragma mark - OUIScalingViewController subclass

- (CGSize)unscaledContentSize;
{
    return CGSizeMake(400, 300);
}

#pragma mark - UIViewController subclass

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    [self sizeInitialViewSizeFromUnscaledContentSize];
    
    _box = [[Box alloc] init];
    _box.bounds = CGRectMake(10, 10, 50, 50);
    
    _scalingView.boxes = @[_box];
    
    _dragRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_dragRecognizerAction:)];
    _dragRecognizer.enabled = YES;
    
    _dragRecognizer.delegate = self;
    
    [_scalingView addGestureRecognizer:_dragRecognizer];
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer;
{
    if (gestureRecognizer == _dragRecognizer) {
        CGPoint pt = [gestureRecognizer locationInView:_scalingView];
        CGAffineTransform viewToModelTransform = _scalingView.transformFromRenderingSpace;
        pt = CGPointApplyAffineTransform(pt, viewToModelTransform);

        return CGRectContainsPoint(_box.bounds, pt);
    }
    
    OBASSERT("Unknown recognizer");
    return YES;
}

#pragma mark - Private

- (void)_dragRecognizerAction:(UIPanGestureRecognizer *)recognizer;
{
    // Terrible dragging support to get some redraw
    CGPoint dragPoint;
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
        case UIGestureRecognizerStateEnded:
            dragPoint = [recognizer locationInView:_scalingView];
            break;
         
        default:
            return;
    }
    
    CGAffineTransform viewToModelTransform = _scalingView.transformFromRenderingSpace;
    dragPoint = CGPointApplyAffineTransform(dragPoint, viewToModelTransform);
    
    CGRect bounds = _box.bounds;
    bounds.origin.x = floor(dragPoint.x - _box.bounds.size.width/2);
    bounds.origin.y = floor(dragPoint.y - _box.bounds.size.height/2);
    
    [_scalingView boxBoundsWillChange:_box];
    _box.bounds = bounds;
    [_scalingView boxBoundsDidChange:_box];
}

@end
