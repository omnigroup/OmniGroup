// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXDAVServerAccountValidator.h"

#import <OmniFileExchange/OFXAgent.h>
#import <OmniFileStore/OFSDAVConformanceTest.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/Errors.h>

#import <OmniFoundation/OFCredentials.h>

#import "OFXServerAccount-Internal.h"

RCS_ID("$Id$")

@interface OFXDAVServerAccountValidator () <OFSFileManagerDelegate>
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
    _validationOperationQueue.name = @"OFXDAVServerAccountValidator operation queue";
    
    _state = NSLocalizedStringFromTableInBundle(@"Validating Account...", @"OmniFileExchange", OMNI_BUNDLE, @"Account validation step description");
    
    return self;
}


#pragma mark - OFXServerAccountValidator

// Protocol properties aren't auto-synthesized
@synthesize account = _account;
@synthesize state = _state;
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
    
    [_validationOperationQueue addOperationWithBlock:^{
        NSURL *address = _account.remoteBaseURL;
        __autoreleasing NSError *error = nil;

        if (!address) {
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

        OFSDAVFileManager *fileManager = [[OFSDAVFileManager alloc] initWithBaseURL:address delegate:self error:&error];
        if (!fileManager) {
            finishWithError(error);
        }
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self _updateState:NSLocalizedStringFromTableInBundle(@"Checking Credentials", @"OmniFileExchange", OMNI_BUNDLE, @"Account validation step description")];
        }];
        error = nil;
        OFSFileInfo *fileInfo = [fileManager fileInfoAtURL:address error:&error];
        
        if (!fileInfo) {
            if (_certificateTrustError) {
                finishWithError(_certificateTrustError);
            }
            finishWithError(error);
        }

        if (!fileInfo.exists) {
            OFXError(&error, OFXServerAccountNotConfigured,
                     NSLocalizedStringFromTableInBundle(@"Server location not found", @"OmniFileExchange", OMNI_BUNDLE, @"account validation error description"),
                     NSLocalizedStringFromTableInBundle(@"This location does not appear to exist in the cloud.", @"OmniFileExchange", OMNI_BUNDLE, @"account validation error suggestion"));
            finishWithError(error);
        }

        // Store the credentials so the conformance tests will work. Also, update the credentials to have session persistence so that we don't get zillions of auth challenges while running conformance checks.
        _credentialsAccepted = YES;
        _attemptCredential = [NSURLCredential credentialWithUser:_username password:_password persistence:NSURLCredentialPersistenceForSession];

        if (_challengeServiceIdentifier) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [_account _storeCredential:_attemptCredential forServiceIdentifier:_challengeServiceIdentifier];
            }];
        } else {
            // This can happen when tests add two accounts and validation succeeds due to NSURLConnection's connection/credential cache. In this case, the test case copies the service identifier to the second account. Terrible.
            //OBASSERT(NO);
        }
        
        // Dispatch to the main queue so that any possible credential adding is done.
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (!_account.isCloudSyncEnabled || _shouldSkipConformanceTests) {
                finishWithError(nil);
            }
            
            [_validationOperationQueue addOperationWithBlock:^{
                
                // An additional test before starting the real validation - check for creation of the OmniPresence folder
                NSURL *remoteSyncDirectory = [_account.remoteBaseURL URLByAppendingPathComponent:@".com.omnigroup.OmniPresence" isDirectory:YES];
                NSError *error;
                if (![fileManager createDirectoryAtURLIfNeeded:remoteSyncDirectory error:&error]) {
                    finishWithError(error);
                }

                if (_challengeServiceIdentifier == nil) {
                    __autoreleasing NSError *noCredentialsError;
                    OFXError(&noCredentialsError, OFXServerAccountNotConfigured,
                             NSLocalizedStringFromTableInBundle(@"Account not configured", @"OmniFileExchange", OMNI_BUNDLE, @"account validation error description"),
                             NSLocalizedStringFromTableInBundle(@"Unable to verify login credentials at this time.", @"OmniFileExchange", OMNI_BUNDLE, @"account validation error suggestion"));
                    finishWithError(noCredentialsError);
                }

                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    OFSDAVConformanceTest *conformanceTest = [[OFSDAVConformanceTest alloc] initWithFileManager:fileManager];
                    conformanceTest.statusChanged = ^(NSString *status){
                        OBASSERT([NSThread isMainThread]);
                        [self _updateState:status];
                    };
                    conformanceTest.finished = ^(NSError *errorOrNil){
                        OBASSERT([NSThread isMainThread]);
                        
                        // Don't leave speculatively added credentials around
                        if (errorOrNil && _challengeServiceIdentifier)
                            OFDeleteCredentialsForServiceIdentifier(_challengeServiceIdentifier);
                        finishWithError(errorOrNil);
                    };
                    [self _updateState:NSLocalizedStringFromTableInBundle(@"Testing Server for Compatibility", @"OmniFileExchange", OMNI_BUNDLE, @"Account validation step description")];
                    [conformanceTest start];
                }];
            }];
        }];
    }];
}

#pragma mark - OFSFileManagerDelegate

- (BOOL)fileManagerShouldAllowCellularAccess:(OFSFileManager *)manager;
{
    return YES; // We could test +[OFXAgent isCellularSyncEnabled] here, but the user doesn't even see the "Use Cellular Data" switch until they've validated an account.
}

- (BOOL)fileManagerShouldUseCredentialStorage:(OFSFileManager *)manager;
{
    // We want to be challenged at least once so we can store the service identifier. But while we are running the WebDAV checks, go ahead and use the credential storage.
    return _credentialsAccepted;
}

- (NSURLCredential *)fileManager:(OFSFileManager *)manager findCredentialsForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    if (_credentialsAccepted)
        return _attemptCredential;
    
    if (_challengeServiceIdentifier) {
        // We've been challenged before and presumably failed if we are being called again
        return nil;
    }
    
    _challengeServiceIdentifier = [OFMakeServiceIdentifier(_account.remoteBaseURL, _username, challenge.protectionSpace.realm) copy];
    
    // Might have old bad credentials, or even existing valid credentials. But we were given a user name and password to use, so we should use them.
    OFDeleteCredentialsForServiceIdentifier(_challengeServiceIdentifier);

    return _attemptCredential;
}

- (void)fileManager:(OFSFileManager *)manager validateCertificateForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    _certificateTrustError = [NSError certificateTrustErrorForChallenge:challenge];
}

#pragma mark - Private

- (void)_updateState:(NSString *)state;
{
    OBASSERT([NSThread isMainThread]);

    _state = [state copy];
    if (_stateChanged)
        _stateChanged(self);
}

@end
