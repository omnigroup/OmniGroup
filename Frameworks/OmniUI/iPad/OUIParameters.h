// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAColor.h>

// OUIInspectorWell
#define kOUIInspectorWellHeight (44) // This makes our inner content height match that of a UITableViewCell.
#define kOUIInspectorWellLightBorderGradientStartColor ((OAHSV){213.0/360.0, 0.06, 0.62, 1.0})
#define kOUIInspectorWellLightBorderGradientEndColor ((OAHSV){216.0/360.0, 0.05, 0.72, 1.0})
#define kOUIInspectorWellDarkBorderGradientStartColor ((OAHSV){213.0/360.0, 0.06, 0.20, 1.0})
#define kOUIInspectorWellDarkBorderGradientEndColor ((OAHSV){216.0/360.0, 0.05, 0.35, 1.0})
#define kOUIInspectorWellInnerShadowColor ((OAWhiteAlpha){0.0, 0.35})
#define kOUIInspectorWellInnerShadowBlur (2)
#define kOUIInspectorWellInnerShadowOffset (CGSizeMake(0,1))
#define kOUIInspectorWellOuterShadowColor ((OAWhiteAlpha){1.0, 0.5})
#define kOUIInspectorWellCornerCornerRadiusSmall (4)
#define kOUIInspectorWellCornerCornerRadiusLarge (10.5)

// OUIInspectorTextWell
#define kOUIInspectorTextWellNormalGradientTopColor ((OAHSV){210.0/360.0, 0.08, 1.00, 1.0})
#define kOUIInspectorTextWellNormalGradientBottomColor ((OAHSV){210.0/360.0, 0.02, 1.00, 1.0})
#define kOUIInspectorTextWellHighlightedGradientTopColor ((OAHSV){210.0/360.0, 0.4, 1.0, 1.0})
#define kOUIInspectorTextWellHighlightedGradientBottomColor ((OAHSV){210.0/360.0, 0.2, 1.0, 1.0})
#define kOUIInspectorTextWellButtonHighlightedGradientTopColor ((OAHSV){209.0/360.0, 0.91, 0.96, 1.0})      // matches UITableViewCellSelectionStyleBlue
#define kOUIInspectorTextWellButtonHighlightedGradientBottomColor ((OAHSV){218.0/360.0, 0.93, 0.90, 1.0})   // matches UITableViewCellSelectionStyleBlue

#define kOUIInspectorTextWellTextColor ((OAWhiteAlpha){0.0, 1.0})
#define kOUIInspectorTextWellHighlightedTextColor ((OAHSV){213.0/360.0, 0.50, 0.30, 1.0})
#define kOUIInspectorTextWellHighlightedButtonTextColor ((OAWhiteAlpha){0.0, 0.4})
#define kOUIInspectorLabelDisabledTextColorAlphaScale (0.5)

// OUIInspectorBackgroundView
#define kOUIInspectorBackgroundTopColor ((OALinearRGBA){255.0/255.0, 255.0/255.0, 255.0/255.0, 1.0})
#define kOUIInspectorBackgroundBottomColor ((OALinearRGBA){255.0/255.0, 255.0/255.0, 255.0/255.0, 1.0})

// OUIMenuController
#define kOUIMenuControllerBackgroundOpacity (0.98) // We can lower this quite a bit except on Retina iPad 3. The popover doesn't blur its background on this hardware.
#define kOUIMenuControllerTableWidth (340)
#define kOUIMenuOptionIndentationWidth (15) // Points per indentation level, system default is 10

// OUIDrawing
#define kOUILightContentOnDarkBackgroundShadowColor ((OAWhiteAlpha){0.0, 0.5})
#define kOUIDarkContentOnLightBackgroundShadowColor ((OAWhiteAlpha){1.0, 0.5})

// OUIInspector
#define kOUIInspectorLabelTextColor ((OAHSV){212.0/360.0, 0.5, 0.35, 1.0}) // Also toggle buttons and segmented control buttons if they have labels instead of images
#define kOUIInspectorValueTextColor ((OAHSV){212.0/360.0, 0.5, 0.35, 1.0}) // For lable+value inspectors in detail/tappable mode (which looks like a UITableView now).

// OUIBarButtonItem
#define kOUIBarButtonItemDisabledTextGrayForColoredButtons (0.9) // The default is too dark against these lighter colored buttons (but OK on the black buttons).

// OUIGradientView
#define kOUIShadowEdgeThickness (6.0f)
#define kOUIShadowEdgeMaximumAlpha (0.4f)

// UIScrollView(OUIExtensions)
#define kOUIAutoscrollBorderWidth (44.0 * 1.1) // Area on edge of the screen that defines the ramp for autoscroll speed. Want to be able to hit the max speed without finger risking going off edge of view
#define kOUIAutoscrollMaximumVelocity (850) // in pixels per second
#define kOUIAutoscrollVelocityRampPower (0.25) // power ramp for autoscroll velocity
