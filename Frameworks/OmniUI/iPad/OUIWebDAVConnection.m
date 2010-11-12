// Copyright 2010 The Omni Group.  All rights reserved.
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

#import <OmniFoundation/NSString-OFSimpleMatching.h>

RCS_ID("$Id$")

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
    [_newKeychainPassword release];
    [_authenticationChallenge release];

    [super dealloc];
}


- (BOOL)validConnection;
{
    if (!_address || [NSString isEmptyString:_username])
        return NO;  // dont want to display an alert in this case since we are not even setup
    
    NSError *outError = nil;
    [OFSDAVFileManager setAuthenticationDelegate:self];
    OFSFileManager *newFileManager = [[[OFSFileManager alloc] initWithBaseURL:_address error:&outError] autorelease];
    [_fileManager release];
    _fileManager = nil;
    if (!newFileManager || outError) {
        OUI_PRESENT_ALERT(outError);    
        return NO;
    }
    
    // TODO: simpler, quicker way to authenticate?
    [newFileManager fileInfoAtURL:_address error:&outError];    // just here to tickle authentication
    if (outError) {
        OUI_PRESENT_ALERT(outError);
        return NO;
    }
    
    _fileManager = [newFileManager retain];
    return YES;
}

- (void)close;
{
    [_fileManager release];
    _fileManager = nil;
    [_address release];
    _address = nil;
    [_username release];
    _username = nil;
    [_newKeychainPassword release];
    _newKeychainPassword = nil;
    
    [_authenticationChallenge release];
    _authenticationChallenge = nil;
}

#pragma mark OFSDAVFileManagerDelegate
- (NSURLCredential *)DAVFileManager:(OFSDAVFileManager *)manager findCredentialsForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
    if (_username && _newKeychainPassword) {        
        OUIWriteCredentialsForProtectionSpace(_username, _newKeychainPassword, protectionSpace);
        [_newKeychainPassword release];
        _newKeychainPassword = nil;
    }
    
    [_authenticationChallenge release];
    _authenticationChallenge = nil;
    
    _authenticationChallenge = [[NSURLAuthenticationChallenge alloc] initWithAuthenticationChallenge:challenge sender:nil];
    
    return OUIReadCredentialsForChallenge(challenge);
}

@synthesize address = _address;
@synthesize username = _username;
@synthesize newKeychainPassword = _newKeychainPassword;
@synthesize fileManager = _fileManager;
@synthesize authenticationChallenge = _authenticationChallenge;
@end
