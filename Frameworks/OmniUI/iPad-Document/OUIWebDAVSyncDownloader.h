// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OUISyncDownloader.h"

@class OFSFileManager;

@interface OUIWebDAVSyncDownloader : OUISyncDownloader <OUIConcreteSyncDownloader>

- initWithFileManager:(OFSFileManager *)fileManager;

@property(nonatomic,readonly) OFSFileManager *fileManager;

@end
