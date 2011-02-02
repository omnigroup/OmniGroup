// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorDividerLine.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniUI/OUIInspector.h>
#import <OmniQuartz/OQDrawing.h>

RCS_ID("$Id$");

@implementation OUIInspectorDividerLine

static id _commonInit(OUIInspectorDividerLine *self)
{
    // The shadow radius leaves partially transparent pixels that look too dark if we marked opaque
    self.opaque = NO;
    self.backgroundColor = nil;
    self.clearsContextBeforeDrawing = YES;
    
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

- (void)drawRect:(CGRect)r;
{
    CGRect bounds = self.bounds;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGContextSaveGState(ctx);
    {
        OUIBeginShadowing(ctx, OUIShadowTypeDarkContentOnLightBackground);
        
        CGRect topLine, remainder;
        CGRectDivide(bounds, &topLine, &remainder, 1, CGRectMinYEdge);
        [[OUIInspector labelTextColor] set];
        
        UIRectFill(topLine);
    }
    CGContextRestoreGState(ctx);
}

@end
