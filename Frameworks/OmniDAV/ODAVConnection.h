// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <Foundation/NSURLSession.h>
#import <OmniDAV/ODAVFeatures.h>

@class NSURLCredential, NSURLAuthenticationChallenge, NSOperation;
@class ODAVMultipleFileInfoResult, ODAVSingleFileInfoResult, ODAVFileInfo, ODAVOperation, ODAVRedirect, ODAVURLResult, ODAVURLAndDataResult;
@protocol OFCertificateTrustDisposition, OFCredentialChallengeDisposition;

typedef void (^ODAVConnectionBasicCompletionHandler)(NSError *errorOrNil);
typedef void (^ODAVConnectionOperationCompletionHandler)(ODAVOperation *op);
typedef void (^ODAVConnectionURLCompletionHandler)(ODAVURLResult *result, NSError *errorOrNil);
typedef void (^ODAVConnectionURLAndDataCompletionHandler)(ODAVURLAndDataResult *result, NSError *errorOrNil);
typedef void (^ODAVConnectionStringCompletionHandler)(NSString *resultString, NSError *errorOrNil);
typedef void (^ODAVConnectionMultipleFileInfoCompletionHandler)(ODAVMultipleFileInfoResult *properties, NSError *errorOrNil);
typedef void (^ODAVConnectionSingleFileInfoCompletionHandler)(ODAVSingleFileInfoResult *properties, NSError *errorOrNil);

typedef NS_ENUM(NSUInteger, ODAVDepth) {
    ODAVDepthLocal,
    ODAVDepthChildren,
    ODAVDepthInfinite, // Not always supported by servers
};

@interface ODAVConnectionConfiguration : NSObject

+ (NSString *)userAgentStringByAddingComponents:(NSArray *)components;

@property(nonatomic,copy) NSString *userAgent;

@property(nonatomic) BOOL HTTPShouldUsePipelining;

@end

@interface ODAVConnection : NSObject

+ (NSDate *)dateFromString:(NSString *)httpDate;

- (instancetype)init NS_UNAVAILABLE;
- initWithSessionConfiguration:(ODAVConnectionConfiguration *)configuration baseURL:(NSURL *)baseURL NS_DESIGNATED_INITIALIZER;

@property(nonatomic,readonly) ODAVConnectionConfiguration *configuration;

@property(nonatomic,readonly) NSURL *originalBaseURL;
@property(nonatomic,readonly) NSURL *baseURL; // Possibly redirected

- (void)updateBaseURLWithRedirects:(NSArray <ODAVRedirect *> *)redirects;
- (NSURL *)suggestRedirectedURLForURL:(NSURL *)url;

// Completely override the user agent string, otherwise the configuration's userAgent will be used.
@property(nonatomic,copy) NSString *userAgent;
@property(nonatomic,copy) NSString *operationReason;

// NOTE: These get called on a private queue, not the queue the connection was created on or the queue the operations were created or started on
// validateCertificateForChallenge: Decide whether to trust a server (NSURLAuthenticationMethodServerTrust), and return the adjusted SecTrustRef credential if so. Returning nil is equivalent to not setting a callback in the first place, which results in NSURLSessionAuthChallengeRejectProtectionSpace. (TODO: Should it be default handling instead of reject?)
// This callback should simply apply any stored exceptions or similar overrides, but probably shouldn't prompt the user: if it takes too long the server may drop the connection, and NSURLSession doesn't automatically handle that timeout. Instead, users of OmniDAV should run a trust dialog if an operation fails for a server-trust-related reason.
@property(nonatomic,copy) NSURLCredential *(^validateCertificateForChallenge)(NSURLAuthenticationChallenge *challenge);
// findCredentialsForChallenge: Start an operation to get a username+password for an operation, and return it. The DAV operation will be canceled, but the NSOperation will be returned in the error block for the caller to wait on if it wants. (In the future we may want the DAV operation to wait on the NSOperation automatically.)
@property(nonatomic,copy) NSOperation <OFCredentialChallengeDisposition> *(^findCredentialsForChallenge)(NSURLAuthenticationChallenge *challenge);

- (void)deleteURL:(NSURL *)url withETag:(NSString *)ETag completionHandler:(ODAVConnectionBasicCompletionHandler)completionHandler;
- (ODAVOperation *)asynchronousDeleteURL:(NSURL *)url withETag:(NSString *)ETag;

- (void)makeCollectionAtURL:(NSURL *)url completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)makeCollectionAtURLIfMissing:(NSURL *)url baseURL:(NSURL *)baseURL completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;

- (void)fileInfosAtURL:(NSURL *)url ETag:(NSString *)predicateETag depth:(ODAVDepth)depth completionHandler:(ODAVConnectionMultipleFileInfoCompletionHandler)completionHandler;
- (void)fileInfoAtURL:(NSURL *)url ETag:(NSString *)predicateETag completionHandler:(void (^)(ODAVSingleFileInfoResult *result, NSError *error))completionHandler;

// Removes the directory URL itself, "._" files, and does some more error checking for non-directory cases.
- (void)directoryContentsAtURL:(NSURL *)url withETag:(NSString *)ETag completionHandler:(ODAVConnectionMultipleFileInfoCompletionHandler)completionHandler;

- (void)getContentsOfURL:(NSURL *)url ETag:(NSString *)ETag completionHandler:(ODAVConnectionOperationCompletionHandler)completionHandler;
- (ODAVOperation *)asynchronousGetContentsOfURL:(NSURL *)url; // Returns an unstarted operation
- (ODAVOperation *)asynchronousGetContentsOfURL:(NSURL *)url withETag:(NSString *)ETag range:(NSString *)range;

- (void)postData:(NSData *)data toURL:(NSURL *)url completionHandler:(ODAVConnectionURLAndDataCompletionHandler)completionHandler;

- (void)putData:(NSData *)data toURL:(NSURL *)url completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (ODAVOperation *)asynchronousPutData:(NSData *)data toURL:(NSURL *)url; // Returns an unstarted operation

- (void)copyURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(NSString *)ETag overwrite:(BOOL)overwrite completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;

- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(NSString *)ETag overwrite:(BOOL)overwrite completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationETag:(NSString *)ETag overwrite:(BOOL)overwrite completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceLock:(NSString *)lock overwrite:(BOOL)overwrite completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationLock:(NSString *)lock overwrite:(BOOL)overwrite completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toMissingURL:(NSURL *)destURL completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL ifURLExists:(NSURL *)tagURL completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;

- (void)lockURL:(NSURL *)url completionHandler:(ODAVConnectionStringCompletionHandler)completionHandler;
- (void)unlockURL:(NSURL *)url token:(NSString *)lockToken completionHandler:(ODAVConnectionBasicCompletionHandler)completionHandler;

@end

@interface ODAVOperationResult : NSObject
@property(nonatomic,copy) NSArray <ODAVRedirect *> *redirects;
@property(nonatomic,copy) NSDate *serverDate;
@end

@interface ODAVMultipleFileInfoResult : ODAVOperationResult
@property(nonatomic,copy) NSArray <ODAVFileInfo *> *fileInfos;
@end
@interface ODAVSingleFileInfoResult : ODAVOperationResult
@property(nonatomic,copy) ODAVFileInfo *fileInfo;
@end
@interface ODAVURLResult : ODAVOperationResult
@property(nonatomic,copy) NSURL *URL;
@end
@interface ODAVURLAndDataResult : ODAVOperationResult
@property(nonatomic,copy) NSURL *URL;
@property(nonatomic,copy) NSData *responseData;
@end

// Utilities to help when we want synchronous operations.

// Adding a macro to wrap this up is a pain since we can't set breakpoints inside the block easily (and we have to wrap the block in an extra (...) if it has embedded commas that aren't inside parens already).
typedef void (^ODAVOperationDone)(void);
typedef void (^ODAVAddOperation)(ODAVOperationDone done);
extern void ODAVSyncOperation(const char *file, unsigned line, ODAVAddOperation op);

// Each call to the 'add' block must be balanced by a call to the 'done' block.
typedef void (^ODAVFinishAction)(void);
typedef void (^ODAVFinishOperation)(ODAVFinishAction completionAction);
typedef void (^ODAVStartAction)(ODAVFinishOperation finish);
typedef void (^OFXStartOperation)(ODAVStartAction backgroundAction);
typedef void (^ODAVAddOperations)(OFXStartOperation start);
extern void ODAVSyncOperations(const char *file, unsigned line, ODAVAddOperations addOperations);

// Synchronous wrappers
@interface ODAVConnection (ODAVSyncExtensions)

- (BOOL)synchronousDeleteURL:(NSURL *)url withETag:(NSString *)ETag error:(NSError **)outError;

- (ODAVURLResult *)synchronousMakeCollectionAtURL:(NSURL *)url error:(NSError **)outError;

- (ODAVFileInfo *)synchronousFileInfoAtURL:(NSURL *)url error:(NSError **)outError;
- (ODAVFileInfo *)synchronousFileInfoAtURL:(NSURL *)url serverDate:(NSDate **)outServerDate error:(NSError **)outError;

- (ODAVMultipleFileInfoResult *)synchronousDirectoryContentsAtURL:(NSURL *)url withETag:(NSString *)ETag error:(NSError **)outError;

- (NSData *)synchronousGetContentsOfURL:(NSURL *)url ETag:(NSString *)ETag error:(NSError **)outError;
- (NSURL *)synchronousPutData:(NSData *)data toURL:(NSURL *)url error:(NSError **)outError;

- (NSURL *)synchronousCopyURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(NSString *)eTag overwrite:(BOOL)overwrite error:(NSError **)outError;

- (NSURL *)synchronousMoveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationETag:(NSString *)ETag overwrite:(BOOL)overwrite error:(NSError **)outError;
- (NSURL *)synchronousMoveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceLock:(NSString *)lock overwrite:(BOOL)overwrite error:(NSError **)outError;
- (NSURL *)synchronousMoveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationLock:(NSString *)lock overwrite:(BOOL)overwrite error:(NSError **)outError;
- (NSURL *)synchronousMoveURL:(NSURL *)sourceURL toMissingURL:(NSURL *)destURL error:(NSError **)outError;

- (NSString *)synchronousLockURL:(NSURL *)url error:(NSError **)outError;
- (BOOL)synchronousUnlockURL:(NSURL *)url token:(NSString *)lockToken error:(NSError **)outError;

@end


