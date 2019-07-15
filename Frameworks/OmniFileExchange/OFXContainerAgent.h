// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class ODAVConnection, ODAVFileInfo;
@class OFFileMotionResult;
@class OFXFileItem, OFXFileMetadata, OFXAccountAgent, OFXServerAccount, OFXFileSnapshotTransfer, OFXRegistrationTable<ValueType>, OFXContainerScan, OFXAccountClientParameters;

@protocol NSFilePresenter;

/*
 Some clients will only be able to deal with a subset of files (OmniOutliner for iPad only needs .oo3 files, for example). To support this, files are split up into containers on the server side based on their path extension. This means we can do a single PROPFIND per path extension to check for changes, and when a client pushes a change, it can post a change to a OFNetStateRegistration for that specific file extension (and so only peers that also care about that kind of file will sync -- OmniOutliner for iPad changes won't cause a OmniGraffle for iPad to sync).
 
 Other clients (the Mac agent) want to greedily sync all file types.
 
 Since we sync documents, not files, clients need to know how to identify if a directory is really a file package. Sadly LaunchServices sometimes gets confused and doesn't register UTIs properly. Even if it did, you might have two Mac's with our agent installed and which have different sets of applications installed. So, each account's remote directory serves as the list of path extensions that should be considered file packages.
 
 This means that if Mac A adds a file package, then Mac B will see that path extension has a package extension and will treat it as such (even if it doesn't have an app installed that deals with that file type). One case this might come up is if the user duplicates the file in Finder, restores a copy from Time Machine, etc.
 
 Containers do not have their own local documents directory, but rather all file items from all containers in an account are mixed into a single local Documents directory for that account. Say you have "foo.ext1/bar.ext2" in the published Documents directory with ext2 being a file package extension and ext1 *not* being a file package extension. Then one bit of fallout of this mixing is that if you install an app that makes ext1 be a file package extension, then foo.ext1 will eat bar.ext2 as an embedded attachment. This is a pretty degenerate case that will hopefully not occur too often since editing a file packages internal guts could lead to data loss.
 
 */

typedef NS_ENUM(NSUInteger, OFXFileItemTransferKind) {
    OFXFileItemUploadTransferKind,
    OFXFileItemDownloadTransferKind,
    OFXFileItemDeleteTransferKind,
};

@interface OFXContainerAgent : NSObject

+ (BOOL)containerAgentIdentifierRepresentsPathExtension:(NSString *)containerIdentifier;
+ (NSString *)containerAgentIdentifierForPathExtension:(NSString *)pathExtension;
+ (NSString *)containerAgentIdentifierForFileURL:(NSURL *)fileURL;

- initWithAccountAgent:(OFXAccountAgent *)accountAgent identifier:(NSString *)identifier metadataRegistrationTable:(OFXRegistrationTable <OFXFileMetadata *> *)metadataRegistrationTable localContainerDirectory:(NSURL *)localContainerDirectory remoteContainerDirectory:(NSURL *)remoteContainerDirectory remoteTemporaryDirectory:(NSURL *)remoteTemporaryDirectory error:(NSError **)outError;


@property(nonatomic,readonly) OFXServerAccount *account;
@property(nonatomic,readonly) NSString *identifier;
@property(nonatomic,readonly) OFXRegistrationTable <OFXFileMetadata *> *metadataRegistrationTable;

@property(nonatomic,readonly) OFXAccountClientParameters *clientParameters;

@property(nonatomic,weak) id <NSFilePresenter> filePresenter;
@property(nonatomic) BOOL automaticallyDownloadFileContents;

@property(nonatomic,readonly) NSURL *localContainerDirectory;
@property(nonatomic,readonly) NSURL *remoteContainerDirectory;
@property(nonatomic,readonly) BOOL hasCreatedRemoteContainerDirectory;

@property(nonatomic,readonly) NSURL *localSnapshotsDirectory; // Internal directory for the client snapshot that originated from the server or needs to be uploaded, etc.

@property(nonatomic,readonly) NSURL *remoteTemporaryDirectory;

@property(nonatomic,readonly) BOOL started;
- (void)start;
- (void)stop;

- (BOOL)syncIfChanged:(ODAVFileInfo *)containerFileInfo serverDate:(NSDate *)serverDate connection:(ODAVConnection *)connection error:(NSError **)outError;

- (void)collectNeededFileTransfers:(void (^)(OFXFileItem *fileItem, OFXFileItemTransferKind kind))addTransfer;
- (OFXFileSnapshotTransfer *)prepareUploadTransferForFileItem:(OFXFileItem *)fileItem error:(NSError **)outError;
- (OFXFileSnapshotTransfer *)prepareDownloadTransferForFileItem:(OFXFileItem *)fileItem error:(NSError **)outError;
- (OFXFileSnapshotTransfer *)prepareDeleteTransferForFileItem:(OFXFileItem *)fileItem error:(NSError **)outError;

- (void)addRecentTransferErrorsByLocalRelativePath:(NSMutableDictionary <NSString *, NSArray <OFXRecentError *> *> *)recentErrorsByLocalRelativePath;
- (void)clearRecentErrorsOnAllFileItems;

// Describes the current state of files on the *server* for this container. When this is updated, the container calls -containerPublishedFileVersionsChanged: on its account agent (on the account agent's queue).
@property(nonatomic,readonly) NSArray <NSString *> *publishedFileVersions;

- (OFXFileItem *)fileItemWithURL:(NSURL *)fileURL;
- (void)addFileItems:(NSMutableArray <OFXFileItem *> *)fileItems inDirectoryWithRelativePath:(NSString *)localDirectoryRelativePath;

//
// File lifecycle calls invoked by OFXAccountAgent as it scans the published documents and reacts to user changes
//

// Scanning; used by OFXAccountAgent
- (OFXContainerScan *)beginScan;
- (BOOL)finishedScan:(OFXContainerScan *)scan error:(NSError **)outError;

// Operations
- (BOOL)fileItemDeleted:(OFXFileItem *)fileItem error:(NSError **)outError;
- (void)fileItemMoved:(OFXFileItem *)fileItem fromURL:(NSURL *)oldURL toURL:(NSURL *)newURL byUser:(BOOL)byUser;
- (void)downloadFileAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
- (void)deleteItemAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
- (void)moveItemAtURL:(NSURL *)originalFileURL toURL:(NSURL *)updatedFileURL completionHandler:(void (^)(OFFileMotionResult *result, NSError *errorOrNil))completionHandler;

@property(nonatomic,copy) NSString *debugName;

@end
