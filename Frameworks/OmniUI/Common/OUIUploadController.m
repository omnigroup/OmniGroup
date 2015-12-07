// Copyright 2013 Omni Development, Inc.  All rights reserved.

#import <OmniUI/OUIUploadController.h>

#import <OmniFoundation/OFCredentials.h>

RCS_ID("$Id$")

//┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
//│                                                State Machine Table                                                │
//├─────────────────────────┬──────────────────────────┬─────────────────────────┬────────────────────────────────────┤
//│======Current State======│==========Input===========│=======Next State========│=Output (Always Notifies Delegate)==│
//├─────────────────────────┼──────────────────────────┼─────────────────────────┼────────────────────────────────────┤
//│         .Unset          │          -login          │  .CheckingCredentials   │                                    │
//├─────────────────────────┼──────────────────────────┼─────────────────────────┼────────────────────────────────────┤
//│                         │        Not Found         │       .LoggingIn        │                                    │
//│  .CheckingCredentials   ├──────────────────────────┼─────────────────────────┼────────────────────────────────────┤
//│                         │          Found           │      .LoggedInIdle      │                                    │
//├─────────────────────────┼──────────────────────────┼─────────────────────────┼────────────────────────────────────┤
//│       .LoggingIn        │      Validate Creds      │      .LoggedInIdle      │             Save Creds             │
//├─────────────────────────┼──────────────────────────┼─────────────────────────┼────────────────────────────────────┤
//│                         │       Receive Data       │       .Uploading        │            Start Upload            │
//│      .LoggedInIdle      ├──────────────────────────┼─────────────────────────┼────────────────────────────────────┤
//│                         │         -logout          │       .LoggingIn        │            Delete Creds            │
//├─────────────────────────┼──────────────────────────┼─────────────────────────┼────────────────────────────────────┤
//│                         │  Failed: Invalid Creds   │       .LoggingIn        │            Delete Creds            │
//│                         ├──────────────────────────┼─────────────────────────┼────────────────────────────────────┤
//│       .Uploading        │      Failed: Other       │      .LoggedInIdle      │                                    │
//│                         ├──────────────────────────┼─────────────────────────┼────────────────────────────────────┤
//│                         │     Upload Succeeded     │    .UploadSucceeded     │                                    │
//├─────────────────────────┼──────────────────────────┼─────────────────────────┼────────────────────────────────────┤
//│    .UploadSucceeded     │                          │          None           │                                    │
//└─────────────────────────┴──────────────────────────┴─────────────────────────┴────────────────────────────────────┘

#if 0 && defined(DEBUG)
#define DEBUG_UPLOADSTATEMACHINE(format, ...) NSLog(@"UPLOADSTATEMACHINE: " format, ## __VA_ARGS__)
#else
#define DEBUG_UPLOADSTATEMACHINE(format, ...)
#endif

// JCTODO: <bug:///124405> (Unassigned: Turn off DEBUG_UPLOADING() logging for release build)
#if 1 //&& defined(DEBUG)
#define DEBUG_UPLOADING(format, ...) NSLog(@"UPLOADING: " format, ## __VA_ARGS__)
#else
#define DEBUG_UPLOADING(format, ...)
#endif

NSString * const OUIUploadControllerErrorDomain = @"com.omnigroup.frameworks.OmniUI.OUIUploadController.ErrorDomain";

static NSString * const UploadLoginURLString = @"https://stenciltown.omnigroup.test/api/auth/v1/get_token/";
static NSString * const UploadFileUploadURLString = @"https://stenciltown.omnigroup.test/api/files/v1/upload/";

/*
static NSString * const UploadLoginURLString = @"https://stenciltown.omnigroup.com/api/auth/v1/get_token/";
static NSString * const UploadFileUploadURLString = @"https://stenciltown.omnigroup.com/api/files/v1/upload/";
*/

static NSString * const UploadCredentialServiceName = @"stenciltown-upload-token";
static NSString * const UploadCredentialUsername = @"stenciltown-upload-username";

static NSString * const UploadJSONTokenKey = @"token";
static NSString * const UploadJSONTokenTypeKey = @"token_type";
static NSString * const UploadJSONAccessTokenKey = @"access_token";
static NSString * const UploadJSONSucceededKey = @"success";

@interface OUIUploadController () <NSURLSessionDataDelegate>

@property (nonatomic, readwrite, assign) UploadControllerState state;
@property (readwrite, strong) NSProgress *progress;

@property (nonatomic, copy) NSString *userAgent;
@property (nonatomic, strong) NSURLSession *session;

// Keychain
@property (nonatomic, readonly) NSString *credentialsServiceIdentifier;

// Login
@property (nonatomic, strong) NSURLSessionDataTask *verifyLoginDataTask;

// Upload
@property (nonatomic, strong) NSData *fileData;
@property (nonatomic, copy) NSString *fileDataFileName;
@property (nonatomic, strong) NSData *previewData;
@property (nonatomic, strong) NSURLSessionUploadTask *fileUploadTask;

@end

@implementation OUIUploadController

- (instancetype)init
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (instancetype)initWithUserAgent:(NSString *)userAgent;
{
    self = [super init];
    if (self) {
        _userAgent = userAgent;
        _state = UploadControllerStateUnset;
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:nil];
        _progress = [NSProgress discreteProgressWithTotalUnitCount:1];
    }
    return self;
}

- (void)login;
{
    if (self.state == UploadControllerStateUnset) {
        [self _transitionFromState:self.state toState:UploadControllerStateCheckingCredentials];
    }
}

- (void)logout;
{
    if (self.state == UploadControllerStateLoggedInIdle) {
        [self _transitionFromState:self.state toState:UploadControllerStateLoggingIn];
    }
}

- (void)cancel;
{
    if (self.verifyLoginDataTask.state == NSURLSessionTaskStateRunning) {
        [self.verifyLoginDataTask cancel];
    }
    if (self.fileUploadTask.state == NSURLSessionTaskStateRunning) {
        [self.fileUploadTask cancel];
    }
}

#pragma mark Private API
- (NSString *)credentialsServiceIdentifier;
{
    static NSString *CredentialsServiceIdentifier;
    
    static dispatch_once_t CredentialsServiceIdentifierOnceToken;
    dispatch_once(&CredentialsServiceIdentifierOnceToken, ^{
        CredentialsServiceIdentifier = [NSString stringWithFormat:@"%@|%@", UploadLoginURLString, UploadCredentialServiceName];
    });

    return CredentialsServiceIdentifier;
}

#pragma mark Private State Machine
/// Caution!!! Only set the state if you know it to be a valid state transition. Currently this is ONLY done from the private State Transition methods.
- (void)setState:(UploadControllerState)state;
{
    if (_state == state) {
        return;
    }
    
    UploadControllerState oldState = _state;
    _state = state;
    
    [self.delegate uploadController:self didTransitionFromState:oldState toState:_state];
}

- (BOOL)_transitionFromState:(UploadControllerState)fromState toState:(UploadControllerState)toState;
{
    DEBUG_UPLOADSTATEMACHINE(@"transitioning from: %@ to %@", [self _debugNameForState:fromState], [self _debugNameForState:toState]);
    if ((fromState == UploadControllerStateUnset) && (toState == UploadControllerStateCheckingCredentials)) {
        [self _unsetToCheckingCredentials];
    }
    else if ((fromState == UploadControllerStateCheckingCredentials) && (toState == UploadControllerStateLoggingIn)) {
        [self _checkingCredentialsToLoggingIn];
    }
    else if ((fromState == UploadControllerStateCheckingCredentials) && (toState == UploadControllerStateLoggedInIdle)) {
        [self _checkingCredentialsToLoggedInIdle];
    }
    else if ((fromState == UploadControllerStateLoggingIn) && (toState == UploadControllerStateLoggedInIdle)) {
        [self _loggingInToLoggedInIdle];
    }
    else if ((fromState == UploadControllerStateLoggedInIdle) && (toState == UploadControllerStateUploading)) {
        [self _loggedInIdleToUploading];
    }
    else if ((fromState == UploadControllerStateLoggedInIdle) && (toState == UploadControllerStateLoggingIn)) {
        [self _loggedInIdleToLoggingIn];
    }
    else if ((fromState == UploadControllerStateUploading) && (toState == UploadControllerStateLoggingIn)) {
        [self _uploadingToLoggingIn];
    }
    else if ((fromState == UploadControllerStateUploading) && (toState == UploadControllerStateLoggedInIdle)) {
        [self _uploadingToLoggedInIdle];
    }
    else if ((fromState == UploadControllerStateUploading) && (toState == UploadControllerStateUploadSucceeded)) {
        [self _uploadingToUploadSucceeded];
    }
    else {
        // Invalid Transition
        return NO;
    }
    
    return YES;
}

- (NSString *)_debugNameForState:(UploadControllerState)state;
{
    switch (state) {
        case UploadControllerStateUnset:
            return @"Unset";
            break;
        case UploadControllerStateCheckingCredentials:
            return @"CheckingCredentials";
            break;
        case UploadControllerStateLoggingIn:
            return @"LoggingIn";
            break;
        case UploadControllerStateLoggedInIdle:
            return @"LoggedInIdle";
            break;
        case UploadControllerStateUploading:
            return @"Uploading";
            break;
        case UploadControllerStateUploadSucceeded:
            return @"UploadSucceeded";
            break;
    }
}

// State Transitions
- (void)_unsetToCheckingCredentials;
{
    self.state = UploadControllerStateCheckingCredentials;
    [self.delegate uploadControllerIsCheckingCredentials:self];
    
    NSURLCredential *credentials = [self _credentials];
    if (credentials == nil) {
        // We don't have credentials, need to login.
        [self _transitionFromState:self.state toState:UploadControllerStateLoggingIn];
    }
    else {
        // We have credentials, assume we're logged in.
        [self _transitionFromState:self.state toState:UploadControllerStateLoggedInIdle];
    }
}

- (void)_checkingCredentialsToLoggingIn;
{
    self.state = UploadControllerStateLoggingIn;
    [self.delegate uploadController:self awaitingLoginCredentialWithHandler:^(NSURLCredential *credential) {
        [self _verifyLoginCredentials:credential];
    }];
}

- (void)_checkingCredentialsToLoggedInIdle;
{
    self.state = UploadControllerStateLoggedInIdle;
    [self _resetProgress];
    [self.delegate uploadController:self awaitingUploadWithHandler:^(NSData *fileData, NSString *fileDataFileName, NSData *previewData) {
        self.fileData = fileData;
        self.fileDataFileName = fileDataFileName;
        self.previewData = previewData;
        [self _transitionFromState:self.state toState:UploadControllerStateUploading];
    }];
}

- (void)_loggingInToLoggedInIdle;
{
    self.state = UploadControllerStateLoggedInIdle;
    [self _resetProgress];
    [self.delegate uploadController:self awaitingUploadWithHandler:^(NSData *fileData, NSString *fileDataFileName, NSData *previewData) {
        self.fileData = fileData;
        self.fileDataFileName = fileDataFileName;
        self.previewData = previewData;
        [self _transitionFromState:self.state toState:UploadControllerStateUploading];
    }];
}

- (void)_loggedInIdleToUploading;
{
    self.state = UploadControllerStateUploading;
    OBASSERT(self.fileData != nil);
    OBASSERT(self.previewData != nil);
    
    [self _startUploadWithFileData:self.fileData previewData:self.previewData];
}

- (void)_loggedInIdleToLoggingIn;
{
    self.state = UploadControllerStateLoggingIn;

    [self _deleteCredentials];
    
    [self.delegate uploadController:self awaitingLoginCredentialWithHandler:^(NSURLCredential *credential) {
        [self _verifyLoginCredentials:credential];
    }];
}

- (void)_uploadingToLoggingIn;
{
    self.state = UploadControllerStateLoggingIn;
    [self _deleteCredentials];
    
    [self.delegate uploadController:self awaitingLoginCredentialWithHandler:^(NSURLCredential *credential) {
        [self _verifyLoginCredentials:credential];
    }];
}

- (void)_uploadingToLoggedInIdle;
{
    self.state = UploadControllerStateLoggedInIdle;
    [self _resetProgress];
    [self.delegate uploadController:self awaitingUploadWithHandler:^(NSData *fileData, NSString *fileDataFileName, NSData *previewData) {
        self.fileData = fileData;
        self.fileDataFileName = fileDataFileName;
        self.previewData = previewData;
        [self _transitionFromState:self.state toState:UploadControllerStateUploading];
    }];
}

- (void)_uploadingToUploadSucceeded;
{
    self.state = UploadControllerStateUploadSucceeded;
    [self.delegate uploadControllerDidFinishUploading:self];
}

#pragma mark Private Helpers
- (void)_resetProgress;
{
    self.progress.completedUnitCount = 0.0;
    self.progress.totalUnitCount = 1.0;
}

- (NSMutableURLRequest *)_mutablePOSTURLRequestWithURL:(NSURL *)url;
{
    NSMutableURLRequest *postRequest = [NSMutableURLRequest requestWithURL:url];
    [postRequest setHTTPMethod:@"POST"];
    [postRequest setValue:self.userAgent forHTTPHeaderField:@"User-Agent"];
    
    return postRequest;
}

/// Nil if not found in keychain.
- (NSURLCredential *)_credentials;
{
    NSError *credentialError = nil;
    NSURLCredential *credentials = OFReadCredentialsForServiceIdentifier(self.credentialsServiceIdentifier, &credentialError);
    if (credentials == nil) {
        [credentialError log:@"No credentials found with identifier %@", self.credentialsServiceIdentifier];
    }
    
    return credentials;
}

- (void)_deleteCredentials;
{
    __autoreleasing NSError *deleteCredentialsError = nil;
    BOOL deleteSucceeded = OFDeleteCredentialsForServiceIdentifier(self.credentialsServiceIdentifier, &deleteCredentialsError);
    if (deleteSucceeded == NO) {
        [deleteCredentialsError log:@"Error deleting credentials"];
    }
}

- (void)_verifyLoginCredentials:(NSURLCredential *)credentials;
{
    OBASSERT(self.verifyLoginDataTask == nil);
    
    NSString *postString = [NSString stringWithFormat:@"username=%@&password=%@", credentials.user, credentials.password];
    NSData *postData = [postString dataUsingEncoding:NSASCIIStringEncoding];
    
    NSMutableURLRequest *verifyLoginRequest = [self _mutablePOSTURLRequestWithURL:[NSURL URLWithString:UploadLoginURLString]];
    [verifyLoginRequest setHTTPBody:postData];

    self.verifyLoginDataTask = [self.session dataTaskWithRequest:verifyLoginRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable dataTaskError) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (dataTaskError != nil) {
                [self _loginFailedWithError:dataTaskError];
                return;
            }
            
            // Not necessarily logged in. Still need to check the response code.
            if (([response isKindOfClass:[NSHTTPURLResponse class]] == NO) || (((NSHTTPURLResponse *)response).statusCode != 200)) {
                NSDictionary *errorUserInfo = @{ NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Invalid username or password.",
                                                                                                                @"OmniUI", OMNI_BUNDLE,
                                                                                                                @"Invalid login credentials error description.")};
                NSError *loginInvalidError = [NSError errorWithDomain:OUIUploadControllerErrorDomain
                                                                 code:OUIUploadControllerErrorLoginFailedInvalid
                                                             userInfo:errorUserInfo];
                [self _loginFailedWithError:loginInvalidError];
                return;
            }
            
            NSError *jsonParseError = nil;
            NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonParseError];
            if ((responseDictionary == nil) || ([responseDictionary isKindOfClass:[NSDictionary class]] == NO)) {
                [self _loginFailedWithError:jsonParseError];
                return;
            }
            
            // JSON will be formatted like so:
            //{
            //    "token": {
            //        "token_type": "Bearer",
            //        "refresh_token": "xxxxxxx",
            //        "access_token": "xxxxxxx",
            //        "scope": [
            //                  "read",
            //                  "write"
            //                  ],
            //        "expires_in": 36000,
            //        "expires_at": 1447902619.973653
            //    }
            //}
            NSDictionary *tokenDictionary = responseDictionary[UploadJSONTokenKey];
            NSString *tokenType = tokenDictionary[UploadJSONTokenTypeKey];
            NSString *accessToken = tokenDictionary[UploadJSONAccessTokenKey];
            
            
            if ((tokenType == nil) || (accessToken == nil)) {
                [self _loginFailedWithError:jsonParseError];
                return;
            }
            
            NSString *authorizationString = [NSString stringWithFormat:@"%@ %@", tokenType, accessToken];
            
            NSError *writeCredentialsError = nil;
            if (OFWriteCredentialsForServiceIdentifier(self.credentialsServiceIdentifier, UploadCredentialUsername, authorizationString, &writeCredentialsError) == NO) {
                [self _loginFailedWithError:writeCredentialsError];
            }
            
            [self _transitionFromState:self.state toState:UploadControllerStateLoggedInIdle];
        }];
    }];
    [self.verifyLoginDataTask resume];
}

- (void)_loginFailedWithError:(NSError *)error;
{
   __autoreleasing NSError *loginError = error;
    
    if (error.domain != OUIUploadControllerErrorDomain) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Login failed.",
                                                                   @"OmniUI", OMNI_BUNDLE,
                                                                   @"Generic login failed error description.");
        OUIUploadControllerWrapError(&loginError, OUIUploadControllerErrorLoginFailedOther, description, nil /* reason */);
    }
    
    [self.delegate uploadController:self failedLoginWithError:loginError];
    [self.delegate uploadController:self awaitingLoginCredentialWithHandler:^(NSURLCredential *credential) {
        [self _verifyLoginCredentials:credential];
    }];

}

- (void)_uploadFailedWithError:(NSError *)error transitionTo:(UploadControllerState)toState;
{
    [self.delegate uploadController:self didFailUploadWithError:error];
    [self _transitionFromState:self.state toState:toState];
}

- (void)_startUploadWithFileData:(NSData *)fileData previewData:(NSData *)previewData;
{
    DEBUG_UPLOADING(@"checking for credentials");
    NSString *tokenString = nil;
    NSURLCredential *credentials = [self _credentials];
    if ((credentials != nil) && ([credentials.user isEqualToString:UploadCredentialUsername]) && [NSString isEmptyString:credentials.password] == NO) {
        DEBUG_UPLOADING(@"  found credentials; move on to uploading");
        // We have a token! Add it to the request.
        tokenString = credentials.password;
    }
    else {
        DEBUG_UPLOADING(@"  no credentials found; bail back to .LoggingIn");
        NSDictionary *errorUserInfo = @{ NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Invalid username or password.",
                                                                                                        @"OmniUI", OMNI_BUNDLE,
                                                                                                        @"Invalid login credentials error description.")};
        NSError *missingCredentialsError = [NSError errorWithDomain:OUIUploadControllerErrorDomain
                                                               code:OUIUploadControllerErrorCredentialsMissing
                                                           userInfo:errorUserInfo];
        
        [self.delegate uploadController:self didFailUploadWithError:missingCredentialsError];
        [self _transitionFromState:self.state toState:UploadControllerStateLoggingIn];
    }
    
    
    DEBUG_UPLOADING(@"creating upload request");
    NSString *multipartFormDataStringBoundry = @"__OMNIGROUP_UPLOAD_STRING-BOUNDRY__";
    
    NSMutableURLRequest *uploadRequest = [self _mutablePOSTURLRequestWithURL:[NSURL URLWithString:UploadFileUploadURLString]];
    [uploadRequest setValue:tokenString forHTTPHeaderField:@"Authorization"];
    [uploadRequest setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", multipartFormDataStringBoundry] forHTTPHeaderField:@"Content-Type"];
    
    
    DEBUG_UPLOADING(@"creating multipart post body data");
    NSMutableData *postBodyData = [NSMutableData data];
    
    // Add fileData
    [postBodyData appendData:[[NSString stringWithFormat:@"--%@\r\n", multipartFormDataStringBoundry] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBodyData appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\n", self.fileDataFileName] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBodyData appendData:[@"Content-Type: application/zip\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [postBodyData appendData:fileData];
    [postBodyData appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Add previewData
    [postBodyData appendData:[[NSString stringWithFormat:@"--%@\r\n", multipartFormDataStringBoundry] dataUsingEncoding:NSUTF8StringEncoding]];
    [postBodyData appendData:[@"Content-Disposition: form-data; name=\"preview\"; filename=\"preview.png\"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [postBodyData appendData:[@"Content-Type: image/png\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [postBodyData appendData:previewData];
    [postBodyData appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Final boundry
    [postBodyData appendData:[[NSString stringWithFormat:@"--%@--\r\n", multipartFormDataStringBoundry] dataUsingEncoding:NSUTF8StringEncoding]];
    
//    NSString *postBodyString = [[NSString alloc] initWithData:postBodyData encoding:NSUTF8StringEncoding];
//    DEBUG_UPLOADING(@"%@", postBodyString);
    
    
    DEBUG_UPLOADING(@"getting upload task from session");
    self.fileUploadTask = [self.session uploadTaskWithRequest:uploadRequest fromData:postBodyData completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            DEBUG_UPLOADING(@"upload completed");
            DEBUG_UPLOADING(@"  response: %@", response);
            if (data != nil) {
                NSString *resonseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                DEBUG_UPLOADING(@"  body:\r\n%@", resonseString);
            }
            
            if (error != nil) {
                DEBUG_UPLOADING(@"upload failed for a network reason");
                [error log:@"error uploading file"];
                [self _uploadFailedWithError:error transitionTo:UploadControllerStateLoggedInIdle];
                return;
            }
            
            OBASSERT([response isKindOfClass:[NSHTTPURLResponse class]] == YES);
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if (httpResponse.statusCode != 200) {
                DEBUG_UPLOADING(@"upload failed; assume credentials error.");
                
                NSDictionary *uploadErrorUserInfo = @{ NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Invalid username or password. Please try logging in again.",
                                                                                                                @"OmniUI", OMNI_BUNDLE,
                                                                                                                @"Invalid login credentials during upload error description.")};
                NSError *uploadError = [NSError errorWithDomain:OUIUploadControllerErrorDomain
                                                           code:OUIUploadControllerErrorUploading
                                                       userInfo:uploadErrorUserInfo];
                
                
                [uploadError log:@"error uploading file"];
                [self _uploadFailedWithError:uploadError transitionTo:UploadControllerStateLoggingIn];
                return;
            }
            
            NSError *jsonParseError = nil;
            NSDictionary *responseDictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonParseError];
            if ((responseDictionary == nil) || ([responseDictionary isKindOfClass:[NSDictionary class]] == NO)) {
                [self _uploadFailedWithError:jsonParseError transitionTo:UploadControllerStateLoggedInIdle];
                return;
            }
            
            // JSON will be formatted like so:
            //{
            //    ...
            //
            //    "success": true,
            //
            //    ...
            //}
            id succeededValue = responseDictionary[UploadJSONSucceededKey];
            BOOL succeeded = [succeededValue boolValue];

            if (succeeded == NO) {
                DEBUG_UPLOADING(@"upload failed; unexpected response from server");
                [self _uploadFailedWithError:nil transitionTo:UploadControllerStateLoggedInIdle]; // JCTODO: Need an error to pass in here.
                return;
            }
            
            DEBUG_UPLOADING(@"upload succeeded");
            [self _transitionFromState:self.state toState:UploadControllerStateUploadSucceeded];
        }];
    }];
    
    DEBUG_UPLOADING(@"starting upload");
    [self.fileUploadTask resume];
}

#pragma mark NSURLSessionDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential * __nullable credential))completionHandler;
{
    if (completionHandler) {
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    }
}

#pragma mark NSURLSessionTaskDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
{
    DEBUG_UPLOADING(@"did send data: %lld total sent, %lld total expected to send", task.countOfBytesSent, task.countOfBytesExpectedToSend);
    self.progress.totalUnitCount = task.countOfBytesExpectedToSend;
    self.progress.completedUnitCount = task.countOfBytesSent;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error;
{
    NSLog(@"session: %@ task: %@ didCompleteWithError: %@", session, task, error);
}
#pragma mark NSURLSessionDataDelegate



@end
