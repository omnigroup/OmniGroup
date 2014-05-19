// Copyright 2007, 2010-2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/objc.h>

@class NSString, NSMutableDictionary;

// This is linked by both OmniSoftwareUpdate and OmniCrashCatcher.
BOOL OSURunTimeHasHandledApplicationTermination(void) OB_HIDDEN;

void OSURunTimeApplicationActivated(NSString *appIdentifier, NSString *bundleVersion) OB_HIDDEN;
void OSURunTimeApplicationDeactivated(NSString *appIdentifier, NSString *bundleVersion, BOOL crashed) OB_HIDDEN;

void OSURunTimeAddStatisticsToInfo(NSString *appIdentifier, NSMutableDictionary *info) OB_HIDDEN;

extern NSString * const OSUNextCheckKey;
