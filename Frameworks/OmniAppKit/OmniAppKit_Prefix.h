// Copyright 2003-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OmniAppKit_Prefix.h 93428 2007-10-25 16:36:11Z kc $

#ifndef DEBUG_automation
#import <CoreFoundation/CoreFoundation.h>

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

#import <OmniBase/OmniBase.h>
#import <OmniBase/system.h>
#import <OmniFoundation/OmniFoundation.h>

// Import just a few commonly used headers from OmniAppKit itself
#import "OAUtilities.h"
#import "FrameworkDefines.h"
#import "OAFindControllerTargetProtocol.h"
//#import "NSImage-OAExtensions.h"

#endif /* __OBJC__ */

#endif /* DEBUG_automation */
