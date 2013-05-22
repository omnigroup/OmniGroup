// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import "OFXFileState.h"

@class OFSDAVFileManager, OFXRegistrationTable, OFSFileInfo;
@class OFXContainerAgent, OFXFileSnapshotTransfer, OFXFileState;
@protocol NSFilePresenter;

/*
 Represents a single file that the sync system knows about. This will register as a file presenter for the local document.
 */

@interface OFXFileItem : NSObject <NSCopying>

- (id)initWithNewLocalDocumentURL:(NSURL *)localDocumentURL container:(OFXContainerAgent *)container error:(NSError **)outError;
- (id)initWithNewRemoteSnapshotAtURL:(NSURL *)remoteSnapshotURL container:(OFXContainerAgent *)container filePresenter:(id <NSFilePresenter>)filePresenter fileManager:(OFSDAVFileManager *)fileManager error:(NSError **)outError;
- (id)initWithExistingLocalSnapshotURL:(NSURL *)localSnapshotURL container:(OFXContainerAgent *)container filePresenter:(id <NSFilePresenter>)filePresenter error:(NSError **)outError;

- (void)invalidate;

@property(nonatomic,readonly,weak) OFXContainerAgent *container;

@property(nonatomic,readonly) NSString *identifier;
@property(nonatomic,readonly) NSUInteger version;

// If set to YES, another file item has the same localDocumentURL as this item. In this case, we cannot publish contents from the file and the file item will stop publishing metadata.
@property(nonatomic,getter=isShadowedByOtherFileItem) BOOL shadowedByOtherFileItem;

@property(nonatomic,readonly) NSURL *localDocumentURL;
@property(nonatomic,readonly) NSString *localRelativePath; // Not valid if the item is deleted.
@property(nonatomic,readonly) NSString *requestedLocalRelativePath; // Valid even if the item is deleted

@property(nonatomic,readonly) NSDate *userCreationDate;
@property(nonatomic,readonly) NSNumber *inode;
@property(nonatomic,readonly) BOOL hasBeenLocallyDeleted;

@property(nonatomic,readonly) BOOL isUploading;
@property(nonatomic,readonly) BOOL isUploadingContents;
@property(nonatomic,readonly) BOOL isUploadingRename;
@property(nonatomic,readonly) BOOL isDownloading;
@property(nonatomic,readonly) BOOL isDownloadingContent;
@property(nonatomic,readonly) BOOL isDeleting;

- (void)setContentsRequested; // Turns on a sticky flag for this run of the app that says downloads should get the contents too.
@property(nonatomic,readonly) BOOL contentsRequested;

@property(nonatomic,readonly) OFXFileState *localState;
@property(nonatomic,readonly) OFXFileState *remoteState;
- (BOOL)markAsLocallyEdited:(NSError **)outError;
- (BOOL)markAsRemotelyEditedWithNewestRemoteVersion:(NSUInteger)newestRemoteVersion error:(NSError **)outError;
- (BOOL)markAsLocallyDeleted:(NSError **)outError;
- (BOOL)markAsRemotelyDeleted:(NSError **)outError;

- (void)didMoveToURL:(NSURL *)localDocumentURL;

- (NSNumber *)hasSameContentsAsLocalDocumentAtURL:(NSURL *)localDocumentURL error:(NSError **)outError;

- (OFXFileSnapshotTransfer *)prepareUploadTransferWithFileManager:(OFSDAVFileManager *)fileManager error:(NSError **)outError;
- (OFXFileSnapshotTransfer *)prepareDownloadTransferWithFileManager:(OFSDAVFileManager *)fileManager filePresenter:(id <NSFilePresenter>)filePresenter;
- (OFXFileSnapshotTransfer *)prepareDeleteTransferWithFileManager:(OFSDAVFileManager *)fileManager filePresenter:(id <NSFilePresenter>)filePresenter;

- (BOOL)handleIncomingDeleteWithFilePresenter:(id <NSFilePresenter>)filePresenter error:(NSError **)outError;

- (NSURL *)fileURLForConflictVersion;

// Helper for debug logs
@property(nonatomic,readonly) NSString *currentContentIdentifier;

@end
