// Copyright 2008-2015 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "ODAVConcreteTestCase.h"

#import "ODAVConnection-Subclass.h"

#import <OmniDAV/OmniDAV.h>

@interface ODAVNoCredentialsTestCase : ODAVConcreteTestCase
@end

@implementation ODAVNoCredentialsTestCase
{
    NSError *_setUpError;
}

- (void)testExpectedError;
{
    XCTAssertNotNil(_setUpError);
    XCTAssertTrue([_setUpError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_UNAUTHORIZED]);
}

- (void)setUp;
{
    _setUpError = nil;
    [super setUp];
}

// It is hard/impossible to get NSURLConnection and NSURLSession to dump their live connections, so we capture the error from -setUp.
- (void)handleSetUpError:(NSError *)error message:(NSString *)message;
{
    _setUpError = error;
}

- (NSURLCredential *)accountCredentialWithPersistence:(NSURLCredentialPersistence)persistence;
{
    return nil;
}

@end

// Sadly, this test only works if it is the first one run, since NSURLConnection/NSURLSession make https connections and reuse them. We don't have a good way to force it to close them so that we get a certificate challenge again. This does work when run directly as the only (first) test.
#if 0
@interface ODAVNoCertificateTestCase : ODAVConcreteTestCase
@end

@implementation ODAVNoCertificateTestCase
{
    NSError *_setUpError;
}

- (void)testExpectedError;
{
    XCTAssertNotNil(_setUpError);
    XCTAssertTrue([_setUpError hasUnderlyingErrorDomain:NSURLErrorDomain code:NSURLErrorServerCertificateUntrusted]);
}

- (void)setUp;
{
    _setUpError = nil;
    
    [super setUp];
}

// It is hard/impossible to get NSURLConnection and NSURLSession to dump their live connections, so we capture the error from -setUp.
- (void)handleSetUpError:(NSError *)error message:(NSString *)message;
{
    _setUpError = error;
}

// This assumes that we are running the test against a server with a self-signed certificate that gets passed back to our validateCertificateForChallenge
- (BOOL)shouldAddTrustForCertificateChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    return NO;
}

@end
#endif
