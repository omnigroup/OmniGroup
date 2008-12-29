// Copyright 2004-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniSoftwareUpdate/OmniSoftwareUpdate_Prefix.h 98770 2008-03-17 22:25:33Z kc $

// Prefix header for all source files of the 'OmniSoftwareUpdate' target in the 'OmniSoftwareUpdate' project.

#ifdef __OBJC__
    #import <Foundation/Foundation.h>
    #import <AppKit/AppKit.h>

    // Command line tool shouldn't bring in all of OmniBase
    #ifdef OMNI_BUNDLE_IDENTIFIER
        #import <OmniBase/OmniBase.h>
    #else
        // Instead, the tool uses one code-less header from OmniBase and then directly references two source files from it.
        #import <OmniBase/rcsid.h>
        #import "assertions.h"
        #import "NSError-OBExtensions.h"
    #endif
#endif
