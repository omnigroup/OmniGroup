// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <Foundation/NSURLSession.h>
#import <OmniDAV/ODAVFeatures.h>
#import <OmniDAV/ODAVConnectionTimeoutDelegate.h>
#import <OmniBase/macros.h>

NS_ASSUME_NONNULL_BEGIN

@class NSURLCredential, NSURLAuthenticationChallenge, NSOperation;
@class ODAVMultipleFileInfoResult, ODAVSingleFileInfoResult, ODAVFileInfo, ODAVOperation, ODAVRedirect, ODAVURLResult, ODAVURLAndDataResult;
@protocol OFCertificateTrustDisposition, OFCredentialChallengeDisposition;

typedef void (^ODAVConnectionBasicCompletionHandler)(NSError * _Nullable errorOrNil);
typedef void (^ODAVConnectionOperationCompletionHandler)(ODAVOperation *op);
typedef void (^ODAVConnectionURLCompletionHandler)(ODAVURLResult * _Nullable result, NSError * _Nullable errorOrNil);
typedef void (^ODAVConnectionURLAndDataCompletionHandler)(ODAVURLAndDataResult * _Nullable result, NSError * _Nullable errorOrNil);
typedef void (^ODAVConnectionStringCompletionHandler)(NSString * _Nullable resultString, NSError * _Nullable errorOrNil);
typedef void (^ODAVConnectionMultipleFileInfoCompletionHandler)(ODAVMultipleFileInfoResult * _Nullable properties, NSError * _Nullable errorOrNil);
typedef void (^ODAVConnectionSingleFileInfoCompletionHandler)(ODAVSingleFileInfoResult * _Nullable properties, NSError * _Nullable errorOrNil);

typedef NS_ENUM(NSUInteger, ODAVDepth) {
    ODAVDepthLocal,
    ODAVDepthChildren,
    ODAVDepthInfinite, // Not always supported by servers
};

@interface ODAVConnectionConfiguration : NSObject

+ (NSString *)userAgentStringByAddingComponents:(nullable NSArray *)components;

@property(nonatomic,copy) NSString *userAgent;

@property(nonatomic) BOOL HTTPShouldUsePipelining;

@property(nonatomic) NSInteger maximumChallengeRetryCount;

@end

@interface ODAVConnection : NSObject

@property(class,nonatomic,weak) id <ODAVConnectionTimeoutDelegate> timeoutDelegate;

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

@property(nonatomic,copy,nullable) NSDictionary <NSString *, NSString *> *customHeaderValues;

// NOTE: These get called on a private queue, not the queue the connection was created on or the queue the operations were created or started on
// validateCertificateForChallenge: Decide whether to trust a server (NSURLAuthenticationMethodServerTrust), and return the adjusted SecTrustRef credential if so. Returning nil is equivalent to not setting a callback in the first place, which results in NSURLSessionAuthChallengeRejectProtectionSpace. (TODO: Should it be default handling instead of reject?)
// This callback should simply apply any stored exceptions or similar overrides, but probably shouldn't prompt the user: if it takes too long the server may drop the connection, and NSURLSession doesn't automatically handle that timeout. Instead, users of OmniDAV should run a trust dialog if an operation fails for a server-trust-related reason.
@property(nonatomic,copy,nullable) NSURLCredential * _Nullable (^validateCertificateForChallenge)(NSURLAuthenticationChallenge *challenge);

// findCredentialsForChallenge: Start an operation to get a username+password for an operation, and return it. The DAV operation will be canceled, but the NSOperation will be returned in the error block for the caller to wait on if it wants. (In the future we may want the DAV operation to wait on the NSOperation automatically.)
@property(nonatomic,copy,nullable) NSOperation <OFCredentialChallengeDisposition> *(^findCredentialsForChallenge)(NSURLAuthenticationChallenge *challenge);

- (void)deleteURL:(NSURL *)url withETag:(nullable NSString *)ETag completionHandler:(nullable ODAVConnectionBasicCompletionHandler)completionHandler;
- (ODAVOperation *)asynchronousDeleteURL:(NSURL *)url withETag:(nullable NSString *)ETag;

- (void)makeCollectionAtURL:(NSURL *)url completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)makeCollectionAtURLIfMissing:(NSURL *)url baseURL:(nullable NSURL *)baseURL completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;

- (void)fileInfosAtURL:(NSURL *)url ETag:(nullable NSString *)predicateETag depth:(ODAVDepth)depth completionHandler:(ODAVConnectionMultipleFileInfoCompletionHandler)completionHandler;
- (void)fileInfoAtURL:(NSURL *)url ETag:(nullable NSString *)predicateETag completionHandler:(void (^)(ODAVSingleFileInfoResult * _Nullable result, NSError * _Nullable error))completionHandler;

// Removes the directory URL itself, "._" files, and does some more error checking for non-directory cases.
- (void)directoryContentsAtURL:(NSURL *)url withETag:(nullable NSString *)ETag completionHandler:(ODAVConnectionMultipleFileInfoCompletionHandler)completionHandler;

- (void)getContentsOfURL:(NSURL *)url ETag:(nullable NSString *)ETag completionHandler:(ODAVConnectionOperationCompletionHandler)completionHandler;
- (ODAVOperation *)asynchronousGetContentsOfURL:(NSURL *)url; // Returns an unstarted operation
- (ODAVOperation *)asynchronousGetContentsOfURL:(NSURL *)url withETag:(nullable NSString *)ETag range:(nullable NSString *)range;

- (void)postData:(NSData *)data toURL:(NSURL *)url completionHandler:(ODAVConnectionURLAndDataCompletionHandler)completionHandler;

- (void)putData:(NSData *)data toURL:(NSURL *)url completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (ODAVOperation *)asynchronousPutData:(NSData *)data toURL:(NSURL *)url; // Returns an unstarted operation

- (void)copyURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(nullable NSString *)ETag overwrite:(BOOL)overwrite completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;

- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(nullable NSString *)ETag overwrite:(BOOL)overwrite completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationETag:(nullable NSString *)ETag overwrite:(BOOL)overwrite completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceLock:(nullable NSString *)lock overwrite:(BOOL)overwrite completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationLock:(nullable NSString *)lock overwrite:(BOOL)overwrite completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toMissingURL:(NSURL *)destURL completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL ifURLExists:(NSURL *)tagURL completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;

- (void)lockURL:(NSURL *)url completionHandler:(ODAVConnectionStringCompletionHandler)completionHandler;
- (void)unlockURL:(NSURL *)url token:(NSString *)lockToken completionHandler:(ODAVConnectionBasicCompletionHandler)completionHandler;

@end

@interface ODAVOperationResult : NSObject
@property(nullable,nonatomic,copy) NSArray <ODAVRedirect *> *redirects;
@property(nullable,nonatomic,copy) NSDate *serverDate;
@end

@interface ODAVMultipleFileInfoResult : ODAVOperationResult
@property(nullable,nonatomic,copy) NSArray <ODAVFileInfo *> *fileInfos;
@end
@interface ODAVSingleFileInfoResult : ODAVOperationResult
@property(nullable,nonatomic,copy) ODAVFileInfo *fileInfo;
@end
@interface ODAVURLResult : ODAVOperationResult
@property(nullable,nonatomic,copy) NSURL *URL;
@end
@interface ODAVURLAndDataResult : ODAVOperationResult
@property(nullable,nonatomic,copy) NSURL *URL;
@property(nullable,nonatomic,copy) NSData *responseData;
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

- (BOOL)synchronousDeleteURL:(NSURL *)url withETag:(nullable NSString *)ETag error:(NSError **)outError;

- (nullable ODAVURLResult *)synchronousMakeCollectionAtURL:(NSURL *)url error:(NSError **)outError;

- (nullable ODAVFileInfo *)synchronousFileInfoAtURL:(NSURL *)url error:(NSError **)outError;
- (nullable ODAVFileInfo *)synchronousFileInfoAtURL:(NSURL *)url serverDate:(NSDate * __nullable OB_AUTORELEASING * __nullable)outServerDate error:(NSError **)outError;

- (nullable ODAVSingleFileInfoResult *)synchronousMetaFileInfoAtURL:(NSURL *)url serverDate:(NSDate * __nullable OB_AUTORELEASING * __nullable)outServerDate error:(NSError **)outError;

- (nullable ODAVMultipleFileInfoResult *)synchronousDirectoryContentsAtURL:(NSURL *)url withETag:(nullable NSString *)ETag error:(NSError **)outError;

- (nullable NSData *)synchronousGetContentsOfURL:(NSURL *)url ETag:(nullable NSString *)ETag error:(NSError **)outError;
- (nullable NSURL *)synchronousPutData:(NSData *)data toURL:(NSURL *)url error:(NSError **)outError;

- (nullable NSURL *)synchronousCopyURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(nullable NSString *)eTag overwrite:(BOOL)overwrite error:(NSError **)outError;

- (nullable NSURL *)synchronousMoveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationETag:(nullable NSString *)ETag overwrite:(BOOL)overwrite error:(NSError **)outError;
- (nullable NSURL *)synchronousMoveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceLock:(nullable NSString *)lock overwrite:(BOOL)overwrite error:(NSError **)outError;
- (nullable NSURL *)synchronousMoveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationLock:(nullable NSString *)lock overwrite:(BOOL)overwrite error:(NSError **)outError;
- (nullable NSURL *)synchronousMoveURL:(NSURL *)sourceURL toMissingURL:(NSURL *)destURL error:(NSError **)outError;

- (nullable NSString *)synchronousLockURL:(NSURL *)url error:(NSError **)outError;
- (BOOL)synchronousUnlockURL:(NSURL *)url token:(NSString *)lockToken error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END

