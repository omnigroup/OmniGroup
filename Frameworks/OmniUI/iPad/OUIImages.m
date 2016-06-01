// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
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

UIImage *OUITableViewItemSelectionMixedImage(void)
{
    return [[UIImage imageNamed:@"OUITableViewItemSelection-Mixed" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
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

UIImage *OUIServerAccountValidationSuccessImage()
{
    return [UIImage imageNamed:@"OUIServerAccountValidationSuccess" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}


@implementation OUIImageLocation

- initWithName:(NSString *)name bundle:(NSBundle *)bundle;
{
    if (!(self = [super init]))
        return nil;
    _bundle = bundle;
    _name = [name copy];
    return self;
}

- (UIImage *)image;
{
    // Allow the main bundle to override images
    NSBundle *mainBundle = [NSBundle mainBundle];
    UIImage *image = [UIImage imageNamed:_name inBundle:mainBundle compatibleWithTraitCollection:nil];
    if (!image && _bundle != mainBundle) {
        image = [UIImage imageNamed:_name inBundle:_bundle compatibleWithTraitCollection:nil];
    }

    OBASSERT_NOTNULL(image);
    return image;
}

@end
