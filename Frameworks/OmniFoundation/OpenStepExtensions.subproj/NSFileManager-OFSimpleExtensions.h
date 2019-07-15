// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSFileManager.h>

@interface NSFileManager (OFSimpleExtensions)

- (NSDictionary *)attributesOfItemAtPath:(NSString *)filePath traverseLink:(BOOL)traverseLink error:(NSError **)outError;

// Directory manipulations

- (BOOL)directoryExistsAtPath:(NSString *)path;
- (BOOL)directoryExistsAtPath:(NSString *)path traverseLink:(BOOL)traverseLink;

/// Returns an array of names of children in the given path that have the given extension. The search here is shallow; files with the given extension nested within one or more folders inside the given path will not be matched.
- (NSArray <NSString *> *)directoryContentsAtPath:(NSString *)path havingExtension:(NSString *)extension error:(NSError **)outError;

- (BOOL)createPathToFile:(NSString *)path attributes:(NSDictionary *)attributes error:(NSError **)outError;
// Creates any directories needed to be able to create a file at the specified path.

// Creates any directories needed to be able to create a file at the specified path.  Returns NO on failure.
- (BOOL)createPathComponents:(NSArray *)components attributes:(NSDictionary *)attributes error:(NSError **)outError;

// Instead of deleting in place, this moves the URL to a temporary location and then deletes it. This really only matters for directories, but this method doesn't try to check if the URL is a directory (since that is a race condition and would be slower anyway).
- (BOOL)atomicallyRemoveItemAtURL:(NSURL *)url error:(NSError **)outError;

// Changing file access/update timestamps.
- (BOOL)touchItemAtURL:(NSURL *)url error:(NSError **)outError;

#ifdef DEBUG
- (void)logPropertiesOfTreeAtURL:(NSURL *)url;
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (BOOL)addExcludedFromBackupAttributeToItemAtURL:(NSURL *)url error:(NSError **)error;
- (BOOL)addExcludedFromBackupAttributeToItemAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)removeExcludedFromBackupAttributeToItemAtURL:(NSURL *)url error:(NSError **)error;
- (BOOL)removeExcludedFromBackupAttributeToItemAtPath:(NSString *)path error:(NSError **)error;
#endif

// Group containers

// baseIdentifier should be 'com.mycompany.whatever'. Appropriate modifications will be made to that base identifier based on platform and sandboxing.
- (NSString *)groupContainerIdentifierForBaseIdentifier:(NSString *)baseIdentifier;
- (NSURL *)containerURLForBaseGroupContainerIdentifier:(NSString *)baseIdentifier;

@end

