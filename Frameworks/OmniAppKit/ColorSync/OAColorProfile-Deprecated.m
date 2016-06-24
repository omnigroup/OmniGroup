// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAColorProfile.h>
#import "OAColorProfile-Deprecated.h"
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OAColorProfile (Deprecated)

- (BOOL)_rawProfileIsBuiltIn:(ColorSyncProfileRef)rawProfile;
{
    CFURLRef url = ColorSyncProfileGetURL(rawProfile, NULL);
    if (url == NULL) {
        return NO;
    }
    
    CFStringRef string = CFURLCopyPath(url);
    BOOL isBuiltIn = [(OB_BRIDGE NSString *)string hasPrefix:@"/System/Library/ColorSync/Profiles"];
    CFRelease(string);
    
    return isBuiltIn;
}

@end
