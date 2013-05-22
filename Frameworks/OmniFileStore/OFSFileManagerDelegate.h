// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSURLCredential, NSURLAuthenticationChallenge;
@class OFSFileManager;

@protocol OFSFileManagerDelegate <NSObject>
@optional
- (BOOL)fileManagerShouldAllowCellularAccess:(OFSFileManager *)manager;
- (BOOL)fileManagerShouldUseCredentialStorage:(OFSFileManager *)manager;
- (NSURLCredential *)fileManager:(OFSFileManager *)manager findCredentialsForChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)fileManager:(OFSFileManager *)manager validateCertificateForChallenge:(NSURLAuthenticationChallenge *)challenge;
@end
