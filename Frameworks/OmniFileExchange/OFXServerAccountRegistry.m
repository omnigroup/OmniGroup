// Copyright 2013-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileExchange/OFXServerAccountRegistry.h>

#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>

#import "OFXServerAccount-Internal.h"
#import "OFXServerAccountRegistry-Internal.h"

RCS_ID("$Id$")

static NSString * const AllAccountsKey = @"allAccounts";
static NSString * const ValidCloudSyncAccounts = @"validCloudSyncAccounts";
static NSString * const ValidImportExportAccounts = @"validImportExportAccounts";

@interface OFXServerAccountRegistry ()
@property(nonatomic,assign) BOOL ownsCredentials;
@property(nonatomic,copy) NSArray *allAccounts;
@end

@implementation OFXServerAccountRegistry

+ (OFXServerAccountRegistry *)defaultAccountRegistry;
{
    static OFXServerAccountRegistry *defaultRegistry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        OBASSERT([[NSUserDefaults standardUserDefaults] objectForKey:@"OFXServerAccountRegistry"] == nil); // Remove this from your plists
        
        // We have a single shared directory for all apps (so the main app's bundle identifier has no influence here). We *do* want the ability to split this off for testing.
        NSURL *accountsDirectoryURL;
        const char *accountsDirectoryString = getenv("OFXAccountsDirectory");
        if (accountsDirectoryString && *accountsDirectoryString) {
            NSString *path = [NSString stringWithUTF8String:accountsDirectoryString];
            if (!path) {
                NSLog(@"OFXAccountsDirectory set to an invalid UTF-8 string!");
                return;
            }
            
            if (![path isAbsolutePath]) {
                NSLog(@"OFXAccountsDirectory is not set to an absolute path!");
                return;
            }
            
            accountsDirectoryURL = [NSURL fileURLWithPath:path];
        } else {
            __autoreleasing NSError *error = nil;
            NSURL *applicationSupportDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
            if (!applicationSupportDirectoryURL) {
                NSLog(@"%s: Unable to create application support directory: %@", __PRETTY_FUNCTION__, [error toPropertyList]);
                return;
            }


            accountsDirectoryURL = [applicationSupportDirectoryURL URLByAppendingPathComponent:@"com.omnigroup.OmniPresence.Accounts" isDirectory:YES];
        }

        __autoreleasing NSError *error = nil;
        defaultRegistry = [[self alloc] initWithAccountsDirectoryURL:accountsDirectoryURL error:&error];
        if (!defaultRegistry) {
            NSLog(@"Error creating account registry at %@: %@", accountsDirectoryURL, [error toPropertyList]);
        }
        
        // See -removeAccounts:. Ugly, but needed so that registries created to support tests don't purge credentials.
//        defaultRegistry.ownsCredentials = YES;
    });
    return defaultRegistry;
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithAccountsDirectoryURL:(NSURL *)accountsDirectoryURL error:(NSError **)outError;
{
    OBPRECONDITION(accountsDirectoryURL); // Doesn't have to exist ... we'll try to make it the first time an account is added.
    
    if (!(self = [super init]))
        return nil;

    // Ensure the directory exists so we can normalize the directory here once. Don't attempt to standardize it until it exists (since standardization silently does nothing if it doesn't).

    __autoreleasing NSError *directoryError;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:accountsDirectoryURL withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
        if ([directoryError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EEXIST] ||
            [directoryError hasUnderlyingErrorDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError]) {
            // OK -- it's there already
        } else {
            if (outError)
                *outError = directoryError;
            return nil;
        }
    }
    
    _accountsDirectoryURL = [[accountsDirectoryURL URLByStandardizingPath] copy];
    
    
    // TODO: Should we add a lock file, or maybe OFXAgent should when using us?

    // Read existing accounts.
    __autoreleasing NSError *error;
    NSArray *accountURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:_accountsDirectoryURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsSubdirectoryDescendants error:&error];
    if (!accountURLs) {
        if ([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT] ||
            [error hasUnderlyingErrorDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError]) {
            // OK; just not created yet
        } else {
            NSLog(@"Error loading sync accounts in %@: %@", _accountsDirectoryURL, [error toPropertyList]);
        }
    }

    NSMutableArray *allAccounts = [NSMutableArray new];

    for (NSURL *accountURL in accountURLs) {
        __autoreleasing NSError *infoError;
        NSURL *infoURL = [accountURL URLByAppendingPathComponent:@"Info.plist"];
        NSDictionary *propertyList = OFReadNSPropertyListFromURL(infoURL, &infoError);
        if (!propertyList) {
            NSLog(@"Error reading account info from %@: %@", infoURL, [infoError toPropertyList]);
            continue;
        }
        
        if (![propertyList isKindOfClass:[NSDictionary class]]) {
            NSLog(@"Account info at %@ is not a dictionary!", infoURL);
            continue;
        }

        // TODO: If there is some error loading an account, it would be nice if we kept it around and at least allowed the user to try to delete it. Or maybe we should just burn it with fire here.
        NSString *uuid = [accountURL lastPathComponent]; // Don't need to check for uniqueness since we can't have two directories with the same name
        __autoreleasing NSError *accountError;
        OFXServerAccount *account = [[OFXServerAccount alloc] _initWithUUID:uuid propertyList:propertyList error:&accountError];
        if (!account) {
            NSLog(@"Error reading account from %@: %@", accountURL, [accountError toPropertyList]);
            continue;
        }
        
        if (account.hasBeenPreparedForRemoval) {
            // We died or were killed before being able to remove the account...
            [self _cleanupAccountAfterRemoval:account];
            continue; // Either way, ignore it.
        }
        
        [allAccounts addObject:account];
    }
    
    // Start in a consistent empty state so our setter can early-out.
    _allAccounts = [NSArray new]; // avoid assertion in the setter for now.
    _validCloudSyncAccounts = [NSArray new];
    _validImportExportAccounts = [NSArray new];
    
    self.allAccounts = allAccounts;

    OBPOSTCONDITION(_allAccounts);
    OBPOSTCONDITION(_validCloudSyncAccounts);
    OBPOSTCONDITION(_validImportExportAccounts);
    return self;
}

- (void)dealloc;
{
    for (OFXServerAccount *account in _allAccounts)
        [self _stopObservingAccount:account];
}

+ (BOOL)automaticallyNotifiesObserversOfAccounts;
{
    return NO;
}

- (NSArray *)accountsWithType:(OFXServerAccountType *)type;
{
    return [self.allAccounts select:^BOOL(OFXServerAccount *account){
        return account.type == type;
    }];
}

- (OFXServerAccount *)accountWithUUID:(NSString *)uuid;
{
    for (OFXServerAccount *account in self.allAccounts) {
        if ([account.uuid isEqual:uuid])
            return account;
    }
    return nil;
}

- (OFXServerAccount *)accountWithDisplayName:(NSString *)name;
{
    for (OFXServerAccount *account in self.allAccounts) {
        if ([account.displayName isEqual:name])
            return account;
    }
    return nil;
}

- (BOOL)_createLocalDocumentsFolderForAccount:(OFXServerAccount *)account error:(NSError **)outError;
{
    NSFileManager *manager = [NSFileManager defaultManager];

    // This will not produce an error if the directory already exists.
    __autoreleasing NSError *createError;
    if (![manager createDirectoryAtURL:account.localDocumentsURL withIntermediateDirectories:YES attributes:nil error:&createError]) {
        NSLog(@"Error creating local documents directory %@: %@", account.localDocumentsURL, [createError toPropertyList]);
        if (outError)
            *outError = createError;
        return NO;
    }

    __autoreleasing NSError *contentsError;
    if (![OFXServerAccount validateLocalDocumentsURL:account.localDocumentsURL reason:OFXServerAccountValidateLocalDirectoryForAccountCreation error:&contentsError]) {
        if (outError)
            *outError = contentsError;
        return NO;
    }

    return YES;
}

- (BOOL)addAccount:(OFXServerAccount *)account error:(NSError **)outError;
{
    OBPRECONDITION([_allAccounts indexOfObject:account] == NSNotFound);
    OBPRECONDITION([self accountWithUUID:account.uuid] == nil);
    OBPRECONDITION(account.hasBeenPreparedForRemoval == NO);

    if (account.credentialServiceIdentifier == nil) {
        if (outError != NULL) {
            OFXError(outError, OFXServerAccountNotConfigured,
                     NSLocalizedStringFromTableInBundle(@"Account not configured", @"OmniFileExchange", OMNI_BUNDLE, @"account validation error description"),
                     NSLocalizedStringFromTableInBundle(@"Account is missing login credentials.", @"OmniFileExchange", OMNI_BUNDLE, @"account credentials missing suggestion"));
        }
        return NO;
    }

    NSFileManager *manager = [NSFileManager defaultManager];

    NSURL *accountURL = [self localStoreURLForAccount:account];
    NSURL *temporaryURL = [manager temporaryURLForWritingToURL:accountURL allowOriginalDirectory:NO error:outError];
    if (!temporaryURL)
        return NO;
    
    if (![manager createDirectoryAtURL:temporaryURL withIntermediateDirectories:NO attributes:nil error:outError])
        return NO;
    
    if (account.usageMode == OFXServerAccountUsageModeCloudSync) {
        // Make the local documents directory for this URL. We need to do this before calling -propertyList so that (on OS X), we can record an app-scoped bookmark.
        // NOTE: We don't delete the document directory here since it was possibly created by the user (and if validation fails, this will let them pick it again). AND, most importantly, it might fail to be valid below due to containing actual files!
        if (![self _createLocalDocumentsFolderForAccount:account error:outError]) {
            [manager removeItemAtURL:temporaryURL error:NULL];
            return NO;
        }
    }

    NSDictionary *plist = account.propertyList;
    if (!OFWriteNSPropertyListToURL(plist, [temporaryURL URLByAppendingPathComponent:@"Info.plist"], outError)) {
        [manager removeItemAtURL:temporaryURL error:NULL];
        return NO;
    }
    
    // We lazily create our accounts directory
    __autoreleasing NSError *createError = nil;
    if (![manager createDirectoryAtURL:_accountsDirectoryURL withIntermediateDirectories:YES attributes:nil error:&createError]) {
        if ([createError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:EEXIST] ||
            [createError hasUnderlyingErrorDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError]) {
            // OK, already set up
        } else {
            if (outError)
                *outError = createError;
            [manager removeItemAtURL:temporaryURL error:NULL];
            return NO;
        }
    }
    
    // Move the new account into place and publish it via KVO.
    if (![manager moveItemAtURL:temporaryURL toURL:accountURL error:outError]) {
        [manager removeItemAtURL:temporaryURL error:NULL];
        return NO;
    }
    
    NSArray *accounts = [self.allAccounts arrayByAddingObject:account];
    OBASSERT(accounts); // accounts should return an empty array if there are none
    self.allAccounts = accounts;
    
    return YES;
}

static unsigned AccountContext;

#pragma mark - NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == &AccountContext) {
        DEBUG_SYNC(1, @"Account property list changed %@", object);
        OBASSERT([_allAccounts indexOfObjectIdenticalTo:object] != NSNotFound);
        
        OFXServerAccount *account = object;
        __autoreleasing NSError *error;
        if (![self _writeUpdatedAccountInfo:account error:&error])
            NSLog(@"Error writing updated Info.plist for account %@: %@", [account shortDescription], [error toPropertyList]);
        
        [self _updateValidatedAccounts];
        return;
    }
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (BOOL)_writeUpdatedAccountInfo:(OFXServerAccount *)account error:(NSError **)outError;
{
    NSURL *accountURL = [self localStoreURLForAccount:account];
    NSURL *plistURL = [[accountURL URLByAppendingPathComponent:@"Info.plist"] absoluteURL];
    
    NSURL *temporaryURL = [[NSFileManager defaultManager] temporaryURLForWritingToURL:plistURL allowOriginalDirectory:YES error:outError];
    if (!temporaryURL)
        return NO;
    
    NSDictionary *plist = account.propertyList;
    if (!OFWriteNSPropertyListToURL(plist, temporaryURL, outError))
        return NO;
    
    return [[NSFileManager defaultManager] replaceItemAtURL:plistURL withItemAtURL:temporaryURL backupItemName:nil options:0 resultingItemURL:NULL error:outError];
}

#pragma mark - Internal

- (NSURL *)localStoreURLForAccount:(OFXServerAccount *)account;
{
    return [[_accountsDirectoryURL URLByAppendingPathComponent:account.uuid isDirectory:YES] absoluteURL];
}

// This is called after an account is marked for removal and after we are sure any syncing operations on it have finished.
- (void)_cleanupAccountAfterRemoval:(OFXServerAccount *)account;
{
    OBPRECONDITION([NSThread isMainThread]);

    if (!account.hasBeenPreparedForRemoval) {
        OBASSERT_NOT_REACHED("UI code should just call -prepareForRemoval on accounts");
        NSLog(@"Account %@ is not prepared for removal.", [account shortDescription]);
        return;
    }

    // Atomically remove the account directory now that any syncing on this account is done.
    __autoreleasing NSError *removeAccountError;
    NSURL *accountStoreDirectory = [self localStoreURLForAccount:account];
    if (![[NSFileManager defaultManager] atomicallyRemoveItemAtURL:accountStoreDirectory error:&removeAccountError]) {
        [removeAccountError log:@"Error removing local account store %@", accountStoreDirectory];
        return;
    }
    
    void (^removalCompleted)(void) = ^{
        OBASSERT([NSThread isMainThread]);
        if (_allAccounts != nil) // Avoid some work and an assertion in -setAllAccounts:
            [self setAllAccounts:[_allAccounts arrayByRemovingObject:account]];
    };
    
    // On the Mac, we'll leave the synchronized files around since they are in a user-visible location and the user may have just decided to stop using our service. On iOS, there is no other way to get to the files, so we need to clean up after ourselves.
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    if (account.usageMode == OFXServerAccountUsageModeCloudSync) {
        // Go through this helper method to make sure we delete the right ancestory URL (since there is an extra 'Documents' component). This does some other checks to make sure we are deleting the right thing.
        [OFXServerAccount deleteGeneratedLocalDocumentsURL:account.localDocumentsURL completionHandler:^(NSError *removeError) {
            if (removeError)
                NSLog(@"Error removing local account documents at %@: %@", account.localDocumentsURL, [removeError toPropertyList]);
            else
                removalCompleted();
        }];
    }
#else
    removalCompleted();
#endif
}

#pragma mark - Private

- (BOOL)_isAccountValid:(OFXServerAccount *)account;
{
    if (account.hasBeenPreparedForRemoval)
        return NO;
    if ([NSString isEmptyString:account.credentialServiceIdentifier])
        return NO;
    return YES;
}

- (void)_updateValidatedAccounts;
{
    NSMutableArray *validCloudSyncAccounts = [NSMutableArray new];
    NSMutableArray *validImportExportAccounts = [NSMutableArray new];
    for (OFXServerAccount *account in _allAccounts) {
        if ([self _isAccountValid:account]) {
            switch (account.usageMode) {
                case OFXServerAccountUsageModeCloudSync:
                    [validCloudSyncAccounts addObject:account];
                    break;
                case OFXServerAccountUsageModeImportExport:
                    [validImportExportAccounts addObject:account];
                    break;
            }
        }
    }
    
    if (![_validImportExportAccounts isEqual:validImportExportAccounts]) {
        [self willChangeValueForKey:ValidImportExportAccounts];
        _validImportExportAccounts = [validImportExportAccounts copy];
        [self didChangeValueForKey:ValidImportExportAccounts];
    }

    if (![_validCloudSyncAccounts isEqual:validCloudSyncAccounts]) {
        [self willChangeValueForKey:ValidCloudSyncAccounts];
        _validCloudSyncAccounts = [validCloudSyncAccounts copy];
        [self didChangeValueForKey:ValidCloudSyncAccounts];
    }
}

- (void)_startObservingAccount:(OFXServerAccount *)account;
{
    [account addObserver:self forKeyPath:OFXAccountPropertListKey options:0 context:&AccountContext];
}

- (void)_stopObservingAccount:(OFXServerAccount *)account;
{
    [account removeObserver:self forKeyPath:OFXAccountPropertListKey context:&AccountContext];
}

- (void)setAllAccounts:(NSArray *)allAccounts;
{
    OBPRECONDITION(_allAccounts); // Make sure our nil->[] transform above won't leave us with _accounts==nil
    
    // Always want a non-nil value so we can do [self.accounts arrayBy...].
    if (!allAccounts)
        allAccounts = [NSArray array];
    
    if (OFISEQUAL(_allAccounts, allAccounts))
        return;
    
    [self willChangeValueForKey:AllAccountsKey];
    {
        for (OFXServerAccount *account in _allAccounts)
            [self _stopObservingAccount:account];
        _allAccounts = [allAccounts copy];
        for (OFXServerAccount *account in _allAccounts)
            [self _startObservingAccount:account];
    }
    [self didChangeValueForKey:AllAccountsKey];
    [self _updateValidatedAccounts];
}

- (void)refreshAccount:(OFXServerAccount *)account;
{
    NSArray *allAccounts = self.allAccounts;
    self.allAccounts = [allAccounts arrayByRemovingObject:account];
    self.allAccounts = allAccounts;
}

@end
