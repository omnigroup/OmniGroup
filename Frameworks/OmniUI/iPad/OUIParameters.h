// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniQuartz/OQColor.h>

typedef struct {
    CGFloat v, a;
} OUIGrayAlpha; // TODO: Add to OmniQuartz?

// OUIInspectorWell
#define kOUIInspectorWellHeight (37)
#define kOUIInspectorWellBorderGradientStartGrayAlpha ((OUIGrayAlpha){0.42, 1.0})
#define kOUIInspectorWellBorderGradientEndGrayAlpha ((OUIGrayAlpha){0.58, 1.0})
#define kOUIInspectorWellInnerShadowGrayAlpha ((OUIGrayAlpha){0.0, 0.4})
#define kOUIInspectorWellInnerShadowBlur (3)
#define kOUIInspectorWellInnerShadowOffset (CGSizeMake(0,1))
#define kOUIInspectorWellOuterShadowGrayAlpha ((OUIGrayAlpha){1.0, 0.5})
#define kOUIInspectorWellCornerRadius (4)

// OUIInspectorTextWell
#define kOUIInspectorTextWellNormalGradientTopColor ((OSHSV){213.0/360.0, 0.10, 1.00, 1.0})
#define kOUIInspectorTextWellNormalGradientBottomColor ((OSHSV){210.0/360.0, 0.02, 1.00, 1.0})
#define kOUIInspectorTextWellHighlightedGradientTopColor ((OSHSV){213.0/360.0, 0.08, 0.58, 1.0})
#define kOUIInspectorTextWellHighlightedGradientBottomColor ((OSHSV){210.0/360.0, 0.05, 0.63, 1.0})

#define kOUIInspectorTextWellTextColor ((OSHSV){213.0/360.0, 0.50, 0.40, 1.0})
#define kOUIInspectorTextWellHighlightedTextColor ((OSHSV){213.0/360.0, 0.50, 0.30, 1.0})
#define kOUIInspectorLabelDisabledTextColorAlphaScale (0.5)

// OUIInspectorBackgroundView
#define kOUIInspectorBackgroundTopColor ((OQLinearRGBA){228.0/255.0, 231.0/255.0, 235.0/255.0, 1.0})
#define kOUIInspectorBackgroundBottomColor ((OQLinearRGBA){197.0/255.0, 200.0/255.0, 207.0/255.0, 1.0})

// OUIInspectorOptionWheel
#define kOUIInspectorOptionWheelEdgeGradientGray (0.53)
#define kOUIInspectorOptionWheelMiddleGradientGray (1.0)
#define kOUIInspectorOptionWheelGradientPower (2.5)

// OUIDrawing
#define kOUILightContentOnDarkBackgroundShadowGrayAlpha ((OUIGrayAlpha){0.0, 0.5})
#define kOUIDarkContentOnLightBackgroundShadowGrayAlpha ((OUIGrayAlpha){1.0, 0.5})

// OUIInspector
#define kOUIInspectorLabelTextColor ((OSHSV){212.0/360.0, 0.5, 0.35, 1.0}) // Also toggle buttons and segmented control buttons if they have labels instead of images

// OUIBarButtonItem
#define kOUIBarButtonItemDisabledTextGrayForColoredButtons (0.9) // The default is too dark against these lighter colored buttons (but OK on the black buttons).

// OUIGradientView
#define kOUIShadowEdgeThickness (6.0f)
#define kOUIShadowEdgeMaximumAlpha (0.4f)

// OUIToolbar
#define kOUIToolbarEdgePadding (5.0f)
#define kOUIToolbarIteritemPadding (12)

// OUIExportOptionsView and friends

// UIScrollView(OUIExtensions)
#define kOUIAutoscrollBorderWidth (44.0 * 1.1) // Area on edge of the screen that defines the ramp for autoscroll speed. Want to be able to hit the max speed without finger risking going off edge of view
#define kOUIAutoscrollMaximumVelocity (850) // in pixels per second
#define kOUIAutoscrollVelocityRampPower (0.25) // power ramp for autoscroll velocity
