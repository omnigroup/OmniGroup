// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFCredentialsTests :  OFTestCase
@end

@implementation OFCredentialsTests
{
    NSString *_serviceIdentifier;
}

- (void)setUp;
{
    _serviceIdentifier = [[self name] copy];
    [super setUp];
}

- (void)tearDown;
{
    _serviceIdentifier = nil;
    
    [super tearDown];
}

- (void)testMakeServiceIdentifier;
{
    NSString *identifier = OFMakeServiceIdentifier([NSURL URLWithString:@"https://www.foo.com"], @"user", @"realm");
    XCTAssertEqualObjects(identifier, @"https://www.foo.com|user|realm");
}

- (void)testReadMissingCredentials;
{
    NSError *error;
    NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(@"xxx", &error);
    XCTAssertNil(credential);
    XCTAssertTrue([error hasUnderlyingErrorDomain:OFCredentialsErrorDomain code:OFCredentialsErrorNotFound]);
}

- (void)testDeleteMissingCredentials;
{
    XCTAssertTrue(OFDeleteCredentialsForServiceIdentifier(@"xxx", NULL));
}

- (void)testWriteAndReadCredential;
{
    // Without this, our build servers need to have xctest allowed to access the entries from previous runs. Make sure we are the process that creates the entry.
    XCTAssertTrue(OFDeleteCredentialsForServiceIdentifier(_serviceIdentifier, NULL));

    NSString *password = OFXMLCreateID();
    XCTAssertTrue(OFWriteCredentialsForServiceIdentifier(_serviceIdentifier, @"user", password, NULL));
    NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(_serviceIdentifier, NULL);
    XCTAssertEqualObjects(credential.user, @"user");
    XCTAssertEqualObjects(credential.password, password);
}

- (void)testUpdateCredential;
{
    NSString *password1 = OFXMLCreateID();
    __autoreleasing NSError *error = nil;

    // Without this, our build servers need to have xctest allowed to access the entries from previous runs. Make sure we are the process that creates the entry.
    XCTAssertTrue(OFDeleteCredentialsForServiceIdentifier(_serviceIdentifier, NULL));

    OBShouldNotError(OFWriteCredentialsForServiceIdentifier(_serviceIdentifier, @"user", password1, &error));
    
    NSURLCredential *credential1;
    OBShouldNotError(credential1 = OFReadCredentialsForServiceIdentifier(_serviceIdentifier, &error));
    
    XCTAssertEqualObjects(credential1.user, @"user");
    XCTAssertEqualObjects(credential1.password, password1);

    NSString *password2 = OFXMLCreateID();
    OBShouldNotError(OFWriteCredentialsForServiceIdentifier(_serviceIdentifier, @"user", password2, &error));
    
    NSURLCredential *credential2;
    OBShouldNotError(credential2 = OFReadCredentialsForServiceIdentifier(_serviceIdentifier, &error));
    XCTAssertEqualObjects(credential2.user, @"user");
    XCTAssertEqualObjects(credential2.password, password2);
}

- (void)testDeleteCredential;
{
    XCTAssertTrue(OFWriteCredentialsForServiceIdentifier(_serviceIdentifier, @"user", @"password", NULL));
    XCTAssertTrue(OFDeleteCredentialsForServiceIdentifier(_serviceIdentifier, NULL));
    
    NSError *error;
    NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(_serviceIdentifier, &error);
    XCTAssertNil(credential);
    XCTAssertTrue([error hasUnderlyingErrorDomain:OFCredentialsErrorDomain code:OFCredentialsErrorNotFound]);
}

@end
