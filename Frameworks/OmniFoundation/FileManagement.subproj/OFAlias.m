// Copyright 2004-2005, 2007-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFAlias.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <Carbon/Carbon.h>
#endif

RCS_ID("$Id$");

// We may want to store the path verbatim as well as the alias.

@implementation OFAlias

// Init and dealloc

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
- initWithPath:(NSString *)path;
{
    if ([super init] == nil)
        return nil;

    CFURLRef urlRef = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)path, kCFURLPOSIXPathStyle, false);
    
    FSRef fsRef;
    AliasHandle aliasHandle = NULL;
    
    require(CFURLGetFSRef(urlRef, &fsRef) == true, error_out);
    require_noerr(FSNewAlias(NULL, &fsRef, &aliasHandle), error_out);

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
        
        result = FSResolveAliasWithMountFlags(NULL, aliasHandle, &target, &wasChanged, mountFlags);
        if (result == noErr) {
            CFURLRef urlRef = CFURLCreateFromFSRef(kCFAllocatorDefault, &target);
            CFStringRef urlString = CFURLCopyFileSystemPath(urlRef, kCFURLPOSIXPathStyle);
            CFRelease(urlRef);
            path = [NSMakeCollectable(urlString) autorelease];
            break;
        } else {
            NSLog(@"FSResolveAliasWithMountFlags -> %d", result);
        }
        
        if (result == nsvErr) {
            if (missingVolume)
                *missingVolume = YES;
        } 
        
        if (allowUnresolvedPath) {
            // Alias points to something that is gone
            CFStringRef aliasPath = NULL;
            result = FSCopyAliasInfo(aliasHandle, 
                                     NULL, // targetName
                                     NULL, // volumeName
                                     &aliasPath,
                                     NULL, // whichInfo
                                     NULL);  // info;
            if (result != noErr) {
                NSLog(@"FSCopyAliasInfo -> %d", result);
            }
            path = [NSMakeCollectable(aliasPath) autorelease];
            break;
        } else {
            NSLog(@"FSResolveAliasWithMountFlags -> %d", result);
        }
    } while (0);

    HUnlock((Handle)aliasHandle);
    DisposeHandle((Handle)aliasHandle);
    return path;
}
#endif

@synthesize data = _aliasData;

@end
