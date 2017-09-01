// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorWell.h>

#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUI/OUIDrawing.h>
#import <OmniUI/OUIImages.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/OmniBase.h>
#import <UIKit/UIImage.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

#define DEBUG_VIEW_PLACEMENT (0)

static CGColorRef InnerShadowColor = NULL;
static CGColorRef OuterShadowColor = NULL;

static const CGFloat kOuterShadowOffset = 1;

static void OUIInspectorWellInitialize(void)
{
    if (InnerShadowColor)
        return;
    
    InnerShadowColor = CGColorRetain([OAMakeUIColor(kOUIInspectorWellInnerShadowColor) CGColor]);
    OuterShadowColor = CGColorRetain([OAMakeUIColor(kOUIInspectorWellOuterShadowColor) CGColor]);
}

static CGRect OUIInspectorWellBorderRect(CGRect frame)
{
    frame.size.height -= kOuterShadowOffset; // room for shadow
    return frame;
}

static CGRect OUIInspectorWellOuterShadowRect(CGRect frame)
{
    frame.origin.y += kOuterShadowOffset;
    frame.size.height -= kOuterShadowOffset;
    return frame;
}

void OUIInspectorWellAddPath(CGContextRef ctx, CGRect frame, OUIInspectorWellCornerType cornerType)
{
    OUIInspectorWellInitialize();
    
    if (cornerType == OUIInspectorWellCornerTypeNone) {
        CGContextAddRect(ctx, frame);
    } else {
        CGFloat radius = (cornerType == OUIInspectorWellCornerTypeSmallRadius) ? kOUIInspectorWellCornerCornerRadiusSmall : kOUIInspectorWellCornerCornerRadiusLarge;
        OQAppendRoundedRect(ctx, frame, radius);
    }
}

typedef void (*OUIDrawIntoImageCache)(CGContextRef ctx, CGRect imageRect, OUIInspectorWellCornerType cornerType, OUIInspectorWellBorderType borderType, BOOL shadowed);

// The shadow we want has 1px offset, 0px radius and it just a shifted down path.
static void _OUIInspectorWellDrawOuterShadow(CGContextRef ctx, CGRect imageRect, OUIInspectorWellCornerType cornerType, OUIInspectorWellBorderType _unusedBorderType, BOOL _unusedShadow)
{
    CGContextSaveGState(ctx);
    
    // On Retina displays, UITableView doesn't give a full 2px to the light outer shadow below its last cell.
    if ([[UIScreen mainScreen] scale] > 1) {
        OBASSERT([[UIScreen mainScreen] scale] == 2);
        
        // pull the bottom edge up half a pixel to get a bit of antialiasing
        imageRect.size.height -= 0.25;
    }
    
    OUIInspectorWellAddPath(ctx, OUIInspectorWellOuterShadowRect(imageRect), cornerType);
    
    CGContextSetFillColorWithColor(ctx, OuterShadowColor);
    CGContextFillPath(ctx);
    
    CGContextRestoreGState(ctx);
}

static CGFloat cornerRadiusForType(OUIInspectorWellCornerType cornerType)
{
    switch (cornerType) {
        case OUIInspectorWellCornerTypeSmallRadius:
            return kOUIInspectorWellCornerCornerRadiusSmall;
        case OUIInspectorWellCornerTypeLargeRadius:
            return kOUIInspectorWellCornerCornerRadiusLarge;
        case OUIInspectorWellCornerTypeNone:
        default:
            return 0;
    }
}

static UIImage *_OUIInspectorWellCachedImage(NSCache *cache, OUIDrawIntoImageCache draw, OUIInspectorWellCornerType cornerType, OUIInspectorWellBorderType borderType, BOOL shadowed, CGFloat height)
{
    // Cache a 9-part image for rounded and not.
    OUIInspectorWellInitialize();
    
    // If this shows up on profiles, it might be cheaper to have a special cache key object with properties for the things we want (and -isEqual:/-hash).
    NSString *cacheKey = [[NSString alloc] initWithFormat:@"corner:%d shadow:%d height:%f", cornerType, shadowed, height];
    UIImage *image = [cache objectForKey:cacheKey];
    
    if (!image) {
        //NSLog(@"Filling OUIInspectorWell cache %@, key %@", cache.name, cacheKey);
        
        CGFloat cornerRadius = cornerRadiusForType(cornerType);
        CGFloat inset = ceil(MAX(cornerRadius, 1 + kOUIInspectorWellInnerShadowBlur)); // Don't stretch the inner shadow on the vertical sides (we don't stretch vertically, so the top/bottom shadow can't be stretched. Matters in the square case where the corner radius wouldn't force the inset high enough to avoid it
                            
        UIEdgeInsets edgeInsets = {
            .left = inset,
            .right = inset,
            .top = inset,
            .bottom = inset + kOuterShadowOffset,
        };
        
        // Add 1 in each dimension for a center area to stretch
        CGSize imageSize = CGSizeMake(edgeInsets.left + edgeInsets.right + 1, edgeInsets.top + edgeInsets.bottom + 1);
        
        // Make sure our image is at least the height we need so that we don't actually stretch vertically (since we'll have a gradient in that direction).
        imageSize.height = MAX(imageSize.height, height);
        
        OUIGraphicsBeginImageContext(imageSize);
        {
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            CGRect imageRect = CGRectMake(0, 0, imageSize.width, imageSize.height);
            draw(ctx, imageRect, cornerType, borderType, shadowed);
            image = UIGraphicsGetImageFromCurrentImageContext();
        }
        OUIGraphicsEndImageContext();
        
        image = [image resizableImageWithCapInsets:edgeInsets];
        [cache setObject:image forKey:cacheKey];
    }
    
    return image;
}

void OUIInspectorWellDrawOuterShadow(CGContextRef ctx, CGRect frame, OUIInspectorWellCornerType cornerType)
{
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.name = @"OUIInspectorWell outer-shadow";
    });

    UIImage *image = _OUIInspectorWellCachedImage(cache, _OUIInspectorWellDrawOuterShadow, cornerType, OUIInspectorWellBorderTypeLight, YES/*shadowed*/, frame.size.height);
    [image drawInRect:frame];
}

static CGImageRef _OUICopyRoundedBorderImageMask(CGSize imageSize, OUIInspectorWellCornerType cornerType)
{
    CGImageRef image;
    UIGraphicsBeginImageContextWithOptions(imageSize, NO/*opaque*/, 0.0/*device scale*/);
    {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGRect frame = CGRectMake(0, 0, imageSize.width, imageSize.height);
        
        OQFlipVerticallyInRect(ctx, frame);
        
        CGContextClearRect(ctx, frame);
        CGContextSetStrokeColorWithColor(ctx, [[UIColor whiteColor] CGColor]);
        CGContextSetLineWidth(ctx, 1);
        OUIInspectorWellAddPath(ctx, CGRectMake(0.5, 0.5, imageSize.width - 1, imageSize.height - 1), cornerType);
        CGContextStrokePath(ctx);
        
        UIImage *uiImage = UIGraphicsGetImageFromCurrentImageContext();
        image = CGImageRetain([uiImage CGImage]);
    }
    UIGraphicsEndImageContext();
    return image;
}

// Border and inner shadow
static void _OUIInspectorWellDrawBorderAndInnerShadow(CGContextRef ctx, CGRect imageRect, OUIInspectorWellCornerType cornerType, OUIInspectorWellBorderType borderType, BOOL shadowed)
{
    CGRect borderRect = OUIInspectorWellBorderRect(imageRect);
    
    // Inner shadow
    if (shadowed) {
        CGContextSaveGState(ctx);
        {
            // Constrain the inner shadow to the specified area
            OUIInspectorWellAddPath(ctx, CGRectInset(borderRect, 0.5, 0.5), cornerType);
            CGContextClip(ctx);
            
            CGContextBeginTransparencyLayer(ctx, NULL/*auxiliaryInfo*/);
            {
                // Draw a big box, with a hole to cast the shadow. The difference between our clip rect above, and this path acts as clip on the shadow ramp.
                OUIInspectorWellAddPath(ctx, borderRect, cornerType);
                CGContextAddRect(ctx, CGRectInset(borderRect, -20, -20));
                
                CGContextSaveGState(ctx);
                CGContextSetShadowWithColor(ctx, kOUIInspectorWellInnerShadowOffset, kOUIInspectorWellInnerShadowBlur/*blur*/, InnerShadowColor);
                CGContextDrawPath(ctx, kCGPathEOFill);
                CGContextRestoreGState(ctx);
            }
            CGContextEndTransparencyLayer(ctx);
        }
        CGContextRestoreGState(ctx);
    }
    
    UIColor *borderGradientStartColor = (borderType == OUIInspectorWellBorderTypeLight) ? OAMakeUIColor(kOUIInspectorWellLightBorderGradientStartColor) : OAMakeUIColor(kOUIInspectorWellDarkBorderGradientStartColor);
    UIColor *borderGradientEndColor = (borderType == OUIInspectorWellBorderTypeLight) ? OAMakeUIColor(kOUIInspectorWellLightBorderGradientEndColor) : OAMakeUIColor(kOUIInspectorWellDarkBorderGradientEndColor);
    
    NSArray *colors = [NSArray arrayWithObjects:(id)[borderGradientStartColor CGColor], (id)[borderGradientEndColor CGColor], nil];
    CGGradientRef borderGradient = CGGradientCreateWithColors(NULL, (CFArrayRef)colors, NULL);
    
    // Border line, with a top-to-bottom gradient.
    CGContextSaveGState(ctx);
    if (cornerType != OUIInspectorWellCornerTypeNone) {
        // If the border is rounded, we can't do the normal path and then the path with a rect with a 1.0 inset since the corners will be too thick. Instead we use an image mask.
        CGImageRef imageMask = _OUICopyRoundedBorderImageMask(borderRect.size, cornerType);
        CGContextClipToMask(ctx, borderRect, imageMask);
        CGImageRelease(imageMask);
    } else {
        OUIInspectorWellAddPath(ctx, borderRect, cornerType);
        OUIInspectorWellAddPath(ctx, CGRectInset(borderRect, 1.0, 1.0), cornerType);
        CGContextEOClip(ctx);
        
    }
    CGPoint startPoint = borderRect.origin;
    CGPoint endPoint = CGPointMake(CGRectGetMinX(borderRect), CGRectGetMaxY(borderRect));
    CGContextDrawLinearGradient(ctx, borderGradient, startPoint, endPoint, 0);
    CGGradientRelease(borderGradient);
    CGContextRestoreGState(ctx);
}

void OUIInspectorWellDrawBorderAndInnerShadow(CGContextRef ctx, CGRect frame, OUIInspectorWellCornerType cornerType, OUIInspectorWellBorderType borderType, BOOL innerShadow)
{
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.name = @"OUIInspectorWell border-inner-shadow";
    });
    
    UIImage *image = _OUIInspectorWellCachedImage(cache, _OUIInspectorWellDrawBorderAndInnerShadow, cornerType, borderType, innerShadow, frame.size.height);
    [image drawInRect:frame];
}

CGRect OUIInspectorWellInnerRect(CGRect frame)
{
    return frame;
}

void OUIInspectorWellDraw(CGContextRef ctx, CGRect frame,
                          OUIInspectorWellCornerType cornerType, OUIInspectorWellBorderType borderType, BOOL innerShadow, BOOL outerShadow,
                          void (^drawInterior)(CGRect interior))
{
    OBPRECONDITION(CGRectEqualToRect(CGRectIntegral(frame), frame));

    if (outerShadow)
        OUIInspectorWellDrawOuterShadow(ctx, frame, cornerType);
    
    // Fill the gradient
    CGContextSaveGState(ctx);
    {
        CGRect borderRect = OUIInspectorWellBorderRect(frame);
        
        if (cornerType == OUIInspectorWellCornerTypeNone)
            // No slop needed
            OUIInspectorWellAddPath(ctx, CGRectInset(borderRect, 1, 1), cornerType);
        else
            // Let the fill extend under where the border will be for antialiasing slop
            OUIInspectorWellAddPath(ctx, CGRectInset(borderRect, 0.5, 0.5), cornerType);
        
        CGContextClip(ctx);
        
        if (drawInterior)
            drawInterior(frame);
    }
    CGContextRestoreGState(ctx);
    
    OUIInspectorWellDrawBorderAndInnerShadow(ctx, frame, cornerType, borderType, innerShadow);
}

@implementation OUIInspectorWell
{
    UIView *_leftView;
    UIView *_rightView;
}

static CGGradientRef NormalGradient = NULL;
static CGGradientRef HighlightedGradient = NULL;
static CGGradientRef HighlightedButtonGradient = NULL;

+ (void)initialize;
{
    OBINITIALIZE;
    
    {
        UIColor *topColor = OAMakeUIColor(kOUIInspectorTextWellNormalGradientTopColor);
        UIColor *bottomColor = OAMakeUIColor(kOUIInspectorTextWellNormalGradientBottomColor);
        NormalGradient = CGGradientCreateWithColors(NULL/*colorSpace*/, (CFArrayRef)[NSArray arrayWithObjects:(id)[topColor CGColor], (id)[bottomColor CGColor], nil], NULL);
    }
    
    {
        UIColor *topColor = OAMakeUIColor(kOUIInspectorTextWellHighlightedGradientTopColor);
        UIColor *bottomColor = OAMakeUIColor(kOUIInspectorTextWellHighlightedGradientBottomColor);
        HighlightedGradient = CGGradientCreateWithColors(NULL/*colorSpace*/, (CFArrayRef)[NSArray arrayWithObjects:(id)[topColor CGColor], (id)[bottomColor CGColor], nil], NULL);
        
        topColor = OAMakeUIColor(kOUIInspectorTextWellButtonHighlightedGradientTopColor);
        bottomColor = OAMakeUIColor(kOUIInspectorTextWellButtonHighlightedGradientBottomColor);
        HighlightedButtonGradient = CGGradientCreateWithColors(NULL/*colorSpace*/, (CFArrayRef)[NSArray arrayWithObjects:(id)[topColor CGColor], (id)[bottomColor CGColor], nil], NULL);
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
    return OAMakeUIColor(kOUIInspectorTextWellTextColor);
}

+ (UIColor *)highlightedTextColor;
{
    return OAMakeUIColor(kOUIInspectorTextWellHighlightedTextColor);
}

+ (UIColor *)highlightedButtonTextColor;
{
    return OAMakeUIColor(kOUIInspectorTextWellHighlightedButtonTextColor);
}

+ (UIImage *)navigationArrowImage;
{
    return OUIDisclosureIndicatorImage();
}

+ (UIImage *)navigationArrowImageHighlighted;
{
    return [UIImage imageNamed:@"OUINavigationArrow-White.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

static id _commonInit(OUIInspectorWell *self)
{
    self->_leftViewEdgeInsets = UIEdgeInsetsZero;
    self->_rightViewEdgeInsets = UIEdgeInsetsZero;
    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    if ((self = [super initWithFrame:frame]) == nil) {
        return nil;
    }
    return _commonInit(self);
}

- (id)initWithCoder:(NSCoder *)coder;
{
    if ((self = [super initWithCoder:coder]) == nil) {
        return nil;
    }
    return _commonInit(self);
}

@synthesize cornerType = _cornerType;
- (void)setCornerType:(OUIInspectorWellCornerType)cornerType;
{
    if (_cornerType == cornerType)
        return;
    _cornerType = cornerType;
    [self setNeedsDisplay];
}

- (BOOL)shouldDrawHighlighted;
{
    return self.highlighted && ([self allControlEvents] != 0);
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
    _leftView = leftView;
    [self addSubview:_leftView];
#if DEBUG_VIEW_PLACEMENT
    _leftView.backgroundColor = [UIColor blueColor];
#endif // DEBUG_VIEW_PLACEMENT
    
    // contentsRect probably changed
    [self setNeedsDisplay];
}

@synthesize rightView = _rightView;
- (void)setRightView:(UIView *)rightView;
{
    if (_rightView == rightView)
        return;
    [_rightView removeFromSuperview];
    _rightView = rightView;
    [self addSubview:_rightView];
#if DEBUG_VIEW_PLACEMENT
    _rightView.backgroundColor = [UIColor redColor];
#endif // DEBUG_VIEW_PLACEMENT
    
    // contentsRect probably changed
    [self setNeedsDisplay];
}

- (BOOL)recurseWhenComputingBorderEdgeInsets;
{
    return NO;
}

- (CGRect)contentsRect;
{
    return OUIInspectorWellInnerRect(self.bounds);
}

- (void)setNavigationArrowRightView;
{
    UIImageView *imageView = [[UIImageView alloc] initWithImage:[[[self class] navigationArrowImage] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    imageView.autoresizingMask = imageView.autoresizingMask | UIViewAutoresizingFlexibleLeftMargin;
    imageView.contentMode = UIViewContentModeRight; // This causes us to right-align the view
    self.rightView = imageView;
    self.rightViewEdgeInsets = (UIEdgeInsets){ .right = -2.0f, .left = 2.0f, .top = 0.0f, .bottom = 0.0f, };
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
    if (self.shouldDrawHighlighted)
        return self.backgroundType == OUIInspectorWellBackgroundTypeButton ? [[self class] highlightedButtonTextColor] : [[self class] highlightedTextColor];
    
    return [[self class] textColor];
}

// <bug:///94098> (Remove -drawInteriorFillWithRect: on our controls and subclass in OmniGraffle)
- (void)drawInteriorFillWithRect:(CGRect)rect; // Draws the interior gradient
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    if (_backgroundType == OUIInspectorWellBackgroundTypeNormal) {
        CGGradientRef gradient = self.shouldDrawHighlighted ? HighlightedGradient : NormalGradient;
        CGContextDrawLinearGradient(ctx, gradient, rect.origin, CGPointMake(rect.origin.x, CGRectGetMaxY(rect)), 0);
    } else {
        if (self.shouldDrawHighlighted) {
            CGGradientRef gradient = HighlightedButtonGradient;
            CGContextDrawLinearGradient(ctx, gradient, rect.origin, CGPointMake(rect.origin.x, CGRectGetMaxY(rect)), 0);
        } else {
            UIColor *backgroundColor = OAMakeUIColor(kOUIInspectorTextWellNormalGradientBottomColor);
            [backgroundColor set];
            UIRectFill(rect);
        }
    }
}

#pragma mark -
#pragma mark UIControl subclass

- (void)setHighlighted:(BOOL)highlighted;
{
    [super setHighlighted:highlighted];
    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark UIView subclass

- (void)layoutSubviews;
{
#if DEBUG_VIEW_PLACEMENT
    self.backgroundColor = [UIColor greenColor];
#endif // DEBUG_VIEW_PLACEMENT
    CGRect contentsRect = OUIInspectorWellInnerRect(self.bounds);

    [super layoutSubviews];
    
    // The left/right views are currently expected to have built-in padding.
    // Also, right now at least, we don't want to resize the views since they are UIImageViews (which stretch their content), though maybe we could use UIViewContentModeCenter
    
    if (_leftView) {
        CGRect leftRect;
        CGRectDivide(contentsRect, &leftRect, &contentsRect, CGRectGetHeight(contentsRect), CGRectMinXEdge);
        
        CGRect frame = _rectWithSizePositionedInRectForContentMode(_leftView.bounds.size, leftRect, _leftView.contentMode);
        frame = UIEdgeInsetsInsetRect(frame, self.leftViewEdgeInsets);
        _leftView.frame = frame;
    }
    
    if (_rightView) {
        CGRect rightRect;
        CGRectDivide(contentsRect, &rightRect, &contentsRect, CGRectGetHeight(contentsRect), CGRectMaxXEdge);

        CGRect frame = _rectWithSizePositionedInRectForContentMode(_rightView.bounds.size, rightRect, _rightView.contentMode);
        frame = UIEdgeInsetsInsetRect(frame, self.rightViewEdgeInsets);
        _rightView.frame = frame;
    }
}

static CGRect _rectWithSizePositionedInRectForContentMode(CGSize size, CGRect bounds, UIViewContentMode contentMode)
{
    CGRect frame;
    switch (contentMode) {
        case UIViewContentModeTopLeft:
            frame = CGRectMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds), size.width, size.height);
            break;
            
        case UIViewContentModeBottomLeft:
            frame = CGRectMake(CGRectGetMinX(bounds), CGRectGetMaxY(bounds) - size.height, size.width, size.height);
            break;
            
        case UIViewContentModeLeft:
        {
            CGFloat offset = (CGRectGetHeight(bounds) - size.height) / 2.0f;
            offset = round(offset);
            frame = CGRectMake(CGRectGetMinX(bounds), CGRectGetMinY(bounds) + offset, size.width, size.height);
            break;
        }
            
        case UIViewContentModeTopRight:
            frame = CGRectMake(CGRectGetMaxX(bounds) - size.width, CGRectGetMinY(bounds), size.width, size.height);
            break;
            
        case UIViewContentModeBottomRight:
            frame = CGRectMake(CGRectGetMaxX(bounds) - size.width, CGRectGetMaxY(bounds) - size.height, size.width, size.height);
            break;
            
        case UIViewContentModeRight:
        {
            CGFloat offset = (CGRectGetHeight(bounds) - size.height) / 2.0f;
            offset = round(offset);
            frame = CGRectMake(CGRectGetMaxX(bounds) - size.width, CGRectGetMinY(bounds) + offset, size.width, size.height);
            break;
        }
            
        case UIViewContentModeTop:
        {
            CGFloat offset = (CGRectGetWidth(bounds) - size.width) / 2.0f;
            offset = round(offset);
            frame = CGRectMake(CGRectGetMinX(bounds) + offset, CGRectGetMinY(bounds), size.width, size.height);
            break;
        }
            
        case UIViewContentModeBottom:
        {
            CGFloat offset = (CGRectGetWidth(bounds) - size.width) / 2.0f;
            offset = round(offset);
            frame = CGRectMake(CGRectGetMinX(bounds) + offset, CGRectGetMaxY(bounds) - size.height, size.width, size.height);
            break;
        }
            
        case UIViewContentModeCenter:
        default: // Anything else, default to centering
            frame = OQCenteredIntegralRectInRect(bounds, size);
            break;
    }
    return frame;
}

@end

