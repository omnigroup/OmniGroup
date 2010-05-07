// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIScrollView.h>
#import <OmniFoundation/OFExtent.h>

#define OUI_SNAP_TO_ZOOM_FIT_PERCENT (0.1)

@interface OUIScalingScrollView : UIScrollView
{
@private
    OFExtent _allowedEffectiveScaleExtent;
    BOOL _lastScaleWasFullScale;
}

@property(assign,nonatomic) OFExtent allowedEffectiveScaleExtent;
@property(readonly) BOOL lastScaleWasFullScale;

- (void)adjustScaleBy:(CGFloat)scale canvasSize:(CGSize)canvasSize;
- (void)adjustScaleTo:(CGFloat)effectiveScale canvasSize:(CGSize)canvasSize;
- (void)adjustContentInset;

@end
