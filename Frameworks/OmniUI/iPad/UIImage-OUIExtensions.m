// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "UIImage-OUIExtensions.h"

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

#ifdef OMNI_ASSERTIONS_ON

@implementation UIImage (OUIExtensions)

static UIImage *(*original_imageNamed)(Class self, SEL _cmd, NSString *name) = NULL;

+ (void)load;
{
    original_imageNamed = (typeof(original_imageNamed))OBReplaceClassMethodImplementationWithSelector(self, @selector(imageNamed:), @selector(replacement_imageNamed:));
}
                           
+ (UIImage *)replacement_imageNamed:(NSString *)imageName;
{
    UIImage *image = original_imageNamed(self, _cmd, imageName);
    OBASSERT(image, @"Unable to find image \"%@\" in main bundle -- don't try to grab images from a different bundle; add API in that bundle to get its images", imageName);
    return image;
}

@end

#endif
