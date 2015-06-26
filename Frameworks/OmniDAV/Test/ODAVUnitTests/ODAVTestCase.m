// Copyright 2012-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ODAVTestCase.h"

#import <readpassphrase.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFUtilities.h>
#import <sys/socket.h>
#import <sys/types.h>
#import <netdb.h>

RCS_ID("$Id$")

NSString * const ODAVTestCaseRedirectSourceDirectoryName = @"redirect-src";
NSString * const ODAVTestCaseRedirectDestinationDirectoryName = @"redirect-dst";

@implementation ODAVTestCase
{
    NSString *_username;
    NSString *_password;
}

static NSUInteger NextUsernameNumber = 0;
static const NSUInteger UsernameCount = 100;

- (void)setUp;
{
    [super setUp];

    const char *env;
    
    if ((env = getenv("ODAVAccountUsername")))
        _username = [NSString stringWithUTF8String:env];
    if ([NSString isEmptyString:_username])
        [NSException raise:NSGenericException reason:@"ODAVAccountUsername not specified in environment"];
    _username = [_username stringByAppendingFormat:@"%ld", NextUsernameNumber];
    
    if ((env = getenv("ODAVAccountPassword")))
        _password = [NSString stringWithUTF8String:env];
    if ([NSString isEmptyString:_password])
        [NSException raise:NSGenericException reason:@"ODAVAccountPassword not specified in environment"];

    // This requires that subclasses call [super setUp] before they call -accountRemoteBaseURL or -accountCredentialWithPersistence:
    NextUsernameNumber++;
    if (NextUsernameNumber >= UsernameCount)
        NextUsernameNumber = 0;
}

- (void)tearDown;
{
    _username = nil;
    _password = nil;
    
    [super tearDown];
}

- (BOOL)shouldUseRedirectingRemoteBaseURL;
{
    const char *env = getenv("ODAVRedirectAccountRemoteBaseURL");
    if (env)
        return YES;
    
    return NO;
}

- (NSURL *)accountRemoteBaseURL;
{
    OBPRECONDITION(_username); // Only call after -setUp
    OBPRECONDITION(_password);

    const char *env = getenv("ODAVAccountRemoteBaseURL");
    if (!env)
        [NSException raise:NSGenericException format:@"ODAVAccountRemoteBaseURL must be set"];
    
    NSString *remoteBaseURLString = [NSString stringWithUTF8String:env];
    remoteBaseURLString = [remoteBaseURLString stringByReplacingOccurrencesOfString:@"LOCAL_HOST" withString:OFHostName()];

    NSURL *remoteBaseURL = [NSURL URLWithString:remoteBaseURLString];
    if (!remoteBaseURL)
        [NSException raise:NSGenericException format:@"ODAVAccountRemoteBaseURL set to an invalid URL"];
    
    remoteBaseURL = [remoteBaseURL URLByAppendingPathComponent:_username isDirectory:YES];
    
    if (self.shouldUseRedirectingRemoteBaseURL) {
        // Our Test/LocalWebDAVServer/StartServer script sets up each user to have this path redirect to redirect-dst
        remoteBaseURL = [remoteBaseURL URLByAppendingPathComponent:ODAVTestCaseRedirectSourceDirectoryName isDirectory:YES];
    }
    
    return remoteBaseURL;
}

- (NSURLCredential *)accountCredentialWithPersistence:(NSURLCredentialPersistence)persistence;
{
    OBPRECONDITION(_username); // Only call after -setUp
    OBPRECONDITION(_password);
    
    return [[NSURLCredential alloc] initWithUser:_username password:_password persistence:persistence];
}

- (BOOL)shouldAddTrustForCertificateChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // Trust all certificates for these tests.
    return YES;
}

@end

