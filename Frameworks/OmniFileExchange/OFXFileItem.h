// Copyright 2013-2015,2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import "OFXFileState.h"

@class ODAVConnection, ODAVFileInfo;
@class OFXContainerAgent, OFXFileSnapshotTransfer, OFXFileState, OFXRecentError;
@protocol NSFilePresenter;

typedef NS_ENUM(NSUInteger, OFXFileItemMoveSource) {
    OFXFileItemMoveSourceLocalUser, // This move represents a user intended move that should be recorded as the name of record and pushed to the server
    OFXFileItemMoveSourceRemoteUser, // This move represents a user intended move that has been downloaded from the server, should be recorded as the name of record, and should ideally become the name of the file locally (conflicts allowing).
    OFXFileItemMoveSourceAutomatic, // The framework has picked a local path for the file that doesn't represent user intent. This could happen due to multiple files requesting the same local relative path (possibly transiently as state is downloaded for renames across two files).
};

/*
 Represents a single file that the sync system knows about. This will register as a file presenter for the local document.
 */

@interface OFXFileItem : NSObject <NSCopying>

- (id)initWithNewLocalDocumentURL:(NSURL *)localDocumentURL container:(OFXContainerAgent *)container error:(NSError **)outError;
- (id)initWithNewLocalDocumentURL:(NSURL *)localDocumentURL asConflictGeneratedFromFileItem:(OFXFileItem *)originalItem coordinator:(NSFileCoordinator *)coordinator container:(OFXContainerAgent *)container error:(NSError **)outError;
- (id)initWithNewRemoteSnapshotAtURL:(NSURL *)remoteSnapshotURL container:(OFXContainerAgent *)container filePresenter:(id <NSFilePresenter>)filePresenter connection:(ODAVConnection *)connection error:(NSError **)outError;
- (id)initWithExistingLocalSnapshotURL:(NSURL *)localSnapshotURL container:(OFXContainerAgent *)container filePresenter:(id <NSFilePresenter>)filePresenter error:(NSError **)outError;

@property(nonatomic,readonly,weak) OFXContainerAgent *container;

@property(nonatomic,readonly) NSString *identifier;
@property(nonatomic,readonly) NSUInteger version;

@property(nonatomic,readonly) NSURL *localDocumentURL;
@property(nonatomic,readonly) NSString *localRelativePath; // Not valid if the item is deleted.
@property(nonatomic,readonly) NSString *intendedLocalRelativePath; // If the item has been automatically moved by the system, this is where the user wanted the item to be originally.
@property(nonatomic,readonly) NSString *requestedLocalRelativePath; // Valid even if the item is deleted

@property(nonatomic,readonly) OFXRecentError *mostRecentTransferError;
- (void)addRecentTransferErrorsByLocalRelativePath:(NSMutableDictionary <NSString *, NSArray <OFXRecentError *> *> *)recentErrorsByLocalRelativePath;
- (void)clearRecentTransferErrors;

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

- (void)markAsMovedToURL:(NSURL *)localDocumentURL source:(OFXFileItemMoveSource)source;

- (NSNumber *)hasSameContentsAsLocalDocumentAtURL:(NSURL *)localDocumentURL error:(NSError **)outError;

- (OFXFileSnapshotTransfer *)prepareUploadTransferWithConnection:(ODAVConnection *)connection error:(NSError **)outError;
- (OFXFileSnapshotTransfer *)prepareDownloadTransferWithConnection:(ODAVConnection *)connection filePresenter:(id <NSFilePresenter>)filePresenter;
- (OFXFileSnapshotTransfer *)prepareDeleteTransferWithConnection:(ODAVConnection *)connection filePresenter:(id <NSFilePresenter>)filePresenter;

- (BOOL)handleIncomingDeleteWithFilePresenter:(id <NSFilePresenter>)filePresenter error:(NSError **)outError;

- (NSURL *)fileURLForConflictVersion;

// Helper for debug logs
@property(nonatomic,readonly) NSString *currentContentIdentifier;

@end
