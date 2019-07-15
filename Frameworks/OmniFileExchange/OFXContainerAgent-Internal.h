// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXContainerAgent.h"

@class OFXFileItem;

@interface OFXContainerAgent ()

- (NSString *)_localRelativePathForFileURL:(NSURL *)fileURL;
- (NSURL *)_URLForLocalRelativePath:(NSString *)relativePath isDirectory:(BOOL)isDirectory;
- (void)_fileItem:(OFXFileItem *)fileItem didGenerateConflictAtURL:(NSURL *)conflictURL coordinator:(NSFileCoordinator *)coordinator;
- (void)_fileItemDidDetectUnknownRemoteEdit:(OFXFileItem *)fileItem;
- (BOOL)_relocateFileAtURL:(NSURL *)fileURL toMakeWayForFileItem:(OFXFileItem *)fileItem coordinator:(NSFileCoordinator *)coordinator error:(NSError **)outError;

- (void)_fileItemNeedsMetadataUpdated:(OFXFileItem *)fileItem;
- (void)_publishMetadataUpdates;

@end
