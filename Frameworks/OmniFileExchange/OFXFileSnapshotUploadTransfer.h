// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFXFileSnapshotTransfer.h"

@class OFSDAVFileManager;
@class OFXFileSnapshot;

@interface OFXFileSnapshotUploadTransfer : OFXFileSnapshotTransfer

- (id)initWithFileManager:(OFSDAVFileManager *)fileManager currentSnapshot:(OFXFileSnapshot *)currentSnapshot remoteTemporaryDirectory:(NSURL *)remoteTemporaryDirectory;

@property(nonatomic,readonly) NSURL *remoteTemporaryDirectoryURL;
@property(nonatomic,copy) NSURL *temporaryRemoteSnapshotURL; // Subclasses can update with the redirected URL
@property(nonatomic,readonly) OFXFileSnapshot *currentSnapshot;

// Subclasses must override this to return a snapshot
@property(nonatomic,readonly) OFXFileSnapshot *uploadingSnapshot;

@end
