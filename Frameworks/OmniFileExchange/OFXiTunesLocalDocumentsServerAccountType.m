// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXiTunesLocalDocumentsServerAccountType.h"

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <OmniFileStore/OFSDocumentStoreLocalDirectoryScope.h>

RCS_ID("$Id$")

NSString * const OFXiTunesLocalDocumentsServerAccountTypeIdentifier = @"com.omnigroup.OmniFileStore.ServerType.iTunes";

@implementation OFXiTunesLocalDocumentsServerAccountType

- (NSString *)identifier;
{
    return OFXiTunesLocalDocumentsServerAccountTypeIdentifier;
}

- (NSString *)displayName;
{
    return NSLocalizedStringFromTableInBundle(@"iTunes", @"OmniFileExchange", OMNI_BUNDLE, @"Server account type");
}

- (float)presentationPriority;
{
    return 20.0;
}

- (BOOL)requiresServerURL;
{
    return NO;
}

- (BOOL)requiresUsername;
{
    return NO;
}

- (BOOL)requiresPassword;
{
    return NO;
}

- (BOOL)usesCredentials;
{
    return NO;
}

- (NSString *)importTitleForDisplayName:(NSString *)displayName;
{
    return NSLocalizedStringFromTableInBundle(@"Copy from iTunes", @"OmniFileExchange", OMNI_BUNDLE, @"iTunes import title");
}

- (NSString *)exportTitleForDisplayName:(NSString *)displayName;
{
    return NSLocalizedStringFromTableInBundle(@"Export to iTunes", @"OmniFileExchange", OMNI_BUNDLE, @"iTunes export title");
}

- (NSString *)accountDetailsStringForAccount:(OFXServerAccount *)account;
{
    return NSLocalizedStringFromTableInBundle(@"Documents", @"OmniFileExchange", OMNI_BUNDLE, @"iTunes import/export account detail string");
}

- (NSString *)addAccountTitle;
{
    OBASSERT_NOT_REACHED("This account type cannot be added");
    return nil;
}

- (NSString *)addAccountDescription;
{
    OBASSERT_NOT_REACHED("This account type cannot be added");
    return nil;
}

- (NSString *)setUpAccountTitle;
{
    OBASSERT_NOT_REACHED("This account type cannot be configured");
    return nil;
}

- (NSURL *)baseURLForServerURL:(NSURL *)serverURL username:(NSString *)username;
{
    return [OFSDocumentStoreLocalDirectoryScope userDocumentsDirectoryURL];
}

- (void)validateAccount:(OFXServerAccount *)account username:(NSString *)username password:(NSString *)password validationHandler:(OFXServerAccountValidationHandler)validationHandler;
{
    OBASSERT_NOT_REACHED("This account type has no credentials to validate, but whatever...");
    if (validationHandler) {
        validationHandler = [validationHandler copy];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            validationHandler(nil);
        }];
    }
}

@end

#endif
