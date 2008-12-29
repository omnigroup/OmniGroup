// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAToolbarImageView.h"

#import <Cocoa/Cocoa.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OAToolbarImageView

- (void)reallySetImage:(NSImage *)anImage;
{
    [super setImage:anImage];
}


// NSImageView subclass

- (void)setImage:(NSImage *)anImage;
{
}

@end
