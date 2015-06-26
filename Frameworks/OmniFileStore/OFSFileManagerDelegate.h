// Copyright 2008-2015 Omni Development, Inc. All rights reserved.
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

// No longer called -- this is managed by user preferences in Settings.app on iOS.
- (BOOL)fileManagerShouldAllowCellularAccess:(OFSFileManager *)manager OB_DEPRECATED_ATTRIBUTE;

// Invoked from our -[NSURLConnectionDelegate connectionShouldUseCredentialStorage:] implementation, which isn't called any more (especially since we've moved from NSURLConnection to NSURLSession), so this is never called either
- (BOOL)fileManagerShouldUseCredentialStorage:(OFSFileManager *)manager;

// These are called to satisfy NSURLSession's authentication delegate methods
- (NSURLCredential *)fileManager:(OFSFileManager *)manager findCredentialsForChallenge:(NSURLAuthenticationChallenge *)challenge;
- (void)fileManager:(OFSFileManager *)manager validateCertificateForChallenge:(NSURLAuthenticationChallenge *)challenge;

@end
