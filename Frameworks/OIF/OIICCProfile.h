// Copyright 2001-2005, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OWF/OWFWeakRetainProtocol.h>
#import <OWF/OWFWeakRetainConcreteImplementation.h>
#import <ApplicationServices/ApplicationServices.h>

@class NSData;

@interface OIICCProfile : OFObject <OWFWeakRetain>
{
    OWFWeakRetainConcreteImplementation_IVARS;
    
    NSData *profileData;
    CGColorSpaceRef profileColorSpace;
    
    // misc. info derived from the profile data
    BOOL profileLooksValid;
    int profileComponentCount;
    unsigned int profileDataColorSpace;
}

// Returns YES if 'profile' appears to contain a valid ICC color profile. (This is only a cursory inspection, checking for things like truncated profiles, completely bogus data, etc.) Stuffs the profile's data color space (a FourCharCode) into *dataColorSpace. Stuffs the number of color components into *componentCount, or -1 if the number can't be determined (because the dataColorSpace is unrecognized or is e.g. a named-color space). Will return YES even if the component count can't be determined.
BOOL checkICCProfile(NSData *profile, int *componentCount, unsigned int *dataColorSpace);

// Return a shared OIICCProfile object for this color profile. Returns nil if the data doesn't look like a valid profile.
+ (OIICCProfile *)profileFromData:(NSData *)profileData;

// Returns the color space ref or NULL. Caller is responsible for retaining it if desired.
- (CGColorSpaceRef)coreGraphicsColorSpace;

// Information derived from the color profile.
- (int)componentCount;
- (unsigned int)iccProfileColorSpace;
- (BOOL)isValid;

@end
