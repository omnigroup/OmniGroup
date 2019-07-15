// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshot.h"

@class ODAVConnection;

@interface OFXDownloadFileSnapshot : OFXFileSnapshot

// Downloads the info about the snapshot from the server and writes it to a local snapshot, which is expected to be in a temporary location.
// This does not validate the format of the snapshot. It is expected that the caller will read this into a plain OFXFileSnapshot (from the temporary URL), whose initializers *will* validate the plists. Then, once it is validated, the caller should move the snapshot into permanent storage.
+ (BOOL)writeSnapshotToTemporaryURL:(NSURL *)temporaryLocalSnapshotURL byFetchingMetadataOfRemoteSnapshotAtURL:(NSURL *)remoteSnapshotURL fileIdentifier:(NSString **)outFileIdentifier connection:(ODAVConnection *)connection error:(NSError **)outError;

// Helpers for OFXFileSnapshotDownloadTransfer
- (BOOL)makeDownloadStructureAt:(NSURL *)temporaryDocumentURL didCreateDirectoryOrLink:(BOOL *)outDidCreateDirectoryOrLink error:(NSError **)outError withFileApplier:(void (^)(NSURL *fileURL, long long fileSize, NSString *hash))fileApplier;
- (BOOL)finishedDownloadingToURL:(NSURL *)temporaryDocumentURL error:(NSError **)outError;

@end
