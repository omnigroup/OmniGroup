// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorWell.h>

#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/OmniBase.h>

#import <UIKit/UIImage.h>

RCS_ID("$Id$");

static CGColorRef BorderColor = NULL;
static CGColorRef InnerShadowColor = NULL;
static CGColorRef OuterShadowColor = NULL;

static void OUIInspectorWellInitialize(void)
{
    if (BorderColor)
        return;
    
    CGColorSpaceRef grayColorSpace = CGColorSpaceCreateDeviceGray();
    
    CGFloat borderComponents[] = {0.33, 1.0};
    BorderColor = CGColorCreate(grayColorSpace, borderComponents);
    
    CGFloat innerShadowComponents[] = {0.0, 0.5};
    InnerShadowColor = CGColorCreate(grayColorSpace, innerShadowComponents);
    
    CGFloat outerShadowComponents[] = {1.0, 0.5};
    OuterShadowColor = CGColorCreate(grayColorSpace, outerShadowComponents);
    
    CFRelease(grayColorSpace);
}

static const CGFloat kBorderRadius = 5;

void OUIInspectorWellAddPath(CGContextRef ctx, CGRect frame, BOOL rounded)
{
    OUIInspectorWellInitialize();
    
    CGRect borderRect = frame;
    borderRect.size.height -= 1; // room for shadow
    
    if (rounded) {
        OQAppendRoundedRect(ctx, borderRect, kBorderRadius);
    } else {
        CGContextAddRect(ctx, borderRect);
    }
    
}

typedef struct {
    UIImage *rounded;
    UIImage *square;
} RoundSquareImageCache;

typedef void (*OUIDrawIntoImageCache)(CGContextRef, CGRect imageRect, BOOL rounded);

// The shadow we want has 1px offset, 0px radius and it just a shifted down path.
static void _OUIInspectorWellDrawOuterShadow(CGContextRef ctx, CGRect imageRect, BOOL rounded)
{
    CGRect shadowRect = imageRect;
    shadowRect.origin.y += 1;
    
    OUIInspectorWellAddPath(ctx, shadowRect, rounded);
    
    CGContextSetFillColorWithColor(ctx, OuterShadowColor);
    CGContextFillPath(ctx);
}

static UIImage *_OUIRoundSquareImageCachedImage(RoundSquareImageCache *cache, OUIDrawIntoImageCache draw, BOOL rounded)
{
    // Cache a 9-part image for rounded and not.
    OUIInspectorWellInitialize();
    
    UIImage **imagep = rounded ? &cache->rounded : &cache->square;
    
    if (!*imagep) {
        // Might be able to get away with just kBorderRadius..
        CGFloat leftCap = kBorderRadius + 1;
        CGFloat topCap = kBorderRadius + 1;
        
        UIImage *image;
        CGSize imageSize = CGSizeMake(2*leftCap + 1, 2*topCap + 1);
        UIGraphicsBeginImageContext(imageSize);
        {
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            CGRect imageRect = CGRectMake(0, 0, imageSize.width, imageSize.height);
            draw(ctx, imageRect, rounded);
            image = UIGraphicsGetImageFromCurrentImageContext();
        }
        UIGraphicsEndImageContext();
        
        *imagep = [[image stretchableImageWithLeftCapWidth:leftCap topCapHeight:topCap] retain];
    }
    
    return *imagep;
}

void OUIInspectorWellDrawOuterShadow(CGContextRef ctx, CGRect frame, BOOL rounded)
{
    static RoundSquareImageCache cache;
    UIImage *image = _OUIRoundSquareImageCachedImage(&cache, _OUIInspectorWellDrawOuterShadow, rounded);
    [image drawInRect:frame];
}

// Border and inner shadow
static void _OUIInspectorWellDrawBorderAndInnerShadow(CGContextRef ctx, CGRect imageRect, BOOL rounded)
{
    OUIInspectorWellAddPath(ctx, imageRect, rounded);
    CGContextClip(ctx);
    CGContextBeginTransparencyLayer(ctx, NULL/*auxiliaryInfo*/);
    {
        OUIInspectorWellAddPath(ctx, CGRectInset(imageRect, 0.5, 0.5), rounded);
        CGContextAddRect(ctx, CGRectInset(imageRect, -20, -20));
        
        CGContextSetShadowWithColor(ctx, CGSizeMake(0,1), 5/*blur*/, InnerShadowColor);
        CGContextSetStrokeColorWithColor(ctx, BorderColor);
        CGContextDrawPath(ctx, kCGPathEOFillStroke);
    }
    CGContextEndTransparencyLayer(ctx);
}

void OUIInspectorWellDrawBorderAndInnerShadow(CGContextRef ctx, CGRect frame, BOOL rounded)
{
    static RoundSquareImageCache cache;
    UIImage *image = _OUIRoundSquareImageCachedImage(&cache, _OUIInspectorWellDrawBorderAndInnerShadow, rounded);
    [image drawInRect:frame];
}

CGRect OUIInspectorWellInnerRect(CGRect frame)
{
    CGRect rect = CGRectInset(frame, 1, 1); // border
    rect.size.height -= 1; // shadow
    return rect;
}

CGColorRef OUIInspectorWellBorderColor(void)
{
    OUIInspectorWellInitialize();
    return BorderColor;
}

void OUIInspectorWellStrokePathWithBorderColor(CGContextRef ctx)
{
    OUIInspectorWellInitialize();

    CGContextSetStrokeColorWithColor(ctx, BorderColor);
    CGContextStrokePath(ctx);
}



