// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXDAVServerAccountType.h"

#import <OmniFileExchange/OFXServerAccount.h>
#import "OFXDAVServerAccountValidator.h"

RCS_ID("$Id$")


@implementation OFXDAVServerAccountType

NSString * const OFXWebDAVServerAccountTypeIdentifier = @"com.omnigroup.OmniFileStore.ServerType.WebDAV";

- (NSString *)identifier;
{
    return OFXWebDAVServerAccountTypeIdentifier;
}

- (NSString *)displayName;
{
    return NSLocalizedStringFromTableInBundle(@"WebDAV", @"OmniFileExchange", OMNI_BUNDLE, @"Server account type");
}

- (float)presentationPriority;
{
    return 10.0;
}

- (BOOL)requiresServerURL;
{
    return YES;
}

- (NSString *)accountDetailsStringForAccount:(OFXServerAccount *)account;
{
    return [account.remoteBaseURL absoluteString];
}

- (NSString *)addAccountTitle;
{
    return NSLocalizedStringFromTableInBundle(@"Add WebDAV Server", @"OmniFileExchange", OMNI_BUNDLE, @"Add server account type");
}

- (NSString *)addAccountDescription;
{
    return NSLocalizedStringFromTableInBundle(@"Use your own WebDAV space.", @"OmniFileExchange", OMNI_BUNDLE, @"Add server account description");
}

- (NSString *)setUpAccountTitle;
{
    return NSLocalizedStringFromTableInBundle(@"WebDAV Server", @"OmniFileExchange", OMNI_BUNDLE, @"Set up server account title");
}

- (id <OFXServerAccountValidator>)validatorWithAccount:(OFXServerAccount *)account username:(NSString *)username password:(NSString *)password;
{
    return [[OFXDAVServerAccountValidator alloc] initWithAccount:account username:username password:password];
}

@end
