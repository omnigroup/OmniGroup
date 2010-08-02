// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

//
// Prefix header for all source files of the 'SampleApp' target in the 'SampleApp' project
//

#import <Availability.h>
#import <AvailabilityMacros.h>
#import <TargetConditionals.h>

// Turn this on to get rid of a few bits that depend on Omni's local build environment
#define NON_OMNI_BUILD_ENVIRONMENT

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import <CoreFoundation/CoreFoundation.h>
#import <CoreFoundation/CFError.h>
#import <stdlib.h>

#import <OmniBase/rcsid.h>
#import <OmniBase/macros.h>
#import <OmniBase/assertions.h>
#import <OmniBase/OBUtilities.h>
#import <OmniBase/NSError-OBExtensions.h>
#import <OmniBase/system.h>

#import <OmniDataObjects/OmniDataObjects.h>

#import <OmniFoundation/CFArray-OFExtensions.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/OFCFCallbacks.h>

#endif
