// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>

#import <OmniFoundation/NSDictionary-OFExtensions.h>

#import <sys/stat.h> // For statbuf, stat, mkdir

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <sys/xattr.h>
#else
#import <OmniFoundation/NSFileManager-OFExtensions.h> // We use a few of the not-shared bit in this case
#import <OmniFoundation/NSProcessInfo-OFExtensions.h>
#endif

RCS_ID("$Id$")

@implementation NSFileManager (OFSimpleExtensions)

- (NSDictionary *)attributesOfItemAtPath:(NSString *)filePath traverseLink:(BOOL)traverseLink error:(NSError **)outError
{
#ifdef MAXSYMLINKS
    int links_followed = 0;
#endif
    
    for(;;) {
        NSDictionary *attributes = [self attributesOfItemAtPath:filePath error:outError];
        if (!attributes) // Error return
            return nil;
        
        if (traverseLink && [[attributes fileType] isEqualToString:NSFileTypeSymbolicLink]) {
#ifdef MAXSYMLINKS
            BOOL linkCountOK = (links_followed++ < MAXSYMLINKS);
            if (!linkCountOK) {
                if (outError)
                    *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:ELOOP userInfo:[NSDictionary dictionaryWithObject:filePath forKey:NSFilePathErrorKey]];
                return nil;
            }
#endif
            NSString *dest = [self destinationOfSymbolicLinkAtPath:filePath error:outError];
            if (!dest)
                return nil;
            if ([dest isAbsolutePath])
                filePath = dest;
            else
                filePath = [[filePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:dest];
            continue;
        }
        
        return attributes;
    }
}

- (BOOL)directoryExistsAtPath:(NSString *)path traverseLink:(BOOL)traverseLink;
{
    NSDictionary *attributes = [self attributesOfItemAtPath:path traverseLink:traverseLink error:NULL];
    return attributes && [[attributes fileType] isEqualToString:NSFileTypeDirectory];
}                                                                                 

- (BOOL)directoryExistsAtPath:(NSString *)path;
{
    return [self directoryExistsAtPath:path traverseLink:NO];
}

- (NSArray <NSString *> *)directoryContentsAtPath:(NSString *)path havingExtension:(NSString *)extension  error:(NSError **)outError;
{
    NSArray <NSString *> *children;
    NSError *error = nil;
    if (!(children = [self contentsOfDirectoryAtPath:path error:&error])) {
        if (outError)
            *outError = error;
        // Return nil in exactly the cases that -directoryContentsAtPath: does (rather than returning an empty array).
        return nil;
    }

    return [children pathsMatchingExtensions:@[extension]];
}

- (BOOL)createPathToFile:(NSString *)path attributes:(NSDictionary *)attributes error:(NSError **)outError;
// Creates any directories needed to be able to create a file at the specified path.  Returns NO on failure.
{
    NSArray *pathComponents = [path pathComponents];
    NSUInteger componentCount = [pathComponents count];
    if (componentCount <= 1)
        return YES;
    
    return [self createPathComponents:[pathComponents subarrayWithRange:(NSRange){0, componentCount-1}] attributes:attributes error:outError];
}

- (BOOL)createPathComponents:(NSArray *)components attributes:(NSDictionary *)attributes error:(NSError **)outError;
{
    if ([attributes count] == 0)
        attributes = nil;
    
    NSUInteger dirCount = [components count];
    NSMutableArray *trimmedPaths = [[NSMutableArray alloc] initWithCapacity:dirCount];
    
    [trimmedPaths autorelease];
    
    NSString *finalPath = [NSString pathWithComponents:components];
    
    NSMutableArray *trim = [[NSMutableArray alloc] initWithArray:components];
    __autoreleasing NSError *error = nil;
    for (NSUInteger trimCount = 0; trimCount < dirCount && !error; trimCount ++) {
        struct stat statbuf;
        
        OBINVARIANT([trim count] == (dirCount - trimCount));
        NSString *trimmedPath = [NSString pathWithComponents:trim];
        const char *path = [trimmedPath fileSystemRepresentation];
        if (stat(path, &statbuf)) {
            int err = errno;
            if (err == ENOENT) {
                [trimmedPaths addObject:trimmedPath];
                [trim removeLastObject];
                // continue
            } else {
                OBErrorWithErrnoObjectsAndKeys(&error, err, "stat", trimmedPath,
                                               NSLocalizedStringFromTableInBundle(@"Could not create directory", @"OmniFoundation", OMNI_BUNDLE, @"Error message when stat() fails when trying to create a directory tree"),
                                               finalPath, NSFilePathErrorKey, nil);
                
            }
        } else if ((statbuf.st_mode & S_IFMT) != S_IFDIR) {
            OBErrorWithErrnoObjectsAndKeys(&error, ENOTDIR, "mkdir", trimmedPath,
                                           NSLocalizedStringFromTableInBundle(@"Could not create directory", @"OmniFoundation", OMNI_BUNDLE, @"Error message when mkdir() will fail because there's a file in the way"),
                                           finalPath, NSFilePathErrorKey, nil);
        } else {
            break;
        }
    }
    [trim release];
    
    if (error) {
        if (outError)
            *outError = error;
        return NO;
    }
    
    mode_t mode;
    mode = 0777; // umask typically does the right thing
    if (attributes && [attributes objectForKey:NSFilePosixPermissions]) {
        mode = (mode_t)[attributes unsignedIntForKey:NSFilePosixPermissions];
        if ([attributes count] == 1)
            attributes = nil;
    }
    
    while ([trimmedPaths count]) {
        NSString *pathString = [trimmedPaths lastObject];
        const char *path = [pathString fileSystemRepresentation];
        if (mkdir(path, mode) != 0) {
            int err = errno;
            OBErrorWithErrnoObjectsAndKeys(outError, err, "mkdir", pathString,
                                           NSLocalizedStringFromTableInBundle(@"Could not create directory", @"OmniFoundation", OMNI_BUNDLE, @"Error message when mkdir() fails"),
                                           finalPath, NSFilePathErrorKey, nil);
            return NO;
        }
        
        if (attributes)
            [self setAttributes:attributes ofItemAtPath:pathString error:NULL];
        
        [trimmedPaths removeLastObject];
    }
    
    return YES;
}

- (BOOL)atomicallyRemoveItemAtURL:(NSURL *)url error:(NSError **)outError;
{
    OBPRECONDITION([url isFileURL]);
    
    /*
     Docs on 10.8, "You can also use this method to create a new temporary directory for storing things like autosave files; to do so, specify NSItemReplacementDirectory for the directory parameter, NSUserDomainMask for the domain parameter, and a valid parent directory for the url parameter."

     This returns something like file://localhost/private/var/folders/xn/8lr83k7x77j2cyxhpmmk99jm0000gp/T/TemporaryItems/(A%20Document%20Being%20Saved%20By%20MyApp)/ on 10.8.
     */
    
    NSURL *temporaryParentURL = [self URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:[url URLByDeletingLastPathComponent] create:YES error:outError];
    if (!temporaryParentURL)
        return NO;
    
    // The call above returns the parent directory
    NSURL *temporaryURL = [temporaryParentURL URLByAppendingPathComponent:[url lastPathComponent]];
    
    if (![self moveItemAtURL:url toURL:temporaryURL error:outError])
        return NO;
    
    return [self removeItemAtURL:temporaryParentURL error:outError];
}

#pragma mark - Changing file access/update timestamps.

- (BOOL)touchItemAtURL:(NSURL *)url error:(NSError **)outError;
{
    NSDictionary *attributes = [[NSDictionary alloc] initWithObjectsAndKeys:[NSDate date], NSFileModificationDate, nil];
    BOOL rc = [self setAttributes:attributes ofItemAtPath:[[url absoluteURL] path] error:outError];
    [attributes release];
    return rc;
}

#pragma mark - Debugging

#ifdef DEBUG

static void _appendPermissions(NSMutableString *str, NSUInteger perms, NSUInteger readMask, NSUInteger writeMask, NSUInteger execMask)
{
    [str appendString:(perms & readMask) ? @"r" : @"-"];
    [str appendString:(perms & writeMask) ? @"w" : @"-"];
    [str appendString:(perms & execMask) ? @"x" : @"-"];
}

// This just does very, very basic file info for now, not setuid/inode/xattr or whatever.
static void _appendPropertiesOfTreeAtURL(NSFileManager *self, NSMutableString *str, NSURL *url, NSUInteger indent)
{
    NSError *error = nil;
    NSDictionary *attributes = [self attributesOfItemAtPath:[[url absoluteURL] path] error:&error];
    if (!attributes) {
        NSLog(@"Unable to get attributes of %@: %@", [url absoluteString], [error toPropertyList]);
        return;
    }
    
    OBASSERT(sizeof(ino_t) == sizeof(unsigned long long));
    [str appendFormat:@"%llu  ", [[attributes objectForKey:NSFileSystemFileNumber] unsignedLongLongValue]];
    
    BOOL isDirectory = NO;
    NSString *fileType = [attributes fileType];
    if ([fileType isEqualToString:NSFileTypeDirectory]) {
        isDirectory = YES;
        [str appendString:@"d"];
    } else if ([fileType isEqualToString:NSFileTypeSymbolicLink]) {
        [str appendString:@"l"];
    } else {
        OBASSERT([fileType isEqualToString:NSFileTypeRegular]); // could add more cases if ever needed
        [str appendString:@"-"];
    }
    
    NSUInteger perms = [attributes filePosixPermissions];
    _appendPermissions(str, perms, S_IRUSR, S_IWUSR, S_IXUSR);
    _appendPermissions(str, perms, S_IRGRP, S_IWGRP, S_IXGRP);
    _appendPermissions(str, perms, S_IROTH, S_IWOTH, S_IXOTH);
    
    for (NSUInteger level = 0; level < indent + 1; level++)
        [str appendString:@"  "];
    
    [str appendString:[url lastPathComponent]];
    
    if (isDirectory)
        [str appendString:@"/"];
    [str appendString:@"\n"];
    
    if (isDirectory) {
        error = nil;
        NSArray *children = [self contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsSubdirectoryDescendants error:&error];
        if (!children) {
            NSLog(@"Unable to get children of %@: %@", [url absoluteString], [error toPropertyList]);
            return;
        }
        
        for (NSURL *child in children) {
            _appendPropertiesOfTreeAtURL(self, str, child, indent + 1);
        }
    }
}

- (void)logPropertiesOfTreeAtURL:(NSURL *)url;
{
    NSMutableString *str = [[NSMutableString alloc] init];
    _appendPropertiesOfTreeAtURL(self, str, url, 0);
    
    NSLog(@"%@:\n%@\n", [url absoluteString], str);
    [str release];
}

#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (BOOL)addExcludedFromBackupAttributeToItemAtPath:(NSString *)path error:(NSError **)error;
{
    NSURL *url = [NSURL fileURLWithPath:path];
    return [self addExcludedFromBackupAttributeToItemAtURL:url error:error];
}

- (BOOL)addExcludedFromBackupAttributeToItemAtURL:(NSURL *)url error:(NSError **)error;
{
    BOOL result = [url setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsExcludedFromBackupKey error:error];
    return result;
}

- (BOOL)removeExcludedFromBackupAttributeToItemAtURL:(NSURL *)url error:(NSError **)error;
{
    NSDictionary *currentValues = [url resourceValuesForKeys:[NSArray arrayWithObject:NSURLIsExcludedFromBackupKey] error:NULL];
    BOOL result = YES;
    if ([((NSNumber *)currentValues[NSURLIsExcludedFromBackupKey]) boolValue] == YES) { // lets only attempt to unset this if it's actually set.
        result = [url setResourceValue:[NSNumber numberWithBool:NO] forKey:NSURLIsExcludedFromBackupKey error:error];
    }
    return result;
}

- (BOOL)removeExcludedFromBackupAttributeToItemAtPath:(NSString *)path error:(NSError **)error;
{
    NSURL *url = [NSURL fileURLWithPath:path];
    return [self removeExcludedFromBackupAttributeToItemAtURL:url error:error];
}

#endif

#pragma mark - Group Containers

- (NSString *)groupContainerIdentifierForBaseIdentifier:(NSString *)baseIdentifier;
{
    OBPRECONDITION(![NSString isEmptyString:baseIdentifier], "Must pass a base identifier");
    OBPRECONDITION([baseIdentifier hasPrefix:@"group."] == NO, "Don't pass in the iOS-style 'group.' prefix");
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // On the iOS, the entitlement and value passed to -containerURLForSecurityApplicationGroupIdentifier: are both 'group.identifier'
    return [@"group." stringByAppendingString:baseIdentifier];
#else
    // On the Mac, the entitlement is "TeamID.identifier". During development, we can grant ourselves any group container entitlement, but MAS would (or should) reject us if we didn't prefix with our Team ID.
    // Individual applications can have their own prefix, instead of using the team prefix. We don't do that currently -- we could possibly look at other entries in the code sign info dictionary to determine the right prefix.
    // Non-sandboxed apps will use a non-prefixed group container since we don't have a team id (meaning they will have different settings values than sandboxed apps, but the apps we care about are all going to be sandboxed) -- only internal apps will be unsandboxed.
    
    if ([[NSProcessInfo processInfo] isSandboxed]) {
        NSString *teamIdentifier = [[NSProcessInfo processInfo] codeSigningTeamIdentifier];
        assert(![NSString isEmptyString:teamIdentifier]); // Signal fatal error ASAP if our code signing entitlements are messed up.
        
        OBASSERT([baseIdentifier hasPrefix:teamIdentifier] == NO, "Don't pass in the Mac-style team/app-prefixed identifier");
        return [NSString stringWithFormat:@"%@.%@", teamIdentifier, baseIdentifier];
    }
    
    // Fall back to a group container without a team prefix if we are not sandboxed or couldn't find the team identifier (though in the latter case, this will only work if our entitlements specify the same identifier and we'll (likely) get rejected from MAS w/o the team identifier.
    return baseIdentifier;
#endif
}

- (NSURL *)containerURLForBaseGroupContainerIdentifier:(NSString *)baseIdentifier;
{
    NSString *groupContainerIdentifier = [self groupContainerIdentifierForBaseIdentifier:baseIdentifier];
    
    // We have no good way of checking these entitlements on iOS, but still need them.
#if (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE) && defined(OMNI_ASSERTIONS_ON)
    if ([[NSProcessInfo processInfo] isSandboxed]) {
        NSDictionary *entitlements = [[NSProcessInfo processInfo] codeSigningEntitlements];
        id value = [entitlements objectForKey:@"com.apple.security.application-groups"];
        if (value == nil)
            value = [NSArray array];
        NSArray *preferenceDomains = [value isKindOfClass:[NSArray class]] ? value : [NSArray arrayWithObject:value];
        assert([preferenceDomains containsObject:groupContainerIdentifier]);
    }
#endif
    
    NSURL *containerURL = [self containerURLForSecurityApplicationGroupIdentifier:groupContainerIdentifier];
    if (!containerURL) {
        if (!OFIsRunningUnitTests()) {
            OBASSERT_NOT_REACHED("Unable to determine shared container location for identifier \"%@\"", groupContainerIdentifier);
        }
        return nil;
    }
    
    // The group container will have been created by the system at this point if our entitlements are right. Double-check in debug builds.
#ifdef DEBUG
    __autoreleasing NSError *error = nil;
    if (![self createDirectoryAtURL:containerURL withIntermediateDirectories:NO attributes:nil error:&error]) {
        if ([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EEXIST]) {
            // Already there.
        } else {
            [error log:@"Unable to create %@", containerURL];
            return nil;
        }
    }
#endif
    
    return containerURL;
}

@end
