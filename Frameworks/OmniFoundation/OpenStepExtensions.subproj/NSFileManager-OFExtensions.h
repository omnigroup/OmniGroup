// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSFileManager.h>
#import <Foundation/NSRange.h> // For NSRange
#import <OmniBase/OBUtilities.h>

// Split out other extensions
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>

// For FSVolumeRefNum
#import <CoreServices/CoreServices.h>

@class NSNumber;

@interface NSFileManager (OFExtensions)

- (NSString *)desktopDirectory;
- (NSString *)documentDirectory;

// Scratch files

- (NSString *)scratchDirectoryPath;
- (NSString *)scratchFilenameNamed:(NSString *)aName error:(NSError **)outError;
- (void)removeScratchDirectory;

// Changing file access/update timestamps.

- (void)touchFile:(NSString *)filePath;

// Following symlinks

- (NSDictionary *)attributesOfItemAtPath:(NSString *)filePath traverseLink:(BOOL)traverseLink error:(NSError **)outError;

// Directory manipulations

- (BOOL)directoryExistsAtPath:(NSString *)path;
- (BOOL)directoryExistsAtPath:(NSString *)path traverseLink:(BOOL)traverseLink;

- (BOOL)createPathToFile:(NSString *)path attributes:(NSDictionary *)attributes error:(NSError **)outError;
    // Creates any directories needed to be able to create a file at the specified path.
- (BOOL)createPath:(NSString *)path attributes:(NSDictionary *)attributes error:(NSError **)outError OB_DEPRECATED_ATTRIBUTE; /* Replace with createDirectoryAtPath:withIntermediateDirectories:attributes:error: */

    // Creates any directories needed to be able to create a file at the specified path.  Returns NO on failure.
- (BOOL)createPathComponents:(NSArray *)components attributes:(NSDictionary *)attributes error:(NSError **)outError;

- (NSString *)existingPortionOfPath:(NSString *)path;

- (BOOL)atomicallyCreateFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary *)attr;

- (NSArray *) directoryContentsAtPath: (NSString *) path havingExtension: (NSString *) extension  error:(NSError **)outError;

- (BOOL)setQuarantineProperties:(NSDictionary *)quarantineDictionary forItemAtPath:(NSString *)path error:(NSError **)outError;
- (NSDictionary *)quarantinePropertiesForItemAtPath:(NSString *)path error:(NSError **)outError; // Implement if needed.

// File locking
// Note: these are *not* industrial-strength robust file locks, but will do for occasional use.

- (NSDictionary *)lockFileAtPath:(NSString *)path overridingExistingLock:(BOOL)override created:(BOOL *)outCreated error:(NSError **)outError;
- (void)unlockFileAtPath:(NSString *)path;

- (BOOL)replaceFileAtPath:(NSString *)originalFile withFileAtPath:(NSString *)newFile error:(NSError **)outError;
- (BOOL)exchangeFileAtPath:(NSString *)originalFile withFileAtPath:(NSString *)newFile error:(NSError **)outError;

//

- (NSNumber *)posixPermissionsForMode:(unsigned int)mode;
- (NSNumber *)defaultFilePermissions;
- (NSNumber *)defaultDirectoryPermissions;

- (BOOL)isFileAtPath:(NSString *)path enclosedByFolderOfType:(OSType)folderType;

- (NSString *)networkMountPointForPath:(NSString *)path returnMountSource:(NSString **)mountSource;
- (NSString *)fileSystemTypeForPath:(NSString *)path;

- (FSVolumeRefNum)volumeRefNumForPath:(NSString *)path error:(NSError **)outError;
    // Returns the Carbon volume ref num for a POSIX path. Returns kFSInvalidVolumeRefNum (and optionally fills *outError) on failure.

- (NSString *)volumeNameForPath:(NSString *)filePath error:(NSError **)outError;
    // Returns Carbon's textual name for the volume on which a file resides. Returns nil on failure.

- (NSString *)resolveAliasAtPath:(NSString *)path;
    // Returns the original path if it isn't an alias, or the path pointed to by the alias (paths are all in POSIX form). Returns nil if an error occurs, such as not being able to resolve the alias. Note that this will not resolve aliases in the middle of the path (e.g. if /foo/bar is an alias to a directory, resolving /foo/bar/baz will fail and return nil).

- (NSString *)resolveAliasesInPath:(NSString *)path;
   // As -resolveAliasAtPath:, but will resolve aliases in the middle of the path as well, returning a path that can be used by POSIX APIs. Unlike -resolveAliasAtPath:, this can return non-nil for nonexistent paths: if the path can be resolved up to a directory which does not contain the next component, it will do so. As a side effect, -resolveAliasesInPath: will often resolve symlinks as well, but this should not be relied upon. Note that resolving aliases can incur some time-consuming operations such as mounting volumes, which can cause the user to be prompted for a password or to insert a disk, etc.

- (BOOL)fileIsStationeryPad:(NSString *)path;

   // Checks whether one path is a subdirectory of another, optionally returning the relative path (a suffix of thisPath). Consults the filesystem in an attempt to discover commonalities due to symlinks and file mounts. (Does not handle aliases, particularly.)
- (BOOL)path:(NSString *)otherPath isAncestorOfPath:(NSString *)thisPath relativePath:(NSString **)relativeResult;

@end

#import <OmniBase/macros.h>
OBDEPRECATED_METHODS(NSFileManagerHandler)
- (BOOL)fileManager:(NSFileManager *)fm shouldProceedAfterError:(NSDictionary *)errorInfo;
- (void)fileManager:(NSFileManager *)fm willProcessPath:(NSString *)path;
@end
