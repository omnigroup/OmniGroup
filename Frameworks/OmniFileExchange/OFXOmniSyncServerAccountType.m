// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXOmniSyncServerAccountType.h"

#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFoundation/OFCredentials.h>

RCS_ID("$Id$")

NSString * const OFXOmniSyncServerAccountTypeIdentifier = @"com.omnigroup.OmniFileStore.ServerType.OmniSyncServer";

@implementation OFXOmniSyncServerAccountType

- (NSString *)identifier;
{
    return OFXOmniSyncServerAccountTypeIdentifier;
}

- (NSString *)displayName;
{
    return NSLocalizedStringFromTableInBundle(@"Omni Sync Server", @"OmniFileExchange", OMNI_BUNDLE, @"Server account type");
}

- (float)presentationPriority;
{
    return 0.0;
}

- (BOOL)requiresServerURL;
{
    return NO;
}

- (NSString *)accountDetailsStringForAccount:(OFXServerAccount *)account;
{
    NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(account.credentialServiceIdentifier, NULL);
    return credential.user;
}

- (NSString *)addAccountTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Add Omni Sync Server Account", @"OmniFileExchange", OMNI_BUNDLE, @"Add server account title");
}

- (NSString *)addAccountDescription;
{
    return NSLocalizedStringFromTableInBundle(@"Easily sync Omni documents. Signup is free!", @"OmniFileExchange", OMNI_BUNDLE, @"Add server account description");
}

- (NSString *)setUpAccountTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Omni Sync Server", @"OmniFileExchange", OMNI_BUNDLE, @"Set up server account title");
}

- (NSURL *)baseURLForServerURL:(nullable NSURL *)serverURL username:(NSString *)username;
{
    OBPRECONDITION(serverURL == nil);
    
    serverURL = [NSURL URLWithString:@"https://sync.omnigroup.com/"];
    return OFURLRelativeToDirectoryURL(serverURL, [username stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]]);
}

@end
