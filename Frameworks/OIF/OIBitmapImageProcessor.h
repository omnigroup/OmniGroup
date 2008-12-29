// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OIF/OIBitmapImageProcessor.h 68913 2005-10-03 19:36:19Z kc $

#import <OIF/OIImageProcessor.h>

@class NSBitmapImageRep;

#define OIBitmapImageProcessor_MaxPlanes 5

@interface OIBitmapImageProcessor : OIImageProcessor
{
    // output storage
    unsigned int numberOfPlanes;
    BOOL isPlanar;
    unsigned char *imageDataPlanes[OIBitmapImageProcessor_MaxPlanes];
    NSBitmapImageRep *resultImageRep;
    NSData *embeddedICCProfile;
}

- (void)setImageRep:(NSBitmapImageRep *)imageRep;
- (NSBitmapImageRep *)imageRep;

- (void)setEmbeddedICCProfile:(NSData *)colorProfile;

- (unsigned char **)imageDataPlanes;

@end
