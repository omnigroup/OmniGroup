// Copyright 2013 Omni Development, Inc.  All rights reserved.
//
// $Id$

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, OUIUploadControllerError) {
    OUIUploadControllerErrorLoginFailedInvalid = 1,
    OUIUploadControllerErrorLoginFailedOther,
    OUIUploadControllerErrorCredentialsMissing,
    OUIUploadControllerErrorUploading
};

extern NSString * const OUIUploadControllerErrorDomain;

#define OUIUploadControllerWrapErrorWithInfo(error, code, description, reason, ...) _OBError(error, OUIUploadControllerErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedFailureReasonErrorKey, (reason), ## __VA_ARGS__)
#define OUIUploadControllerWrapError(error, code, description, reason) OUIUploadControllerWrapErrorWithInfo((error), (code), (description), (reason), nil)

typedef NS_ENUM(NSUInteger, UploadControllerState) {
    UploadControllerStateUnset,
    UploadControllerStateCheckingCredentials, // Only checks the keychain. Does not include validating from server. Server validation is done during the .LoggingIn state or indirectly via the .Uploading state.
    UploadControllerStateLoggingIn,
    UploadControllerStateLoggedInIdle,
    UploadControllerStateUploading,
    UploadControllerStateUploadSucceeded
};

typedef void (^UploadControllerLoginCredentialHandler)(NSURLCredential *credential);
/// Assumes the previewData is PNG. URL Encodes the fileDataFileName.
typedef void (^UploadControllerUploadHandler)(NSData *fileData, NSString *fileDataFileName, NSData *previewData);

@protocol OUIUploadControllerDelegate;

/// This class is being designed to facilitate uploading stencils to Stenciltown. Once we need it for something else, we can refactor to be more generic.
@interface OUIUploadController : NSObject <NSProgressReporting>

@property (nonatomic, readonly, assign) UploadControllerState state;
@property (nonatomic, weak) id<OUIUploadControllerDelegate> delegate;

/// Used to report the upload progress.
@property (readonly) NSProgress *progress;

/// We've been requested to use the App's bundleIdentifier as the User-Agent for all requests.
- (instancetype)initWithUserAgent:(NSString *)userAgent;

/// This method kicks off the internal state machine which will notify the delegate as transitions occur. (Ensures the state machine is currently in .Unset, otherwise no action is taken.)
- (void)login;

/// Only logs out if the state machine is currently in .LoggedInIdle, otherwise no action is taken. (Dirtying my beautiful state machine, but this is a special case.)
- (void)logout;

- (void)cancel;

/// Decided to leave this for debugging.
- (NSString *)_debugNameForState:(UploadControllerState)state;

@end

@protocol OUIUploadControllerDelegate <NSObject>

@required
- (void)uploadController:(OUIUploadController *)uploadController didTransitionFromState:(UploadControllerState)fromState toState:(UploadControllerState)toState;

- (void)uploadControllerIsCheckingCredentials:(OUIUploadController *)uploadController;

- (void)uploadController:(OUIUploadController *)uploadController awaitingLoginCredentialWithHandler:(UploadControllerLoginCredentialHandler)loginHandler;
- (void)uploadController:(OUIUploadController *)uploadController failedLoginWithError:(NSError *)error;

/// Data will be zipped before uploading.
- (void)uploadController:(OUIUploadController *)uploadController awaitingUploadWithHandler:(UploadControllerUploadHandler)uploadHandler;
- (void)uploadController:(OUIUploadController *)uploadController didFailUploadWithError:(NSError *)error;
- (void)uploadControllerDidFinishUploading:(OUIUploadController *)uploadController;


@end
