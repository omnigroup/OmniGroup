// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorDividerLine.h>
#import <OmniUI/OUIDrawing.h>

RCS_ID("$Id$");

@implementation OUIInspectorDividerLine

- (void)drawRect:(CGRect)r;
{
    CGRect bounds = self.bounds;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    [[UIColor colorWithWhite:1 alpha:0.3] set];
    OUIBeginShadowing(ctx);
    
    CGRect bottomLine, remainder;
    CGRectDivide(bounds, &bottomLine, &remainder, 1, CGRectMaxYEdge);
    
    UIRectFill(bottomLine);
}

@end
