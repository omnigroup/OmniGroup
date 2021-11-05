// Copyright 1997-2021 Omni Development, Inc. All rights reserved.
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

#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSBundle-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSProcessInfo-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSString-OFPathExtensions.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/OFUtilities.h>

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
static mode_t permissionsMask = 0022;

OBDidLoad(^{
    scratchDirectoryPath = nil;
    scratchDirectoryLock = [[NSLock alloc] init];

    permissionsMask = umask(permissionsMask);
    umask(permissionsMask); // Restore the original value
});

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
    
    [self createDirectoryAtPath:defaultsScratchDirectoryPath withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @(0700 | S_ISVTX)} error:NULL];

#if MAC_APP_STORE_RETAIL_DEMO
    // Retail demos clear and reuse the same scratch directory every time
    workingScratchDirectoryPath = defaultsScratchDirectoryPath;
    [self removeItemAtPath:workingScratchDirectoryPath error:NULL];
#else
    workingScratchDirectoryPath = [defaultsScratchDirectoryPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@-######", [[NSProcessInfo processInfo] processName], NSUserName()]];
    workingScratchDirectoryPath = [self tempFilenameFromHashesTemplate:workingScratchDirectoryPath];
#endif

    BOOL success = [self createDirectoryAtPath:workingScratchDirectoryPath withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions: @(0700)} error:NULL];
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
    
    if (![data writeToFile:lockFilePath options:NSDataWritingAtomic error:outError]) {
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

- (NSURL *)trashDirectoryURLForURL:(NSURL *)fileURL error:(NSError **)outError;
{
    OBPRECONDITION([fileURL isFileURL]);
    
    // This will return ~/.Trash for something in the user's home directory, or /Volume/.Trashes/$UID for something on another disk. But, if the user doesn't have permission to create the trash directory (read-only filesystem/directory), this might return nil.
    // This also works if the file is already in the trash.
    return [self URLForDirectory:NSTrashDirectory inDomain:NSAllDomainsMask appropriateForURL:fileURL create:YES error:outError];
}

- (BOOL)isFileInTrashAtURL:(NSURL *)fileURL;
{
    // Check the Trash that should be used for this specific file.
    NSURL *trashDirectoryURL = [[NSFileManager defaultManager] trashDirectoryURLForURL:fileURL error:NULL]; // Might be nil if this is a read-only volume
    if (trashDirectoryURL)
        return OFURLContainsURL(trashDirectoryURL, fileURL);

    OBASSERT([[fileURL pathComponents] containsObject:@".Trash"] == NO, "User directories have '.Trash', but we should have handled this already");

    // As a fallback, check all the trashes. NSTrashDirectory/NSAllDomainsMask doesn't cover all the cases since it won't report the trashes on other volumes (like encrypted disk images).
    NSArray *trashURLs = [[NSFileManager defaultManager] URLsForDirectory:NSTrashDirectory inDomains:NSAllDomainsMask];
    for (NSURL *trashURL in trashURLs) {
        if (OFURLContainsURL(trashURL, fileURL))
            return YES;
    }
    OBASSERT([[fileURL pathComponents] containsObject:@".Trashes"] == NO, "Volumes use '.Trashes', but we should have handled this already");
    
    return NO;
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

- (NSString *)resolveAliasAtPath:(NSString *)path
{
    // <bug:///89013> (Rewrite alias resolution methods in OmniFoundation using NSURL/CFURL support)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    FSRef ref;
    OSErr err;
    OSStatus serr;
    char *buffer;
    UInt32 bufferSize;
    Boolean isFolder, wasAliased;

    if ([NSString isEmptyString:path])
        return nil;
    
    serr = FSPathMakeRef((const unsigned char *)[path fileSystemRepresentation], &ref, NULL);
    if (serr != noErr)
        return nil;

    err = FSResolveAliasFile(&ref, TRUE, &isFolder, &wasAliased);
    /* if it's a regular file and not an alias, FSResolveAliasFile() will return noErr and set wasAliased to false */
    if (err != noErr)
        return nil;
    if (!wasAliased)
        return path;

    buffer = malloc(bufferSize = (PATH_MAX * 4));
    serr = FSRefMakePath(&ref, (unsigned char *)buffer, bufferSize);
    if (serr == noErr) {
        path = [NSString stringWithUTF8String:buffer];
    } else {
        path = nil;
    }
    free(buffer);

    return path;
#pragma clang diagnostic pop
}

- (NSString *)resolveAliasesInPath:(NSString *)originalPath
{
    // <bug:///89013> (Rewrite alias resolution methods in OmniFoundation using NSURL/CFURL support)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    FSRef ref, originalRefOfPath;
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
        OSStatus err = FSPathMakeRef((const unsigned char *)[path fileSystemRepresentation], &ref, &isFolder);
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
        OSErr err = FSResolveAliasFile(&ref, TRUE, &isFolder, &wasAliased);
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
        OSStatus err = FSRefMakePath(&ref, (unsigned char *)buffer, bufferSize);
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
#pragma clang diagnostic pop
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
    return [self setQuarantineProperties:quarantineDictionary forItemAtURL:[NSURL fileURLWithPath:path] error:outError];
}

- (NSDictionary *)quarantinePropertiesForItemAtPath:(NSString *)path error:(NSError **)outError;
{
    return [self quarantinePropertiesForItemAtURL:[NSURL fileURLWithPath:path] error:outError];
}

- (BOOL)setQuarantineProperties:(NSDictionary *)quarantineDictionary forItemAtURL:(NSURL *)url error:(NSError **)outError;
{
    // As of 10.10.5, LaunchServices looks at the following dictionary keys:
    //  "LSQuarantineEventIdentifier"
    //  kLSQuarantineTimeStampKey
    //  kLSQuarantineAgentBundleIdentifierKey
    //  kLSQuarantineAgentNameKey
    //  "LSQuarantineDataURLString"
    //  "LSQuarantineSenderName"
    //  "LSQuarantineSenderAddress"
    //  "LSQuarantineTypeNumber"
    //  "LSQuarantineOriginTitle"
    //  "LSQuarantineOriginURLString"
    //  "LSQuarantineOriginAlias"
    
    // The following keys are set automatically if not passed in:
    //  kLSQuarantineAgentNameKey -> NSString
    //  kLSQuarantineAgentBundleIdentifierKey -> NSString
    //  kLSQuarantineTimeStampKey -> NSDate
    //  "LSQuarantineDataURLString" -> stringified value of kLSQuarantineDataURLKey
    //  "LSQuarantineTypeNumber"  -> derived from kLSQuarantineTypeKey
    //  kLSQuarantineOriginURLKey -> converted to a CFURL from string if needed; populated from kLSQuarantineOriginURLKey and/or LSQuarantineOriginAlias
    //  "LSQuarantineEventIdentifier" -> a new CFUUID
    //

    return [url setResourceValue:quarantineDictionary forKey:NSURLQuarantinePropertiesKey error:outError];
}

- (NSDictionary *)quarantinePropertiesForItemAtURL:(NSURL *)url error:(NSError **)outError;
{
    id __nullable __autoreleasing value = NULL;
    if (![url getResourceValue:&value forKey:NSURLQuarantinePropertiesKey error:outError])
        return nil;
    
    // Nil is a valid result, meaning it successfully determined that the property isn't there.
    if (!value) {
        if (outError)
            *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOATTR userInfo:@{ NSURLErrorKey: url, @"property": NSURLQuarantinePropertiesKey }];
        return nil;
    }
    
    return value;
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
    
    OSStatus status = SecStaticCodeCreateWithPath((__bridge CFURLRef)applicationURL, kSecCSDefaultFlags, &applicationCode);
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
    
#ifdef DEBUG_kc0
    if (error != NULL)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil];
    return NO;
#endif
    
    OSStatus sandboxStatus = SecStaticCodeCheckValidity(applicationCode, kSecCSNoNetworkAccess, sandboxRequirement);
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
    
    status = SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags, &codeRef);
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
    
    NSDictionary *codeSigningDictionary = [NSDictionary dictionaryWithDictionary:(__bridge NSDictionary *)information];
    
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
