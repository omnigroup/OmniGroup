// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFXFileSnapshotTransfer.h"

@class OFXFileSnapshot;

@interface OFXFileSnapshotDownloadTransfer : OFXFileSnapshotTransfer

- initWithFileManager:(OFSDAVFileManager *)fileManager remoteSnapshotURL:(NSURL *)remoteSnapshotURL localTemporaryDocumentContentsURL:(NSURL *)localTemporaryDocumentContentsURL currentSnapshot:(OFXFileSnapshot *)currentSnapshot;

@property(nonatomic,readonly) OFXFileSnapshot *downloadedSnapshot;
@property(nonatomic,readonly) NSURL *localTemporaryDocumentContentsURL;
@property(nonatomic,readonly) BOOL didMakeLocalTemporaryDocumentContentsURL;

@property(nonatomic,copy) void (^started)(void);
@property(nonatomic,readonly) BOOL isContentDownload; // This will be NO until the 'started' block is called and then might switch to YES.

@end
