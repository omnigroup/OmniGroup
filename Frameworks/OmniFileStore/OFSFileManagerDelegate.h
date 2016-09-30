// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSOperation, NSURLCredential, NSURLAuthenticationChallenge;
@class ODAVFileInfo, OFSFileManager, OFSDocumentKey, OFSMutableDocumentKey;
@protocol OFCredentialChallengeDisposition, OFCertificateTrustDisposition;

NS_ASSUME_NONNULL_BEGIN

@protocol OFSFileManagerDelegate <NSObject>
@optional

// These are called to satisfy NSURLSession's authentication delegate methods. See ODAVConnection's documentation for details.
- (NSOperation <OFCredentialChallengeDisposition> * _Nullable)fileManager:(OFSFileManager *)manager findCredentialsForChallenge:(NSURLAuthenticationChallenge *)challenge;
- (NSURLCredential * _Nullable)fileManager:(OFSFileManager *)manager validateCertificateForChallenge:(NSURLAuthenticationChallenge *)challenge;

/// This is called to determine whether it's okay to silently accept an encrypted database when we were expecting an unencrypted database. (Defaults to NO if not implemented.)
- (BOOL)shouldAllowUnexpectedEncryptionForURL:(NSURL *)documentURL;

/// This is called after silently accepting an encrypted database was successful when we were expecting an unencrypted database. <code>-shouldAllowUnexpectedEncryptionForURL:</code> must have given prior consent for this to be a possibility.
- (void)didAllowUnexpectedEncryptionForURL:(NSURL *)documentURL;
@property (nonatomic, copy, readonly) NSURL  * _Nullable proposedXMLSyncURLAfterAddingTrailingEncryptionMarker;

// This is called to satisfy client-side-encryption challenges
- (OFSDocumentKey * _Nullable)fileManager:(OFSFileManager *)fileManager
                                   getKey:(ODAVFileInfo *)encryptionInfo
                             refreshCache:(BOOL)refreshing
                                    error:(NSError **)outError;
- (BOOL)fileManager:(OFSFileManager *)fileManager verifyKey:(OFSDocumentKey *)derivation originURL:(NSURL *)originURL error:(NSError **)outError;
- (BOOL)fileManager:(OFSFileManager *)fileManager changePasswordOfKey:(OFSMutableDocumentKey *)derivation originURL:(NSURL *)originURL error:(NSError **)outError;
- (OFSMutableDocumentKey * _Nullable)fileManager:(OFSFileManager *)underlyingFileManager initialKeyWithError:(NSError **)outError;
- (void)fileManagerDidStore:(NSURL *)where key:(OFSDocumentKey * _Nullable)keyStore data:(NSData *)d;

// For keeping track of key slot usage
- (void)fileManager:(OFSFileManager *)fileManager usedSlot:(unsigned)keyslot URL:(NSURL *)location flags:(NSUInteger)fileManagerSlotUsageFlags;

@end

NS_ASSUME_NONNULL_END
