// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentSlider.h"

RCS_ID("$Id$");

enum {
    OUIDocumentSliderKnobDisplayFlatSides           = 0,
    OUIDocumentSliderKnobDisplayRoundedLeftSide     = 1, 
    OUIDocumentSliderKnobDisplayRoundedRightSide    = 2,
};
typedef NSUInteger OUIDocumentSliderKnobDisplayOptions;

@interface OUIDocumentSliderKnob : UIView {
@private
    OUIDocumentSliderKnobDisplayOptions _displayOptions;
}
@property (nonatomic) NSUInteger displayOptions;
@end

@implementation OUIDocumentSliderKnob
static id _commonKnobInit(OUIDocumentSliderKnob *self)
{
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    self.exclusiveTouch = NO;
    self.displayOptions = OUIDocumentSliderKnobDisplayRoundedLeftSide | OUIDocumentSliderKnobDisplayRoundedRightSide;
    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonKnobInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonKnobInit(self);
}

- (void)setFrame:(CGRect)rect;
{
    rect.size.width = rint(rect.size.width);
    if (!CGSizeEqualToSize(rect.size, [self frame].size))
        [self setNeedsDisplay];
    [super setFrame:rect];
}

- (void)drawRect:(CGRect)rect;
{
    /*
    [[UIColor colorWithWhite:1 alpha:0.65] set];
    CGFloat corner = floor(rect.size.height/2);
    
    UIBezierPath *path = nil;
    if (_displayOptions) {
        NSUInteger corners = 0;
        if (_displayOptions & OUIDocumentSliderKnobDisplayRoundedLeftSide)
            corners = (corners|UIRectCornerTopLeft|UIRectCornerBottomLeft);
        if (_displayOptions & OUIDocumentSliderKnobDisplayRoundedRightSide)
            corners = (corners|UIRectCornerTopRight|UIRectCornerBottomRight);
        path = [UIBezierPath bezierPathWithRoundedRect:[self bounds] byRoundingCorners:corners cornerRadii:CGSizeMake(corner, corner)];
    } else {
        path = [UIBezierPath bezierPathWithRect:[self bounds]];
    }
    
    [path fill];
     */
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    [[UIBezierPath bezierPathWithRoundedRect:[self bounds] cornerRadius:[self bounds].size.height/2] addClip];
    NSArray *gradientColors = [NSArray arrayWithObjects:(id)[[UIColor colorWithRed:188.0f/255.0f green:188.0f/255.0f blue:188.0f/255.0f alpha:1] CGColor], (id)[[UIColor colorWithRed:248.0f/255.0f green:248.0f/255.0f blue:248.0f/255.0f alpha:1] CGColor], nil];
    CGGradientRef gradient = CGGradientCreateWithColors(NULL, (CFArrayRef)gradientColors, NULL);        
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0,0), CGPointMake(0,[self bounds].size.height), 0);
    CGGradientRelease(gradient);
    
    [[UIColor colorWithWhite:234.0f/255.0f alpha:1] set];
    UIRectFill(CGRectMake(0,0, [self bounds].size.width, 1));
    UIRectFill(CGRectMake(0,[self bounds].size.height -1, [self bounds].size.width, 1));
    CGContextRestoreGState(context);
    
    CGFloat center = floor(CGRectGetMidX([self bounds]));

    [[UIColor colorWithWhite:0 alpha:0.2f] set];
    UIRectFrameUsingBlendMode(CGRectMake(center - 5, [self bounds].origin.y + 3, 1, [self bounds].size.height-6), kCGBlendModeNormal);
    UIRectFrameUsingBlendMode(CGRectMake(center, [self bounds].origin.y + 3, 1, [self bounds].size.height-6), kCGBlendModeNormal);
    UIRectFrameUsingBlendMode(CGRectMake(center + 5, [self bounds].origin.y + 3, 1, [self bounds].size.height-6), kCGBlendModeNormal);

    [[UIColor colorWithWhite:1 alpha:0.4f] set];
    UIRectFrameUsingBlendMode(CGRectMake(center - 4, [self bounds].origin.y + 3, 1, [self bounds].size.height-6), kCGBlendModeNormal);
    UIRectFrameUsingBlendMode(CGRectMake(center + 1, [self bounds].origin.y + 3, 1, [self bounds].size.height-6), kCGBlendModeNormal);
    UIRectFrameUsingBlendMode(CGRectMake(center + 6, [self bounds].origin.y + 3, 1, [self bounds].size.height-6), kCGBlendModeNormal);
}

- (void)setDisplayOptions:(NSUInteger)option;
{
    // TODO: animate this change
    _displayOptions = option;
    [self setNeedsDisplay];
}

@synthesize displayOptions = _displayOptions;
@end

@implementation OUIDocumentSlider

static id _commonInit(OUIDocumentSlider *self)
{
    self->_sliderKnob = [[OUIDocumentSliderKnob alloc] initWithFrame:CGRectZero];
    [self addSubview:self->_sliderKnob];
    
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
    [_sliderKnob release];
    [super dealloc];
}

- (CGFloat)sliderWidth;
{
    if (!count)
        return [self bounds].size.width;
    return MAX(32, [self bounds].size.width/count);
}

- (CGFloat)sliderHeight;
{
    return MIN(12, [self bounds].size.height);
}

- (CGFloat)verticalOffset;
{
    return floor(([self bounds].size.height-[self sliderHeight])/2);
}

- (void)animationDidStop:(NSString *)animationID finished:(NSNumber *)finished context:(void *)context;
{
    /*
    if (value == 0)
        _sliderKnob.displayOptions = (value == (count-1)) ? OUIDocumentSliderKnobDisplayRoundedLeftSide|OUIDocumentSliderKnobDisplayRoundedRightSide : OUIDocumentSliderKnobDisplayRoundedLeftSide;
    else if (value == (count-1))
        _sliderKnob.displayOptions = OUIDocumentSliderKnobDisplayRoundedRightSide;
    else
        _sliderKnob.displayOptions = OUIDocumentSliderKnobDisplayFlatSides;
     */
}

- (void)setValue:(NSUInteger)aValue animate:(BOOL)animate;
{
    value = aValue;
    
    CGFloat sliderWidth = [self sliderWidth];
    CGFloat maxSliderLocation = [self bounds].size.width - sliderWidth;
    CGFloat sliderIncrement = (count == 1) ? 0 : maxSliderLocation/(count-1);
    
    sliderLocation = floor(sliderIncrement * value);
    
    CGFloat sliderHeight = [self sliderHeight];
    CGFloat verticalOffset = [self verticalOffset];
    CGRect sliderRect = CGRectMake(sliderLocation, verticalOffset, sliderWidth, sliderHeight);
    
    if (animate || CGRectEqualToRect(_sliderKnob.frame, CGRectZero)) {
        [_sliderKnob setFrame:sliderRect];
        //        _sliderKnob.displayOptions = (value == (count-1)) ? OUIDocumentSliderKnobDisplayRoundedLeftSide|OUIDocumentSliderKnobDisplayRoundedRightSide : OUIDocumentSliderKnobDisplayRoundedLeftSide;
    } else {
        [UIView beginAnimations:nil context:NULL]; {
            [UIView setAnimationCurve:UIViewAnimationCurveLinear];
            [UIView setAnimationDuration:0.1];
            [UIView setAnimationDidStopSelector:@selector(animationDidStop:finished:context:)];
            [UIView setAnimationDelegate:self];
            [_sliderKnob setFrame:sliderRect];
        } [UIView commitAnimations];
    }
}


- (void)setValue:(NSUInteger)aValue;
{
    [self setValue:aValue animate:YES];
}

- (void)setCount:(NSUInteger)aValue;
{
    if (count != aValue) {
        count = aValue;
        [self setNeedsDisplay];
        [_sliderKnob setHidden:(count <=1)];
        
        CGRect oldFrame = _sliderKnob.frame;
        oldFrame.size.width = [self sliderWidth];
        [_sliderKnob setFrame:oldFrame];
    }
}

@synthesize value;
@synthesize count;

- (void)_setValueFromDragTouch:(UITouch *)touch;
{
    if (count <= 1)
        return;
    
    CGPoint point = [touch locationInView:self];
    
    CGFloat newLocation = point.x - offsetFromDragStart;
    CGFloat sliderWidth = [self sliderWidth];
    CGFloat maxSliderLocation = [self bounds].size.width - sliderWidth;
    CGFloat sliderIncrement = maxSliderLocation/(count-1);
    
    newLocation = MAX(0, newLocation);
    newLocation = MIN(newLocation, maxSliderLocation);
    
    CGFloat newValue = rint(newLocation/sliderIncrement);

    CGRect knobFrame = [_sliderKnob frame];
    knobFrame.origin.x = newLocation;
    [_sliderKnob setFrame:knobFrame];
    
    if (value == newValue)
        return;
    
    {
        // Update our value
        value = newValue;
        
        // Inform the picker, inside the animation block and before our layout/display, as it will call back and set our knob's color
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
}

#pragma mark -
#pragma mark UIControl subclass

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
{
    // Multi-touch should be off, so we should get only one begin/{end|cancel} cycle.
    OBPRECONDITION(!self.multipleTouchEnabled);
    OBPRECONDITION([[event touchesForView:self] count] <= 1);
    
    CGPoint point = [touch locationInView:self];
    CGFloat sliderWidth = [self sliderWidth];
    if (point.x > sliderLocation && point.x < (sliderLocation + sliderWidth)) {
        offsetFromDragStart = point.x - sliderLocation;
    } else {
        offsetFromDragStart = sliderWidth/2;
        [self _setValueFromDragTouch:touch];
    }
    
    return YES; // we want contiuous tracking
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
{
    // Multi-touch should be off, so we should get only one begin/{end|cancel} cycle.
    OBPRECONDITION(!self.multipleTouchEnabled);
    OBPRECONDITION([[event touchesForView:self] count] <= 1);
    
    [self _setValueFromDragTouch:touch];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event;
{
    [super endTrackingWithTouch:touch withEvent:event];
    [self setValue:value animate:YES];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event;
{
    [super cancelTrackingWithEvent:event];
    [self setValue:value animate:YES];
}

#pragma mark UIView subclass

- (void)drawSeparators:(CGRect)rect;
{
    CGFloat verticalOffset = [self verticalOffset];
    CGFloat sliderHeight = [self sliderHeight];

    [[UIColor colorWithWhite:1 alpha:0.4] set];
    
    CGFloat separatorWidth = [self bounds].size.width/count;
    for (NSUInteger separatorIndex = 1; separatorIndex < count; separatorIndex++) {
        CGFloat xPosition = floor(rect.origin.x + separatorWidth*separatorIndex);
        if (xPosition > CGRectGetMaxX(rect))
            continue;
        
        CGRect separatorRect = CGRectMake(xPosition, verticalOffset, 1, sliderHeight);
        UIRectFill(separatorRect);
    }
}

- (void)drawRect:(CGRect)rect;
{
    if (count <= 1)
        return;
    
    CGFloat sliderHeight = [self sliderHeight];
    CGFloat verticalOffset = [self verticalOffset];
    
    CGRect sliderFrame = [self bounds];
    sliderFrame.origin.y = verticalOffset;
    sliderFrame.size.height = sliderHeight;
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    [[UIBezierPath bezierPathWithRoundedRect:sliderFrame cornerRadius:sliderHeight/2] addClip];
    NSArray *gradientColors = [NSArray arrayWithObjects:(id)[[UIColor colorWithRed:63.0f/255.0f green:63.0f/255.0f blue:63.0f/255.0f alpha:1] CGColor], (id)[[UIColor colorWithRed:81.0f/255.0f green:81.0f/255.0f blue:81.0f/255.0f alpha:1] CGColor], nil];
    CGGradientRef gradient = CGGradientCreateWithColors(NULL, (CFArrayRef)gradientColors, NULL);        
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0,sliderFrame.origin.y), CGPointMake(0,sliderFrame.origin.y+sliderFrame.size.height), 0);
    CGGradientRelease(gradient);
    CGContextRestoreGState(context);
    
    [[UIColor blackColor] set];
    CGRect borderRect = CGRectInset(sliderFrame,-1,-1);
    borderRect.origin.y += 0.5;
    [[UIBezierPath bezierPathWithRoundedRect:borderRect cornerRadius:(sliderHeight+2/2)] stroke];
    
    [[UIColor colorWithWhite:83.0f/255.0f alpha:1] set];
    UIRectFill(CGRectMake(sliderFrame.origin.x + sliderHeight/2, CGRectGetMaxY(sliderFrame)-1, sliderFrame.size.width-sliderHeight, 1));
    
    // background
    /*
    [[UIColor colorWithWhite:1 alpha:0.25] set];
    CGRect sliderFrame = [self bounds];
    sliderFrame.origin.y = verticalOffset;
    sliderFrame.size.height = sliderHeight;
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:sliderFrame cornerRadius:floor(sliderHeight/2)];
    [path fill];
    */
}

@end
