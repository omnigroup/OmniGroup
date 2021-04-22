// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <CoreGraphics/CoreGraphics.h>

@class UIImage, UILabel;

extern UIImage *OUIImageByFlippingHorizontally(UIImage *image);

#ifdef DEBUG
extern void OUILogAncestorViews(UIView *view);
#endif

// Convenience for UIGraphicsBegin/EndImageContext for resolution independent drawing
static inline void OUIGraphicsBeginImageContext(CGSize size)
{
    // NO = we want a transparent context
    // 0 = scale factor is set to the scale factor of the device's main screen
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
}
static inline void OUIGraphicsEndImageContext(void)
{
    UIGraphicsEndImageContext();
}

// For segmented contorls, stepper buttons, etc.

typedef enum {
    OUIShadowTypeLightContentOnDarkBackground,
    OUIShadowTypeDarkContentOnLightBackground,
    OUIShadowTypeDynamic,
} OUIShadowType;

extern CGSize OUIShadowOffset(OUIShadowType type);
extern UIColor *OUIShadowColor(OUIShadowType type);

extern CGRect OUIShadowContentRectForRect(CGRect rect, OUIShadowType type);

extern void OUIBeginShadowing(CGContextRef ctx, OUIShadowType type);
extern void OUIBeginControlImageShadow(CGContextRef ctx, OUIShadowType type);
extern void OUIEndControlImageShadow(CGContextRef ctx);
extern UIImage *OUIMakeShadowedImage(UIImage *image, OUIShadowType type);

extern void OUISetShadowOnLabel(UILabel *label, OUIShadowType type);

extern void OUIDrawTransparentColorBackground(CGContextRef ctx, CGRect rect, CGSize phase);
extern void OUIDrawPatternBackground(CGContextRef ctx, UIImage *patternImage, CGRect rect, CGSize phase);

static inline CGRect OUIEdgeInsetsOutsetRect(CGRect rect, UIEdgeInsets insets)
{
    UIEdgeInsets outsets = {
        .top = -insets.top,
        .bottom = -insets.bottom,
        .left = -insets.left,
        .right = -insets.right,
    };
    return UIEdgeInsetsInsetRect(rect, outsets);
}

