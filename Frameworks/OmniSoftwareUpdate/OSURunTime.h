// Copyright 2007-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/objc.h>
#import <OmniBase/macros.h>

@class NSString, NSMutableDictionary;

extern BOOL OSURunTimeHasHandledApplicationTermination(void) OB_HIDDEN;

extern void OSURunTimeApplicationActivated(NSString *appIdentifier, NSString *bundleVersion) OB_HIDDEN;
extern void OSURunTimeApplicationDeactivated(NSString *appIdentifier, NSString *bundleVersion, BOOL crashed); // NOT hidden since OmniCrashCatcherReports uses it.

extern void OSURunTimeAddStatisticsToInfo(NSString *appIdentifier, NSMutableDictionary *info) OB_HIDDEN;

extern NSString * const OSULastSuccessfulCheckDateKey;
