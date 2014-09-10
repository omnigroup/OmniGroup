// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXDAVServerAccountValidator.h"

#import <OmniDAV/ODAVConformanceTest.h>
#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVFeatures.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniFileExchange/OFXAgent.h>

#import <OmniFoundation/OFCredentials.h>

#import "OFXServerAccount-Internal.h"

RCS_ID("$Id$")

@interface OFXDAVServerAccountValidator ()
@end

@implementation OFXDAVServerAccountValidator
{
    NSString *_username;
    NSString *_password;
    NSOperationQueue *_validationOperationQueue;
    
    NSError *_certificateTrustError;

    BOOL _credentialsAccepted;
    NSString *_challengeServiceIdentifier;
    NSURLCredential *_attemptCredential;
    
    ODAVConnection *_connection;
}

- initWithAccount:(OFXServerAccount *)account username:(NSString *)username password:(NSString *)password;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == [NSOperationQueue mainQueue]); // We call the validation handler on the main queue for now; we could record the originating queue if that turns out to be useful
    OBPRECONDITION(account);
    OBPRECONDITION(![NSString isEmptyString:username]);
    OBPRECONDITION(![NSString isEmptyString:password]); // We assert on unsecured WebDAV credentials, but they should work below.
    
    if (!(self = [super init]))
        return nil;
    
    _account = account;
    _username = [username copy];
    _password = [password copy];
    
    _validationOperationQueue = [[NSOperationQueue alloc] init];
    _validationOperationQueue.maxConcurrentOperationCount = 1;
    _validationOperationQueue.name = @"OFXDAVServerAccountValidator operation queue";
    
    _state = NSLocalizedStringFromTableInBundle(@"Validating Account...", @"OmniFileExchange", OMNI_BUNDLE, @"Account validation step description");
    
    // We could leave this as is (set from +[OFXAgent isCellularSyncEnabled]) here, but the user doesn't even see the "Use Cellular Data" switch until they've validated an account.
    ODAVConnectionConfiguration *configuration = [OFXAgent makeConnectionConfiguration];
    configuration.allowsCellularAccess = YES;

    _connection = [[ODAVConnection alloc] initWithSessionConfiguration:configuration];
    
    __weak OFXDAVServerAccountValidator *weakSelf = self;
    
    // This gets called on an anonymous queue, so we need to serialize access to our state
    _connection.validateCertificateForChallenge = ^(NSURLAuthenticationChallenge *challenge){
        OFXDAVServerAccountValidator *stongSelf = weakSelf;
        if (!stongSelf)
            return;
        stongSelf->_certificateTrustError = [NSError certificateTrustErrorForChallenge:challenge];
    };
    _connection.findCredentialsForChallenge = ^NSURLCredential *(NSURLAuthenticationChallenge *challenge){
        OFXDAVServerAccountValidator *stongSelf = weakSelf;
        if (!stongSelf)
            return nil;
        return [stongSelf _findCredentialsForChallenge:challenge];
    };
    
    return self;
}

#pragma mark - OFXServerAccountValidator

// Protocol properties aren't auto-synthesized
@synthesize account = _account;
@synthesize state = _state;
@synthesize percentDone = _percentDone;
@synthesize errors = _errors;
@synthesize stateChanged = _stateChanged;
@synthesize finished = _finished;
@synthesize shouldSkipConformanceTests = _shouldSkipConformanceTests;

static void _finishWithError(OFXDAVServerAccountValidator *self, NSError *error)
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        // Break possible retain cycles
        typeof(self->_finished) finished = self->_finished;
        
        self->_finished = nil;
        self->_stateChanged = nil;
        [self->_account reportError:error];
        
        if (finished)
            finished(error);
        
        OBStrongRelease(self); // Matching retain at the top of -startValidation
    }];
    
}

#define finishWithError(err) do { \
    _finishWithError(self, err); \
    return; \
} while (0)

- (void)startValidation;
{
    OBStrongRetain(self); // Hard retain ourselves until the end of the operation (even when we switch to ARC)
    
    [_account clearError];
    
    __autoreleasing NSError *error = nil;
    
    if (!_account.remoteBaseURL) {
        OFXError(&error, OFXServerAccountNotConfigured,
                 NSLocalizedStringFromTableInBundle(@"Account not configured", @"OmniFileExchange", OMNI_BUNDLE, @"account validation error description"),
                 NSLocalizedStringFromTableInBundle(@"Please enter an address for the account.", @"OmniFileExchange", OMNI_BUNDLE, @"account validation error suggestion"));
        finishWithError(error);
    }
    if ([NSString isEmptyString:_username]) {
        OFXError(&error, OFXServerAccountNotConfigured,
                 NSLocalizedStringFromTableInBundle(@"Account not configured", @"OmniFileExchange", OMNI_BUNDLE, @"account validation error description"),
                 NSLocalizedStringFromTableInBundle(@"Please enter an username for the account.", @"OmniFileExchange", OMNI_BUNDLE, @"account validation error suggestion"));
        finishWithError(error);
    }

    _credentialsAccepted = NO;
    _attemptCredential = [NSURLCredential credentialWithUser:_username password:_password persistence:NSURLCredentialPersistenceNone];
    
    [self _checkCredentials];
}

#pragma mark - Private

- (void)_updateState:(NSString *)state percentDone:(double)percentDone;
{
    OBASSERT([NSThread isMainThread]);

    // We don't currently show the messages from the tests since it is too flashy.
    _state = NSLocalizedStringFromTableInBundle(@"Testing Server for Compatibility", @"OmniFileExchange", OMNI_BUNDLE, @"Account validation step description");
    //_state = [state copy];
    
    _percentDone = percentDone;
    
    if (_stateChanged)
        _stateChanged(self);
}

- (void)_checkCredentials;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == [NSOperationQueue mainQueue]);
    
    [self _updateState:NSLocalizedStringFromTableInBundle(@"Checking Credentials", @"OmniFileExchange", OMNI_BUNDLE, @"Account validation step description") percentDone:0];
    
    [_validationOperationQueue addOperationWithBlock:^{
        [_connection fileInfoAtURL:_account.remoteBaseURL ETag:nil completionHandler:^(ODAVSingleFileInfoResult *result, NSError *error) {
            OBASSERT([NSOperationQueue currentQueue] == _validationOperationQueue);
            
            ODAVFileInfo *fileInfo = result.fileInfo;
            if (!fileInfo) {
                if (_certificateTrustError) {
                    finishWithError(_certificateTrustError);
                }
                finishWithError(error);
            }
            
            if (!fileInfo.exists) {
                // Credentials worked out, but the specified URL doesn't exist (wrong path w/in the account possibly). Build a 404 as the base error (since this signals the UI that it shouldn't offer to report the error to support -- we can't do anything about it).
                
                __autoreleasing NSError *fileMissingError = [NSError errorWithDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND userInfo:nil];
                OFXError(&fileMissingError, OFXServerAccountLocationNotFound,
                         NSLocalizedStringFromTableInBundle(@"Server location not found", @"OmniFileExchange", OMNI_BUNDLE, @"account validation error description"),
                         NSLocalizedStringFromTableInBundle(@"Please check that the account information you entered is correct.", @"OmniFileExchange", OMNI_BUNDLE, @"account validation error suggestion"));
                finishWithError(fileMissingError);
            }
            
            // Store the credentials so the conformance tests will work. Also, update the credentials to have session persistence so that we don't get zillions of auth challenges while running conformance checks.
            _credentialsAccepted = YES;
            _attemptCredential = [NSURLCredential credentialWithUser:_username password:_password persistence:NSURLCredentialPersistenceForSession];
            
            if (_challengeServiceIdentifier) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [_account _storeCredential:_attemptCredential forServiceIdentifier:_challengeServiceIdentifier];
                }];
            } else {
                OBASSERT_NOT_REACHED("We specified that the connection should not use credential storage, so it should have been challenged");
            }
            
            // Dispatch to the main queue so that any possible credential adding is done.
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (_account.usageMode != OFXServerAccountUsageModeCloudSync || _shouldSkipConformanceTests) {
                    finishWithError(nil);
                }
                [self _checkRemoteAccountDirectory];
            }];
        }];
    }];
}

- (void)_checkRemoteAccountDirectory;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == [NSOperationQueue mainQueue]);
    
    [_validationOperationQueue addOperationWithBlock:^{
        // An additional test before starting the real validation - check for creation of the OmniPresence folder
        NSURL *remoteSyncDirectory = [_account.remoteBaseURL URLByAppendingPathComponent:@".com.omnigroup.OmniPresence" isDirectory:YES];
        
        [_connection makeCollectionAtURLIfMissing:remoteSyncDirectory baseURL:_account.remoteBaseURL completionHandler:^(NSURL *resultURL, NSError *errorOrNil) {
            OBASSERT([NSOperationQueue currentQueue] == _validationOperationQueue);

            if (!resultURL)
                finishWithError(errorOrNil);
            
            if (_challengeServiceIdentifier == nil) {
                __autoreleasing NSError *noCredentialsError;
                OFXError(&noCredentialsError, OFXServerAccountNotConfigured,
                         NSLocalizedStringFromTableInBundle(@"Account not configured", @"OmniFileExchange", OMNI_BUNDLE, @"account validation error description"),
                         NSLocalizedStringFromTableInBundle(@"Unable to verify login credentials at this time.", @"OmniFileExchange", OMNI_BUNDLE, @"account validation error suggestion"));
                finishWithError(noCredentialsError);
            }
            
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self _checkConformance];
            }];
        }];
    }];
}

- (void)_checkConformance;
{
    OBPRECONDITION([NSOperationQueue currentQueue] == [NSOperationQueue mainQueue]);
    
    // ODAVConformanceTest uses its own background queue.
    
    ODAVConformanceTest *conformanceTest = [[ODAVConformanceTest alloc] initWithConnection:_connection baseURL:_account.remoteBaseURL];
    conformanceTest.statusChanged = ^(NSString *status, double percentDone){
        OBASSERT([NSThread isMainThread]);
        [self _updateState:status percentDone:percentDone];
    };
    conformanceTest.finished = ^(NSError *errorOrNil){
        OBASSERT([NSThread isMainThread]);
        
        // Don't leave speculatively added credentials around
        if (errorOrNil && _challengeServiceIdentifier) {
            OFDeleteCredentialsForServiceIdentifier(_challengeServiceIdentifier, NULL);
        }
        finishWithError(errorOrNil);
    };
    [self _updateState:nil percentDone:0];
    [conformanceTest start];
}

- (NSURLCredential *)_findCredentialsForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // This gets called on an anonymous queue, so we need to serialize access to our state
    // OBPRECONDITION([NSOperationQueue currentQueue] == _validationOperationQueue);
    
    if (_credentialsAccepted)
        return _attemptCredential;
    
    if (_challengeServiceIdentifier) {
        // We've been challenged before and presumably failed if we are being called again
        return nil;
    }
    
    _challengeServiceIdentifier = [OFMakeServiceIdentifier(_account.remoteBaseURL, _username, challenge.protectionSpace.realm) copy];
    
    // Might have old bad credentials, or even existing valid credentials. But we were given a user name and password to use, so we should use them.
    __autoreleasing NSError *deleteError;
    if (!OFDeleteCredentialsForServiceIdentifier(_challengeServiceIdentifier, &deleteError))
        [deleteError log:@"Error deleting credentials for service identifier %@", _challengeServiceIdentifier];
    
    return _attemptCredential;
}

@end
