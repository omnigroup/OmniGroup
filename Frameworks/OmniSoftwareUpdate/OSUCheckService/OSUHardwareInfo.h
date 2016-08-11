// Copyright 2002-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <CoreFoundation/CFDictionary.h>

@class NSString, NSDictionary;

extern CFMutableDictionaryRef OSUCopyHardwareInfo(NSString *applicationIdentifier, NSString *uuidString, NSDictionary *runtimeStats, NSDictionary *probes, bool collectHardwareInformation, NSString *licenseType, bool reportMode);

#define OSUReportInfoUUIDKey (@"uuid")
#define OSUReportInfoLicenseTypeKey (@"license-type")
#define OSUReportInfoOSVersionKey (@"os")
#define OSUReportInfoLanguageKey (@"lang")
#define OSUReportInfoMachineNameKey (@"machine_name")
#define OSUReportInfoHardwareModelKey (@"hw-model")
#define OSUReportInfoCPUCountKey (@"ncpu")
#define OSUReportInfoCPUTypeKey (@"cpu")
#define OSUReportInfoCPUFrequencyKey (@"cpuhz")
#define OSUReportInfoBusFrequencyKey (@"bushz")
#define OSUReportInfoMemorySizeKey (@"mem")
#define OSUReportInfoVolumeSizeKey (@"vol") // Total size of local volumes
