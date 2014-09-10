// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDrawing.h>

#import <OmniBase/OmniBase.h>
#import "OUIParameters.h"

RCS_ID("$Id$");

UIImage *OUIImageByFlippingHorizontally(UIImage *image)
{
    OBPRECONDITION([NSThread isMainThread]); // UIGraphics stuff isn't thread safe. Could rewrite using only CG if needed.
    
    UIImage *result;
    CGSize size = [image size];
    OUIGraphicsBeginImageContext(size);
    {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGContextTranslateCTM(ctx, size.width, 0);
        CGContextScaleCTM(ctx, -1, 1);
        [image drawAtPoint:CGPointZero];
        result = UIGraphicsGetImageFromCurrentImageContext();
    }
    OUIGraphicsEndImageContext();
        
    return result;
}

#ifdef DEBUG
void OUILogAncestorViews(UIView *view)
{
    while (view) {
        NSLog(@"%@", view);
        view = view.superview;
    }
}

#endif

#define kOUILightContentOnDarkBackgroundShadowOffset ((CGSize){0, -1})
#define kOUIDarkContentOnLightBackgroundShadowOffset ((CGSize){0, 1})


static UIColor *OUILightContentOnDarkBackgroundShadowColor = nil;
static UIColor *OUIDarkContentOnLightBackgroundShadowColor = nil;
static void OUIDrawingInitialize(void)
{
    if (OUILightContentOnDarkBackgroundShadowColor)
        return;
    OUILightContentOnDarkBackgroundShadowColor = OQMakeUIColor(kOUILightContentOnDarkBackgroundShadowColor);
    OUIDarkContentOnLightBackgroundShadowColor = OQMakeUIColor(kOUIDarkContentOnLightBackgroundShadowColor);
}

CGSize OUIShadowOffset(OUIShadowType type)
{
    return (type == OUIShadowTypeLightContentOnDarkBackground) ? kOUILightContentOnDarkBackgroundShadowOffset : kOUIDarkContentOnLightBackgroundShadowOffset;
}

UIColor *OUIShadowColor(OUIShadowType type)
{
    OUIDrawingInitialize();
    
    UIColor *shadowColor = (type == OUIShadowTypeLightContentOnDarkBackground) ? OUILightContentOnDarkBackgroundShadowColor : OUIDarkContentOnLightBackgroundShadowColor;
    OBASSERT(shadowColor);
    return shadowColor;
}

void OUIGraphicsBeginImageContext(CGSize size)
{
    // NO = we want a transparent context
    // 0 = scale factor is set to the scale factor of the device's main screen
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
}

void OUIGraphicsEndImageContext(void) 
{
    UIGraphicsEndImageContext();
}

// Shifts the content within the rect so that it looks centered with the shadow applied. Assumes there is enough padding already so that we aren't going to shift the content far enough to get clipped.
CGRect OUIShadowContentRectForRect(CGRect rect, OUIShadowType type)
{
    if (type == OUIShadowTypeLightContentOnDarkBackground) {
        rect.origin.y += 1;
    } else {
        rect.origin.y -= 1;
    }
    return rect;
}

void OUIBeginShadowing(CGContextRef ctx, OUIShadowType type)
{
    OUIDrawingInitialize();
    
    CGContextSetShadowWithColor(ctx, OUIShadowOffset(type), 0, [OUIShadowColor(type) CGColor]);
}

void OUIBeginControlImageShadow(CGContextRef ctx, OUIShadowType type)
{
    OUIDrawingInitialize();
    
    CGContextSaveGState(ctx);
    OUIBeginShadowing(ctx, type);
    CGContextBeginTransparencyLayer(ctx, NULL);
}

void OUIEndControlImageShadow(CGContextRef ctx)
{
    CGContextEndTransparencyLayer(ctx);
    CGContextRestoreGState(ctx);
}

UIImage *OUIMakeShadowedImage(UIImage *image, OUIShadowType type)
{
    OBPRECONDITION(image);
    if (!image)
        return nil;
    
    OUIDrawingInitialize();

    CGSize size = image.size;
    size.height += 2; // 1px on top and bottom, one for shadow, one to stay centered
    
    UIImage *shadowedImage;
    OUIGraphicsBeginImageContext(size);
    {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        OUIBeginControlImageShadow(ctx, type);
        {
            CGSize shadowOffset = OUIShadowOffset(type);
            [image drawAtPoint:CGPointMake(0, shadowOffset.height)];
        }
        OUIEndControlImageShadow(ctx);
        shadowedImage = UIGraphicsGetImageFromCurrentImageContext();
    }
    OUIGraphicsEndImageContext();
    
    return shadowedImage;
}

void OUISetShadowOnLabel(UILabel *label, OUIShadowType type)
{
    OUIDrawingInitialize();

    label.shadowColor = OUIShadowColor(type);
    label.shadowOffset = OUIShadowOffset(type);
}

void OUIDrawTransparentColorBackground(CGContextRef ctx, CGRect rect, CGSize phase)
{
    OUIDrawPatternBackground(ctx, @"OUITransparencyCheckerboardBackground-24", rect, phase);
}

void OUIDrawPatternBackground(CGContextRef ctx, NSString *imageName, CGRect rect, CGSize phase)
{
    UIImage *patternImage = [UIImage imageNamed:imageName];
    OBASSERT(patternImage);

    UIColor *patternColor = [UIColor colorWithPatternImage:patternImage];
    
    CGColorRef patternColorRef = [patternColor CGColor];
    OBASSERT(patternColor);

    CGContextSaveGState(ctx);
    {
        CGContextSetFillColorWithColor(ctx, patternColorRef);
        CGContextSetPatternPhase(ctx, phase);
        CGContextFillRect(ctx, rect);
    }
    CGContextRestoreGState(ctx);
}
