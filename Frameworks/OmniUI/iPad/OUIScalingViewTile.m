// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIScalingViewTile.h>
#import <OmniUI/OUITileDebug.h>

#import <OmniUI/OUIScalingView.h>
#import <QuartzCore/QuartzCore.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFBacktrace.h>

RCS_ID("$Id$");

OFDeclareDebugLogLevel(OUIScalingTileViewDebugLayout);
OFDeclareDebugLogLevel(OUIScalingTileViewDebugDrawing);

@implementation OUIScalingViewTile
{
    UIView *_recentlyDrawnDebugView;
    NSTimer *_removeRecentlyDrawnDebugViewTimer;
}

static id _commonInit(OUIScalingViewTile *self)
{
    self.contentMode = UIViewContentModeRedraw;
    self.layer.zPosition = -100;
    self.opaque = NO;
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

- (void)dealloc;
{
    [_removeRecentlyDrawnDebugViewTimer invalidate];
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
    
    if (_recentlyDrawnDebugView) {
        _recentlyDrawnDebugView.frame = self.bounds;
    }
    
    [self setNeedsDisplay];
}

- (void)setNeedsDisplay;
{
    DEBUG_TILE_DRAW(1, "Tile %p -setNeedsDisplay", self);
    DEBUG_TILE_DRAW(2, "Calling stack:\n%@", OFCopySymbolicBacktrace());
    
    [super setNeedsDisplay];
}

- (void)setNeedsDisplayInRect:(CGRect)rect;
{
    DEBUG_TILE_DRAW(1, "Tile %p -setNeedsDisplayInRect:%@", self, NSStringFromCGRect(rect));
    DEBUG_TILE_DRAW(2, "Calling stack:\n%@", OFCopySymbolicBacktrace());

    [super setNeedsDisplayInRect:rect];
}

- (void)drawRect:(CGRect)rect;
{
    OUIScalingView *view = _scalingView(self);
    if (!view) {
        [[UIColor redColor] set];
        UIRectFill(rect);
        return;
    }
    
    DEBUG_TILE_DRAW(1, "Tile %p with frame %@", self, NSStringFromCGRect(self.frame));
                  
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGContextSaveGState(ctx);
    {
        // translate the context for our frame
        CGAffineTransform tileFrameTranslation = CGAffineTransformMakeTranslation(-self.frame.origin.x, -self.frame.origin.y);
        CGContextConcatCTM(ctx, tileFrameTranslation);
        
        // and do the inverse for the drawing rect
        CGRect drawingRect = CGRectApplyAffineTransform(rect, CGAffineTransformInvert(tileFrameTranslation));
        
        // context and rect are now in "ViewSpace", meaning the coordinate space belonging to the scaling view which this tile is a part of
        
        // and allow scaling view to deal with scale (or anything else it wants, really, but probably it's just a scale)
        [view establishTransformFromViewSpaceToUnscaledSpace:ctx];
        
        // and apply the inverse to the rect
        drawingRect = [view convertRectFromViewSpaceToUnscaledSpace:drawingRect];
        
        if (CGRectEqualToRect(drawingRect, CGRectZero)) {
            OBASSERT_NOT_REACHED("something wrong with a transform?");
        }
        // and ask the view to draw
        [view drawScaledContent:drawingRect];
    }
    CGContextRestoreGState(ctx);
    
#ifdef DEBUG_shannon
    [[UIColor redColor] set];
    UIRectFrame(self.bounds);
#endif
    
    if (OUIScalingTileViewDebugDrawing > 0) {
        [[UIColor redColor] set];
        UIRectFrame(self.bounds);
        
        if (_recentlyDrawnDebugView == nil) {
            [UIView performWithoutAnimation:^{
                _recentlyDrawnDebugView = [[UIView alloc] initWithFrame:self.bounds];
                _recentlyDrawnDebugView.backgroundColor = [UIColor colorWithRed:1 green:0.5 blue:0.5 alpha:0.25];
                [self addSubview:_recentlyDrawnDebugView];
            }];
        }
        
        [_removeRecentlyDrawnDebugViewTimer invalidate];
        _removeRecentlyDrawnDebugViewTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(_removeRecentlyDrawnDebugViewTimerFired:) userInfo:nil repeats:NO];
    }
}

#pragma mark - Private

- (void)_removeRecentlyDrawnDebugViewTimerFired:(NSTimer *)timer;
{
    OBASSERT(_recentlyDrawnDebugView);
    
    _removeRecentlyDrawnDebugViewTimer = nil;
    
    [UIView performWithoutAnimation:^{
        [_recentlyDrawnDebugView removeFromSuperview];
        _recentlyDrawnDebugView = nil;
    }];
}

@end
