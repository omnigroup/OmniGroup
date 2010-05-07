// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUILoadedImage.h>

RCS_ID("$Id$");

void OUILoadImage(NSString *name, OUILoadedImage *info)
{
    info->image = [[UIImage imageNamed:name] retain];
    OBASSERT(info->image);
    OBASSERT(info->image.imageOrientation == UIImageOrientationUp);
    info->size = [info->image size];
}

