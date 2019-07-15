// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXFileSnapshotTransfer.h"

@class OFXFileSnapshot;

@interface OFXFileSnapshotDownloadTransfer : OFXFileSnapshotTransfer

- initWithConnection:(ODAVConnection *)connection remoteSnapshotURL:(NSURL *)remoteSnapshotURL localTemporaryDocumentContentsURL:(NSURL *)localTemporaryDocumentContentsURL currentSnapshot:(OFXFileSnapshot *)currentSnapshot;

@property(nonatomic,readonly) OFXFileSnapshot *downloadedSnapshot;
@property(nonatomic,readonly) NSURL *localTemporaryDocumentContentsURL;

@property(nonatomic,copy) void (^started)(void);
@property(nonatomic,readonly) BOOL isContentDownload; // This will be NO until the 'started' block is called and then might switch to YES.

@end
