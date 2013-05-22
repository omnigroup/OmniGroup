// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

/*
 A record of the state of a version of a document.
 */

@class OFSFileManager, OFSDAVFileManager, OFSFileInfo;
@class OFXFileState;

@interface OFXFileSnapshot : NSObject

- initWithExistingLocalSnapshotURL:(NSURL *)localSnapshotURL error:(NSError **)outError;
- initWithTargetLocalSnapshotURL:(NSURL *)localTargetURL forNewLocalDocumentAtURL:(NSURL *)localDocumentURL localRelativePath:(NSString *)localRelativePath error:(NSError **)outError;

@property(nonatomic,readonly) NSURL *localSnapshotURL;
@property(nonatomic,readonly) NSDictionary *infoDictionary;
@property(nonatomic,readonly) NSDictionary *versionDictionary;
@property(nonatomic,readonly) NSString *localRelativePath;
@property(nonatomic,readonly) OFXFileState *localState;
@property(nonatomic,readonly) OFXFileState *remoteState;

@property(nonatomic,readonly,getter=isDirectory) BOOL directory;
@property(nonatomic,readonly,getter=isSymbolicLink) BOOL symbolicLink;
@property(nonatomic,readonly) unsigned long long totalSize;
@property(nonatomic,readonly) NSDate *userCreationDate;
@property(nonatomic,readonly) NSDate *userModificationDate;

@property(nonatomic,readonly) NSUInteger version;
@property(nonatomic,readonly) NSNumber *inode;

- (NSNumber *)hasSameContentsAsLocalDocumentAtURL:(NSURL *)localDocumentURL coordinator:(NSFileCoordinator *)coordinator withChanges:(BOOL)withChanges error:(NSError **)outError;
- (BOOL)hasSameContentsAsSnapshot:(OFXFileSnapshot *)otherSnapshot;
- (BOOL)markAsLocallyEdited:(NSError **)outError;
- (BOOL)markAsRemotelyEdited:(NSError **)outError;
- (BOOL)markAsLocallyDeleted:(NSError **)outError;
- (BOOL)markAsRemotelyDeleted:(NSError **)outError;
- (BOOL)markAsLocallyMovedToRelativePath:(NSString *)relativePath error:(NSError **)outError;
- (BOOL)didGiveUpLocalContents:(NSError **)outError;

- (BOOL)didPublishContentsToLocalDocumentURL:(NSURL *)localDocumentURL error:(NSError **)outError;
- (BOOL)didTakePublishedContentsFromSnapshot:(OFXFileSnapshot *)otherSnapshot error:(NSError **)outError;

- (void)didMoveToTargetLocalSnapshotURL:(NSURL *)targetLocalSnapshotURL;

// Helper for upload transfers
- (BOOL)finishedUploadingWithError:(NSError **)outError;

// Helper for debug logs
@property(nonatomic,readonly) NSString *currentContentIdentifier;

@end
