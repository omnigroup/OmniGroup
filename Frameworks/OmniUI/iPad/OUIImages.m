// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIImages.h>

RCS_ID("$Id$");

static const CGFloat DisclosureIndicatorWidth = 8;
static const CGFloat DisclosureIndicatorHeight = 13;

UIImage *disclosureIndicatorFallbackImage(void);
UIImage *findDisclosureImageStartingAtView(UIView *view);
UIImage *disclosureIndicatorSystemImage(void);

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

UIImage *OUIToolbarForwardImage(void)
{
    UIImage *image = [UIImage systemImageNamed:@"chevron.forward"];
    if (image != nil)
        return image;
    else
        return [UIImage imageNamed:@"OUIToolbarForward" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

UIImage *OUIToolbarBackImage(void)
{
    UIImage *image = [UIImage systemImageNamed:@"chevron.backward"];
    if (image != nil)
        return image;
    else
        return [UIImage imageNamed:@"OUIToolbarBack" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

extern UIImage *OUIContextMenuCopyIcon(void)
{
    return [UIImage imageNamed:@"OUIContextMenuCopy" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

extern UIImage *OUIContextMenuCutIcon(void)
{
    return [UIImage imageNamed:@"OUIContextMenuCut" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

extern UIImage *OUIContextMenuPasteIcon(void)
{
    return [UIImage imageNamed:@"OUIContextMenuPaste" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

extern UIImage *OUIContextMenuDeleteIcon(void)
{
    return [UIImage imageNamed:@"OUIContextMenuDelete" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

extern UIImage *OUIContextMenuCopyStyleIcon(void)
{
    return [UIImage imageNamed:@"OUIContextMenuCopyStyle" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

extern UIImage *OUIContextMenuPasteStyleIcon(void)
{
    return [UIImage imageNamed:@"OUIContextMenuPasteStyle" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

extern UIImage *OUIContextMenuSelectAllIcon(void)
{
    return [UIImage imageNamed:@"OUIContextMenuSelectAll" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

extern UIImage *OUIContextMenuCopyAsJavaScriptIcon(void)
{
    return [UIImage imageNamed:@"OUIContextMenuCopyAsJavaScript" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

extern UIImage *OUIContextMenuShareIcon(void)
{
    return [UIImage imageNamed:@"OUIContextMenuShare" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

UIImage *disclosureIndicatorFallbackImage(void)
{
    UIImage *image = nil;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(DisclosureIndicatorWidth, DisclosureIndicatorHeight), NO, 0);
    {
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGRect indicatorRect = CGRectMake(0, 0, DisclosureIndicatorWidth, DisclosureIndicatorHeight);

        CGFloat lineWidth = 2.0;
        CGFloat inset = (lineWidth / 2.0);

        indicatorRect = CGRectInset(indicatorRect, inset, inset);
        CGContextSetLineWidth(context, lineWidth);

        [[UIColor greenColor] set]; // Arbitrary; tinted image

        CGContextMoveToPoint(context, CGRectGetMinX(indicatorRect), CGRectGetMinY(indicatorRect));
        CGContextAddLineToPoint(context, CGRectGetMaxX(indicatorRect), CGRectGetMidY(indicatorRect));
        CGContextAddLineToPoint(context, CGRectGetMinX(indicatorRect), CGRectGetMaxY(indicatorRect));
        CGContextStrokePath(context);

        image = UIGraphicsGetImageFromCurrentImageContext();
        image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

    }
    UIGraphicsEndImageContext();

    return image;
}

UIImage *findDisclosureImageStartingAtView(UIView *view)
{
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = OB_CHECKED_CAST(UIImageView, view);
        CGSize imageSize = imageView.image.size;
        if (imageSize.width <= 20 && imageSize.height <= 20) {
            // Looks like the disclosure image, which in reality is 8x13
            return imageView.image;
        }
    }

    for (UIView *subview in view.subviews) {
        UIImage *image = findDisclosureImageStartingAtView(subview);
        if (image != nil) {
            return image;
        }
    }

    return nil;
}

UIImage *disclosureIndicatorSystemImage(void)
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    [cell layoutIfNeeded];

    UIImage *systemImage = findDisclosureImageStartingAtView(cell);
    if (systemImage != nil) {
        return [systemImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }

    return nil;
}

UIImage *OUIDisclosureIndicatorImage(void)
{
    static UIImage *disclosureIndicatorImage = nil;

    if (disclosureIndicatorImage == nil) {
        // This code is a bit sketchy. We prefer to use the system image if we can, otherwise we drawn an approximation of it in code.
        // The approximation can be replaced with a local fallback image asset if necessary.
        //
        // The code which finds the system image does so by traversing a stock UITableViewCell and looking for an image view of approximately appropriate dimensions.

        disclosureIndicatorImage = disclosureIndicatorSystemImage();

        if (disclosureIndicatorImage == nil) {
            disclosureIndicatorImage = disclosureIndicatorFallbackImage();
        }
    }

    return disclosureIndicatorImage;
}

@implementation OUIImageLocation

- initWithName:(NSString *)name bundle:(NSBundle *)bundle;
{
    return [self initWithName:name bundle:bundle renderingMode:UIImageRenderingModeAutomatic];
}

- initWithName:(NSString *)name bundle:(NSBundle *)bundle renderingMode:(UIImageRenderingMode)renderingMode;
{
    if (!(self = [super init]))
        return nil;
    _bundle = bundle;
    _name = [name copy];
    _renderingMode = renderingMode;
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

    if (_renderingMode != UIImageRenderingModeAutomatic) {
        image = [image imageWithRenderingMode:_renderingMode];
    }

    OBASSERT_NOTNULL(image);
    return image;
}

@end
