// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

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
