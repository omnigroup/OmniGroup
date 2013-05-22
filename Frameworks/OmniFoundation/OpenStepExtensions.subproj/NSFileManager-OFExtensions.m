// Copyright 1997-2008, 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSFileManager-OFExtensions.h>

#import <Foundation/NSPropertyList.h>
#import <OmniBase/system.h>
#import <OmniBase/macros.h>
#import <OmniBase/NSError-OBExtensions.h>

#import <OmniFoundation/NSProcessInfo-OFExtensions.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFUtilities.h>
#import <OmniFoundation/OFVersionNumber.h>

#import <CoreServices/CoreServices.h>
#import <Security/SecCode.h>
#import <Security/SecStaticCode.h>
#import <Security/SecRequirement.h> // For SecRequirementCreateWithString()
#import <sys/errno.h>
#import <sys/param.h>
#import <stdio.h>
#import <sys/mount.h>
#import <unistd.h>
#import <sys/types.h>
#import <sys/stat.h>
#import <sys/attr.h>
#import <fcntl.h>

RCS_ID("$Id$")

OBDEPRECATED_METHOD(-fileManager:shouldProceedAfterError:);
OBDEPRECATED_METHOD(-fileManager:willProcessPath:);

@interface NSFileManager (OFPrivate)
- (int)filesystemStats:(struct statfs *)stats forPath:(NSString *)path;
- (NSString *)lockFilePathForPath:(NSString *)path;
@end

@implementation NSFileManager (OFExtensions)

static NSString *scratchDirectoryPath;
static NSLock *scratchDirectoryLock;
static int permissionsMask = 0022;

+ (void)didLoad;
{
    scratchDirectoryPath = nil;
    scratchDirectoryLock = [[NSLock alloc] init];

    permissionsMask = umask(permissionsMask);
    umask(permissionsMask); // Restore the original value
}

- (NSString *)desktopDirectory;
{
    FSRef dirRef;
    OSErr err = FSFindFolder(kUserDomain, kDesktopFolderType, kCreateFolder, &dirRef);
    if (err != noErr) {
#ifdef DEBUG
        NSLog(@"FSFindFolder(kDesktopFolderType) -> %d", err);
#endif
        [NSException raise:NSInvalidArgumentException format:@"Unable to find desktop directory"];
    }

    CFURLRef url;
    url = CFURLCreateFromFSRef(kCFAllocatorDefault, &dirRef);
    if (!url)
        [NSException raise:NSInvalidArgumentException format:@"Unable to create URL to desktop directory"];

    NSString *path = [[[(NSURL *)url path] copy] autorelease];
    CFRelease(url);

    return path;
}

- (NSString *)documentDirectory;
{
    FSRef dirRef;
    OSErr err = FSFindFolder(kUserDomain, kDocumentsFolderType, kCreateFolder, &dirRef);
    if (err != noErr) {
#ifdef DEBUG
        NSLog(@"FSFindFolder(kDocumentsFolderType) -> %d", err);
#endif
        [NSException raise:NSInvalidArgumentException format:@"Unable to find document directory"];
    }

    CFURLRef url;
    url = CFURLCreateFromFSRef(kCFAllocatorDefault, &dirRef);
    if (!url)
        [NSException raise:NSInvalidArgumentException format:@"Unable to create URL to document directory"];

    NSString *path = [[[(NSURL *)url path] copy] autorelease];
    CFRelease(url);

    return path;
}

- (NSString *)scratchDirectoryPath;
{
    NSUserDefaults *defaults;
    NSString *defaultsScratchDirectoryPath;
    NSString *workingScratchDirectoryPath;

    [scratchDirectoryLock lock];

    if (scratchDirectoryPath) {
        BOOL isDir;
        
        if ([self fileExistsAtPath:scratchDirectoryPath isDirectory:&isDir] && isDir) {
            [scratchDirectoryLock unlock];
            return scratchDirectoryPath;
        } else {
            [scratchDirectoryPath release];
            scratchDirectoryPath = nil;
        }
    }

    defaults = [NSUserDefaults standardUserDefaults];

    defaultsScratchDirectoryPath = [defaults stringForKey:@"OFScratchDirectory"];
    if ([NSString isEmptyString:defaultsScratchDirectoryPath] || [defaultsScratchDirectoryPath isEqualToString:@"NSTemporaryDirectory"]) {
        defaultsScratchDirectoryPath = NSTemporaryDirectory();
    } else {
        defaultsScratchDirectoryPath = [defaultsScratchDirectoryPath stringByExpandingTildeInPath];
    }
    
    [self createDirectoryAtPath:defaultsScratchDirectoryPath
    withIntermediateDirectories:YES
                     attributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0777 | S_ISVTX] forKey:NSFilePosixPermissions]
                          error:NULL];

    workingScratchDirectoryPath = [defaultsScratchDirectoryPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@-######", [[NSProcessInfo processInfo] processName], NSUserName()]];
    workingScratchDirectoryPath = [self tempFilenameFromHashesTemplate:workingScratchDirectoryPath];

    BOOL success = [self createDirectoryAtPath:workingScratchDirectoryPath
                   withIntermediateDirectories:NO
                                    attributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0700] forKey:NSFilePosixPermissions]
                                         error:NULL];
    
    if (!success) {
        [scratchDirectoryLock unlock];
        return nil;
    }
    
    scratchDirectoryPath = [workingScratchDirectoryPath copy];

    [scratchDirectoryLock unlock];
    return scratchDirectoryPath;
}

- (NSString *)scratchFilenameNamed:(NSString *)aName error:(NSError **)outError;
{
    if (!aName || [aName length] == 0)
	aName = @"scratch";
    return [self uniqueFilenameFromName:[[self scratchDirectoryPath] stringByAppendingPathComponent:aName] error:outError];
}

- (void)removeScratchDirectory;
{
    if (!scratchDirectoryPath)
	return;
    [self removeItemAtPath:scratchDirectoryPath error:NULL];
    [scratchDirectoryPath release];
    scratchDirectoryPath = nil;
}

- (NSString *)existingPortionOfPath:(NSString *)path;
{
    NSArray *pathComponents = [path pathComponents];
    NSUInteger componentCount = [pathComponents count];
    NSUInteger startingIndex  = 0;
    
    NSUInteger goodComponentsCount;
    for (goodComponentsCount = startingIndex; goodComponentsCount < componentCount; goodComponentsCount++) {
        NSString *testPath = [NSString pathWithComponents:[pathComponents subarrayWithRange:NSMakeRange(0, goodComponentsCount + 1)]];
        if (goodComponentsCount < componentCount - 1) {
            // For the leading components, test to see if a directory exists at that path
            if (![self directoryExistsAtPath:testPath traverseLink:YES])
                break;
        } else {
            // For the final component, test to see if any sort of file exists at that path
            if (![self fileExistsAtPath:testPath])
                break;
        }
    }
    if (goodComponentsCount == 0) {
        return @"";
    } else if (goodComponentsCount == componentCount) {
        return path;
    } else if (goodComponentsCount == 1) {
        // Returns @"/" on UNIX, and (hopefully) @"C:\" on Windows
        return [pathComponents objectAtIndex:0];
    } else {
        // Append a trailing slash to the existing directory
        return [[NSString pathWithComponents:[pathComponents subarrayWithRange:NSMakeRange(0, goodComponentsCount)]] stringByAppendingString:@"/"];
    }
}

// The NSData method -writeToFile:atomically: doesn't take an attribute dictionary.
// This means that you could write the file w/o setting the attributes, which might
// be a security hole if the file gets left in the default attribute state.  This method
// gets the attributes right on the first pass and then gets the name right, potentially
// leaving turds in the filesystem.
- (BOOL)atomicallyCreateFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary *)attr;
{
    // Create a temporary file in the same directory
    NSString *tmpPath = [self tempFilenameFromHashesTemplate: [NSString stringWithFormat: @"%@-tmp-######", path]];
    
    if (![self createFileAtPath: tmpPath contents: data attributes: attr])
        return NO;
        
    // -movePath:toPath:handler: is documented to copy the original file rather than renaming it.
    // It is also documented to fail if the destination exists.  So, we will use our trusty Unix
    // APIs.
    int rc = rename([tmpPath UTF8String], [path UTF8String]);
    return rc == 0;
}

- (NSArray *) directoryContentsAtPath: (NSString *) path havingExtension: (NSString *) extension  error:(NSError **)outError;
{
    NSArray *children;
    NSError *error = nil;
    if (!(children = [self contentsOfDirectoryAtPath:path error:&error])) {
        if (outError)
            *outError = error;
        // Return nil in exactly the cases that -directoryContentsAtPath: does (rather than returning an empty array).
        return nil;
    }
    
    NSMutableArray *filteredChildren = [NSMutableArray array];
    for (NSString *child in children) {
        if ([[child pathExtension] isEqualToString: extension])
            [filteredChildren addObject: child];
    }
    
    return filteredChildren;
}

// File locking

- (NSDictionary *)lockFileAtPath:(NSString *)path overridingExistingLock:(BOOL)override created:(BOOL *)outCreated error:(NSError **)outError;
{
    if (outError)
        *outError = nil;
    *outCreated = NO;
    
    NSString *lockFilePath = [self lockFilePathForPath:path];
    if (override == NO && [self fileExistsAtPath:lockFilePath]) {
        // Someone else already has the lock. Report the owner.
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:lockFilePath];
        if (!dict) {
            // Couldn't parse the lock file for some reason.
            dict = [NSDictionary dictionary];
        } else {
            // If we're on the same host, we can check if the locking process is gone. In that case, we can safely override the lock.
            if ([OFUniqueMachineIdentifier() isEqualToString:[dict objectForKey:@"hostIdentifier"]] || [OFHostName() isEqualToString:[dict objectForKey:@"hostName"]]) {
                int processNumber;
            
                processNumber = [[dict objectForKey:@"processNumber"] intValue];
                if (processNumber > 0) {
                    if (kill(processNumber, 0) == -1 && OMNI_ERRNO() == ESRCH) {
                        dict = nil;  // And go on to override
                    }
                }
            }
        }
        
        if (dict)
            return dict;
    }

    id value;
    NSMutableDictionary *lockDictionary = [NSMutableDictionary dictionaryWithCapacity:4];
    if ((value = OFUniqueMachineIdentifier()))
        [lockDictionary setObject:value forKey:@"hostIdentifier"];
    if ((value = OFHostName()))
        [lockDictionary setObject:value forKey:@"hostName"];
    if ((value = NSUserName()))
        [lockDictionary setObject:value forKey:@"userName"];
    if ((value = [[NSProcessInfo processInfo] processNumber]))
        [lockDictionary setObject:value forKey:@"processNumber"];

    if (![self createPathToFile:lockFilePath attributes:nil error:outError])
        return nil;
    
    NSData *data = OFCreateNSDataFromPropertyList(lockDictionary, kCFPropertyListXMLFormat_v1_0, outError);
    if (!data) {
        // Stack our error code on top of the CF error code
        OFError(outError, OFUnableToSerializeLockFileDictionaryError, nil, nil);
        return nil;
    }
    
    if (![data writeToFile:lockFilePath options:NSAtomicWrite error:outError]) {
        OFError(outError, OFUnableToCreateLockFileError, ([NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to create lock file '%@'.", @"OmniFoundation", OMNI_BUNDLE, @"error description"), lockFilePath]), nil);
        [data release];
        return nil;
    }
    [data release];
    
    *outCreated = YES;
    return lockDictionary;
}


- (void)unlockFileAtPath:(NSString *)path;
{
#if 1
    // <bug://50010> Port or remove NSFileManager locking extensions
    OBRequestConcreteImplementation(self, _cmd);
#else
    NSString *lockFilePath;
    NSDictionary *lockDictionary;
    
    lockFilePath = [self lockFilePathForPath:path];
    if ([self fileExistsAtPath:lockFilePath] == NO) {
        [NSException raise:NSInternalInconsistencyException format:@"Error unlocking file at %@: lock file %@ does not exist", path, lockFilePath];
    }

    lockDictionary = [NSDictionary dictionaryWithContentsOfFile:lockFilePath];
    if (!lockDictionary) {
        [NSException raise:NSInternalInconsistencyException format:@"Error unlocking file at %@: couldn't read lock file %@", path, lockFilePath];
    }

    if (! ([[lockDictionary objectForKey:@"hostName"] isEqualToString:OFHostName()] && [[lockDictionary objectForKey:@"userName"] isEqualToString:NSUserName()] && [[lockDictionary objectForKey:@"processNumber"] intValue] == [[[NSProcessInfo processInfo] processNumber] intValue])) {
        [NSException raise:NSInternalInconsistencyException format:@"Error unlocking file at %@: lock file doesn't match current process", path];
    }

    if ([self removeFileAtPath:lockFilePath handler:nil] == NO) {
        [NSException raise:NSGenericException format:@"Error unlocking file at %@: lock file couldn't be removed", path];
    }
#endif
}

//
- (NSURL *)specialDirectory:(OSType)whatDirectoryType forFileSystemContainingPath:(NSString *)path create:(BOOL)createIfMissing error:(NSError **)outError;
{
    FSRef ref;
    OSStatus err;
    
    // The file in question might not exist yet.  This loop assumes that it will terminate due to '/' always being valid.
    NSString *attempt = path;
    while (YES) {
        const char *posixPath = [self fileSystemRepresentationWithPath:attempt];
        err = FSPathMakeRefWithOptions((const unsigned char *)posixPath, kFSPathMakeRefDoNotFollowLeafSymlink, &ref, NULL);
        if (err == noErr)
            break;
        attempt = [attempt stringByDeletingLastPathComponent];
    }
    
    // Find the path's volume number.
    FSCatalogInfo catalogInfo;
    err = FSGetCatalogInfo(&ref, kFSCatInfoVolume, &catalogInfo, NULL, NULL, NULL);
    if (err != noErr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil]; // underlying error
        OFError(outError, OFCannotFindTemporaryDirectoryError, ([NSString stringWithFormat:@"Unable to get catalog info for '%@' (for '%@')", attempt, path]), nil);
        return nil;
    }
    
    // Actually look up the folder.
    FSRef folderRef;
    err = FSFindFolder(catalogInfo.volume, whatDirectoryType, createIfMissing? kCreateFolder : kDontCreateFolder, &folderRef);
    if (err != noErr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil]; // underlying error
        OFError(outError, OFCannotFindTemporaryDirectoryError, ([NSString stringWithFormat:@"Unable to find temporary items directory for '%@'", attempt]), nil);
        return nil;
    }
    
    CFURLRef temporaryItemsURL;
    temporaryItemsURL = CFURLCreateFromFSRef(kCFAllocatorDefault, &folderRef);
    if (!temporaryItemsURL) {
        OFError(outError, OFCannotFindTemporaryDirectoryError, ([NSString stringWithFormat:@"Unable to create URL to temporary items directory for '%@'", attempt]), nil);
        return nil;
    }
    
    NSURL *resultURL = [NSMakeCollectable(temporaryItemsURL) autorelease];
    
    return [resultURL URLByStandardizingPath];
}

- (NSURL *)trashDirectoryURLForURL:(NSURL *)fileURL error:(NSError **)outError;
{
    OBPRECONDITION([fileURL isFileURL]);
    
    return [self specialDirectory:kTrashFolderType forFileSystemContainingPath:[fileURL path] create:NO error:outError];
}

- (NSNumber *)posixPermissionsForMode:(unsigned int)mode;
{
    return [NSNumber numberWithUnsignedLong:mode & (~permissionsMask)];
}

- (NSNumber *)defaultFilePermissions;
{
    return [self posixPermissionsForMode:0666];
}

- (NSNumber *)defaultDirectoryPermissions;
{
    return [self posixPermissionsForMode:0777];
}

- (BOOL)isFileAtPath:(NSString *)path enclosedByFolderOfType:(OSType)folderType;
{
    Boolean result;
    OSErr err = DetermineIfPathIsEnclosedByFolder (kOnAppropriateDisk, folderType, (UInt8 *)[path UTF8String], false, &result);
    return (err == noErr && result);
}

//

- (NSString *)networkMountPointForPath:(NSString *)path returnMountSource:(NSString **)mountSource;
{
    struct statfs stats;

    if ([self filesystemStats:&stats forPath:path] == -1)
        return nil;

    if (strcmp(stats.f_fstypename, "nfs") != 0)
        return nil;

    if (mountSource)
        *mountSource = [self stringWithFileSystemRepresentation:stats.f_mntfromname length:strlen(stats.f_mntfromname)];
    
    return [self stringWithFileSystemRepresentation:stats.f_mntonname length:strlen(stats.f_mntonname)];
}

- (NSString *)fileSystemTypeForPath:(NSString *)path;
{
    struct statfs stats;

    if ([[NSFileManager defaultManager] filesystemStats:&stats forPath:path] == -1)
        return nil; // Apparently the file doesn't exist
    return [NSString stringWithCString:stats.f_fstypename encoding:NSASCIIStringEncoding];
}

- (FSVolumeRefNum)volumeRefNumForPath:(NSString *)path error:(NSError **)outError;
{
    FSRef pathRef;
    FSCatalogInfo pathInfo;
    OSErr err;
    
    bzero(&pathRef, sizeof(pathRef));
    err = FSPathMakeRef((const UInt8 *)[path fileSystemRepresentation], &pathRef, NULL);
    if (err != noErr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:[NSDictionary dictionaryWithObject:path forKey:NSFilePathErrorKey]];
        return kFSInvalidVolumeRefNum;
    }

    bzero(&pathInfo, sizeof(pathInfo));
    err = FSGetCatalogInfo(&pathRef, kFSCatInfoVolume, &pathInfo, NULL, NULL, NULL);
    if (err != noErr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:[NSDictionary dictionaryWithObject:path forKey:NSFilePathErrorKey]];
        return kFSInvalidVolumeRefNum;
    }
    
    if (pathInfo.volume == kFSInvalidVolumeRefNum) {
        // Shouldn't happen, but let's not cause our caller to crash when it looks at *outError.
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:nsvErr userInfo:[NSDictionary dictionaryWithObject:path forKey:NSFilePathErrorKey]];
        return kFSInvalidVolumeRefNum;
    }
    
    return pathInfo.volume;
}

- (NSString *)volumeNameForPath:(NSString *)filePath error:(NSError **)outError;
{    
    FSVolumeRefNum vRef = [self volumeRefNumForPath:filePath error:outError];
    if (vRef == kFSInvalidVolumeRefNum)
        return nil;
    
    OSErr err;
    HFSUniStr255 nameBuf;
    bzero(&nameBuf, sizeof(nameBuf));
    err = FSGetVolumeInfo(vRef, 0, NULL,
                          kFSVolInfoNone, NULL,
                          &nameBuf, NULL);
    
    if (err != noErr) {
        if (outError)
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:[NSDictionary dictionaryWithObject:filePath forKey:NSFilePathErrorKey]];
        return nil;
    }
    
    return [NSString stringWithCharacters:nameBuf.unicode length:nameBuf.length];
}

- (NSString *)resolveAliasAtPath:(NSString *)path
{
    FSRef ref;
    OSErr err;
    char *buffer;
    UInt32 bufferSize;
    Boolean isFolder, wasAliased;

    if ([NSString isEmptyString:path])
        return nil;
    
    err = FSPathMakeRef((const unsigned char *)[path fileSystemRepresentation], &ref, NULL);
    if (err != noErr)
        return nil;

    err = FSResolveAliasFile(&ref, TRUE, &isFolder, &wasAliased);
    /* if it's a regular file and not an alias, FSResolveAliasFile() will return noErr and set wasAliased to false */
    if (err != noErr)
        return nil;
    if (!wasAliased)
        return path;

    buffer = malloc(bufferSize = (PATH_MAX * 4));
    err = FSRefMakePath(&ref, (unsigned char *)buffer, bufferSize);
    if (err == noErr) {
        path = [NSString stringWithUTF8String:buffer];
    } else {
        path = nil;
    }
    free(buffer);

    return path;
}

- (NSString *)resolveAliasesInPath:(NSString *)originalPath
{
    FSRef ref, originalRefOfPath;
    OSErr err;
    char *buffer;
    UInt32 bufferSize;
    Boolean isFolder, wasAliased;
    NSMutableArray *strippedComponents;
    NSString *path;

    if ([NSString isEmptyString:originalPath])
        return nil;
    
    path = [originalPath stringByStandardizingPath]; // maybe use stringByExpandingTildeInPath instead?
    strippedComponents = [[NSMutableArray alloc] init];
    [strippedComponents autorelease];

    /* First convert the path into an FSRef. If necessary, strip components from the end of the pathname until we reach a resolvable path. */
    for(;;) {
        bzero(&ref, sizeof(ref));
        err = FSPathMakeRef((const unsigned char *)[path fileSystemRepresentation], &ref, &isFolder);
        if (err == noErr)
            break;  // We've resolved the first portion of the path to an FSRef.
        else if (err == fnfErr || err == nsvErr || err == dirNFErr) {  // Not found --- try walking up the tree.
            NSString *stripped;

            stripped = [path lastPathComponent];
            if ([NSString isEmptyString:stripped])
                return nil;

            [strippedComponents addObject:stripped];
            path = [path stringByDeletingLastPathComponent];
        } else
            return nil;  // Some other error; return nil.
    }
    /* Stash a copy of the FSRef we got from 'path'. In the common case, we'll be converting this very same FSRef back into a path, in which case we can just re-use the original path. */
    bcopy(&ref, &originalRefOfPath, sizeof(FSRef));

    /* Repeatedly resolve aliases and add stripped path components until done. */
    for(;;) {
        
        /* Resolve any aliases. */
        /* TODO: Verify that we don't need to repeatedly call FSResolveAliasFile(). We're passing TRUE for resolveAliasChains, which suggests that the call will continue resolving aliases until it reaches a non-alias, but that parameter's meaning is not actually documented in the Apple File Manager API docs. However, I can't seem to get the finder to *create* an alias to an alias in the first place, so this probably isn't much of a problem.
        (Why not simply call FSResolveAliasFile() repeatedly since I don't know if it's necessary? Because it can be a fairly time-consuming call if the volume is e.g. a remote WebDAVFS volume.) */
        err = FSResolveAliasFile(&ref, TRUE, &isFolder, &wasAliased);
        /* if it's a regular file and not an alias, FSResolveAliasFile() will return noErr and set wasAliased to false */
        if (err != noErr)
            return nil;

        /* Append one stripped path component. */
        if ([strippedComponents count] > 0) {
            UniChar *componentName;
            UniCharCount componentNameLength;
            NSString *nextComponent;
            FSRef newRef;
            
            if (!isFolder) {
                // Whoa --- we've arrived at a non-folder. Can't continue.
                // (A volume root is considered a folder, as you'd expect.)
                return nil;
            }
            
            nextComponent = [strippedComponents lastObject];
            componentNameLength = [nextComponent length];
            componentName = malloc(componentNameLength * sizeof(*componentName));
            OBASSERT(sizeof(UniChar) == sizeof(unichar));
            [nextComponent getCharacters:componentName];
            bzero(&newRef, sizeof(newRef));
            err = FSMakeFSRefUnicode(&ref, componentNameLength, componentName, kTextEncodingUnknown, &newRef);
            free(componentName);

            if (err == fnfErr) {
                /* The current ref is a directory, but it doesn't contain anything with the name of the next component. Quit walking the filesystem and append the unresolved components to the name of the directory. */
                break;
            } else if (err != noErr) {
                /* Some other error. Give up. */
                return nil;
            }

            bcopy(&newRef, &ref, sizeof(ref));
            [strippedComponents removeLastObject];
        } else {
            /* If we don't have any path components to re-resolve, we're done. */
            break;
        }
    }

    if (FSCompareFSRefs(&originalRefOfPath, &ref) != noErr) {
        /* Convert our FSRef back into a path. */
        /* PATH_MAX*4 is a generous guess as to the largest path we can expect. CoreFoundation appears to just use PATH_MAX, so I'm pretty confident this is big enough. */
        buffer = malloc(bufferSize = (PATH_MAX * 4));
        err = FSRefMakePath(&ref, (unsigned char *)buffer, bufferSize);
        if (err == noErr) {
            path = [NSString stringWithUTF8String:buffer];
        } else {
            path = nil;
        }
        free(buffer);
    }

    /* Append any unresolvable path components to the resolved directory. */
    while ([strippedComponents count] > 0) {
        path = [path stringByAppendingPathComponent:[strippedComponents lastObject]];
        [strippedComponents removeLastObject];
    }

    return path;
}

- (BOOL)fileIsStationeryPad:(NSString *)filename;
{
    const char *posixPath;
    FSRef myFSRef;
    FSCatalogInfo catalogInfo;
    
    posixPath = [filename fileSystemRepresentation];
    if (posixPath == NULL)
        return NO; // Protect FSPathMakeRef() from crashing
    if (FSPathMakeRef((UInt8 *)posixPath, &myFSRef, NULL))
        return NO;
    if (FSGetCatalogInfo(&myFSRef, kFSCatInfoFinderInfo, &catalogInfo, NULL, NULL, NULL) != noErr)
        return NO;
    return (((FileInfo *)(&catalogInfo.finderInfo))->finderFlags & kIsStationery) != 0;
}

- (BOOL)path:(NSString *)otherPath isAncestorOfPath:(NSString *)thisPath relativePath:(NSString **)relativeResult
{
    NSArray *myContinuation = nil;
    NSArray *parentContinuation = nil;
    NSArray *commonComponents = OFCommonRootPathComponents(thisPath, otherPath, &myContinuation, &parentContinuation);
    
    if (commonComponents != nil && [parentContinuation count] == 0) {
        if (relativeResult)
            *relativeResult = [NSString pathWithComponents:myContinuation];
        return YES;
    }
    
    NSString *lastParentComponent = [otherPath lastPathComponent];
    NSDictionary *lastParentComponentStat = nil;
    NSArray *myComponents = [thisPath pathComponents];
    NSUInteger componentIndex, componentCount = [myComponents count];
    
    componentIndex = componentCount;
    while (componentIndex--) {
        if ([lastParentComponent caseInsensitiveCompare:[myComponents objectAtIndex:componentIndex]] == NSOrderedSame) {
            if (lastParentComponentStat == nil) {
                lastParentComponentStat = [self attributesOfItemAtPath:otherPath traverseLink:YES error:NULL];
                if (!lastParentComponentStat) {
                    // Can't stat the putative parent --- so there's no way we're a subdirectory of it.
                    return NO;
                }
            }
            
            NSString *thisPartialPath = [NSString pathWithComponents:[myComponents subarrayWithRange:(NSRange){0, componentIndex+1}]];
            NSDictionary *thisPartialPathStat = [self attributesOfItemAtPath:thisPartialPath traverseLink:YES error:NULL];
            // Compare the file stats. In particular, we're comparing the filesystem number and inode number: we're checking to see if they're the same file.
            if ([lastParentComponentStat isEqual:thisPartialPathStat]) {
                if (relativeResult) {
                    *relativeResult = (componentIndex == componentCount-1 && [[lastParentComponentStat fileType] isEqualToString:NSFileTypeDirectory]) ? @"." : [NSString pathWithComponents:[myComponents subarrayWithRange:(NSRange){componentIndex+1, componentCount-componentIndex-1}]]; 
                }
                return YES;
            }
        }
    }
    
    return NO;
}

- (BOOL)setQuarantineProperties:(NSDictionary *)quarantineDictionary forItemAtPath:(NSString *)path error:(NSError **)outError;
{
    FSRef carbonRef;
    OSStatus err;
    
    bzero(&carbonRef, sizeof(carbonRef));
    err = FSPathMakeRef((void *)[self fileSystemRepresentationWithPath:path], &carbonRef, NULL);
    if (err != noErr)
        goto errorReturn;
    
    err = LSSetItemAttribute(&carbonRef, kLSRolesAll, kLSItemQuarantineProperties, quarantineDictionary);
    if (err != noErr)
        goto errorReturn;
    
    return YES;
    
errorReturn:
    if (outError) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:[NSDictionary dictionaryWithObjectsAndKeys:path, NSFilePathErrorKey, quarantineDictionary, kLSItemQuarantineProperties, nil]];
    }
    return NO;
}

- (NSDictionary *)quarantinePropertiesForItemAtPath:(NSString *)path error:(NSError **)outError;
{
    FSRef carbonRef;
    OSStatus err;
    
    bzero(&carbonRef, sizeof(carbonRef));
    err = FSPathMakeRef((void *)[self fileSystemRepresentationWithPath:path], &carbonRef, NULL);
    if (err != noErr)
        goto errorReturn;
    
    CFTypeRef quarantineDictionary = NULL;
    err = LSCopyItemAttribute(&carbonRef, kLSRolesAll, kLSItemQuarantineProperties, &quarantineDictionary);
    if (err != noErr)
        goto errorReturn;
    if (!quarantineDictionary) {
        // This doesn't appear to happen in practice (we get kLSAttributeNotFoundErr instead), but just to be safe...
        err = kLSAttributeNotFoundErr;
        goto errorReturn;
    }
    if (CFGetTypeID(quarantineDictionary) != CFDictionaryGetTypeID()) {
        CFRelease(quarantineDictionary);
        err = kLSUnknownErr;
        goto errorReturn;
    }
    
    return [NSMakeCollectable(quarantineDictionary) autorelease];
    
errorReturn:
    if (outError) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:[NSDictionary dictionaryWithObjectsAndKeys:path, NSFilePathErrorKey, nil]];
    }
    return nil;
}

#pragma mark Code signing

- (BOOL)getSandboxed:(out BOOL *)outSandboxed forApplicationAtURL:(NSURL *)applicationURL error:(NSError **)error;
{
    OBPRECONDITION(outSandboxed != NULL);
    if (error != NULL) {
        *error = nil;
    }
    
    // Test for sandbox entitlement
    // If we can't tell, then we will assume we're sandboxed
    const BOOL uncertainResult = YES;
    SecStaticCodeRef applicationCode = NULL;
    OSStatus status = noErr;
    
    status = SecStaticCodeCreateWithPath((CFURLRef)applicationURL, kSecCSDefaultFlags, &applicationCode);
    if (status != noErr) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        return NO;
    }
    
    OBASSERT(applicationCode != NULL);
    if (applicationCode == NULL) {
        *outSandboxed = uncertainResult;
        return YES;
    }
    
    // The Code Signing Language Requirement documentation says:
    //
    //    The existence operator tests whether the value exists. It evaluates to
    //    false only if the value does not exist at all or is exactly the Boolean
    //    value false. An empty string and the number 0 are considered to exist.
    //
    // Testing `entitlement["com.apple.security.app-sandbox"] exists` will
    // therefore evaluate to TRUE for sandboxed applications, and FALSE when the
    // sandbox entitlement is missing or false. Malformed code signing
    // entitlements (non-boolean value for the sandbox entitlement) may produce
    // an unexpected result.
    
    SecRequirementRef sandboxRequirement = NULL;
    status = SecRequirementCreateWithString(CFSTR("entitlement[\"com.apple.security.app-sandbox\"] exists"), kSecCSDefaultFlags, &sandboxRequirement);
    if (status != noErr) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        return NO;
    }
    
    OBASSERT(sandboxRequirement != NULL);
    if (sandboxRequirement == NULL) {
        *outSandboxed = uncertainResult;
        return YES;
    }
    
    OSStatus sandboxStatus = SecStaticCodeCheckValidity(applicationCode, kSecCSDefaultFlags, sandboxRequirement);
    switch (sandboxStatus) {
        case errSecSuccess: {
            *outSandboxed = YES;
            break;
        }
            
        case errSecCSUnsigned: { // We're unsigned
        case errSecCSReqFailed:  // Our signature doesn't have the sandbox requirement
        case errSecCSSignatureFailed: // Invalid signature (code or signature have been modified)
        case errSecCSBadResource: // A sealed resource is missing or invalid
            *outSandboxed = NO;
            break;
        }
            
        default: {
            OBASSERT_NOT_REACHED("-getSandboxed:forApplicationAtURL:error: encountered an unexpected return code from SecCodeCheckValidity()");
#ifdef DEBUG
            NSLog(@"_isCurrentProcessSandboxed() should explicitly handle the %@ return code from SecCodeCheckValidity()", OFOSStatusDescription(sandboxStatus));
#endif
            *outSandboxed = uncertainResult;
            break;
        }
    }
    
    CFRelease(applicationCode);
    CFRelease(sandboxRequirement);

    return YES; // return value indicates success/failure
}

- (NSDictionary *)codeSigningInfoDictionaryForURL:(NSURL *)url error:(NSError **)error;
{
    OSStatus status = noErr;
    SecStaticCodeRef codeRef = NULL;
    
    status = SecStaticCodeCreateWithPath((CFURLRef)url, kSecCSDefaultFlags, &codeRef);
    if (status != noErr) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        return nil;
    }
    
    SecCSFlags flags = ( // REVIEW: Which flags should we pass by default? Incorporate into exposed API?
        kSecCSInternalInformation |
        kSecCSSigningInformation |
        kSecCSRequirementInformation |
        kSecCSDynamicInformation |
        kSecCSContentInformation
    );
    
    CFDictionaryRef information = NULL;
    status = SecCodeCopySigningInformation(codeRef, flags, &information);
    if (status != noErr) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        CFRelease(codeRef);
        return nil;
    }
    
    NSDictionary *codeSigningDictionary = [NSDictionary dictionaryWithDictionary:(NSDictionary *)information];
    
    CFRelease(codeRef);
    CFRelease(information);
    
    return codeSigningDictionary;
}

- (NSDictionary *)codeSigningEntitlementsForURL:(NSURL *)signedURL error:(NSError **)error;
{
    NSDictionary *codeSigningInfoDictionary = [self codeSigningInfoDictionaryForURL:signedURL error:error];
    if (codeSigningInfoDictionary == nil) {
        return nil;
    }

    // N.B. kSecCodeInfoEntitlementsDict is not available on 10.7, but is not annotated as such
    // rdar://problem/11799071

    NSString *ENTITLEMENTS_DICT_KEY = @"entitlements-dict";
    NSDictionary *entitlements = [codeSigningInfoDictionary objectForKey:ENTITLEMENTS_DICT_KEY];
    if (entitlements != nil) {
        return entitlements;
    }

    NSData *entitlementsData = [codeSigningInfoDictionary objectForKey:(id)kSecCodeInfoEntitlements];
    if (entitlementsData != nil) {
        // On Mac OS X 10.7, the entitlements data appears to be a prefixed plist XML blob.
        // Interpret it, if we can...
        
        const char expectedSignature[] = {0xFA, 0xDE, 0x71, 0x71};
        const NSUInteger signatureLength = sizeof(expectedSignature);
        const NSUInteger headerLength = signatureLength + 4; // 4 skip bytes
        if ([entitlementsData length] > headerLength) {
            if (0 == memcmp(expectedSignature, [entitlementsData bytes], signatureLength)) {
                NSData *plistData = [entitlementsData subdataWithRange:NSMakeRange(headerLength, [entitlementsData length] - headerLength)];
                NSError *localError = nil;
                id plist = [NSPropertyListSerialization propertyListWithData:plistData options:NSPropertyListImmutable format:NULL error:&localError];
                if (plist != nil && [plist isKindOfClass:[NSDictionary class]]) {
                    return plist;
                }
            }
        }
        
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPropertyListReadCorruptError userInfo:nil];
        }
        return nil;
    }

    // Return an empty dictionary to indicate no entitlements, but success
    return [NSDictionary dictionary];
}

@end

@implementation NSFileManager (OFPrivate)

- (int)filesystemStats:(struct statfs *)stats forPath:(NSString *)path;
{
    const char *posixPath = [self fileSystemRepresentationWithPath:path];
    
    struct stat filestat;
    bzero(&filestat, sizeof(filestat));
    if (lstat(posixPath, &filestat) == 0 && S_ISLNK(filestat.st_mode))
        // BUG: statfs() will return stats on the file we link to, not the link itself.  We want stats on the link itself, but there is no lstatfs().  As a mostly-correct hackaround, I get the stats on the link's parent directory. This will fail if you NFS-mount a link as the source from a remote machine -- it'll report that the link isn't network mounted, because its local parent dir isn't.  Hopefully, this isn't real common.
        return statfs([self fileSystemRepresentationWithPath:[path stringByDeletingLastPathComponent]], stats);
    else
        return statfs(posixPath, stats);
}

- (NSString *)lockFilePathForPath:(NSString *)path;
{
    return [[path stringByStandardizingPath] stringByAppendingString:@".lock"];
    // This could be a problem if the resulting filename is too long for the filesystem. Alternatively, we could create a lock filename as a fixed-length hash of the real filename.
}

@end
