// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "UIBarButtonItem-OUITheming.h"

RCS_ID("$Id$");

@implementation UIBarButtonItem (OUITheming)

- (void)applyAppearance:(OUIAppearanceType)appearance;
{
    NSString *backgroundNormalImageName = nil;
    NSString *backgroundHighlightedImageName = nil;
    
    switch (appearance) {
        case OUIAppearanceTypeClear:
            backgroundNormalImageName = @"OUIToolbarButton-Clear-Normal.png";
            backgroundHighlightedImageName = @"OUIToolbarButton-Clear-Highlighted.png";
            break;
            
        default:
            OBASSERT_NOT_REACHED("Should always have a valid OUIThemeBackgroundType.");
            break;
    }
    
    OBASSERT_NOTNULL(backgroundNormalImageName);
    OBASSERT_NOTNULL(backgroundHighlightedImageName);
    
    UIEdgeInsets standardInsets = (UIEdgeInsets){
        .top = 0,
        .right = 6,
        .bottom = 0,
        .left = 6
    };
    
    UIImage *resizeableBackgroundNormalImage = [[UIImage imageNamed:backgroundNormalImageName] resizableImageWithCapInsets:standardInsets];
    UIImage *resizeableBackgroundHighlightedImage = [[UIImage imageNamed:backgroundHighlightedImageName] resizableImageWithCapInsets:standardInsets];
    
    [self setBackgroundImage:resizeableBackgroundNormalImage forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [self setBackgroundImage:resizeableBackgroundHighlightedImage forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
}

@end
