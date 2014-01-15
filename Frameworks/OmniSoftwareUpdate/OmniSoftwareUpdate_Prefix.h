// Copyright 2004-2005, 2007-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

// Prefix header for all source files of the 'OmniSoftwareUpdate' target in the 'OmniSoftwareUpdate' project.

#include <tgmath.h>

#import "InfoPlist.h"

#ifdef __OBJC__
    #import <Foundation/Foundation.h>

    #if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
        #import <UIKit/UIKit.h>
        #import <OmniBase/OmniBase.h>
    #else
        #import <AppKit/AppKit.h>

        // Command line tool shouldn't bring in all of OmniBase
        #ifdef OMNI_BUNDLE_IDENTIFIER
            #import <OmniBase/OmniBase.h>
        #else
            // Instead, the tool uses one code-less header from OmniBase and then directly references two source files from it.
            #import <OmniBase/rcsid.h>
            #import <OmniBase/assertions.h>
            #import <OmniBase/NSError-OBExtensions.h>
        #endif
    #endif
#endif
