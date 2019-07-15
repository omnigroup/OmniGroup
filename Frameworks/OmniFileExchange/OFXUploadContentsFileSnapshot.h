// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshot.h"

/*
 Contains metadata about a version of a document, plus a temporary copy of the document to be uploaded.
 */

@class OFSFileManager;

@interface OFXUploadContentsFileSnapshot : OFXFileSnapshot

- (instancetype)initWithTargetLocalSnapshotURL:(NSURL *)localTargetURL forUploadingVersionOfDocumentAtURL:(NSURL *)localDocumentURL localRelativePath:(NSString *)localRelativePath previousSnapshot:(OFXFileSnapshot *)previousSnapshot error:(NSError **)outError;

// Helpers for transfers
- (BOOL)iterateFiles:(NSError **)outError withApplier:(BOOL (^)(NSURL *fileURL, NSString *hash, NSError **outError))applier;
- (void)removeTemporaryCopyOfDocument;

@property(nonatomic,copy) NSString *debugName;

@end
