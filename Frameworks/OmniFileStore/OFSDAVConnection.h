// Copyright 2008-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class OFSDAVMultipleFileInfoResult, OFSDAVSingleFileInfoResult, OFSFileInfo, OFSDAVOperation;

typedef void (^OFSDAVConnectionBasicCompletionHandler)(NSError *errorOrNil);
typedef void (^OFSDAVConnectionOperationCompletionHandler)(OFSDAVOperation *op);
typedef void (^OFSDAVConnectionURLCompletionHandler)(NSURL *resultURL, NSError *errorOrNil);
typedef void (^OFSDAVConnectionStringCompletionHandler)(NSString *resultString, NSError *errorOrNil);
typedef void (^OFSDAVConnectionMultipleFileInfoCompletionHandler)(OFSDAVMultipleFileInfoResult *properties, NSError *errorOrNil);
typedef void (^OFSDAVConnectionSingleFileInfoCompletionHandler)(OFSDAVSingleFileInfoResult *properties, NSError *errorOrNil);

typedef NS_ENUM(NSUInteger, OFSDAVDepth) {
    OFSDAVDepthLocal,
    OFSDAVDepthChildren,
    OFSDAVDepthInfinite, // Not always supported by servers
};

@interface OFSDAVConnection : NSObject

@property(nonatomic,copy) void (^validateCertificateForChallenge)(OFSDAVConnection *connection, NSURLAuthenticationChallenge *challenge);
@property(nonatomic,copy) NSURLCredential *(^findCredentialsForChallenge)(OFSDAVConnection *connection, NSURLAuthenticationChallenge *challenge);
@property(nonatomic) BOOL shouldDisableCellularAccess;

- (void)deleteURL:(NSURL *)url withETag:(NSString *)ETag completionHandler:(OFSDAVConnectionBasicCompletionHandler)completionHandler;

- (void)makeCollectionAtURL:(NSURL *)url completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;

- (void)fileInfosAtURL:(NSURL *)url ETag:(NSString *)predicateETag depth:(OFSDAVDepth)depth completionHandler:(OFSDAVConnectionMultipleFileInfoCompletionHandler)completionHandler;
- (void)fileInfoAtURL:(NSURL *)url ETag:(NSString *)predicateETag completionHandler:(void (^)(OFSDAVSingleFileInfoResult *result, NSError *error))completionHandler;

- (void)getContentsOfURL:(NSURL *)url ETag:(NSString *)ETag completionHandler:(OFSDAVConnectionOperationCompletionHandler)completionHandler;
- (OFSDAVOperation *)asynchronousGetContentsOfURL:(NSURL *)url; // Returns an unstarted operation

- (void)putData:(NSData *)data toURL:(NSURL *)url completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
- (OFSDAVOperation *)asynchronousPutData:(NSData *)data toURL:(NSURL *)url; // Returns an unstarted operation

- (void)copyURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(NSString *)ETag overwrite:(BOOL)overwrite completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;

- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceETag:(NSString *)ETag overwrite:(BOOL)overwrite completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationETag:(NSString *)ETag overwrite:(BOOL)overwrite completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withSourceLock:(NSString *)lock overwrite:(BOOL)overwrite completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL withDestinationLock:(NSString *)lock overwrite:(BOOL)overwrite completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toMissingURL:(NSURL *)destURL completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;
- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL ifURLExists:(NSURL *)tagURL completionHandler:(OFSDAVConnectionURLCompletionHandler)completionHandler;

- (void)lockURL:(NSURL *)url completionHandler:(OFSDAVConnectionStringCompletionHandler)completionHandler;
- (void)unlockURL:(NSURL *)url token:(NSString *)lockToken completionHandler:(OFSDAVConnectionBasicCompletionHandler)completionHandler;

@end

@interface OFSDAVMultipleFileInfoResult : NSObject
@property(nonatomic,copy) NSArray *fileInfos;
@property(nonatomic,copy) NSArray *redirects;
@property(nonatomic,copy) NSDate *serverDate;
@end
@interface OFSDAVSingleFileInfoResult : NSObject
@property(nonatomic,copy) OFSFileInfo *fileInfo;
@property(nonatomic,copy) NSArray *redirects;
@property(nonatomic,copy) NSDate *serverDate;
@end
