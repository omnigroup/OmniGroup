// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIOverlayView.h"
#import <UIKit/UIKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OUIOverlayView

#pragma mark -
#pragma mark Convenience methods

static OUIOverlayView *_overlayView = nil;

+ (void)displayTemporaryOverlayInView:(UIView *)view withString:(NSString *)string avoidingTouchPoint:(CGPoint)touchPoint;
{
    if (!_overlayView) {
        _overlayView = [[OUIOverlayView alloc] initWithFrame:CGRectMake(300, 100, 200, 26)];
    }
    
    _overlayView.text = string;
    
    if (CGPointEqualToPoint(touchPoint, CGPointZero)) {
        [_overlayView useAlignment:OUIOverlayViewAlignmentUpCenter withinBounds:view.bounds];
    } else {
        [_overlayView avoidTouchPoint:touchPoint withinBounds:view.bounds];
    }
    
    [_overlayView displayTemporarilyInView:view];
}

+ (void)displayTemporaryOverlayInView:(UIView *)view withString:(NSString *)string centeredAbovePoint:(CGPoint)touchPoint displayInterval:(NSTimeInterval)displayInterval; 
{
    if (!_overlayView) {
        _overlayView = [[OUIOverlayView alloc] initWithFrame:CGRectMake(300, 100, 200, 26)];
    }
    
    _overlayView.text = string;
    
    [_overlayView centerAbovePoint:touchPoint withinBounds:view.bounds];
    
    if (displayInterval) {
        _overlayView.messageDisplayInterval = displayInterval;
    }

    [_overlayView displayTemporarilyInView:view];
}

+ (void)displayTemporaryOverlayInView:(UIView *)view withString:(NSString *)string alignment:(OUIOverlayViewAlignment)alignment displayInterval:(NSTimeInterval)displayInterval;
{
    if (!_overlayView) {
        _overlayView = [[OUIOverlayView alloc] initWithFrame:CGRectMake(300, 100, 200, 26)];
    }
    
    _overlayView.text = string;
    
    [_overlayView useAlignment:alignment withinBounds:view.bounds];
    
    if (displayInterval) {
        _overlayView.messageDisplayInterval = displayInterval;
    }
    
    [_overlayView displayTemporarilyInView:view];
}

- (void)displayTemporarilyInView:(UIView *)view;
{
    shouldHide = NO;
    
    // If an overlay is already being displayed, replace it and cancel its timer
    if (_overlayTimer) {
        [_overlayTimer invalidate];
        _overlayTimer = nil;
    }
    // If new, fade in the overlay
    else {
        [self displayInView:view];
    }
    
    _overlayTimer = [NSTimer scheduledTimerWithTimeInterval:self.messageDisplayInterval target:self selector:@selector(_temporaryOverlayTimerFired:) userInfo:nil repeats:NO];
}

- (void)displayInView:(UIView *)view;
{
    shouldHide = NO;
    
    if (self.superview != view) {
        self.alpha = 0;
        [view addSubview:self];
    }
    
    [UIView beginAnimations:@"RSTemporaryOverlayAnimation" context:NULL];
    {
        //[UIView setAnimationDuration:SELECTION_DELAY];
        self.alpha = 1;
    }
    [UIView commitAnimations];
}

- (void)hide;
{
    shouldHide = YES;
    
    [UIView beginAnimations:@"RSTemporaryOverlayAnimation" context:NULL];
    {
        //[UIView setAnimationDuration:SELECTION_DELAY];
        self.alpha = 0;
        
        [UIView setAnimationDelegate:self];
        [UIView setAnimationDidStopSelector:@selector(_hideOverlayEffectDidStop:finished:context:)];
    }
    [UIView commitAnimations];
}

- (void)_temporaryOverlayTimerFired:(NSTimer *)timer;
{
    _overlayTimer = nil;
    
    [self hide];
}

- (void)_hideOverlayEffectDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context;
{
    // Cancel if a new overlay was created
    if (_overlayTimer)
        return;
    
    // Cancel if the overlay was told to show before finishing hiding
    if (!shouldHide)
        return;
    
    [self removeFromSuperview];
}


#pragma mark -
#pragma mark alloc/init

- (id)initWithFrame:(CGRect)aRect;
{
    if (!(self = [super initWithFrame:aRect]))
        return nil;
    
    self.userInteractionEnabled = NO;
    self.opaque = NO;
    
    _font = [[UIFont boldSystemFontOfSize:16] retain];
    _borderSize = CGSizeMake(8, 8);
    _messageDisplayInterval = 1.5;
    
    _cachedSuggestedSize = CGSizeZero;
    
    return self;
}

- (void)dealloc;
{
    [_font release];
    self.text = nil;
    
    [super dealloc];
}

#pragma mark -
#pragma mark Class methods

@synthesize text = _text;
- (void)setText:(NSString *)string;
{
    if (_text == string)
        return;
    
    [_text release];
    _text = [string retain];
    
    _cachedSuggestedSize = CGSizeZero;
    [self setNeedsDisplay];
}

@synthesize borderSize = _borderSize;
@synthesize messageDisplayInterval = _messageDisplayInterval;

- (void)setFrame:(CGRect)newFrame;
{
    if (!CGSizeEqualToSize(self.frame.size, newFrame.size)) {
        [self setNeedsDisplay];
    }
    
    [super setFrame:newFrame];
}

- (CGSize)suggestedSize;
{
    if (_cachedSuggestedSize.width) {
        return _cachedSuggestedSize;
    }

    //NSLog(@"########### Calculating size");
    CGSize textSize = [self.text sizeWithFont:_font];
    CGSize suggestedSize = CGSizeMake(textSize.width + self.borderSize.width*2, textSize.height + self.borderSize.height*2);
    suggestedSize.width += 1;  // Just in case the -sizeWithFont result is off slightly
    _cachedSuggestedSize = suggestedSize;
    return _cachedSuggestedSize;
}

- (void)useSuggestedSize;
{
    CGSize suggestedSize = [self suggestedSize];
    self.bounds = CGRectMake(0, 0, suggestedSize.width, suggestedSize.height);
}

- (void)avoidTouchPoint:(CGPoint)touchPoint withinBounds:(CGRect)superBounds;
{
    CGRect upperLeftRect = CGRectMake(0, 0, superBounds.size.width/2, superBounds.size.height/2);
    //NSLog(@"upperLeftRect: %@; touchPoint: %@", NSStringFromCGRect(upperLeftRect), NSStringFromCGPoint(touchPoint));
    
    CGRect newFrame;
    CGSize suggestedSize = [self suggestedSize];
    if (CGRectContainsPoint(upperLeftRect, touchPoint)) {
        CGFloat x = superBounds.size.width - 100 - suggestedSize.width;
        newFrame = CGRectMake(x, 70, suggestedSize.width, suggestedSize.height);
    } else {
        newFrame = CGRectMake(100, 70, suggestedSize.width, suggestedSize.height);
    }
    
    self.frame = newFrame;
}

- (void)centerAbovePoint:(CGPoint)touchPoint withinBounds:(CGRect)superBounds;
{
    CGSize suggestedSize = [self suggestedSize];
    
    CGPoint topLeft = touchPoint;
    topLeft.x -= suggestedSize.width/2;
    topLeft.y -= suggestedSize.height;
    topLeft.y -= 80;
    
    // Don't go past edges
    if (topLeft.y < OUIOverlayViewDistanceFromTopEdge)
        topLeft.y = OUIOverlayViewDistanceFromTopEdge;
    if (topLeft.x < OUIOverlayViewDistanceFromHorizontalEdge)
        topLeft.x = OUIOverlayViewDistanceFromHorizontalEdge;
    
    CGRect newFrame = CGRectMake(topLeft.x, topLeft.y, suggestedSize.width, suggestedSize.height);
    
    // Don't go past edges
    if (newFrame.origin.y < OUIOverlayViewDistanceFromTopEdge)
        newFrame.origin.y = OUIOverlayViewDistanceFromTopEdge;
    if (newFrame.origin.x < OUIOverlayViewDistanceFromHorizontalEdge)
        newFrame.origin.x = OUIOverlayViewDistanceFromHorizontalEdge;
    if (CGRectGetMaxX(newFrame) + OUIOverlayViewDistanceFromHorizontalEdge > CGRectGetMaxX(superBounds))
        newFrame.origin.x = CGRectGetMaxX(superBounds) - suggestedSize.width - OUIOverlayViewDistanceFromHorizontalEdge;
    
    newFrame = CGRectIntegral(newFrame);
    
    self.frame = newFrame;
}

- (void)useAlignment:(OUIOverlayViewAlignment)alignment withinBounds:(CGRect)superBounds;
{
    CGSize suggestedSize = [self suggestedSize];
    
    CGFloat horizontalCenter = CGRectGetMidX(superBounds);
    CGFloat left = horizontalCenter - suggestedSize.width/2;
    
    CGFloat top = OUIOverlayViewDistanceFromTopEdge;
    switch (alignment) {
        case OUIOverlayViewAlignmentMidCenter:
            top = CGRectGetMidY(superBounds);
            top -= suggestedSize.height/2;
            break;
        case OUIOverlayViewAlignmentDownCenter:
            top = CGRectGetMaxY(superBounds) - OUIOverlayViewDistanceFromTopEdge - suggestedSize.height;
            break;
        default:
            break;
    }
    
    CGRect newFrame = CGRectMake(left, top, suggestedSize.width, suggestedSize.height);
    newFrame = CGRectIntegral(newFrame);
    
    self.frame = newFrame;
}


#pragma mark -
#pragma mark UIView

- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    
    // Draw background
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:6];
    [[UIColor colorWithWhite:0.2 alpha:0.8] set];
    [path fill];
    
    // Draw border
    [[UIColor colorWithWhite:0.8 alpha:0.8] set];
    path.lineWidth = 1.5;
    [path stroke];
    
    // Draw text
    if (self.text.length) {
        [[UIColor whiteColor] set];
        CGRect textRect = CGRectInset(bounds, self.borderSize.width, self.borderSize.height);
        [self.text drawInRect:textRect withFont:_font];
    }
}

@end
