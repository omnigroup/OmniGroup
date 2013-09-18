// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUILoadedImage.h>

RCS_ID("$Id$");

@implementation OUILoadedImage
@end

OUILoadedImage *OUILoadImage(NSString *name)
{
    UIImage *image = [UIImage imageNamed:name];
    OBASSERT(image);
    OBASSERT(image.imageOrientation == UIImageOrientationUp);

    OUILoadedImage *info = [OUILoadedImage new];
    info.image = image;
    info.size = [image size];
    return info;
}

