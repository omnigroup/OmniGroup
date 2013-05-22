// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/UIBarButtonItem-OUITheming.h>

RCS_ID("$Id$");

OBDEPRECATED_METHOD(-applyAppearance:); // -> -applyAppearanceWithBackgroundType:

@implementation UIBarButtonItem (OUITheming)

- (void)applyAppearanceWithBackgroundType:(OUIBarButtonItemBackgroundType)backgroundType;
{
    if (backgroundType == OUIBarButtonItemBackgroundTypeNone) {
        // No need to do anything, just return.
        return;
    }
    
    NSString *backgroundNormalImageName = nil;
    NSString *backgroundHighlightedImageName = nil;
    
    switch (backgroundType) {
        case OUIBarButtonItemBackgroundTypeNone:
            OBASSERT_NOT_REACHED("No need to do anything. Should have returned above.");
            break;
        case OUIBarButtonItemBackgroundTypeBlack:
            backgroundNormalImageName = @"OUIToolbarButton-Black-Normal.png";
            backgroundHighlightedImageName = @"OUIToolbarButton-Black-Highlighted.png";
            break;
        case OUIBarButtonItemBackgroundTypeRed:
            backgroundNormalImageName = @"OUIToolbarButton-Red-Normal.png";
            backgroundHighlightedImageName = @"OUIToolbarButton-Red-Highlighted.png";
            break;
        case OUIBarButtonItemBackgroundTypeBlue:
            backgroundNormalImageName = @"OUIToolbarButton-Blue-Normal.png";
            backgroundHighlightedImageName = @"OUIToolbarButton-Blue-Highlighted.png";
            break;
        case OUIBarButtonItemBackgroundTypeClear:
            backgroundNormalImageName = @"OUIToolbarButton-Clear-Normal.png";
            backgroundHighlightedImageName = @"OUIToolbarButton-Clear-Highlighted.png";
            break;
        case OUIBarButtonItemBackgroundTypeBack: // Left-pointing arrow.
            backgroundNormalImageName = @"OUIToolbarBackButton-Black-Normal.png";
            backgroundHighlightedImageName = @"OUIToolbarBackButton-Black-Highlighted.png";
            break;
        default:
            OBASSERT_NOT_REACHED("Should always have a valid OUIThemeBackgroundType.");
            break;
    }
    
    OBASSERT_NOTNULL(backgroundNormalImageName);
    OBASSERT_NOTNULL(backgroundHighlightedImageName);
    
    // Set standard inset.
    UIEdgeInsets imageInset = (UIEdgeInsets){
        .top = 0,
        .right = 7,
        .bottom = 0,
        .left = 7
    };
    
    // Set custom inset as needed.
    if (backgroundType == OUIBarButtonItemBackgroundTypeBack) {
        imageInset = (UIEdgeInsets){
            .top = 0,
            .right = 7,
            .bottom = 0,
            .left = 14
        };
    }
    
    // Build the resizable background images.
    UIImage *resizeableBackgroundNormalImage = [[UIImage imageNamed:backgroundNormalImageName] resizableImageWithCapInsets:imageInset];
    UIImage *resizeableBackgroundHighlightedImage = [[UIImage imageNamed:backgroundHighlightedImageName] resizableImageWithCapInsets:imageInset];
    
    if (backgroundType == OUIBarButtonItemBackgroundTypeBack) {
        [self setBackButtonBackgroundImage:resizeableBackgroundNormalImage forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
        [self setBackButtonBackgroundImage:resizeableBackgroundHighlightedImage forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    }
    else {
        [self setBackgroundImage:resizeableBackgroundNormalImage forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
        [self setBackgroundImage:resizeableBackgroundHighlightedImage forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    }
}

@end
