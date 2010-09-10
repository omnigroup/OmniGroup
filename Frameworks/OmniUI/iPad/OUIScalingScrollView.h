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

@interface OUIScalingScrollView : UIScrollView
{
@private
    OFExtent _allowedEffectiveScaleExtent;
    BOOL _centerContent;
}

@property(assign,nonatomic) OFExtent allowedEffectiveScaleExtent;
@property (assign) BOOL centerContent;

- (CGFloat)fullScreenScaleForCanvasSize:(CGSize)canvasSize;

- (void)adjustScaleTo:(CGFloat)effectiveScale canvasSize:(CGSize)canvasSize;
- (void)adjustContentInset;

@end
