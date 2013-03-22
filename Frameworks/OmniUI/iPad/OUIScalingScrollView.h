// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIScrollView.h>
#import <OmniFoundation/OFExtent.h>

@interface OUIScalingScrollView : UIScrollView

@property(nonatomic) OFExtent allowedEffectiveScaleExtent;
@property(nonatomic) BOOL centerContent;
@property(nonatomic) UIEdgeInsets extraEdgeInsets;

- (CGFloat)fullScreenScaleForCanvasSize:(CGSize)canvasSize;

- (void)adjustScaleTo:(CGFloat)effectiveScale canvasSize:(CGSize)canvasSize;
- (void)adjustContentInsetAnimated:(BOOL)animated;

@end

@interface UIViewController (OUIScalingScrollView)
// Called on the top view controller by -fullScreenScaleForCanvasSize:. Defaults to returning just the bounds. of the view controller's view.
@property(nonatomic,readonly) CGRect contentViewFullScreenBounds;
@end
