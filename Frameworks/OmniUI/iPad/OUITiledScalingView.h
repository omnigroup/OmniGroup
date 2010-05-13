// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIScalingView.h>

@class OUITiledScalingView;
typedef void (*OUITiledScalingViewTiling)(OUITiledScalingView *self, NSMutableArray *tiles);

// For this to be effective, the subclass needs to reliably dirty only the right rects and to only render stuff within the given clip rect. Otherwise, this can be much slower than the untiled approach (for example if text is rasterized and then completely clipped).
@interface OUITiledScalingView : OUIScalingView
{
@private
    NSMutableArray *_tiles;
}

// defaults to returning a regular square tiling
+ (OUITiledScalingViewTiling)tiling;

- (void)tileVisibleRect;

@end
