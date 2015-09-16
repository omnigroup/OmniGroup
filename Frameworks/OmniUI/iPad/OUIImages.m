// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIImages.h>

RCS_ID("$Id$");

UIImage *OUITableViewItemSelectionImage(UIControlState state)
{    
    // Not handling all the permutations of states, just the base states.
    NSString *imageName;
    switch (state) {
        case UIControlStateHighlighted:
            imageName = @"OUITableViewItemSelection-Highlighted";
            break;
        case UIControlStateSelected:
            imageName = @"OUITableViewItemSelection-Selected";
            break;
        case UIControlStateDisabled:
        default:
            OBASSERT_NOT_REACHED("No images for these states.");
            // fall through
        case UIControlStateNormal:
            imageName = @"OUITableViewItemSelection-Normal";
            break;
    }
    
    UIImage *image = [[UIImage imageNamed:imageName inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    OBASSERT(image);
    OBASSERT(state == UIControlStateNormal || CGSizeEqualToSize([image size], [OUITableViewItemSelectionImage(UIControlStateNormal) size]));
             
    return image;
}

UIImage *OUIStepperMinusImage(void)
{
    return [UIImage imageNamed:@"OUIStepperMinus" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

UIImage *OUIStepperPlusImage(void)
{
    return [UIImage imageNamed:@"OUIStepperPlus" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

UIImage *OUIToolbarUndoImage(void)
{
    return [UIImage imageNamed:@"OUIToolbarUndo" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}
