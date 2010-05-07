// Copyright 2010 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

/* This just draws parallel lines separated by (dx,dy) in order to fill the rectangle with a bit of extra (outset). */
static void OQAppendHatchingForRect(CGContextRef ctxt, CGRect rect, CGFloat outset, CGFloat dx, CGFloat dy)
{
    CGAffineTransform xform = CGAffineTransformMakeTranslation(rect.origin.x, rect.origin.y);
    
    if (fabs(dx) < fabs(dy)) {
        SWAP(xform.a, xform.c);
        SWAP(xform.b, xform.d);
        SWAP(dx, dy);
        SWAP(rect.size.width, rect.size.height);
    }
    
    if (dx < 0) {
        dx = -dx;
        dy = -dy;
    }
    
    CGFloat minx;
    CGFloat shadow = rect.size.height * ( -dy / dx );
    if (dy < 0) 
        minx = - shadow;
    else
        minx = 0;
    
    CGFloat outset_dx = outset * ( -dy / dx );
    
    CGFloat thisx = minx;
    for(;;) {
        CGPoint p;
        
        p.x = thisx - outset_dx;
        p.y = - outset;
        p = CGPointApplyAffineTransform(p, xform);
        CGContextMoveToPoint(ctxt, p.x, p.y);
        
        p.x += ( shadow + outset_dx ) * xform.a + ( rect.size.height + outset ) * xform.c;
        p.y += ( shadow + outset_dx ) * xform.b + ( rect.size.height + outset ) * xform.d;
        CGContextAddLineToPoint(ctxt, p.x, p.y);
        
        if (thisx > rect.size.width && thisx+shadow > rect.size.width)
            break;
        thisx += ( dy*dy / dx ) + dx;
    }
    
}

void OQCrosshatchRect(CGContextRef ctxt, CGRect rect, CGFloat lineWidth, CGFloat dx, CGFloat dy)
{
    CGContextSaveGState(ctxt);
    CGContextClipToRect(ctxt, rect);
    CGContextSetLineWidth(ctxt, lineWidth);
    CGContextBeginPath(ctxt);
    OQAppendHatchingForRect(ctxt, rect, lineWidth, dx, dy);
    OQAppendHatchingForRect(ctxt, rect, lineWidth, -dy, dx);
    CGContextStrokePath(ctxt);
    CGContextRestoreGState(ctxt);
}

