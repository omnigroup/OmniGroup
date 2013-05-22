// Copyright 2008-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFSDAVTestCase.h"

#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/OFRandom.h>

@implementation OFSDAVTestCase

- (void)setUp;
{
    [super setUp];
    
    NSURL *remoteBaseURL = self.accountRemoteBaseURL;
    
    __autoreleasing NSError *error;
    OFSDAVFileManager *fileManager = [[OFSDAVFileManager alloc] initWithBaseURL:remoteBaseURL delegate:self error:&error];
    OBShouldNotError(fileManager);
    STAssertTrue([fileManager isKindOfClass:[OFSDAVFileManager class]], @"Wrong URL scheme");
    
    // Make sure we start with a clean directory. Use a unique id in case we are testing locks (where we have to restart the server or wait for the lock to timeout).
    NSString *testName = self.name;
    if ([testName containsString:@"Lock"])
        testName = [testName stringByAppendingFormat:@"-%@", OFXMLCreateID()];
    
    NSURL *testDirectory = [remoteBaseURL URLByAppendingPathComponent:testName isDirectory:YES];

    error = nil;
    if (![fileManager deleteURL:testDirectory error:&error]) {
        STAssertTrue([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_NOT_FOUND], nil);
    }

    error = nil;
    _remoteBaseURL = [fileManager createDirectoryAtURL:testDirectory attributes:nil error:&error];
    if (!_remoteBaseURL) {
        NSLog(@"Error creating base URL %@: %@", testDirectory, [error toPropertyList]);
        [NSException raise:NSGenericException format:@"Test can't continue"];
    }

    // Recreate the real file manager with the per-test base directory.
    _fileManager = [[OFSDAVFileManager alloc] initWithBaseURL:_remoteBaseURL delegate:self error:&error];
}

- (void)tearDown;
{
    _fileManager = nil;
    
    [super tearDown];
}

#pragma mark - OFSFileManagerDelegate

- (NSURLCredential *)fileManager:(OFSFileManager *)manager findCredentialsForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    if ([challenge previousFailureCount] <= 2) {
        NSURLCredential *credential = [self accountCredentialWithPersistence:NSURLCredentialPersistenceForSession];
        OBASSERT(credential);
        return credential;
    }
    return nil;
}

- (void)fileManager:(OFSFileManager *)manager validateCertificateForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // Trust all certificates for these tests.
    OFAddTrustForChallenge(challenge, OFCertificateTrustDurationSession);
}

@end
