// Copyright 2015-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Availability.h>

#import <OmniSoftwareUpdate/OSUHardwareInfo.h>
#import <OmniSoftwareUpdate/OSUReportKeys.h>
#import <OmniSoftwareUpdate/OSUChecker.h>
#import <OmniSoftwareUpdate/OSUCheckerTarget.h>
#import <OmniSoftwareUpdate/OSUProbe.h>
#import <OmniSoftwareUpdate/OSUDeviceDetails.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <OmniSoftwareUpdate/OSUPreferences.h>
#import <OmniSoftwareUpdate/OSUController.h>
#import <OmniSoftwareUpdate/OSUPreferencesViewController.h>
#else
#import <OmniSoftwareUpdate/NSApplication-OSUSupport.h>
#import <OmniSoftwareUpdate/NSApplication-OSUNewsSupport.h>
#import <OmniSoftwareUpdate/OSUCheckOperation.h>
#import <OmniSoftwareUpdate/OSUDownloadController.h>
#import <OmniSoftwareUpdate/OSURunTime.h>
#import <OmniSoftwareUpdate/OSUSystemConfigurationController.h>
#endif
