// Copyright 2008-2015 Omni Development, Inc. All rights reserved.
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
#import <OmniFoundation/OFXMLIdentifier.h>

@implementation ODAVConcreteTestCase

- (void)setUp;
{
    [super setUp];
    
    NSURL *remoteBaseURL = self.accountRemoteBaseURL;
    
    __weak ODAVConcreteTestCase *weakSelf = self;
    
    _connection = [[ODAVConnection alloc] init];
    _connection.validateCertificateForChallenge = ^(NSURLAuthenticationChallenge *challenge){
        // Trust all certificates for these tests.
        OFAddTrustForChallenge(challenge, OFCertificateTrustDurationSession);
    };
    _connection.findCredentialsForChallenge = ^NSURLCredential *(NSURLAuthenticationChallenge *challenge){
        if ([challenge previousFailureCount] <= 2) {
            NSURLCredential *credential = [weakSelf accountCredentialWithPersistence:NSURLCredentialPersistenceForSession];
            OBASSERT(credential);
            return credential;
        }
        return nil;
    };
    
    // Make sure we start with a clean directory. Use a unique id in case we are testing locks (where we have to restart the server or wait for the lock to timeout).
    
    NSString *testName = self.name;
    if ([testName containsString:@"Lock"])
        testName = [testName stringByAppendingFormat:@"-%@", OFXMLCreateID()];
    
    NSURL *testDirectory = [remoteBaseURL URLByAppendingPathComponent:testName isDirectory:YES];

    __autoreleasing NSError *error;
    if (![_connection synchronousDeleteURL:testDirectory withETag:nil error:&error]) {
        if (![error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND]) {
            [error log:@"Error removing base URL %@", testDirectory];
            [NSException raise:NSGenericException format:@"Test can't continue"];
        }
    }
    
    error = nil;
    ODAVURLResult *createResult = [_connection synchronousMakeCollectionAtURL:testDirectory error:&error];
    if (!createResult) {
        [error log:@"Error creating base URL %@", testDirectory];
        [NSException raise:NSGenericException format:@"Test can't continue"];
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

@end
