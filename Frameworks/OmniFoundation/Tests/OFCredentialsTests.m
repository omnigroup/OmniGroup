// Copyright 2010-2013 The Omni Group. All rights reserved.
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
    STAssertEqualObjects(identifier, @"https://www.foo.com|user|realm", nil);
}

- (void)testReadMissingCredentials;
{
    NSError *error;
    NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(@"xxx", &error);
    STAssertNil(credential, nil);
    STAssertTrue([error hasUnderlyingErrorDomain:OFCredentialsErrorDomain code:OFCredentialsErrorNotFound], nil);
}

- (void)testDeleteMissingCredentials;
{
    STAssertTrue(OFDeleteCredentialsForServiceIdentifier(@"xxx", NULL), nil);
}

- (void)testWriteAndReadCredential;
{
    NSString *password = OFXMLCreateID();
    STAssertTrue(OFWriteCredentialsForServiceIdentifier(_serviceIdentifier, @"user", password, NULL), nil);
    NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(_serviceIdentifier, NULL);
    STAssertEqualObjects(credential.user, @"user", nil);
    STAssertEqualObjects(credential.password, password, nil);
}

- (void)testUpdateCredential;
{
    NSString *password1 = OFXMLCreateID();
    STAssertTrue(OFWriteCredentialsForServiceIdentifier(_serviceIdentifier, @"user", password1, NULL), nil);

    NSURLCredential *credential1 = OFReadCredentialsForServiceIdentifier(_serviceIdentifier, NULL);
    STAssertEqualObjects(credential1.user, @"user", nil);
    STAssertEqualObjects(credential1.password, password1, nil);

    NSString *password2 = OFXMLCreateID();
    STAssertTrue(OFWriteCredentialsForServiceIdentifier(_serviceIdentifier, @"user", password2, NULL), nil);
    
    NSURLCredential *credential2 = OFReadCredentialsForServiceIdentifier(_serviceIdentifier, NULL);
    STAssertEqualObjects(credential2.user, @"user", nil);
    STAssertEqualObjects(credential2.password, password2, nil);
}

- (void)testDeleteCredential;
{
    STAssertTrue(OFWriteCredentialsForServiceIdentifier(_serviceIdentifier, @"user", @"password", NULL), nil);
    STAssertTrue(OFDeleteCredentialsForServiceIdentifier(_serviceIdentifier, NULL), nil);
    
    NSError *error;
    NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(_serviceIdentifier, &error);
    STAssertNil(credential, nil);
    STAssertTrue([error hasUnderlyingErrorDomain:OFCredentialsErrorDomain code:OFCredentialsErrorNotFound], nil);
}

@end
