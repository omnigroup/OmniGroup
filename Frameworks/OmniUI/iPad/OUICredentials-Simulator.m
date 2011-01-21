// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUICredentials.h"
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$");

#if TARGET_IPHONE_SIMULATOR

// The SecItem API isn't available on the simulator.  Use the normal credential storage.  This lacks the ability to create 'generic' entries which means that if a bad entry gets stuck in the keychain as an 'internet password' item, you'll be screwed.  NSURLRequest can just keep trying the bad one w/o giving us a challenge.  Remove your 'Library/Application Support/iPhone Simulator' directory in this case.

NSURLCredential *OUIReadCredentialsForProtectionSpace(NSURLProtectionSpace *protectionSpace)
{
    // Get the default credential for this space; maybe we've stored it before.
    return [[NSURLCredentialStorage sharedCredentialStorage] defaultCredentialForProtectionSpace:protectionSpace];
}

NSURLCredential *OUIReadCredentialsForChallenge(NSURLAuthenticationChallenge *challenge)
{
    
    // We only have one set of credentials.
    if ([challenge previousFailureCount] == 0) {
        NSURLCredential *result = OUIReadCredentialsForProtectionSpace([challenge protectionSpace]);
        if (result)
            return result;
    }
    
    return nil;
}

void OUIWriteCredentialsForProtectionSpace(NSString *userName, NSString *password, NSURLProtectionSpace *protectionSpace)
{
    NSURLCredential *keychainCredential = [NSURLCredential credentialWithUser:userName password:password persistence:NSURLCredentialPersistencePermanent];
    [[NSURLCredentialStorage sharedCredentialStorage] setDefaultCredential:keychainCredential forProtectionSpace:protectionSpace];
    // Just in case the persistent credential isn't working (as in the 9A292g version of beta 6), make sure we store a copy as a session credential
    NSURLCredential *sessionCredential = [NSURLCredential credentialWithUser:userName password:password persistence:NSURLCredentialPersistenceNone];
    [[NSURLCredentialStorage sharedCredentialStorage] setDefaultCredential:sessionCredential forProtectionSpace:protectionSpace];
    
}

void OUIDeleteAllCredentials(void)
{
    NSLog(@"Cannot delete credentials in the simulator easily; just manually delete the keychain it creates in your \"~/Library/Application Support/iPhone Simulator\".");
}

void OUIDeleteCredentialsForProtectionSpace(NSURLProtectionSpace *protectionSpace)
{
    OUIDeleteAllCredentials();
    
    if ([OFSDAVFileManager isTrustedHost:[protectionSpace host]]) {
        [OFSDAVFileManager removeTrustedHost:[protectionSpace host]];
        [[OFPreferenceWrapper sharedPreferenceWrapper] removeObjectForKey:[protectionSpace host]];
    }
}

#endif
