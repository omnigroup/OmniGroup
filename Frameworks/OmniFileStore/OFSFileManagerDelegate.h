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
@class ODAVFileInfo, OFSFileManager, OFSDocumentKey;

@protocol OFSFileManagerDelegate <NSObject>
@optional

// Invoked from our -[NSURLConnectionDelegate connectionShouldUseCredentialStorage:] implementation, which isn't called any more (especially since we've moved from NSURLConnection to NSURLSession), so this is never called either
- (BOOL)fileManagerShouldUseCredentialStorage:(OFSFileManager * __nonnull)manager;

// These are called to satisfy NSURLSession's authentication delegate methods
- (NSURLCredential * __nullable)fileManager:(OFSFileManager * __nonnull)manager findCredentialsForChallenge:(NSURLAuthenticationChallenge * __nonnull)challenge;
- (void)fileManager:(OFSFileManager * __nonnull)manager validateCertificateForChallenge:(NSURLAuthenticationChallenge * __nonnull)challenge;

// This is called to satisfy client-side-encryption challenges
- (OFSDocumentKey * __nullable)fileManager:(OFSFileManager * __nonnull)fileManager
                                    getKey:(ODAVFileInfo * __nonnull)encryptionInfo
                                     error:(NSError * __nullable * __nullable)outError;
- (OFSDocumentKey * __nullable)fileManager:(OFSFileManager * __nonnull)underlyingFileManager initialKeyWithError:(NSError * __nullable * __nullable)outError;

@end
