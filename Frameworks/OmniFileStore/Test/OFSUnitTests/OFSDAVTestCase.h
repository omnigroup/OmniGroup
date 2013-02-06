// Copyright 2008-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFSTestCase.h"

#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>

@interface OFSDAVTestCase : OFSTestCase <OFSFileManagerDelegate>
@property(nonatomic,readonly) OFSDAVFileManager *fileManager;
@property(nonatomic,readonly) NSURL *remoteBaseURL;
@end
