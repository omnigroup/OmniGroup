// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAColorProfile.h"
#import "OAColorProfile-Deprecated.h"
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OAColorProfile (Deprecated)

- (BOOL)_rawProfileIsBuiltIn:(CMProfileRef)rawProfile;
{
    UInt32 locationSize;
    CMError err = NCMGetProfileLocation(rawProfile, NULL, &locationSize);
    if (err != noErr)
        return NO;

    CMProfileLocation *profileLocation = malloc(locationSize);
    err = NCMGetProfileLocation(rawProfile, profileLocation, &locationSize);
    if (err != noErr) {
        free(profileLocation);
        return NO;
    }
    
    // FSpMakeFSRef is deprecated on 10.5 with no replacement.  One hopes that they will only return path-based locations
    // The struct/enum for the FSSpec-based location are deprecated in 10.5 too and Apple shouldn't be returning them.  Logged <bug://41073> Radar 5466091
    // Until this is fixed we are breaking this out into this separate class file so deprecation warnings can be ignored.
    BOOL isBuiltIn = NO;
#if !__LP64__ && !TARGET_OS_WIN32 && !TARGET_OS_IPHONE
    if (profileLocation->locType == cmFileBasedProfile) {
        FSRef fsRef;
        FSpMakeFSRef(&profileLocation->u.fileLoc.spec, &fsRef);
        CFURLRef url = CFURLCreateFromFSRef(NULL, &fsRef);
        CFStringRef string = CFURLCopyPath(url);
        isBuiltIn = [(NSString *)string hasPrefix:@"/System/Library/ColorSync/Profiles"];
        CFRelease(url);
        CFRelease(string);
    } else
#endif
        if (profileLocation->locType == cmPathBasedProfile) {
        isBuiltIn = !strncmp(profileLocation->u.pathLoc.path, "/System/Library/ColorSync/Profiles/", 35);
    }
    
    free(profileLocation);
    return isBuiltIn;
}

@end
