// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OmniUIDocumentImages.h>

RCS_ID("$Id$");

@implementation UIImage (OmniUIDocumentImages)

+ (UIImage *)OmniUIDocument_MenuItemConvertToFile;
{
    return [UIImage imageNamed:@"OUIMenuItemConvertToFile" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

+ (UIImage *)OmniUIDocument_MenuItemTemplate;
{
    return [UIImage imageNamed:@"OUIMenuItemTemplate" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}

+ (UIImage *)OmniUIDocument_ServerAccountValidationSuccessImage;
{
    return [UIImage imageNamed:@"OUIServerAccountValidationSuccess" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
}


@end
