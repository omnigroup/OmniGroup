// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBLog.h>

os_log_t OBLogCreate(const char *subsystem, const char *category)
{
#ifdef DEBUG
    @autoreleasepool {
        NSString *subsystemVariable = [[NSString alloc] initWithFormat:@"OBLogDisabled_%s", subsystem];
        if (getenv(subsystemVariable.UTF8String) != NULL) {
            return OS_LOG_DISABLED;
        }
        NSString *categoryVariable = [[NSString alloc] initWithFormat:@"OBLogDisabled_%s_%s", subsystem, category];
        if (getenv(categoryVariable.UTF8String) != NULL) {
            return OS_LOG_DISABLED;
        }
    }
#endif
    return os_log_create(subsystem, category);
}


