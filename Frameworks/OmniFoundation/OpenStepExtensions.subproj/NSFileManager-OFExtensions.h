// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSFileManager.h>
#import <Foundation/NSRange.h> // For NSRange
#import <OmniBase/OBUtilities.h>

// Split out other extensions
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>

@class NSNumber;

@interface NSFileManager (OFExtensions)

// Scratch files

- (NSString *)scratchDirectoryPath;
- (NSString *)scratchFilenameNamed:(NSString *)aName error:(NSError **)outError;
- (void)removeScratchDirectory;

// Directory manipulations

- (NSString *)existingPortionOfPath:(NSString *)path;

- (BOOL)atomicallyCreateFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary *)attr;

- (BOOL)setQuarantineProperties:(NSDictionary *)quarantineDictionary forItemAtPath:(NSString *)path error:(NSError **)outError OB_DEPRECATED_ATTRIBUTE;
- (NSDictionary *)quarantinePropertiesForItemAtPath:(NSString *)path error:(NSError **)outError OB_DEPRECATED_ATTRIBUTE;

- (BOOL)setQuarantineProperties:(NSDictionary *)quarantineDictionary forItemAtURL:(NSURL *)url error:(NSError **)outError;
- (NSDictionary *)quarantinePropertiesForItemAtURL:(NSURL *)url error:(NSError **)outError;

// File locking
// Note: these are *not* industrial-strength robust file locks, but will do for occasional use.

- (NSDictionary *)lockFileAtPath:(NSString *)path overridingExistingLock:(BOOL)override created:(BOOL *)outCreated error:(NSError **)outError;
- (void)unlockFileAtPath:(NSString *)path  DEPRECATED_MSG_ATTRIBUTE("-unlockFileAtPath: has been nonfunctional since 2008");

// Special directories
- (NSURL *)trashDirectoryURLForURL:(NSURL *)fileURL error:(NSError **)outError;
- (BOOL)isFileInTrashAtURL:(NSURL *)fileURL;

- (NSNumber *)posixPermissionsForMode:(unsigned int)mode;
- (NSNumber *)defaultFilePermissions;
- (NSNumber *)defaultDirectoryPermissions;

- (NSString *)networkMountPointForPath:(NSString *)path returnMountSource:(NSString **)mountSource;
- (NSString *)fileSystemTypeForPath:(NSString *)path;

- (NSString *)resolveAliasAtPath:(NSString *)path;
    // Returns the original path if it isn't an alias, or the path pointed to by the alias (paths are all in POSIX form). Returns nil if an error occurs, such as not being able to resolve the alias. Note that this will not resolve aliases in the middle of the path (e.g. if /foo/bar is an alias to a directory, resolving /foo/bar/baz will fail and return nil).

- (NSString *)resolveAliasesInPath:(NSString *)path;
   // As -resolveAliasAtPath:, but will resolve aliases in the middle of the path as well, returning a path that can be used by POSIX APIs. Unlike -resolveAliasAtPath:, this can return non-nil for nonexistent paths: if the path can be resolved up to a directory which does not contain the next component, it will do so. As a side effect, -resolveAliasesInPath: will often resolve symlinks as well, but this should not be relied upon. Note that resolving aliases can incur some time-consuming operations such as mounting volumes, which can cause the user to be prompted for a password or to insert a disk, etc.

   // Checks whether one path is a subdirectory of another, optionally returning the relative path (a suffix of thisPath). Consults the filesystem in an attempt to discover commonalities due to symlinks and file mounts. (Does not handle aliases, particularly.)
- (BOOL)path:(NSString *)otherPath isAncestorOfPath:(NSString *)thisPath relativePath:(NSString **)relativeResult;

// Code signing

- (BOOL)getSandboxed:(out BOOL *)outSandboxed forApplicationAtURL:(NSURL *)applicationURL error:(NSError **)error;
    // Works with bundled applications and standalone executables
    // N.B. You need to have read access to the application bundle or executable to determine sandboxedness.
    // As an implementation detail this appears to work for everything under /Applications for sandboxed applications on 10.7 and 10.8 but probably should not be relied upon.

- (NSDictionary *)codeSigningInfoDictionaryForURL:(NSURL *)signedURL error:(NSError **)error;
    // Various pieces of information extraced from the code signature for the bundle/executable at this URL
    // See Security/SecCode.h for the dictionary keys

- (NSDictionary *)codeSigningEntitlementsForURL:(NSURL *)signedURL error:(NSError **)error;
    // The extracted entitlements for the signed entity at the URL

@end
