// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorWell.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/OmniBase.h>
#import <UIKit/UIImage.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

static CGColorRef BorderColor = NULL;
static CGColorRef InnerShadowColor = NULL;
static CGColorRef OuterShadowColor = NULL;

static void OUIInspectorWellInitialize(void)
{
    if (InnerShadowColor)
        return;
    
    CGColorSpaceRef grayColorSpace = CGColorSpaceCreateDeviceGray();
    
    CGFloat innerShadowComponents[] = {kOUIInspectorWellInnerShadowWhiteAlpha.w, kOUIInspectorWellInnerShadowWhiteAlpha.a};
    InnerShadowColor = CGColorCreate(grayColorSpace, innerShadowComponents);
    
    CGFloat outerShadowComponents[] = {kOUIInspectorWellOuterShadowWhiteAlpha.w, kOUIInspectorWellOuterShadowWhiteAlpha.a};
    OuterShadowColor = CGColorCreate(grayColorSpace, outerShadowComponents);
    
    CFRelease(grayColorSpace);
}

void OUIInspectorWellAddPath(CGContextRef ctx, CGRect frame, BOOL rounded)
{
    OUIInspectorWellInitialize();
    
    CGRect borderRect = frame;
    borderRect.size.height -= 1; // room for shadow
    
    if (rounded) {
        OQAppendRoundedRect(ctx, borderRect, kOUIInspectorWellCornerRadius);
    } else {
        CGContextAddRect(ctx, borderRect);
    }
    
}

enum {
    RoundMask = (1 << 0),
    ShadowMask = (2 << 0),
};

#define ROUND_SQUARE_IMAGE_CACHE_SIZE (4)
typedef struct {
    UIImage *images[ROUND_SQUARE_IMAGE_CACHE_SIZE]; // {round,square}x{inner shadow, flat}
} RoundSquareImageCache;

typedef void (*OUIDrawIntoImageCache)(CGContextRef, CGRect imageRect, BOOL rounded, BOOL shadowed);

// The shadow we want has 1px offset, 0px radius and it just a shifted down path.
static void _OUIInspectorWellDrawOuterShadow(CGContextRef ctx, CGRect imageRect, BOOL rounded, BOOL shadowed)
{
    OBPRECONDITION(shadowed); // Ignores the shadowed parameter; this always is YES here.
    
    CGRect shadowRect = imageRect;
    shadowRect.origin.y += 1;
    
    OUIInspectorWellAddPath(ctx, shadowRect, rounded);
    
    CGContextSetFillColorWithColor(ctx, OuterShadowColor);
    CGContextFillPath(ctx);
}

static UIImage *_OUIRoundSquareImageCachedImage(RoundSquareImageCache *cache, OUIDrawIntoImageCache draw, BOOL rounded, BOOL shadowed)
{
    // Cache a 9-part image for rounded and not.
    OUIInspectorWellInitialize();
    
    NSUInteger cacheSlot = 0;
    if (rounded)
        cacheSlot |= RoundMask;
    if (shadowed)
        cacheSlot |= ShadowMask;
    OBASSERT(cacheSlot < ROUND_SQUARE_IMAGE_CACHE_SIZE);
    
    UIImage **imagep = &cache->images[cacheSlot];
    
    if (!*imagep) {
        // Might be able to get away with just kOUIInspectorWellCornerRadius..
        CGFloat leftCap = kOUIInspectorWellCornerRadius + 1;
        CGFloat topCap = kOUIInspectorWellCornerRadius + 1;
        
        UIImage *image;
        CGSize imageSize = CGSizeMake(2*leftCap + 1, 2*topCap + 1);
        OUIGraphicsBeginImageContext(imageSize);
        {
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            CGRect imageRect = CGRectMake(0, 0, imageSize.width, imageSize.height);
            draw(ctx, imageRect, rounded, shadowed);
            image = UIGraphicsGetImageFromCurrentImageContext();
        }
        OUIGraphicsEndImageContext();
        
        *imagep = [[image stretchableImageWithLeftCapWidth:leftCap topCapHeight:topCap] retain];
    }
    
    return *imagep;
}

void OUIInspectorWellDrawOuterShadow(CGContextRef ctx, CGRect frame, BOOL rounded)
{
    static RoundSquareImageCache cache;
    UIImage *image = _OUIRoundSquareImageCachedImage(&cache, _OUIInspectorWellDrawOuterShadow, rounded, YES/*shadowed*/);
    [image drawInRect:frame];
}

// Border and inner shadow
static void _OUIInspectorWellDrawBorderAndInnerShadow(CGContextRef ctx, CGRect imageRect, BOOL rounded, BOOL shadowed)
{
    OUIInspectorWellAddPath(ctx, imageRect, rounded);
    CGContextClip(ctx);
    CGContextBeginTransparencyLayer(ctx, NULL/*auxiliaryInfo*/);
    {
        OUIInspectorWellAddPath(ctx, CGRectInset(imageRect, 0.5, 0.5), rounded);
        CGContextAddRect(ctx, CGRectInset(imageRect, -20, -20));
        
        CGContextSaveGState(ctx);
        if (shadowed)
            CGContextSetShadowWithColor(ctx, kOUIInspectorWellInnerShadowOffset, kOUIInspectorWellInnerShadowBlur/*blur*/, InnerShadowColor);
        CGContextSetStrokeColorWithColor(ctx, [[UIColor clearColor] CGColor]);
        CGContextDrawPath(ctx, kCGPathEOFillStroke);
        CGContextRestoreGState(ctx);
        
        static CGGradientRef borderGradient = NULL;
        if (!borderGradient) {
            NSArray *colors = [NSArray arrayWithObjects:
                               (id)[[UIColor colorWithWhite:kOUIInspectorWellBorderGradientStartWhiteAlpha.w alpha:kOUIInspectorWellBorderGradientStartWhiteAlpha.a] CGColor],
                               (id)[[UIColor colorWithWhite:kOUIInspectorWellBorderGradientEndWhiteAlpha.w alpha:kOUIInspectorWellBorderGradientEndWhiteAlpha.a] CGColor],
                               nil
                               ];
            CGFloat locations[] = {0, 1.0};
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
            borderGradient = CGGradientCreateWithColors(colorSpace, (CFArrayRef)colors, locations);
            CGColorSpaceRelease(colorSpace);
        }    
        
        OUIInspectorWellAddPath(ctx, imageRect, rounded);
        OUIInspectorWellAddPath(ctx, CGRectInset(imageRect, 1.0, 1.0), rounded);
        
        CGPoint startPoint = imageRect.origin;
        CGPoint endPoint = CGPointMake(CGRectGetMinX(imageRect), CGRectGetMaxY(imageRect));
        CGContextSaveGState(ctx);
        CGContextEOClip(ctx);
        CGContextDrawLinearGradient(ctx, borderGradient, startPoint, endPoint, 0);
        CGContextRestoreGState(ctx);
    }
    CGContextEndTransparencyLayer(ctx);
}

void OUIInspectorWellDrawBorderAndInnerShadow(CGContextRef ctx, CGRect frame, BOOL rounded, BOOL innerShadow)
{
    static RoundSquareImageCache cache;
    UIImage *image = _OUIRoundSquareImageCachedImage(&cache, _OUIInspectorWellDrawBorderAndInnerShadow, rounded, innerShadow);
    [image drawInRect:frame];
}

CGRect OUIInspectorWellInnerRect(CGRect frame)
{
    CGRect rect = CGRectInset(frame, 1, 1); // border
    rect.size.height -= 1; // shadow
    return rect;
}

void OUIInspectorWellStrokePathWithBorderColor(CGContextRef ctx)
{
    OUIInspectorWellInitialize();

    CGContextSetStrokeColorWithColor(ctx, BorderColor);
    CGContextStrokePath(ctx);
}


@implementation OUIInspectorWell

static CGGradientRef NormalGradient = NULL;
static CGGradientRef HighlightedGradient = NULL;

+ (void)initialize;
{
    OBINITIALIZE;
    
    {
        UIColor *topColor = OQPlatformColorFromHSV(kOUIInspectorTextWellNormalGradientTopColor);
        UIColor *bottomColor = OQPlatformColorFromHSV(kOUIInspectorTextWellNormalGradientBottomColor);
        NormalGradient = CGGradientCreateWithColors(NULL/*colorSpace*/, (CFArrayRef)[NSArray arrayWithObjects:(id)[topColor CGColor], (id)[bottomColor CGColor], nil], NULL);
    }
    
    {
        UIColor *topColor = OQPlatformColorFromHSV(kOUIInspectorTextWellHighlightedGradientTopColor);
        UIColor *bottomColor = OQPlatformColorFromHSV(kOUIInspectorTextWellHighlightedGradientBottomColor);
        HighlightedGradient = CGGradientCreateWithColors(NULL/*colorSpace*/, (CFArrayRef)[NSArray arrayWithObjects:(id)[topColor CGColor], (id)[bottomColor CGColor], nil], NULL);
    }
    
}

+ (CGFloat)fontSize;
{
    return [UIFont labelFontSize];
}

+ (UIFont *)italicFormatFont;
{
    return [UIFont fontWithName:@"HoeflerText-Italic" size:[self fontSize]];
}

+ (UIColor *)textColor;
{
    return OQPlatformColorFromHSV(kOUIInspectorTextWellTextColor);
}

+ (UIColor *)highlightedTextColor;
{
    return OQPlatformColorFromHSV(kOUIInspectorTextWellHighlightedTextColor);
}

+ (UIImage *)navigationArrowImage;
{
    return [UIImage imageNamed:@"OUINavigationArrow.png"];
}

@synthesize rounded = _rounded;
- (void)setRounded:(BOOL)rounded;
{
    if (rounded == _rounded)
        return;
    _rounded = rounded;
    [self setNeedsDisplay];
}

- (BOOL)shouldDrawHighlighted;
{
    return !self.enabled || (self.highlighted && ([self allControlEvents] != 0));
}

@synthesize backgroundType = _backgroundType;
- (void)setBackgroundType:(OUIInspectorWellBackgroundType)backgroundType;
{
    if (_backgroundType == backgroundType)
        return;
    
    _backgroundType = backgroundType;
    
    [self setNeedsDisplay];
    return;
}

@synthesize leftView = _leftView;
- (void)setLeftView:(UIView *)leftView;
{
    if (_leftView == leftView)
        return;
    [_leftView removeFromSuperview];
    _leftView = [leftView retain];
    [self addSubview:_leftView];
    
    // contentsRect probably changed
    [self setNeedsDisplay];
}

@synthesize rightView = _rightView;
- (void)setRightView:(UIView *)rightView;
{
    if (_rightView == rightView)
        return;
    [_rightView removeFromSuperview];
    _rightView = [rightView retain];
    [self addSubview:_rightView];
    
    // contentsRect probably changed
    [self setNeedsDisplay];
}

- (CGRect)contentsRect;
{
    CGRect contentsRect = OUIInspectorWellInnerRect(self.bounds);
    
    static const CGFloat edgeInset = 8;
    
    UIEdgeInsets edgeInsets = UIEdgeInsetsMake(edgeInset, edgeInset, edgeInset, edgeInset);
    
    // The left/right views are currently expected to have built-in padding.
    if (_leftView) {
        CGRect leftRect;
        CGRectDivide(contentsRect, &leftRect, &contentsRect, CGRectGetHeight(contentsRect), CGRectMinXEdge);
        edgeInsets.left = 0;
    }
    
    if (_rightView) {
        CGRect rightRect;
        CGRectDivide(contentsRect, &rightRect, &contentsRect, CGRectGetHeight(contentsRect), CGRectMaxXEdge);
        edgeInsets.right = 0;
    }
    
    return UIEdgeInsetsInsetRect(contentsRect, edgeInsets);
}

- (void)setNavigationArrowRightView;
{
    UIImageView *imageView = [[UIImageView alloc] initWithImage:[[self class] navigationArrowImage]];
    self.rightView = imageView;
    [imageView release];
}

- (void)setNavigationTarget:(id)target action:(SEL)action;
{
    // OBPRECONDITION(target); nil OK for sending up the responder chain
    OBPRECONDITION(action);

    [self setNavigationArrowRightView];

    [self addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
}

- (UIColor *)textColor;
{
    return self.shouldDrawHighlighted ? [[self class] highlightedTextColor] : [[self class] textColor];
}

- (void)drawInteriorFillWithRect:(CGRect)rect; // Draws the interior gradient
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    if (_backgroundType == OUIInspectorWellBackgroundTypeNormal) {
        CGGradientRef gradient = self.shouldDrawHighlighted ? HighlightedGradient : NormalGradient;
        CGContextDrawLinearGradient(ctx, gradient, rect.origin, CGPointMake(rect.origin.x, CGRectGetMaxY(rect)), 0);
    } else {
        UIColor *backgroundColor = OQPlatformColorFromHSV(self.shouldDrawHighlighted ? kOUIInspectorTextWellHighlightedGradientBottomColor : kOUIInspectorTextWellNormalGradientBottomColor);
        [backgroundColor set];
        UIRectFill(rect);
    }
}

- (CGFloat)buttonHeight;
// Graffle subclasses this in GPImageTextWell
{
    return kOUIInspectorWellHeight;
}

#pragma mark -
#pragma mark UIControl subclass

- (void)setHighlighted:(BOOL)highlighted;
{
    [super setHighlighted:highlighted];
    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark UIView (OUIExtensions)

- (UIEdgeInsets)borderEdgeInsets
{
    // 1px white shadow at the bottom.
    return UIEdgeInsetsMake(0/*top*/, 0/*left*/, 1/*bottom*/, 0/*right*/);
}

#pragma mark -
#pragma mark UIView subclass

- (void)layoutSubviews;
{
    CGRect contentsRect = OUIInspectorWellInnerRect(self.bounds);

    [super layoutSubviews];
    
    // The left/right views are currently expected to have built-in padding.
    // Also, right now at least, we don't want to resize the views since they are UIImageViews (which stretch their content), though maybe we could use UIViewContentModeCenter
    
    if (_leftView) {
        CGRect leftRect;
        CGRectDivide(contentsRect, &leftRect, &contentsRect, CGRectGetHeight(contentsRect), CGRectMinXEdge);
        
        _leftView.frame = OQCenteredIntegralRectInRect(leftRect, _leftView.bounds.size);
    }
    
    if (_rightView) {
        CGRect rightRect;
        CGRectDivide(contentsRect, &rightRect, &contentsRect, CGRectGetHeight(contentsRect), CGRectMaxXEdge);

        _rightView.frame = OQCenteredIntegralRectInRect(rightRect, _rightView.bounds.size);
}
}

- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    
    OBASSERT(bounds.size.height == [self buttonHeight]);
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    OUIInspectorWellDrawOuterShadow(ctx, bounds, _rounded);
    
    // Fill the gradient
    CGContextSaveGState(ctx);
    {
        OUIInspectorWellAddPath(ctx, bounds, _rounded);
        CGContextClip(ctx);
        
        [self drawInteriorFillWithRect:bounds];
    }
    CGContextRestoreGState(ctx);
    
    BOOL innerShadow = _backgroundType == OUIInspectorWellBackgroundTypeNormal;
    OUIInspectorWellDrawBorderAndInnerShadow(ctx, bounds, _rounded, innerShadow);
}

@end

