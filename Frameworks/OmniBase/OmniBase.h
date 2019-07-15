// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AvailabilityMacros.h>

#import <OmniBase/assertions.h>
#import <OmniBase/macros.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/OBBacktraceBuffer.h>

#if !defined(TARGET_OS_WATCH) || !TARGET_OS_WATCH
#import <OmniBase/OBBundle.h>
#import <OmniBase/OBCasting.h>
#endif

#import <OmniBase/OBUtilities.h>
#import <OmniBase/OBExpectedDeallocation.h>

#import <OmniBase/OBObject.h>
#import <OmniBase/OBLoadAction.h>

#import <OmniBase/OBUtilities.h>
#import <OmniBase/OBLogger.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniBase/NSData-OBObjectCompatibility.h>
#endif
#import <OmniBase/NSException-OBExtensions.h>
#import <OmniBase/NSError-OBExtensions.h>
#import <OmniBase/NSError-OBUtilities.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <OmniBase/OBRuntimeCheck.h>
#endif
