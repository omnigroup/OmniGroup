// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIScalingViewTile.h"
#import "OUITileDebug.h"

#import <OmniUI/OUIScalingView.h>
#import <QuartzCore/QuartzCore.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OUIScalingViewTile

static id _commonInit(OUIScalingViewTile *self)
{
    self.contentMode = UIViewContentModeRedraw;
    self.layer.zPosition = -100;
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


#pragma mark -
#pragma mark UIView subclass

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
{
    return nil; // Hammer time!
}

static OUIScalingView *_scalingView(OUIScalingViewTile *self)
{
    UIView *view = self.superview;
    if (![view isKindOfClass:[OUIScalingView class]]) {
        OBASSERT_NOT_REACHED("Tiles must live inside an scaling view.");
        return nil;
    }
    return (OUIScalingView *)view;
}

// our frame controls what portion of our superview we draw.
- (void)setFrame:(CGRect)frame;
{
    if (CGRectEqualToRect(frame, self.frame))
        return;
    [super setFrame:frame];
    [self setNeedsDisplay];
}

#if 0
- (void)setNeedsDisplay;
{
    DEBUG_TILE_DRAW("Tile %p -setNeedsDisplay", self);
    [super setNeedsDisplay];
}

- (void)setNeedsDisplayInRect:(CGRect)rect;
{
    DEBUG_TILE_DRAW("Tile %p -setNeedsDisplayInRect:%@", self, NSStringFromCGRect(rect));
    [super setNeedsDisplayInRect:rect];
}
#endif

- (void)drawRect:(CGRect)rect;
{
    OUIScalingView *view = _scalingView(self);
    if (!view) {
        [[UIColor redColor] set];
        UIRectFill(rect);
        return;
    }
    
    // Our frame is the rect in the scaling view that we are responsible for caching. Our bounds, will be zero-based, though.
    CGRect frame = self.frame;
    DEBUG_TILE_DRAW("Tile %p with frame %@", self, NSStringFromCGRect(frame));
                  
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGContextSaveGState(ctx);
    {
        CGContextTranslateCTM(ctx, -frame.origin.x, -frame.origin.y);
        [view establishTransformToRenderingSpace:ctx];
        [view drawScaledContent:frame];
    }
    CGContextRestoreGState(ctx);
    
#if 0 && defined(DEBUG_bungi)
    [[UIColor redColor] set];
    UIRectFrame(self.bounds);
#endif
}

@end
