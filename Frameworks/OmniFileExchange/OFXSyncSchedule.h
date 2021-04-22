// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

// These are ordered so that greater-/less-than checks are usable.
typedef NS_ENUM(NSUInteger, OFXSyncSchedule) {
    OFXSyncScheduleNone, // Syncing is completely disabled. -sync: will just call its completion handler.
    OFXSyncScheduleManual, // Calls to -sync: will result in sync operations happending.
    OFXSyncScheduleAutomatic, // Bonjour and timers will be used to detect when to call -sync:. On iOS, background fetching will be requested.
};
