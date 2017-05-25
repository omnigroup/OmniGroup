// Copyright 2004-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFAlias.h>

// <bug:///89022> (Rewrite OFAlias to use non-deprecated API or remove it)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <Carbon/Carbon.h>
#endif

#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

RCS_ID("$Id$");

// TODO: Switch to +[NSURL bookmarkDataWithOptions:includingResourceValuesForKeys:relativeToURL:error:]?

// We may want to store the path verbatim as well as the alias.

@implementation OFAlias

// Init and dealloc

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- initWithPath:(NSString *)path;
{
    if (!(self = [super init]))
        return nil;

    CFURLRef urlRef = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)path, kCFURLPOSIXPathStyle, false);
    
    FSRef fsRef;
    AliasHandle aliasHandle = NULL;

    if (!CFURLGetFSRef(urlRef, &fsRef)) {
        goto error_out;
    }

    OSErr err = FSNewAlias(NULL, &fsRef, &aliasHandle);
    if (err != noErr || aliasHandle == NULL) {
        goto error_out;
    }

    CFRelease(urlRef);
    
    HLock((Handle)aliasHandle);
    _aliasData = [[NSData alloc] initWithBytes:*aliasHandle length:GetHandleSize((Handle)aliasHandle)];
    HUnlock((Handle)aliasHandle);

    DisposeHandle((Handle)aliasHandle);

    return self;
error_out:
    CFRelease(urlRef);
    [self release];
    return nil;

}
#endif

- initWithData:(NSData *)data;
{
    OBPRECONDITION(data);
    
    if (!(self = [super init]))
        return nil;

    _aliasData = [data copy];
      
    return self;
}


- (void)dealloc;
{
    [_aliasData release];
    [super dealloc];
}


// API

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
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
    
    unsigned long mountFlags = kResolveAliasTryFileIDFirst;
    if (!allowUserInterface)
	mountFlags |= kResolveAliasFileNoUI;
    
    if (missingVolume)
	*missingVolume = NO;

    AliasHandle aliasHandle = (AliasHandle)NewHandle([_aliasData length]);
    HLock((Handle)aliasHandle);
    [_aliasData getBytes:*aliasHandle length:[_aliasData length]];

    NSString *path = nil;
    do {
        Boolean wasChanged;
        FSRef target;
        OSErr result;
        OSStatus sresult;
        
        result = FSResolveAliasWithMountFlags(NULL, aliasHandle, &target, &wasChanged, mountFlags);
        if (result == noErr) {
            CFURLRef urlRef = CFURLCreateFromFSRef(kCFAllocatorDefault, &target);
            CFStringRef urlString = CFURLCopyFileSystemPath(urlRef, kCFURLPOSIXPathStyle);
            CFRelease(urlRef);
            path = CFBridgingRelease(urlString);
            break;
        } else {
            if (result == fnfErr || result == nsvErr) {
                // This is an expected 'error' -- ideally we'd either remove this code or pass back an NSError.
            } else {
                NSLog(@"FSResolveAliasWithMountFlags -> %d", result);
            }
        }
        
        if (result == nsvErr) {
            if (missingVolume)
                *missingVolume = YES;
        } 
        
        if (allowUnresolvedPath) {
            // Alias points to something that is gone
            CFStringRef aliasPath = NULL;
            sresult = FSCopyAliasInfo(aliasHandle,
                                      NULL, // targetName
                                      NULL, // volumeName
                                      &aliasPath,
                                      NULL, // whichInfo
                                      NULL);  // info;
            if (sresult != noErr) {
                NSLog(@"FSCopyAliasInfo -> %d", sresult);
            }
            path = CFBridgingRelease(aliasPath);
            break;
        } else {
            if (result == fnfErr || result == nsvErr) {
                // This is an expected 'error' -- ideally we'd either remove this code or pass back an NSError.
            } else {
                NSLog(@"FSResolveAliasWithMountFlags -> %d", result);
            }
        }
    } while (0);

    HUnlock((Handle)aliasHandle);
    DisposeHandle((Handle)aliasHandle);
    return path;
}
#endif

@synthesize data = _aliasData;

@end

#pragma clang diagnostic pop
