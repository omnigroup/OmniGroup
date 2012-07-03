// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIInspectorTextWellEditor.h"

RCS_ID("$Id$");

@implementation OUIInspectorTextWellEditor

@synthesize clipRect = _clipRect;
- (void)setClipRect:(CGRect)clipRect;
{
    if (CGRectEqualToRect(_clipRect, clipRect))
        return;
    _clipRect = clipRect;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    {
#ifdef DEBUG_EDITOR_FRAME_ENABLED
        // avoid clipping and just draw the rect that would be the clip
        CGContextAddRect(ctx, CGRectInset(_clipRect, 0.5, 0.5));
        [[UIColor blueColor] set];
        CGContextStrokePath(ctx);
#else
        CGContextAddRect(ctx, _clipRect);
        CGContextClip(ctx);
#endif
        
        [super drawRect:rect];
    }
    CGContextRestoreGState(ctx);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
{
    UIView *hitView = [super hitTest:point withEvent:event];
    
    // We extent beyond what the user can see with our clipping rect hiding this. Don't let touches happen outside our unclipped area (unless they are some other view, like the text system autocorrection widgets).
    if (hitView == self && !CGRectContainsPoint(_clipRect, point))
        return nil;
    
    return hitView;
}

@end

