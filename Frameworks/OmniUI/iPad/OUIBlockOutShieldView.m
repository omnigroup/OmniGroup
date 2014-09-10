// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIBlockOutShieldView.h>

RCS_ID("$Id$");

@implementation OUIBlockOutShieldView

- (void)_commonInit;
{
    self.backgroundColor = [UIColor clearColor];
}

- (id)init;
{
    self = [super init];
    if (self != nil) {
        [self _commonInit];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    self = [super initWithCoder:aDecoder];
    if (self != nil) {
        [self _commonInit];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    self = [super initWithFrame:frame];
    if (self != nil) {
        [self _commonInit];
    }
    return self;
}

- (void)drawRect:(CGRect)rect;
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGContextSaveGState(context);
    [[UIColor blackColor] set];
    
    if (self.passthroughViews.count > 0) {
        // This is a quick and dirty hack that will work for a single pass-through view or ones that stack to form a contiguous block. We just union all the pass-through views together and punch out a single rectangular hole.
        // TODO: make this robust
        UIView *passThroughView = self.passthroughViews.firstObject;
        CGRect holeRect = [self convertRect:passThroughView.bounds fromView:passThroughView];
        for (passThroughView in self.passthroughViews) {
            holeRect = CGRectUnion(holeRect, [self convertRect:passThroughView.bounds fromView:passThroughView]);
        }
        holeRect = CGRectStandardize(holeRect);
        CGRect rectToDraw, rectToSkip;
        
        // top
        CGRectDivide(rect, &rectToDraw, &rectToSkip, holeRect.origin.y, CGRectMinYEdge);
        CGContextFillRect(context, rectToDraw);
        
        // left
        CGRectDivide(rect, &rectToDraw, &rectToSkip, holeRect.origin.x, CGRectMinXEdge);
        CGContextFillRect(context, rectToDraw);
        
        // bottom
        CGRectDivide(rect, &rectToSkip, &rectToDraw, holeRect.origin.y + holeRect.size.height, CGRectMinYEdge);
        CGContextFillRect(context, rectToDraw);
        
        // right
        CGRectDivide(rect, &rectToSkip, &rectToDraw, holeRect.origin.x + holeRect.size.width, CGRectMinXEdge);
        CGContextFillRect(context, rectToDraw);
        
    } else {
        // no pass-through views, so block the whole thing
        CGContextFillRect(context, rect);
    }
    
    
    CGContextRestoreGState(context);
}

@end
