// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "ODAVConcreteTestCase.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFCredentialChallengeDispositionProtocol.h>
#import <OmniFoundation/OFXMLIdentifier.h>

@implementation ODAVConcreteTestCase

- (void)setUp;
{
    [super setUp];
    
    NSURL *remoteBaseURL = self.accountRemoteBaseURL;
    
    __weak ODAVConcreteTestCase *weakSelf = self;
    
    _connection = [[ODAVConnection alloc] initWithSessionConfiguration:[ODAVConnectionConfiguration new] baseURL:remoteBaseURL];
    _connection.validateCertificateForChallenge = ^NSURLCredential *(NSURLAuthenticationChallenge *challenge){
        if ([weakSelf shouldAddTrustForCertificateChallenge:challenge])
            OFAddTrustForChallenge(challenge, OFCertificateTrustDurationSession);
        if (OFHasTrustForChallenge(challenge)) {
            return [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
        } else
            return nil;
    };
    _connection.findCredentialsForChallenge = ^NSOperation <OFCredentialChallengeDisposition> *(NSURLAuthenticationChallenge *challenge){
        NSURLCredential *credential;
        if ([challenge previousFailureCount] <= 2) {
            credential = [weakSelf accountCredentialWithPersistence:NSURLCredentialPersistenceForSession];
        } else {
            credential = nil;
        }
        return OFImmediateCredentialResponse(NSURLSessionAuthChallengeUseCredential, credential);
    };
    
    // Make sure we start with a clean directory. Use a unique id in case we are testing locks (where we have to restart the server or wait for the lock to timeout).
    
    NSString *testName = self.name;
    if ([testName containsString:@"Lock"])
        testName = [testName stringByAppendingFormat:@"-%@", OFXMLCreateID()];
    
    NSURL *testDirectory = [remoteBaseURL URLByAppendingPathComponent:testName isDirectory:YES];

    __autoreleasing NSError *error;
    if (![_connection synchronousDeleteURL:testDirectory withETag:nil error:&error]) {
        if (![error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND]) {
            // Allow subclasses to override this, but we'll still bail in case our throwing version isn't called.
            [self handleSetUpError:error message:[NSString stringWithFormat:@"Error removing base URL %@", testDirectory]];
            return;
        }
    }
    
    error = nil;
    ODAVURLResult *createResult = [_connection synchronousMakeCollectionAtURL:testDirectory error:&error];
    if (!createResult) {
        [self handleSetUpError:error message:[NSString stringWithFormat:@"Error creating base URL %@", testDirectory]];
        return;
    }
    NSURL *createdDirectory = createResult.URL;
    
    if (self.shouldUseRedirectingRemoteBaseURL) {
        // createdDirectory will have been redirected already; use our original instead.
        createdDirectory = testDirectory;
    }
    
    _remoteBaseURL = createdDirectory;
}

- (void)tearDown;
{
    _connection = nil;
    
    [super tearDown];
}

- (void)handleSetUpError:(NSError *)error message:(NSString *)message;
{
    [error log:@"%@", message];
    [NSException raise:NSGenericException format:@"Test can't continue"];
}

@end
