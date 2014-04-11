// Copyright 2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFFileUtilities.h>

#include <pwd.h>

RCS_ID("$Id$");

NSString *OFUnsandboxedHomeDirectory(void) {
    long bufsize;
    
    if ((bufsize = sysconf(_SC_GETPW_R_SIZE_MAX)) == -1) {
        abort();
    }
    
    char buffer[bufsize];
    struct passwd pwd, *result = NULL;
    if (getpwuid_r(getuid(), &pwd, buffer, bufsize, &result) != 0 || !result) {
        abort();
    }
    
    return [NSString stringWithUTF8String:pwd.pw_dir];
}
