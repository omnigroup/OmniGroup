// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIToolbarTitleButton.h"

RCS_ID("$Id$");

@implementation OUIToolbarTitleButton

#pragma mark -
#pragma mark UIControl subclass

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
{
    _touchesInside = YES;
    
    _highlightView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"OUIToolbarButtonFauxHighlight.png"]];
    CGRect imageRect = [self bounds];
    imageRect.origin.x = floor(CGRectGetMidX(imageRect));
    imageRect.origin.y = floor(CGRectGetMidY(imageRect));
    imageRect.size = [_highlightView frame].size;
    imageRect.origin.x -= floor(imageRect.size.width/2);
    imageRect.origin.y -= floor(imageRect.size.height/2);
    [_highlightView setFrame:imageRect];
    [self addSubview:_highlightView];
    return [super beginTrackingWithTouch:touch withEvent:event];
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
{
    CGPoint location = [touch locationInView:self];
    CGRect rect = [self bounds];
    BOOL inside = CGRectContainsPoint(rect, location);
    if (inside != _touchesInside) {
        _touchesInside = inside;
        [_highlightView setHidden:!_touchesInside];
    }
    return [super continueTrackingWithTouch:touch withEvent:event];
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event
{
    [super endTrackingWithTouch:touch withEvent:event];
    [_highlightView removeFromSuperview];
    [_highlightView release];
    _highlightView = nil;
}

- (void)cancelTrackingWithEvent:(UIEvent *)event;
{
    [super cancelTrackingWithEvent:event];
    [_highlightView removeFromSuperview];
    [_highlightView release];
    _highlightView = nil;
}

- (void)dealloc;
{
    [_highlightView release];
    [super dealloc];
}

#pragma mark -
#pragma mark UIButton subclass

- (CGRect)titleRectForContentRect:(CGRect)contentRect;
{
    CGRect originalTitleRect = [super titleRectForContentRect:contentRect];
    CGRect titleRect = originalTitleRect;
    titleRect.origin.x = CGRectGetMinX(contentRect);
    return titleRect;
}

- (CGRect)imageRectForContentRect:(CGRect)contentRect;
{
    CGRect originalImageRect = [super imageRectForContentRect:contentRect];
    CGRect imageRect = originalImageRect;
    imageRect.origin.x = CGRectGetMaxX(contentRect) - imageRect.size.width;
    return imageRect;
}

@end
