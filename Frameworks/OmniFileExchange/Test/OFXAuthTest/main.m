// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/Foundation.h>

#import <OmniFileExchange/OmniFileExchange.h>
#import <OmniCommandLine/OmniCommandLine.h>
#import <OmniFoundation/OmniFoundation.h>

static NSString *_getSetting(const char *name)
{
    const char *env;
    if ((env = getenv(name)))
        return [NSString stringWithUTF8String:env];
    
    return [[NSUserDefaults standardUserDefaults] stringForKey:[NSString stringWithUTF8String:name]];
}

int main(int argc, const char * argv[])
{

    @autoreleasepool {
        OCLCommand *strongCommand = [OCLCommand command];
        __weak OCLCommand *cmd = strongCommand;
        
        // Register defaults
        OBInvokeRegisteredLoadActions();
        
        NSURL *libraryDirectoryURL;
        NSURL *accountsRegistryURL;
        {
            __autoreleasing NSError *error;
            libraryDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
            if (!libraryDirectoryURL)
                [cmd error:@"Cannot find application support directory: %@", [error toPropertyList]];
            accountsRegistryURL = [libraryDirectoryURL URLByAppendingPathComponent:@"com.omnigroup.OFXAuthTest/Accounts" isDirectory:YES];
        }
        

        [cmd add:@"init # Removes any previous accounts and configures a new set of accounts" with:^{
            // Lots of stuff copied from ODAVTestCase and OFXTestCase. Can clean up later if needed...
            static const NSUInteger UsernameCount = 9;
                        
            NSString *baseUsername = _getSetting("OFSAccountUsername");
            if ([NSString isEmptyString:baseUsername])
                [NSException raise:NSGenericException reason:@"OFSAccountUsername not specified in environment"];
            
            NSString *password = _getSetting("OFSAccountPassword");
            if ([NSString isEmptyString:password])
                [NSException raise:NSGenericException reason:@"OFSAccountPassword not specified in environment"];
            
            NSString *remoteBaseURLString = _getSetting("OFSAccountRemoteBaseURL");
            remoteBaseURLString = [remoteBaseURLString stringByReplacingOccurrencesOfString:@"LOCAL_HOST" withString:OFHostName()];
            
            if ([NSString isEmptyString:remoteBaseURLString])
                [NSException raise:NSGenericException format:@"OFSAccountRemoteBaseURL must be set"];
            NSURL *remoteBaseURL = [NSURL URLWithString:remoteBaseURLString];
            if (!remoteBaseURL)
                [NSException raise:NSGenericException format:@"OFSAccountRemoteBaseURL set to an invalid URL"];
            
            OFXServerAccountRegistry *registry;
            {
                __autoreleasing NSError *error;

                // Clean up cruft from previous runs
                if (![[NSFileManager defaultManager] removeItemAtURL:accountsRegistryURL error:&error]) {
                    if (![error causedByMissingFile])
                        [cmd error:@"Cannot remove old accounts directory at %@: %@", accountsRegistryURL, [error toPropertyList]];
                }
                
                if (!(registry = [[OFXServerAccountRegistry alloc] initWithAccountsDirectoryURL:accountsRegistryURL error:&error]))
                    [cmd error:@"Cannot create account registry at %@: %@", accountsRegistryURL, [error toPropertyList]];
                
                assert([registry.allAccounts count] == 0);
            }
            
            NSURL *localBaseDocumentsURL;
            {
                localBaseDocumentsURL = [libraryDirectoryURL URLByAppendingPathComponent:@"com.omnigroup.OFXAuthTest/Documents" isDirectory:YES];
                                
                // Clean up cruft from previous runs
                __autoreleasing NSError *error;
                if (![[NSFileManager defaultManager] removeItemAtURL:localBaseDocumentsURL error:&error]) {
                    if (![error causedByMissingFile])
                        [cmd error:@"Cannot remove old documents directory at %@: %@", localBaseDocumentsURL, [error toPropertyList]];
                }
            }
            
            // validate all 100 accounts so that credentials are coming out of the keychain.
            for (NSUInteger accountIndex = 1; accountIndex <= UsernameCount; accountIndex++) {
                OFXServerAccountType *accountType = [OFXServerAccountType accountTypeWithIdentifier:OFXOmniSyncServerAccountTypeIdentifier];
                OBASSERT(accountType);
                
                NSString *accountNumberString = [NSString stringWithFormat:@"%ld", accountIndex];
                NSString *username = [baseUsername stringByAppendingString:accountNumberString];
                NSURL *accountRemoteURL = [remoteBaseURL URLByAppendingPathComponent:username isDirectory:YES];
                NSURL *accountLocalURL = [localBaseDocumentsURL URLByAppendingPathComponent:username isDirectory:YES];
                
                NSError *error;
                if (![[NSFileManager defaultManager] createDirectoryAtURL:accountLocalURL withIntermediateDirectories:YES attributes:nil error:&error])
                    [cmd error:@"Error creating local directory at %@: %@", accountLocalURL, [error toPropertyList]];
                
                OFXServerAccount *account = [[OFXServerAccount alloc] initWithType:accountType remoteBaseURL:accountRemoteURL localDocumentsURL:accountLocalURL error:&error];
                if (!account)
                    [cmd error:@"Error creating account at %@: %@", accountLocalURL, [error toPropertyList]];
                
                __block BOOL finished = NO;
                
                id <OFXServerAccountValidator> accountValidator = [account.type validatorWithAccount:account username:username password:password];
                accountValidator.shouldSkipConformanceTests = YES;
                accountValidator.finished = ^(NSError *errorOrNil){
                    if (errorOrNil) {
                        NSLog(@"Error registering testing account: %@", [errorOrNil toPropertyList]);
                        [NSException raise:NSGenericException format:@"Test can't continue"];
                    } else {
                        OBASSERT(account.credential);
                        
                        __autoreleasing NSError *addError;
                        if (![registry addAccount:account error:&addError])
                            [cmd error:@"Error adding account: %@", [addError toPropertyList]];
                    }
                    finished = YES;
                };
                [accountValidator startValidation];
                
                while (!finished) {
                    @autoreleasepool {
                        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
                    }
                }
            }
        }];
        
        [cmd add:@"run # Runs operations against the previously registered accounts" with:^{
            __autoreleasing NSError *error;
            OFXServerAccountRegistry *registry;
            {
                if (!(registry = [[OFXServerAccountRegistry alloc] initWithAccountsDirectoryURL:accountsRegistryURL error:&error]))
                    [cmd error:@"Cannot create account registry at %@: %@", accountsRegistryURL, [error toPropertyList]];
                assert([registry.allAccounts count] > 0);
            }

            
            OFXAgent *agent = [[OFXAgent alloc] initWithAccountRegistry:registry remoteDirectoryName:nil syncPathExtensions:[OFXAgent wildcardSyncPathExtensions]];
            [agent applicationLaunched];
            [agent sync:^{
                NSLog(@"done");
            }];
            
            while (YES) {
                @autoreleasepool {
                    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:5]];
                    
                    // Periodically lock the default keychain
                    SecKeychainRef keychain = NULL;
                    OSStatus rc = SecKeychainCopyDefault(&keychain);
                    if (rc != errSecSuccess) {
                        NSLog(@"SecKeychainCopyDefault returned %d", rc);
                    } else {
                        rc = SecKeychainLock(keychain);
                        if (rc != errSecSuccess) {
                            NSLog(@"SecKeychainLock returned %d", rc);
                        }
                    }

#if 0
                    for (OFXServerAccount *account in registry.validCloudSyncAccounts) {
                        NSURLCredential *credential = account.credential;
                        assert([credential.user length] > 0);
                        assert([credential.password length] > 0);
                    }
#endif
                }
            }
        }];
        
        NSMutableArray *argumentStrings = [NSMutableArray array];
        for (int argi = 1; argi < argc; argi++)
            [argumentStrings addObject:[NSString stringWithUTF8String:argv[argi]]];
        [strongCommand runWithArguments:argumentStrings];
    }
    return 0;
}

#if 0
- (NSURLCredential *)fileManager:(OFSFileManager *)manager findCredentialsForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // Called from background transfer queue or NSURLConnection private queue. Who knows.
    
    if ([challenge previousFailureCount] <= 2) {
        NSURLCredential *credential = _account.credential;
        OBASSERT(credential);
        return credential;
    }
    return nil;
}
#endif
