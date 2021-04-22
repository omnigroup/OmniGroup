// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <os/log.h>

// Wrapper that allows disabling log streams via environment variables (since Xcode globally enables logs).
// In debug builds, set the enviroment variable "OBLogDisabled_subsystem" or "OBLogDisabled_subsystem_category" and OS_LOG_DISABLED will be returned.
// In non-debug builds, this is a no-op.
extern os_log_t OBLogCreate(const char *subsystem, const char *category) NS_REFINED_FOR_SWIFT;
