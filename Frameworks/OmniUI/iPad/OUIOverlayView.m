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
    [_overlayView avoidTouchPoint:touchPoint withinBounds:view.bounds];
    
    [_overlayView displayTemporarilyInView:view];
}

+ (void)displayTemporaryOverlayInView:(UIView *)view withString:(NSString *)string centeredAbovePoint:(CGPoint)touchPoint displayInterval:(NSTimeInterval)displayInterval; 
{
    if (!_overlayView) {
        _overlayView = [[OUIOverlayView alloc] initWithFrame:CGRectMake(300, 100, 200, 26)];
    }
    
    _overlayView.text = string;
    
    CGRect _frame = [_overlayView frame];
    touchPoint.y -= _frame.size.height;
    touchPoint.x -= _frame.size.width/2;
    touchPoint.y = round(touchPoint.y);
    touchPoint.x = round(touchPoint.x);
    _frame.origin = touchPoint;
    CGSize suggested = [_overlayView suggestedSize];
    _frame.size = suggested;
    _overlayView.frame = _frame;
    _overlayView.messageDisplayInterval = displayInterval;

    [_overlayView displayTemporarilyInView:view];
}

- (void)displayTemporarilyInView:(UIView *)view;
{
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
    if (self.superview == view)
        return;
    
    self.alpha = 0;
    [view addSubview:self];
    
    [UIView beginAnimations:@"RSTemporaryOverlayAnimation" context:NULL];
    {
        //[UIView setAnimationDuration:SELECTION_DELAY];
        self.alpha = 1;
    }
    [UIView commitAnimations];
}

- (void)hide;
{
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
    if (_overlayTimer) {
        return;
    }
    
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
    
    _font = [[UIFont systemFontOfSize:16] retain];
    _borderSize = CGSizeMake(8, 4);
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
    
    BOOL needsDisplay = !CGSizeEqualToSize(self.frame.size, newFrame.size);

    self.frame = newFrame;
    if (needsDisplay)
        [self setNeedsDisplay];
}


#pragma mark -
#pragma mark UIView

- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    
    // Draw background
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:4];
    UIColor *color = [UIColor colorWithWhite:0.2 alpha:0.8];
    [color set];
    [path fill];
    
    // Draw text
    if (self.text.length) {
        [[UIColor whiteColor] set];
        CGRect textRect = CGRectInset(bounds, self.borderSize.width, self.borderSize.height);
        [self.text drawInRect:textRect withFont:_font];
    }
}

@end
