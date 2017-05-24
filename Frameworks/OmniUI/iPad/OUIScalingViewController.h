// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIScrollNotifier.h>
#import <OmniUI/OUIScalingScrollView.h>

#define OUI_SNAP_TO_ZOOM_PERCENT (0.05)

@class OUIScalingScrollView;

@interface OUIScalingViewController : UIViewController <OUIScalingScrollViewDelegate, OUIScrollNotifier>

@property(nonatomic,strong) IBOutlet OUIScalingScrollView *scrollView;

// UIScrollViewDelegate methods that we implement, so subclasses can know whether to call super
- (void)scrollViewDidScroll:(UIScrollView *)scrollView;
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate;
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView;
- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view;
- (void)scrollViewDidZoom:(UIScrollView *)scrollView;
- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale;

// Mostly internal methods. Need to work more on a good public subclass API for this class
- (void)adjustScaleBy:(CGFloat)scale;
- (void)adjustScaleTo:(CGFloat)effectiveScale;
- (void)adjustScaleToExactly:(CGFloat)scale;
- (CGFloat)fullScreenScale;
- (CGSize)fullScreenSize;
- (void)adjustContentInset;
- (void)sizeInitialViewSizeFromUnscaledContentSize;

// OUIScalingScrollViewDelegate
- (CGFloat)scrollBufferAsPercentOfViewportSize;

// Added so that OUIScalingScrollView can tell if it is in the middle of a zoom (Used by Graffle to get rid of stutter when zooming way out on a canvas)
- (BOOL)isZooming;

// Subclasses
@property(readonly,nonatomic) CGSize unscaledContentSize; // Return CGSizeZero if you don't know yet (and then make sure you call -sizeInitialViewSizeFromUnscaledContentSize when you can answer)

@end
