// Copyright 2010 The Omni Group.  All rights reserved.
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
            imageName = @"OUITableViewItemSelection-Highlighted.png";
            break;
        case UIControlStateSelected:
            imageName = @"OUITableViewItemSelection-Selected.png";
            break;
        case UIControlStateDisabled:
        default:
            OBASSERT_NOT_REACHED("No images for these states.");
            // fall through
        case UIControlStateNormal:
            imageName = @"OUITableViewItemSelection-Normal.png";
            break;
    }
    
    UIImage *image = [UIImage imageNamed:imageName];
    OBASSERT(image);
    OBASSERT(state == UIControlStateNormal || CGSizeEqualToSize([image size], [OUITableViewItemSelectionImage(UIControlStateNormal) size]));
             
    return image;
}

