// Copyright 2008-2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniDAV/ODAVFeatures.h>

@class ODAVMultipleFileInfoResult, ODAVSingleFileInfoResult, ODAVFileInfo, ODAVOperation;

typedef void (^ODAVConnectionBasicCompletionHandler)(NSError *errorOrNil);
typedef void (^ODAVConnectionOperationCompletionHandler)(ODAVOperation *op);
typedef void (^ODAVConnectionURLCompletionHandler)(NSURL *resultURL, NSError *errorOrNil);
typedef void (^ODAVConnectionStringCompletionHandler)(NSString *resultString, NSError *errorOrNil);
typedef void (^ODAVConnectionMultipleFileInfoCompletionHandler)(ODAVMultipleFileInfoResult *properties, NSError *errorOrNil);
typedef void (^ODAVConnectionSingleFileInfoCompletionHandler)(ODAVSingleFileInfoResult *properties, NSError *errorOrNil);

typedef NS_ENUM(NSUInteger, ODAVDepth) {
    ODAVDepthLocal,
    ODAVDepthChildren,
    ODAVDepthInfinite, // Not always supported by servers
};

#if !ODAV_NSURLSESSION
// Stand-in until we use NSURLSessionConfiguration
@interface ODAVConnectionConfiguration : NSObject

+ (NSString *)userAgentStringByAddingComponents:(NSArray *)components;

@property(nonatomic) BOOL allowsCellularAccess;
@property(nonatomic,copy) NSString *userAgent;

@end
#endif

@interface ODAVConnection : NSObject

- initWithSessionConfiguration:(ODAV_NSURLSESSIONCONFIGURATION_CLASS *)configuration;

// Completely override the user agent string, otherwise the configuration's userAgent will be used.
@property(nonatomic,copy) NSString *userAgent;

// NOTE: These get called on a private queue, not the queue the connection was created on or the queue the operations were created or started on
@property(nonatomic,copy) void (^validateCertificateForChallenge)(NSURLAuthenticationChallenge *challenge);
@property(nonatomic,copy) NSURLCredential *(^findCredentialsForChallenge)(NSURLAuthenticationChallenge *challenge);

- (void)deleteURL:(NSURL *)url withETag:(NSString *)ETag completionHandler:(ODAVConnectionBasicCompletionHandler)completionHandler;

- (void)makeCollectionAtURL:(NSURL *)url completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;
- (void)makeCollectionAtURLIfMissing:(NSURL *)url baseURL:(NSURL *)baseURL completionHandler:(ODAVConnectionURLCompletionHandler)completionHandler;

- (void)fileInfosAtURL:(NSURL *)url ETag:(NSString *)predicateETag depth:(ODAVDepth)depth completionHandler:(ODAVConnectionMultipleFileInfoCompletionHandler)completionHandler;
- (void)fileInfoAtURL:(NSURL *)url ETag:(NSString *)predicateETag completionHandler:(void (^)(ODAVSingleFileInfoResult *result, NSError *error))completionHandler;

// Removes the directory URL itself, "._" files, and does some more error checking for non-directory cases.
- (void)directoryContentsAtURL:(NSURL *)url withETag:(NSString *)ETag completionHandler:(ODAVConnectionMultipleFileInfoCompletionHandler)completionHandler;

- (void)getContentsOfURL:(NSURL *)url ETag:(NSString *)ETag completionHandler:(ODAVConnectionOperationCompletionHandler)completionHandler;
- (ODAVOperation *)asynchronousGetContentsOfURL:(NSURL *)url; // Returns an unstarted operation

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

@interface ODAVMultipleFileInfoResult : NSObject
@property(nonatomic,copy) NSArray *fileInfos;
@property(nonatomic,copy) NSArray *redirects;
@property(nonatomic,copy) NSDate *serverDate;
@end
@interface ODAVSingleFileInfoResult : NSObject
@property(nonatomic,copy) ODAVFileInfo *fileInfo;
@property(nonatomic,copy) NSArray *redirects;
@property(nonatomic,copy) NSDate *serverDate;
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

- (NSURL *)synchronousMakeCollectionAtURL:(NSURL *)url error:(NSError **)outError;

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

