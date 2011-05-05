// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorStepperButton.h>

#import <OmniUI/OUIDrawing.h>
#import <UIKit/UIKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniQuartz/OQDrawing.h>

RCS_ID("$Id$");

@interface OUIInspectorStepperButton (/*Private*/)
- (void)_makeLabel;
- (void)_initialRepeatTimerFired:(NSTimer *)timer;
- (void)_followingRepeatTimerFired:(NSTimer *)timer;
- (void)_cancelRepeat;
- (void)_rebuildImage;
@end

@implementation OUIInspectorStepperButton

static const NSTimeInterval kTimeToPauseBeforeInitialRepeat = 0.5;
static const NSTimeInterval kTimeToPauseBetweenFollowingRepeats = 0.25;
static UIImage *StepperImage = nil;

+ (CGSize)stepperButtonSize;
{
    OBASSERT(StepperImage);
    return [StepperImage size];
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    StepperImage = [[UIImage imageNamed:@"OUIInspectorStepper.png"] retain];
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

- (void)dealloc;
{
    [_label release];
    [_image release];
    [_cachedImage release];
    [super dealloc];
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
    [_image autorelease];
    _image = [image retain];
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
            _repeatTimer = [[NSTimer scheduledTimerWithTimeInterval:kTimeToPauseBeforeInitialRepeat target:self selector:@selector(_initialRepeatTimerFired:) userInfo:nil repeats:NO] retain];
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
    _label.textAlignment = UITextAlignmentCenter;
}

- (void)_initialRepeatTimerFired:(NSTimer *)timer;
{
    // resend our event *before* clearing our timer
    [self sendActionsForControlEvents:UIControlEventTouchDown];
    
    // Make sure the action didn't cancel our repeat
    if (_repeats && _repeatTimer) {
        OBASSERT([self isTracking]); // otherwise the timer would have been cleared
        [self _cancelRepeat];
        _repeatTimer = [[NSTimer scheduledTimerWithTimeInterval:kTimeToPauseBetweenFollowingRepeats target:self selector:@selector(_followingRepeatTimerFired:) userInfo:nil repeats:YES] retain];
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
    [_repeatTimer release];
    _repeatTimer = nil;
}

- (void)_rebuildImage;
{
    OBPRECONDITION(CGSizeEqualToSize(self.bounds.size, StepperImage.size)); // Don't stretch this image as it has gradients going both vertically and horizontally.
    
    // We could maybe just set this once in -drawRect:, but that scares me since we'd maybe be queuing a display request while servicing one. This isn't performance critical anyway.
    [_cachedImage release];
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
        
        if (_flipped) {
            CGContextSaveGState(ctx);
            CGContextScaleCTM(ctx, -1, 1);
            CGContextTranslateCTM(ctx, -cacheSize.width, 0);
        }
        
        UIImage *stepperImage = [UIImage imageNamed:@"OUIInspectorStepper.png"];
        OBASSERT(stepperImage);
                
        [stepperImage drawInRect:cacheRect];
        
        if (_flipped) {
            CGContextRestoreGState(ctx);
        }
        
        OUIBeginControlImageShadow(ctx, OUIShadowTypeLightContentOnDarkBackground);
        {
            if (_image) {
                CGContextSaveGState(ctx);
                CGContextScaleCTM(ctx, 1, -1);
                CGContextTranslateCTM(ctx, 0, -cacheSize.height);                    
                OQDrawImageCenteredInRect(ctx, _image, contentRect);
                CGContextRestoreGState(ctx);
            }
            if ([_label.text length] > 0) {
                [_label sizeToFit];
                
                CGSize labelSize = _label.frame.size;
                labelSize.width = contentRect.size.width; // Let the label text centering handle horizontal centering.
                
                CGRect labelRect = OQCenteredIntegralRectInRect(contentRect, labelSize);
                labelRect = OUIShadowContentRectForRect(labelRect, OUIShadowTypeLightContentOnDarkBackground);
                
                CGRect textRect = [_label textRectForBounds:labelRect limitedToNumberOfLines:1];
                
                [_label drawTextInRect:textRect];
                
            }
        }
        OUIEndControlImageShadow(ctx);
        
        _cachedImage = [UIGraphicsGetImageFromCurrentImageContext() retain];
    }
    OUIGraphicsEndImageContext();
    
    [self setImage:_cachedImage forState:UIControlStateNormal];
    [self setNeedsDisplay];
}

@end
