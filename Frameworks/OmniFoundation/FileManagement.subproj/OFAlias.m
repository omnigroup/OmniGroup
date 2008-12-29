// Copyright 2004-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFAlias.h>

RCS_ID("$Id$");

// We may want to store the path verbatim as well as the alias.

@implementation OFAlias

// Init and dealloc

- initWithPath:(NSString *)path;
{
    if ([super init] == nil)
        return nil;

    CFURLRef urlRef = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)path, kCFURLPOSIXPathStyle, false);
    
    FSRef fsRef;

    require(CFURLGetFSRef(urlRef, &fsRef) == true, error_out);
    require_noerr(FSNewAlias(NULL, &fsRef, &_aliasHandle), error_out);

    CFRelease(urlRef);
    
    return self;
error_out:
    CFRelease(urlRef);
    [self release];
    return nil;

}

- initWithData:(NSData *)data;
{
    if ([super init] == nil)
        return nil;

    unsigned int length = [data length];
    _aliasHandle = (AliasHandle)NewHandle(length);   
    [data getBytes:*_aliasHandle length:length];
      
    return self;
}


- (void)dealloc;
{
    if (_aliasHandle != NULL)
        DisposeHandle((Handle)_aliasHandle);
    [super dealloc];
}


// API

- (NSString *)path;
{
    return [self pathAllowingUserInterface:YES missingVolume:NULL];
}

- (NSString *)pathAllowingUnresolvedPath;
{
    return [self pathAllowingUserInterface:YES missingVolume:NULL allowUnresolvedPath:YES];
}

- (NSString *)pathAllowingUserInterface:(BOOL)allowUserInterface missingVolume:(BOOL *)missingVolume;
{
    return [self pathAllowingUserInterface:allowUserInterface missingVolume:missingVolume allowUnresolvedPath:NO];
}

- (NSString *)pathAllowingUserInterface:(BOOL)allowUserInterface missingVolume:(BOOL *)missingVolume allowUnresolvedPath:(BOOL)allowUnresolvedPath;
{
    // We want to allow the caller to avoid blocking if the volume in question is not reachable.  The only way I see to do that is to pass the kResolveAliasFileNoUI flag to FSResolveAliasWithMountFlags.  This will cause it to fail immediately with nsvErr (no such volume).
    FSRef target;
    Boolean wasChanged;
    OSErr result;
    
    unsigned long mountFlags = kResolveAliasTryFileIDFirst;
    if (!allowUserInterface)
	mountFlags |= kResolveAliasFileNoUI;
    
    if (missingVolume)
	*missingVolume = NO;

    result = FSResolveAliasWithMountFlags(NULL, _aliasHandle, &target, &wasChanged, mountFlags);
    if (result == noErr) {
        CFURLRef urlRef = CFURLCreateFromFSRef(kCFAllocatorDefault, &target);
        NSString *urlString = (NSString *)CFURLCopyFileSystemPath(urlRef, kCFURLPOSIXPathStyle);
        CFRelease(urlRef);
        return [urlString autorelease];
    } else {
	NSLog(@"FSResolveAliasWithMountFlags -> %d", result);
    }
    
    if (result == nsvErr) {
	if (missingVolume)
	    *missingVolume = YES;
    } 
    
    if (allowUnresolvedPath) {
        // Alias points to something that is gone
        CFStringRef path = NULL;
        result = FSCopyAliasInfo(_aliasHandle, 
                                 NULL, // targetName
                                 NULL, // volumeName
                                 &path,
                                 NULL, // whichInfo
                                 NULL);  // info;
        if (result != noErr) {
            NSLog(@"FSCopyAliasInfo -> %d", result);
        }
        return [(id)path autorelease];
    } else {
	NSLog(@"FSResolveAliasWithMountFlags -> %d", result);
    }

    return nil;
}

- (NSData *)data;
{
    HLock((Handle)_aliasHandle);
    NSData *retval = [NSData dataWithBytes:*_aliasHandle length:GetHandleSize((Handle)_aliasHandle)];
    HUnlock((Handle)_aliasHandle);
    return retval;
}


@end
