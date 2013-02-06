// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniBase/rcsid.h>

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
    [_serviceIdentifier release];
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
    NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(@"xxx");
    STAssertNil(credential, nil);
}

- (void)testDeleteMissingCredentials;
{
    OFDeleteCredentialsForServiceIdentifier(@"xxx");
}

- (void)testWriteAndReadCredential;
{
    NSString *password = [OFXMLCreateID() autorelease];
    OFWriteCredentialsForServiceIdentifier(_serviceIdentifier, @"user", password);
    NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(_serviceIdentifier);
    STAssertEqualObjects(credential.user, @"user", nil);
    STAssertEqualObjects(credential.password, password, nil);
}

- (void)testUpdateCredential;
{
    NSString *password1 = [OFXMLCreateID() autorelease];
    OFWriteCredentialsForServiceIdentifier(_serviceIdentifier, @"user", password1);

    NSURLCredential *credential1 = OFReadCredentialsForServiceIdentifier(_serviceIdentifier);
    STAssertEqualObjects(credential1.user, @"user", nil);
    STAssertEqualObjects(credential1.password, password1, nil);

    NSString *password2 = [OFXMLCreateID() autorelease];
    OFWriteCredentialsForServiceIdentifier(_serviceIdentifier, @"user", password2);
    
    NSURLCredential *credential2 = OFReadCredentialsForServiceIdentifier(_serviceIdentifier);
    STAssertEqualObjects(credential2.user, @"user", nil);
    STAssertEqualObjects(credential2.password, password2, nil);
}

- (void)testDeleteCredential;
{
    OFWriteCredentialsForServiceIdentifier(_serviceIdentifier, @"user", @"password");
    OFDeleteCredentialsForServiceIdentifier(_serviceIdentifier);
    
    NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(_serviceIdentifier);
    STAssertNil(credential, nil);
}

@end
