// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIWebDAVConnection.h"

#import <OmniUI/OUIAppController.h>
#import "OUICredentials.h"
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>

RCS_ID("$Id$")

NSString * const OUICertificateTrustUpdated = @"OUICertificateTrustUpdated";

@implementation OUIWebDAVConnection

static OUIWebDAVConnection *_sharedConnection;

+ (OUIWebDAVConnection *)sharedConnection;
{
    if (!_sharedConnection) {
        _sharedConnection = [[OUIWebDAVConnection alloc] init];
    }
    
    return _sharedConnection;
}

- (void)dealloc;
{
    [_address release];
    [_username release];
    [_fileManager release];
    [_password release];
    [_authenticationChallenge release];
    [_certAlert release];

    [super dealloc];
}

- (OUIWebDAVConnectionValidity)validateConnection;
{
    if (!_address || [NSString isEmptyString:_username])
        return OUIWebDAVConnectionNotConfigured;  // dont want to display an alert in this case since we are not even setup
    
    NSError *outError = nil;
    [OFSDAVFileManager setAuthenticationDelegate:self];
    OFSFileManager *newFileManager = [[[OFSFileManager alloc] initWithBaseURL:_address error:&outError] autorelease];
    [_fileManager release];
    _fileManager = nil;
    if (!newFileManager || outError) {
        OUI_PRESENT_ALERT(outError);    
        return OUIWebDAVOtherConnectionError;
    }
    
    // TODO: simpler, quicker way to authenticate?
    [newFileManager fileInfoAtURL:_address error:&outError];    // just here to tickle authentication
    if (_certAlert) {
        return OUIWebDAVCertificateTrustIssue;
    } else if (outError) {
        OUI_PRESENT_ALERT(outError);
        if (outError.domain == NSURLErrorDomain && outError.code == NSURLErrorNotConnectedToInternet)
            return OUIWebDAVNoInternetConnection;
        else
            return OUIWebDAVOtherConnectionError;
    }
    
    _fileManager = [newFileManager retain];
    return OUIWebDAVConnectionValid;
}

- (void)close;
{
    [_fileManager release];
    _fileManager = nil;
    [_address release];
    _address = nil;
    [_username release];
    _username = nil;
    [_password release];
    _password = nil;
    
    [_authenticationChallenge release];
    _authenticationChallenge = nil;
    [_certAlert release];
    _certAlert = nil;
}

- (BOOL)trustAlertVisible;
{
    return _certAlert != nil;
}

#pragma mark OFSDAVFileManagerDelegate
- (NSURLCredential *)DAVFileManager:(OFSDAVFileManager *)manager findCredentialsForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
    if (_username && _password) {        
        OUIWriteCredentialsForProtectionSpace(_username, _password, protectionSpace);
        [_password release];
        _password = nil;
    }
    
    [_authenticationChallenge release];
    _authenticationChallenge = nil;
    
    _authenticationChallenge = [[NSURLAuthenticationChallenge alloc] initWithAuthenticationChallenge:challenge sender:nil];
    
    return OUIReadCredentialsForChallenge(challenge);
}

- (void)DAVFileManager:(OFSDAVFileManager *)manager validateCertificateForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    OBASSERT(_certAlert == nil);
    _certAlert = [[OUICertificateTrustAlert alloc] initWithDelegate:self forChallenge:challenge];
    [_certAlert show];
}

#pragma mark OUICertificateTrustAlertDelegate
- (void)certificateTrustAlert:(OUICertificateTrustAlert *)alert didDismissWithButtonIndex:(NSInteger)buttonIndex challenge:(NSURLAuthenticationChallenge *)challenge;
{
    switch (buttonIndex) {
        case 0: /* Cancel */
            break;
            
        case 1: /* Continue */
        {
            [OFSDAVFileManager setTrustedHost:[[challenge protectionSpace] host]];
            [_certAlert release];
            _certAlert = nil;
            
            [[NSNotificationCenter defaultCenter] postNotificationName:OUICertificateTrustUpdated object:nil];

            break;
        }
        case 2: /* Trust always */
        {
            [OFSDAVFileManager setTrustedHost:[[challenge protectionSpace] host]];
            [[OFPreferenceWrapper sharedPreferenceWrapper] setObject:[[challenge protectionSpace] host] forKey:OFSTrustedSyncHostPreference];
            [_certAlert release];
            _certAlert = nil;
            
            [[NSNotificationCenter defaultCenter] postNotificationName:OUICertificateTrustUpdated object:nil];

            break;
        }
        default:
            break;
    }
}

@synthesize address = _address;
@synthesize username = _username;
@synthesize password = _password;
@synthesize fileManager = _fileManager;
@synthesize authenticationChallenge = _authenticationChallenge;
@end
