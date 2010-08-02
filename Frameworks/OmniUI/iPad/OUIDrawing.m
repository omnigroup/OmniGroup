// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDrawing.h>
#import <UIKit/UIKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

UIImage *OUIImageByFlippingHorizontally(UIImage *image)
{
    OBPRECONDITION([NSThread isMainThread]); // UIGraphics stuff isn't thread safe. Could rewrite using only CG if needed.
    
    UIImage *result;
    CGSize size = [image size];
    UIGraphicsBeginImageContext(size);
    {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGContextTranslateCTM(ctx, size.width, 0);
        CGContextScaleCTM(ctx, -1, 1);
        [image drawAtPoint:CGPointZero];
        result = UIGraphicsGetImageFromCurrentImageContext();
    }
    UIGraphicsEndImageContext();
        
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

static const CGSize OUIShadowOffset = {0, -1};
static UIColor *OUIShadowColor = nil;
static void OUIDrawingInitialize(void)
{
    if (OUIShadowColor)
        return;
    OUIShadowColor = [[UIColor colorWithWhite:0 alpha:0.5] retain];
}

void OUIBeginShadowing(CGContextRef ctx)
{
    OUIDrawingInitialize();
    CGContextSetShadowWithColor(ctx, OUIShadowOffset, 0, [OUIShadowColor CGColor]);
}

void OUIBeginControlImageShadow(CGContextRef ctx)
{
    OUIDrawingInitialize();
    
    CGContextSaveGState(ctx);
    OUIBeginShadowing(ctx);
    CGContextBeginTransparencyLayer(ctx, NULL);
}

void OUIEndControlImageShadow(CGContextRef ctx)
{
    CGContextEndTransparencyLayer(ctx);
    CGContextRestoreGState(ctx);
}

UIImage *OUIMakeShadowedImage(UIImage *image)
{
    OBPRECONDITION(image);
    if (!image)
        return nil;
    
    OUIDrawingInitialize();

    CGSize size = image.size;
    size.height += 2; // 1px on top and bottom, one for shadow, one to stay centered
    
    UIImage *shadowedImage;
    UIGraphicsBeginImageContext(size);
    {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        OUIBeginControlImageShadow(ctx);
        {
            [image drawAtPoint:CGPointMake(0, 1)];
        }
        OUIEndControlImageShadow(ctx);
        shadowedImage = UIGraphicsGetImageFromCurrentImageContext();
    }
    UIGraphicsEndImageContext();
    
    return shadowedImage;
}

void OUISetShadowOnLabel(UILabel *label)
{
    OUIDrawingInitialize();

    label.shadowColor = OUIShadowColor;
    label.shadowOffset = OUIShadowOffset;
}
