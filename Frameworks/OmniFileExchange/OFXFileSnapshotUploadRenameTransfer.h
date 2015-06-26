// Copyright 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFXFileSnapshotUploadTransfer.h"

@interface OFXFileSnapshotUploadRenameTransfer : OFXFileSnapshotUploadTransfer

- (id)initWithConnection:(ODAVConnection *)connection currentSnapshot:(OFXFileSnapshot *)currentSnapshot remoteTemporaryDirectory:(NSURL *)remoteTemporaryDirectory currentRemoteSnapshotURL:(NSURL *)currentRemoteSnapshotURL error:(NSError **)outError;

@end
