// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/trunk/OmniGroup/Frameworks/OmniBase/OBPostLoader.m 81954 2006-12-01 18:40:08Z bungi $

#import <AvailabilityMacros.h>
#import <TargetConditionals.h>
#import <Foundation/NSObjCRuntime.h>

#import <objc/objc.h>
#if !TARGET_OS_IPHONE
#import <objc/objc-class.h>
#import <objc/objc-runtime.h>
#else
#import <objc/runtime.h>
#endif
#import <Foundation/NSObjCRuntime.h>
