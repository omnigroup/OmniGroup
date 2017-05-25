// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorStepperButton.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniQuartz/OQDrawing.h>

RCS_ID("$Id$");

@interface OUIInspectorStepperButton ()
- (void)_rebuildImage; // Forward declared so that C functions can call it
@end

@implementation OUIInspectorStepperButton
{
    BOOL _flipped;
    BOOL _repeats;
    
    NSTimer *_repeatTimer;
    
    UILabel *_label;
    UIImage *_image;
    
    UIImage *_cachedImage;
}

static const NSTimeInterval kTimeToPauseBeforeInitialRepeat = 0.5;
static const NSTimeInterval kTimeToPauseBetweenFollowingRepeats = 0.25;

+ (CGSize)stepperButtonSize;
{
    return CGSizeMake(34,44);
}

static id _commonInit(OUIInspectorStepperButton *self)
{
    self.clearsContextBeforeDrawing = YES;
    self.opaque = NO;
    self.backgroundColor = nil;
    
    self->_repeats = YES;

    [self _rebuildImage];
    
    return self;
}

- (id)initWithFrame:(CGRect)frame;
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

@synthesize flipped = _flipped;
- (void)setFlipped:(BOOL)flipped;
{
    if (_flipped == flipped)
        return;
    _flipped = flipped;
    [self _rebuildImage];
}

@synthesize repeats = _repeats;
- (void)setRepeats:(BOOL)repeats;
{
    _repeats = repeats;
    if (!_repeats)
        [self _cancelRepeat];
}

- (NSString *)title;
{
    return _label.text;
}
- (void)setTitle:(NSString *)title;
{
    if (!_label)
        [self _makeLabel];
    
    _label.text = title;
    [self _rebuildImage];
}

- (UIFont *)titleFont;
{
    return _label.font;
}
- (void)setTitleFont:(UIFont *)font;
{
    if (!_label)
        [self _makeLabel];

    _label.font = font;
    [self _rebuildImage];
}

- (UIColor *)titleColor;
{
    return _label.textColor;
}
- (void)setTitleColor:(UIColor *)color;
{
    if (!_label)
        [self _makeLabel];

    _label.textColor = color;
    [self _rebuildImage];
}

- (UIImage *)image;
{
    return _image;
}
- (void)setImage:(UIImage *)image;
{
    _image = image;
    [self _rebuildImage];
}

#pragma mark -
#pragma mark UIControl subclass

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
{
    [super endTrackingWithTouch:touch withEvent:event];
    [self _cancelRepeat];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event;
{
    [super cancelTrackingWithEvent:event];
    [self _cancelRepeat];
}

- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event;
{
    [super sendAction:action to:target forEvent:event];
    
    if (_repeats && !_repeatTimer) {
        if ([self isTracking]) { // In case the action causes -cancelTrackingWithEvent:, we don't want to leave a timer firing forever!
            _repeatTimer = [NSTimer scheduledTimerWithTimeInterval:kTimeToPauseBeforeInitialRepeat target:self selector:@selector(_initialRepeatTimerFired:) userInfo:nil repeats:NO];
        }
    }
}

#pragma mark -
#pragma mark Private

- (void)_makeLabel;
{
    if (_label)
        return;
    
    // Not added as a subview; we treat this as a cell to just draw out text into our own backing store
    _label = [[UILabel alloc] initWithFrame:self.bounds];
    _label.textColor = [UIColor colorWithWhite:0.3 alpha:1];
    _label.textAlignment = NSTextAlignmentCenter;
}

- (void)_initialRepeatTimerFired:(NSTimer *)timer;
{
    // resend our event *before* clearing our timer
    [self sendActionsForControlEvents:UIControlEventTouchDown];
    
    // Make sure the action didn't cancel our repeat
    if (_repeats && _repeatTimer) {
        OBASSERT([self isTracking]); // otherwise the timer would have been cleared
        [self _cancelRepeat];
        _repeatTimer = [NSTimer scheduledTimerWithTimeInterval:kTimeToPauseBetweenFollowingRepeats target:self selector:@selector(_followingRepeatTimerFired:) userInfo:nil repeats:YES];
    }
}

- (void)_followingRepeatTimerFired:(NSTimer *)timer;
{
    // Just continue sending our down action
    [self sendActionsForControlEvents:UIControlEventTouchDown];
}

- (void)_cancelRepeat;
{
    [_repeatTimer invalidate];
    _repeatTimer = nil;
}

- (void)_rebuildImage;
{    
    // We could maybe just set this once in -drawRect:, but that scares me since we'd maybe be queuing a display request while servicing one. This isn't performance critical anyway.
    _cachedImage = nil;
    
    CGSize cacheSize = self.bounds.size;
    CGRect cacheRect = CGRectMake(0, 0, cacheSize.width, cacheSize.height);

    // Inset the available content area, based on whether we are flipped or not.
    UIEdgeInsets contentInsets = UIEdgeInsetsMake(1/*top*/, 0/*left*/, 2/*bottom*/, 1/*right*/);
    if (_flipped)
        SWAP(contentInsets.left, contentInsets.right);
    CGRect contentRect = UIEdgeInsetsInsetRect(cacheRect, contentInsets);
    
    OUIGraphicsBeginImageContext(cacheSize);
    {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGContextClearRect(ctx, cacheRect);
        
        //OUIBeginControlImageShadow(ctx, OUIShadowTypeLightContentOnDarkBackground);
        {
            [self.tintColor set];

            if (_image) {
                CGContextSaveGState(ctx);
                UIImage *tintImage = [_image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                CGRect imageRect = OQCenteredIntegralRectInRect(self.bounds, [tintImage size]);
                [tintImage drawAtPoint:imageRect.origin];
                CGContextRestoreGState(ctx);
            }
            if ([_label.text length] > 0) {
                [_label sizeToFit];
                
                CGSize labelSize = _label.frame.size;
                labelSize.width = contentRect.size.width; // Let the label text centering handle horizontal centering.
                
                CGRect labelRect = OQCenteredIntegralRectInRect(contentRect, labelSize);
                //labelRect = OUIShadowContentRectForRect(labelRect, OUIShadowTypeLightContentOnDarkBackground);
                
                CGRect textRect = [_label textRectForBounds:labelRect limitedToNumberOfLines:1];
                
                [_label drawTextInRect:textRect];
                
            }
        }
        //OUIEndControlImageShadow(ctx);
        
        _cachedImage = UIGraphicsGetImageFromCurrentImageContext();
    }
    OUIGraphicsEndImageContext();
    
    [self setImage:_cachedImage forState:UIControlStateNormal];
    [self setNeedsDisplay];
}

- (void)tintColorDidChange;
{
    [self _rebuildImage];
}

@end
