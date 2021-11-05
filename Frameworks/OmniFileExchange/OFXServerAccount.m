// Copyright 2013-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXServerAccount-Internal.h"

#import <OmniDAV/ODAVErrors.h>
#import <OmniFileExchange/OFXFeatures.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/NSURL-OFExtensions.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFPreference.h>
#import <sys/mount.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

static NSString * const RemoteBaseURLKey = @"remoteBaseURL";
static NSString * const DisplayNameKey = @"displayName";

static NSString * const LastKnownDislpayNameKey = @"lastKnownDisplayName";
static NSString * const LocalDocumentsBookmarkDataKey = @"localDocumentsBookmarkData";

static NSString * const UnmigratedNicknameKey = @"nickname";

static NSString * const UsageModeKey = @"usageMode";
static NSString * const CredentialServiceIdentifierKey = @"credentialServiceIdentifier";
static NSString * const HasBeenPreparedForRemovalKey = @"hasBeenPreparedForRemoval";

NSString * const OFXAccountPropertListKey = @"propertyList";

static const NSUInteger ServerAccountPropertyListVersion = 1;

@interface OFXServerAccount ()
@property(nullable,nonatomic,readwrite,strong) NSError *lastError;
@property(nonatomic,copy) NSString *lastKnownDisplayName;
@end

static OFDeclareDebugLogLevel(OFXBookmarkDebug);
#define DEBUG_BOOKMARK(level, format, ...) do { \
    if (OFXBookmarkDebug >= (level)) \
        NSLog(@"BOOKMARK %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)

// When running unit tests on Mac OS X 10.9, we cannot use app-scoped bookmarks. This worked in 10.8, but under 10.9 we get a generic 'cannot open' error. We don't just check -[NSProcessInfo isSandboxed] since we archive the "bookmark" in a plist. We don't want to handle archiving/unarchiving different styles of bookmarks between sandboxed/non-sandboxed.
static BOOL CannotUseAppScopedBookmarks(void)
{
    return OFIsRunningUnitTests();
}

static NSData *bookmarkDataWithURL(NSURL *url, NSError **outError)
{
    if (CannotUseAppScopedBookmarks()) {
        NSData *data = [[url absoluteString] dataUsingEncoding:NSUTF8StringEncoding];
        assert(data); // otherwise we need to fill out the outError
        return data;
    }

#if OMNI_BUILDING_FOR_MAC
    NSURLBookmarkCreationOptions options = NSURLBookmarkCreationWithSecurityScope;
#elif OMNI_BUILDING_FOR_IOS
    NSURLBookmarkCreationOptions options = 0;
#else
#error Unknown platform
#endif

    return [url bookmarkDataWithOptions:options includingResourceValuesForKeys:nil relativeToURL:nil/*app scoped*/ error:outError];
}

#if OMNI_BUILDING_FOR_IOS
static NSURL * _Nullable RecoveredURLFromBookmarkData(NSData *data, BOOL *outStale)
{
    NSString *originalPath = [NSURL resourceValuesForKeys:@[NSURLPathKey] fromBookmarkData:data][NSURLPathKey];
    if (originalPath == nil)
        return nil;

    // Try to figure out the original path relative to the original location of our NSHomeDirectory() sandbox
    NSString *homeDirectory = NSHomeDirectory();
    NSURL *homeURL = [NSURL fileURLWithPath:homeDirectory];
    NSURL *documentsURL = OFUserDocumentsDirectoryURL();
    if (homeURL == nil || documentsURL == nil)
        return nil;

    NSString *relativeDocumentsPath = OFFileURLRelativePath(homeURL, documentsURL);
    NSString *pathToHome = [homeDirectory stringByDeletingLastPathComponent];
    NSString *oldDocumentsPrefixPattern = [NSString stringWithFormat:@"^.*%@/[^/]+/%@", [pathToHome regularExpressionForLiteralString], [relativeDocumentsPath regularExpressionForLiteralString]];
    NSString *recoveredPath = [originalPath stringByReplacingAllOccurrencesOfRegularExpressionPattern:oldDocumentsPrefixPattern withString:[documentsURL path]];
    NSURL *recoveredURL = [NSURL fileURLWithPath:recoveredPath];

    // Test to make sure we actually found a valid directory
    __autoreleasing NSNumber *isDirectoryValue = nil;
    if (![recoveredURL getResourceValue:&isDirectoryValue forKey:NSURLIsDirectoryKey error:NULL] || !isDirectoryValue.boolValue) {
        return nil;
    }

    if (outStale) {
        *outStale = YES;
    }
    return recoveredURL;
}
#endif

static NSURL * _Nullable URLWithBookmarkData(NSData *data, BOOL *outStale, NSError **outError)
{
    if (CannotUseAppScopedBookmarks()) {
        NSString *urlString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSURL *url = [NSURL URLWithString:urlString];
        assert(url); // otherwise we need to fill out the outError
        return url;
    }

#if OMNI_BUILDING_FOR_MAC
    NSURLBookmarkResolutionOptions options = NSURLBookmarkResolutionWithSecurityScope;
#elif OMNI_BUILDING_FOR_IOS
    NSURLBookmarkResolutionOptions options = 0;
#else
#error Unknown platform
#endif

    NSURL *url = [NSURL URLByResolvingBookmarkData:data options:NSURLBookmarkResolutionWithoutUI|options relativeToURL:nil/*app-scoped*/ bookmarkDataIsStale:outStale error:outError];
    if (url != nil)
        return url;

    // Note: We've already populated outError
#if OMNI_BUILDING_FOR_IOS
    return RecoveredURLFromBookmarkData(data, outStale);
#else
    return nil;
#endif

}

static BOOL StartAccessing(NSURL *url)
{
#if OMNI_BUILDING_FOR_IOS
    // On iOS, this isn't necessary since our local documents folder is in our container. Also *sometimes* this works and sometimes it fails for reasons that aren't clear.
    return YES;
#else
    return [url startAccessingSecurityScopedResource];
#endif
}
#define startAccessingSecurityScopedResource Use_StartAccessing_Wrapper

static void StopAccessing(NSURL *url)
{
#if OMNI_BUILDING_FOR_IOS
    // Nothing, since we didn't call -startAccessingSecurityScopedResource above
#else
    [url stopAccessingSecurityScopedResource];
#endif
}
#define stopAccessingSecurityScopedResource Use_StopAccessing_Wrapper

@implementation OFXServerAccount
{
    // We access these from the account agent queue, but set them up on the main queue (at least currently). We avoid races where we'd temporarily have a nil _accessedLocalDocumentsBookmarkURL via @synchronized in the 'resolve' method and the lookup method. All other access is required to by on the main thread (other than initializers, since no one can be asking yet there).
    NSData *_localDocumentsBookmarkData; // The archived bookmark, which is what we store in our archived plist.
    NSURL *_localDocumentsBookmarkURL; // The security scoped bookmark (with the ?applesecurityscope=BAG_OF_HEX needed to gain access).
    NSURL *_accessedLocalDocumentsBookmarkURL; // The result of -startAccessingSecurityScopedResource.
    NSString *_lastKnownDisplayName;

#if !OFX_MAC_STYLE_ACCOUNT
    // For unmigrated iOS accounts, where the per-account Documents directory was stored in the container's ~/Library/Application/Support/OmniPresence/<random-id>/Documents.
    NSURL *_unmigratedLocalDocumentsURL;
    NSString *_unmigratedNickname;
    
    BOOL _hasStartedMigration;
#endif
}


#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
static BOOL _testURLPathForHomeDirectoryFolder(NSString *urlPath, NSString *homeDirectory, NSString *folder)
{
    NSString *prefixPath = [homeDirectory stringByAppendingPathComponent:folder];
    return [urlPath hasPrefix:prefixPath] && (urlPath.length == prefixPath.length || [urlPath characterAtIndex:prefixPath.length] == '/');
}

static BOOL _validateNotDropbox(NSURL *url, NSError **outError)
{
    NSString *homeDirectory = OFUnsandboxedHomeDirectory();
    NSString *urlPath = url.path;
    // 10.12 Sierra prompts people to store their Desktop and Documents in iCloud
    for (NSString *dangerousFolder in [[OFPreference preferenceForKey:@"OFXDangerousSierraFolders"] arrayValue]) {
        if (_testURLPathForHomeDirectoryFolder(urlPath, homeDirectory, dangerousFolder)) {
            if (outError) {
                NSString *description = NSLocalizedStringFromTableInBundle(@"Please choose another location for your synced documents.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
                BOOL isOnDesktop = OFISEQUAL(dangerousFolder, @"Desktop");
                NSString *reason = isOnDesktop ? NSLocalizedStringFromTableInBundle(@"The selected local folder is on your Desktop, which can be synchronized by iCloud Drive on Sierra. Using two file synchronization systems on the same folder can result in data loss.", @"OmniFileExchange", OMNI_BUNDLE, @"error description") : [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The selected local folder is in your %@ folder, which can be synchronized by iCloud Drive on Sierra. Using two file synchronization systems on the same folder can result in data loss.", @"OmniFileExchange", OMNI_BUNDLE, @"error description"), dangerousFolder];
                OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
            }
            return NO;
        }
    }

    for (NSString *dangerousFolder in [[OFPreference preferenceForKey:@"OFXDangerousHomeFolders"] arrayValue]) {
        if (_testURLPathForHomeDirectoryFolder(urlPath, homeDirectory, dangerousFolder)) {
            if (outError) {
                NSString *description = NSLocalizedStringFromTableInBundle(@"Please choose another location for your synced documents.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
                NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The selected local folder is in your %@ folder. Using two file synchronization systems on the same folder can result in data loss.", @"OmniFileExchange", OMNI_BUNDLE, @"error description"), dangerousFolder];
                OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
            }
            return NO;
        }
    }

    NSArray *components = [url pathComponents];
    for (NSString *dangerousFolder in [[OFPreference preferenceForKey:@"OFXDangerousSyncedFolders"] arrayValue]) {
        if ([components containsObject:dangerousFolder]) {
            if (outError) {
                NSString *description = NSLocalizedStringFromTableInBundle(@"Please choose another location for your synced documents.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
                NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The selected local folder appears to be inside a %@ folder. Using two file synchronization systems on the same folder can result in data loss.", @"OmniFileExchange", OMNI_BUNDLE, @"error description"), dangerousFolder];
                OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
            }
            return NO;
        }
    }

    return YES;
}

static BOOL _validateLocalFileSystem(NSURL *url, NSError **outError)
{
    struct statfs fs_info = {0};
    if (statfs([[url path] UTF8String], &fs_info) < 0) {
        if (outError) {
            OBErrorWithErrno(outError, errno, "statfs", [url path], @"statfs failed for proposed local documents URL");
            
            NSString *description = NSLocalizedStringFromTableInBundle(@"Local documents folder cannot be used.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
            NSString *reason = NSLocalizedStringFromTableInBundle(@"Unable to determine the filesystem properties of the proposed documents folder.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
            OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
        }
        return NO;
    }
    
    // Require local filesystems so that we don't have cache coherency issues between clients over NFS/AFP/webdav_fs (making it look like files are missing that really should be there, leading to us deleting them from the server). Also, we don't want network issues to cause us to think files have gone missing, possibly leading to us issuing deletes.
    if ((fs_info.f_flags & MNT_LOCAL) == 0) {
        if (outError) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Local documents folder cannot be used.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
            NSString *reason = NSLocalizedStringFromTableInBundle(@"The proposed local documents folder is not on a local volume. Please pick a location that is local to your computer.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
            OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
        }
        return NO;
    }
    
    return YES;
}

#else /* TARGET_OS_IPHONE */

static BOOL _validateWithinSandboxedDocumentsFolder(NSURL *url, NSError **outError)
{
    NSURL *proposedURL = url.URLByStandardizingPath;
    NSURL *documentsDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:outError];
    if (documentsDirectoryURL == nil) {
        return NO;
    }

    NSString *proposedPath = proposedURL.path;
    NSString *documentsPath = documentsDirectoryURL.path;
    if (![proposedPath hasPrefix:documentsPath]) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Local documents folder cannot be used.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"The proposed local documents folder is not within the app's local documents. Please pick a location within that folder.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
        return NO;
    }

    NSString *trashPath = [documentsPath stringByAppendingPathComponent:@".Trash"];
    if ([proposedPath hasPrefix:trashPath]) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Local documents folder cannot be used.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"The proposed local documents folder is within the app's trash. This could lead to files getting unintentionally removed.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
        return NO;
    }

    return YES;
}

#endif

+ (BOOL)validateLocalDocumentsURL:(NSURL *)documentsURL reason:(OFXServerAccountLocalDirectoryValidationReason)validationReason error:(NSError **)outError;
{
    if (validationReason == OFXServerAccountValidateLocalDirectoryForAccountCreation) {
        // The directory needs to be empty since we don't want to spuriously generate conflicts/deletions when attaching a folder with gunk in it.
        __autoreleasing NSError *contentsError;
        NSArray *existingURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:documentsURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsSubdirectoryDescendants error:&contentsError];
        if (!existingURLs) {
            NSLog(@"Error getting contents of proposed local documents directory %@: %@", documentsURL, [contentsError toPropertyList]);
            if (outError)
                *outError = contentsError;
            return NO;
        }
        for (NSURL *existingURL in existingURLs) {
            if (OFShouldIgnoreURLDuringScan(existingURL))
                continue;
            
            NSString *description = NSLocalizedStringFromTableInBundle(@"Local documents folder cannot be used.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
            NSString *reason = NSLocalizedStringFromTableInBundle(@"The proposed local documents folder already contains files. Please specify an empty folder or one that doesn't yet exist.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
            OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
            return NO;
        }
    } else {
        OBASSERT(validationReason == OFXServerAccountValidateLocalDirectoryForSyncing);
    }
    
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    // Make sure the proposed URL isn't located inside other synchronized folders.
    if (!_validateNotDropbox(documentsURL, outError))
        return NO;
    
    if (!_validateLocalFileSystem(documentsURL, outError))
        return NO;
#else
    if (!_validateWithinSandboxedDocumentsFolder(documentsURL, outError))
        return NO;
#endif
    
    // Make sure we can create a temporary items folder on this filesystem. We may not have permission to create <FS_ROOT>/.TemporaryItems, but we want to be able to atomically move stuff into the documents directory. If we get this too often, we could make our own <DOC_DIR>/.com.omnigroup.OmniPresence.TemporaryItems/ folder and exclude it from scanning.
    {
        NSURL *temporaryURL = [[NSFileManager defaultManager] temporaryURLForWritingToURL:[documentsURL URLByAppendingPathComponent:@"test" isDirectory:NO] allowOriginalDirectory:NO error:outError];
        if (!temporaryURL) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Local documents folder cannot be used.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
            NSString *reason = NSLocalizedStringFromTableInBundle(@"Unable to create temporary items in the proposed location.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
            OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
            return NO;
        }
    }
    
    return YES;
}

+ (BOOL)validatePotentialLocalDocumentsParentURL:(NSURL *)documentsURL registry:(OFXServerAccountRegistry *)registry error:(NSError **)outError;
{
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    if (!_validateNotDropbox(documentsURL, outError))
        return NO;
    
    if (!_validateLocalFileSystem(documentsURL, outError))
        return NO;
#endif

    NSArray *syncAccounts = [[registry validCloudSyncAccounts] copy];
    for (OFXServerAccount *account in syncAccounts) {
        if (![account resolveLocalDocumentsURL:NULL])
            continue;

        if (OFURLContainsURL(account.localDocumentsURL, documentsURL)) {
            NSString *description = NSLocalizedStringFromTableInBundle(@"Local documents folder cannot be used.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
            NSString *reason = NSLocalizedStringFromTableInBundle(@"Another account is syncing to this folder already.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
            OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
            return NO;
        }
    }
    
    return YES;
}

+ (nullable OFXServerAccount *)accountSyncingLocalURL:(NSURL *)url fromRegistry:(OFXServerAccountRegistry *)registry;
{
    NSArray *syncAccounts = [[registry validCloudSyncAccounts] copy];
    for (OFXServerAccount *account in syncAccounts) {
        if (![account resolveLocalDocumentsURL:NULL])
            continue;

        if (OFURLContainsURL(account.localDocumentsURL, url)) {
            return account;
        }
    }

    return nil;
}

+ (nullable NSURL *)signinURLFromWebDAVString:(NSString *)webdavString;
{
    NSURL *url = [NSURL URLWithString:webdavString];

    if (url == nil)
        url = [NSURL URLWithString:[webdavString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]]];

    OFCreateRegularExpression(reasonableHostnameRegularExpression, @"^[-_$A-Za-z0-9]+\\.[-_$A-Za-z0-9]+");

    if ([url scheme] == nil && ![NSString isEmptyString:webdavString] && [reasonableHostnameRegularExpression of_firstMatchInString:webdavString])
        url = [NSURL URLWithString:[@"http://" stringByAppendingString:webdavString]];

    NSString *scheme = [url scheme];
    if (OFNOTEQUAL(scheme, @"http") && OFNOTEQUAL(scheme, @"https"))
        return nil;

    if ([NSString isEmptyString:[url host]])
        return nil;

    return url;
}

+ (NSString *)suggestedDisplayNameForAccountType:(OFXServerAccountType *)accountType url:(nullable NSURL *)url username:(nullable NSString *)username excludingAccount:(nullable OFXServerAccount *)excludeAccount;
{
    OFXServerAccountRegistry *registry = [OFXServerAccountRegistry defaultAccountRegistry];
    NSArray <OFXServerAccount *> *allAccounts = registry.allAccounts;
    if (allAccounts.count == 0) {
        // If there aren't any other accounts, suggest "OmniPresence"
        return @"OmniPresence";
    }

    NSMutableArray <OFXServerAccount *> *similarAccounts = [NSMutableArray array];
    for (OFXServerAccount *account in allAccounts) {
        if (account.type != accountType || account == excludeAccount)
            continue;
        [similarAccounts addObject:account];
    }

    NSString *locationForDisplay;
    if (accountType.requiresServerURL && url.host != nil)
        locationForDisplay = url.host;
    else
        locationForDisplay = accountType.displayName;
    
    if (!accountType.requiresServerURL && similarAccounts.count == 0)
        return accountType.displayName; // The display name is sufficient unless the account type requires a server URL
    
    BOOL sameLocation = NO;
    for (OFXServerAccount *account in similarAccounts)
        if ((sameLocation = [[account _locationForDisplay] isEqualToString:locationForDisplay]))
            break;

    if (!sameLocation)
        return locationForDisplay;

    if (![NSString isEmptyString:username]) {
        BOOL sameUser = NO;
        for (OFXServerAccount *account in similarAccounts) {
            NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(account.credentialServiceIdentifier, NULL);
            if ((sameUser = OFISEQUAL(credential.user, username)))
                break;
        }
        if (!sameUser)
            return [NSString stringWithFormat:@"%@ (%@)", locationForDisplay, username];
    }

    NSString *commonRoot = [url path];
    for (OFXServerAccount *account in similarAccounts) {
        if ([account.remoteBaseURL.host isEqualToString:url.host])
            commonRoot = [NSString commonRootPathOfFilename:commonRoot andFilename:account.remoteBaseURL.path];
    }

    NSString *displayPath = [url path];
    if (commonRoot.length == displayPath.length)
        displayPath = @"";
    else if (commonRoot.length != 0)
        displayPath = [[NSString horizontalEllipsisString] stringByAppendingString:[displayPath substringFromIndex:commonRoot.length]];
    if (![NSString isEmptyString:displayPath])
        return [NSString stringWithFormat:@"%@ %@", locationForDisplay, displayPath];

    return locationForDisplay;
}

#if !OFX_MAC_STYLE_ACCOUNT

+ (nullable NSURL *)_localDocumentsArea:(NSError **)outError;
{
    static NSURL *localDocumentsArea = nil;
    static NSError *localDocumentsError = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // We don't have the server account's uuid yet the local documents directory has its own uuid.
        // Can't be directly in $HOME since that'll hit a sandbox violation.
        __autoreleasing NSError *error;
        NSURL *appSupportURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
        if (!appSupportURL) {
            localDocumentsError = error;
            return;
        }
        
        localDocumentsArea = [appSupportURL URLByAppendingPathComponent:@"OmniPresence" isDirectory:YES];
    });
    
    // We don't retry the creation if it fails on the first call, but at least make sure callers get the original error if they call again.
    if (!localDocumentsArea) {
        if (outError)
            *outError = localDocumentsError;
    }
    return localDocumentsArea;
}

// Returns a URL that is appropriate for use as the localDocumentsURL of a newly added account on iOS.
// Now that we store OmniPresence accounts in the ~/Documents folder this is a user-visible URL.
+ (nullable NSURL *)generateLocalDocumentsURLForNewAccountWithName:(nullable NSString *)nickname error:(NSError **)outError;
{
    NSURL *documentsDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:outError];
    if (!documentsDirectoryURL) {
        return nil;
    }
    
    if (OFIsEmptyString(nickname)) {
        nickname = @"OmniPresence";
    }
    nickname = [nickname stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    
    NSURL *accountDirectoryURL = [documentsDirectoryURL URLByAppendingPathComponent:nickname];
    NSString *path = [[NSFileManager defaultManager] uniqueFilenameFromName:[[accountDirectoryURL absoluteURL] path] allowOriginal:YES create:NO error:outError];
    if (!path) {
        return nil;
    }
    
    // We need to create the directory (passing create:NO above since that would make a flat file).
    NSURL *result = [NSURL fileURLWithPath:path isDirectory:YES];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:result withIntermediateDirectories:YES attributes:nil error:outError]) {
        return nil;
    }
    
    return result;
}

// At least one thing this method does (more checking history might be needed), is to deal with new installs of the app getting a new UUID for the container data. We archive the full URL and need to adjust it to the new location on an app upgrade.
+ (NSURL *)_fixLocalDocumentsURL:(NSURL *)documentsURL;
{
    NSURL *localDocumentsArea = [self _localDocumentsArea:NULL];
    assert(localDocumentsArea != nil);

    if (![[documentsURL lastPathComponent] isEqual:@"Documents"]) {
        return documentsURL; // It's not one of our generated documents URLs, so let's leave it alone
    }
    NSURL *accountIdURL = [documentsURL URLByDeletingLastPathComponent]; // Remove 'Documents', leaving the per-account random ID
    if ([[accountIdURL URLByDeletingLastPathComponent] isEqual:localDocumentsArea])
        return documentsURL; // This URL is already in the documents area

    NSURL *fixedDocumentsURL = [[localDocumentsArea URLByAppendingPathComponent:[accountIdURL lastPathComponent] isDirectory:YES] URLByAppendingPathComponent:@"Documents" isDirectory:YES];;
    return fixedDocumentsURL;
}

// This should only be called for non-migrated accounts. For migrated accounts, the documents folder is user visible and we treat it like we do on the Mac (in the iOS interface code we trash it).
+ (void)deleteGeneratedLocalDocumentsURL:(NSURL *)documentsURL accountRequiredMigration:(BOOL)accountRequiredMigration completionHandler:(void (^ _Nullable)(NSError * _Nullable errorOrNil))completionHandler;
{
    DEBUG_ACCOUNT_REMOVAL(1, @"Removing generated local documents directory at %@.", documentsURL);
    DEBUG_ACCOUNT_REMOVAL(1, @"  accountRequiredMigration is %d", accountRequiredMigration);

    if (accountRequiredMigration) {
        // In this case, check that this is a documents folder in the expected spot in the Library/Application Support folder.

        __autoreleasing NSError *error;
        NSURL *localDocumentsArea = [self _localDocumentsArea:&error];
        if (!localDocumentsArea) {
            if (completionHandler)
                completionHandler(error);
            return;
        }
        
        if (![[documentsURL lastPathComponent] isEqual:@"Documents"]) {
            NSLog(@"Refusing to delete local documents URL %@ because it doesn't end in \"Documents\".", documentsURL);
            if (completionHandler) {
                error = nil;
                OFXError(&error, OFXAccountLocalDocumentsDirectoryInvalidForDeletion, @"Error attempting to delete local account documentts", @"The passed in URL doesn't end in \"Documents\"");
                completionHandler(error);
            }
            return;
        }
        
        documentsURL = [documentsURL URLByDeletingLastPathComponent]; // Remove 'Documents', leaving the per-account random ID
        
        if (![[documentsURL URLByDeletingLastPathComponent] isEqual:localDocumentsArea]) {
            NSLog(@"Refusing to delete local documents URL %@ because it isn't in the local documents area %@.", documentsURL, localDocumentsArea);
            if (completionHandler) {
                error = nil;
                OFXError(&error, OFXAccountLocalDocumentsDirectoryInvalidForDeletion, @"Error attempting to delete local account documentts", @"The passed in URL is not inside the local documents area.");
                completionHandler(error);
            }
            return;
        }
    } else {
        // Otherwise, this should be a folder inside the user's local documents folder.
    }
    
    DEBUG_ACCOUNT_REMOVAL(1, @"Removing documents at URL %@", documentsURL);

    // Looks good! Go ahead and do the deletion. We need to do this with file coordination since there might still be documents open in some edge conditions. For example, on iOS a preview might be being generated, in which case the document will be open (and it will not accommodate deletion until that is done).
    // We can't block the main queue here or we'll deadlock, so this needs to be done on a background queue.
    
    NSOperationQueue *deletionQueue = [[NSOperationQueue alloc] init];
    deletionQueue.name = @"com.omnigroup.OmniFileExchange.AccountDeletion";
    
    completionHandler = [completionHandler copy];
    
    [deletionQueue addOperationWithBlock:^{
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __autoreleasing NSError *coordinationError;
        
        BOOL ok = [coordinator removeItemAtURL:documentsURL error:&coordinationError byAccessor:^BOOL(NSURL *newURL, NSError **outRemoveError) {
            __autoreleasing NSError *removeError;
            if (![[NSFileManager defaultManager] atomicallyRemoveItemAtURL:newURL error:&removeError]) {
                NSLog(@"Error removing local account documents at %@: %@", newURL, [removeError toPropertyList]);
                if (outRemoveError)
                    *outRemoveError = removeError;
                return NO;
            }
            return YES;
        }];
        
        if (completionHandler) {
            NSError *completionError = coordinationError;
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (!ok)
                    completionHandler(completionError);
                else
                    completionHandler(nil);
            }];
        }
    }];
}

#endif

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (nullable instancetype)initWithType:(OFXServerAccountType *)type usageMode:(OFXServerAccountUsageMode)usageMode remoteBaseURL:(NSURL *)remoteBaseURL localDocumentsURL:(NSURL *)localDocumentsURL error:(NSError **)outError;
{
    OBPRECONDITION(type);
    OBPRECONDITION(remoteBaseURL);
    OBPRECONDITION(![remoteBaseURL isFileURL]);
    OBPRECONDITION(localDocumentsURL);
    OBPRECONDITION([localDocumentsURL isFileURL]);
    
    if (!(self = [super init]))
        return nil;
    
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    CFStringRef uuidString = CFUUIDCreateString(kCFAllocatorDefault, uuid);
    _uuid = CFBridgingRelease(uuidString);
    CFRelease(uuid);
    
    _type = type;
    _remoteBaseURL = [[remoteBaseURL absoluteURL] copy];
    
    __autoreleasing NSError *bookmarkError;
    
    _localDocumentsBookmarkData = bookmarkDataWithURL(localDocumentsURL, &bookmarkError);
    if (!_localDocumentsBookmarkData) {
        [bookmarkError log:@"Error creating app-scoped bookmark data for %@", localDocumentsURL];
        if (outError)
            *outError = bookmarkError;
        return nil;
    }
    DEBUG_BOOKMARK(1, @"Made bookmark from %@, resulting in data %@", localDocumentsURL, _localDocumentsBookmarkData);
    
    __autoreleasing NSError *resolveError;
    if (![self resolveLocalDocumentsURL:&resolveError]) {
        [resolveError log:@"Error resolving just-created bookmark data %@", _localDocumentsBookmarkData];
        OBASSERT_NOT_REACHED("We were *just* passed this URL, so it should be good");
        if (outError)
            *outError = resolveError;
        return nil;
    }

    _usageMode = usageMode;
    
    OBASSERT_IF(_usageMode == OFXServerAccountUsageModeCloudSync, [[self.localDocumentsURL absoluteString] hasSuffix:@"/"]);
    return self;
}

- (void)dealloc;
{
    if (_localDocumentsBookmarkURL) {
        DEBUG_BOOKMARK(1, @"Stopping security scoped access of %@", _localDocumentsBookmarkURL);
        StopAccessing(_localDocumentsBookmarkURL);
        _localDocumentsBookmarkURL = nil;
    }
}

+ (NSSet *)keyPathsForValuesAffectingDisplayName;
{
    // uuid, type, and remoteBaseURL not included since they can't change.
    return [NSSet setWithObjects:
            LastKnownDislpayNameKey, // The display name is derived from the local folder name

            // On unmigrated accounts on iOS, the display name is derived from the nickname
            UnmigratedNicknameKey,

            RemoteBaseURLKey, // TODO: Comment above says this can't change, but this was included in previous iOS builds.
            nil];
}

- (NSString *)_locationForDisplay;
{
    if (_type.requiresServerURL)
        return self.remoteBaseURL.host;
    else
        return _type.displayName;
}

- (NSString *)displayName;
{
    OBPRECONDITION([NSThread isMainThread], "Not synchronizing here, but this should only be called for UI on the main thread.");
    
#if !OFX_MAC_STYLE_ACCOUNT
    // Older iOS accounts had an editable nickname.
    if (self.requiresMigration) {
        if (OFIsEmptyString(_unmigratedNickname)) {
            NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(self.credentialServiceIdentifier, NULL);
            return [OFXServerAccount suggestedDisplayNameForAccountType:_type url:self.remoteBaseURL username:credential.user excludingAccount:self];
        } else {
            return _unmigratedNickname;
        }
    }
#endif
    
    // On Mac, the display name is derived from the local folder name.
    OBASSERT(_lastKnownDisplayName, "Should have resolved the local documents URL once");
    return _lastKnownDisplayName;
}

- (NSString *)importTitle;
{
    return [_type importTitleForDisplayName:self.displayName];
}

- (NSString *)exportTitle;
{
    return [_type exportTitleForDisplayName:self.displayName];
}

- (NSString *)accountDetailsString;
{
    return [_type accountDetailsStringForAccount:self];
}

- (BOOL)_resolveLocalDocumentsURL:(NSError **)outError; // Decodes the bookmark and attempts to start accessing the security scoped bookmark
{
    // Does NOT early out if _accessedLocalDocumentsBookmarkURL != nil. This happens when we shut down an account agent and restart it due to the local documents directory moving.
    
#define ERROR_DESCRIPTION NSLocalizedStringFromTableInBundle(@"Cannot locate synchronized documents folder.", @"OmniFileExchange", OMNI_BUNDLE, @"error reason")
    
    if (!_localDocumentsBookmarkData) {
        OFXError(outError, OFXCannotResolveLocalDocumentsURL,
                 ERROR_DESCRIPTION,
                 NSLocalizedStringFromTableInBundle(@"No documents folder has been picked.", @"OmniFileExchange", OMNI_BUNDLE, @"error reason"));
        return NO;
    }
    
    if (_localDocumentsBookmarkURL) {
        DEBUG_BOOKMARK(1, @"Stopping security scoped access of %@", _localDocumentsBookmarkURL);
        DEBUG_BOOKMARK(3, @"from:\n%@", OFCopySymbolicBacktrace());
        StopAccessing(_localDocumentsBookmarkURL);
        _localDocumentsBookmarkURL = nil;
        _accessedLocalDocumentsBookmarkURL = nil;
    }
        
    BOOL stale = NO;
    _localDocumentsBookmarkURL = URLWithBookmarkData(_localDocumentsBookmarkData, &stale, outError);

    DEBUG_BOOKMARK(1, @"Resolved bookmark data to %@", _localDocumentsBookmarkURL);
    if (!_localDocumentsBookmarkURL) {
        DEBUG_BOOKMARK(2, @"Bookmark data was %@", _localDocumentsBookmarkData);
        OFXError(outError, OFXCannotResolveLocalDocumentsURL,
                 ERROR_DESCRIPTION,
                 NSLocalizedStringFromTableInBundle(@"Could not resolve archived bookmark for synchronized documents folder.", @"OmniFileExchange", OMNI_BUNDLE, @"error reason"));
        return NO;
    }
    
    DEBUG_BOOKMARK(1, @"Starting security scoped access of %@", _localDocumentsBookmarkURL);
    DEBUG_BOOKMARK(3, @"from:\n%@", OFCopySymbolicBacktrace());
    
    if (!StartAccessing(_localDocumentsBookmarkURL)) {
        OFXError(outError, OFXCannotResolveLocalDocumentsURL,
                 ERROR_DESCRIPTION,
                 NSLocalizedStringFromTableInBundle(@"Could not access synchronized documents folder.", @"OmniFileExchange", OMNI_BUNDLE, @"error reason"));
        return NO;
    }
    
    // The security scoped bookmark has file://path/?applesecurityscope=BAG_OF_HEX
    // Use whatever the bookmark said, but strip the query.
    _accessedLocalDocumentsBookmarkURL = [[NSURL fileURLWithPath:[[_localDocumentsBookmarkURL absoluteURL] path]] URLByStandardizingPath];
    DEBUG_BOOKMARK(1, @"Resolved local documents URL to %@", _accessedLocalDocumentsBookmarkURL);

    if (stale) {
        // We have to wait until we have access to the URL in order to make a new bookmark.
        NSLog(@"Bookmark data flagged as stale for %@ -- will rearchive.", _accessedLocalDocumentsBookmarkURL);
        
        // We are supposed to re-create our bookmark data in this case. In case of some system craziness, don't clobber our current data (since it gave us a URL...) and instead try next time.
        __autoreleasing NSError *error;
        NSData *updatedData = bookmarkDataWithURL(_accessedLocalDocumentsBookmarkURL, &error);
        if (!updatedData) {
            [error log:@"Error attempting to refresh bookmark data for stale bookmark at %@", _accessedLocalDocumentsBookmarkURL];
        } else {
            // Trigger a save of the plist.
            [self willChangeValueForKey:LocalDocumentsBookmarkDataKey];
            _localDocumentsBookmarkData = [updatedData copy];
            [self didChangeValueForKey:LocalDocumentsBookmarkDataKey];
        }
    }
    
    NSString *displayName = [_accessedLocalDocumentsBookmarkURL lastPathComponent];
    if (OFNOTEQUAL(_lastKnownDisplayName, displayName))
        self.lastKnownDisplayName = displayName; // Trigger a save of the plist
    
    return YES;
}

- (BOOL)resolveLocalDocumentsURL:(NSError **)outError; // Decodes the bookmark and attempts to start accessing the security scoped bookmark
{
#if !OFX_MAC_STYLE_ACCOUNT
    OBPRECONDITION(self.requiresMigration == NO, "An account that isn't migrated doesn't have a local documents bookmark to resolve yet");
#endif
    
    __autoreleasing NSError *resolveError;
    BOOL success;
    
    @synchronized(self) {
        success = [self _resolveLocalDocumentsURL:&resolveError];
    }
    
    if (!success) {
        [resolveError log:@"Error resolving local documents URL"];
        if (outError) {
            *outError = resolveError;
        }
        return NO;
    }
    return YES;
}

- (void)clearLocalDocumentsURL;
{
    @synchronized(self) {
        if (_localDocumentsBookmarkData == nil)
            return;
        
        DEBUG_BOOKMARK(1, @"Clearing local documents URL");
        [self willChangeValueForKey:OFValidateKeyPath(self, localDocumentsURL)];
        _accessedLocalDocumentsBookmarkURL = nil;
        StopAccessing(_localDocumentsBookmarkURL);
        _localDocumentsBookmarkURL = nil;
        _localDocumentsBookmarkData = nil;
        [self didChangeValueForKey:OFValidateKeyPath(self, localDocumentsURL)];
    }
}

- (void)recoverLostLocalDocumentsURL:(NSURL *)url;
{
    @synchronized(self) {
        [self willChangeValueForKey:OFValidateKeyPath(self, propertyList)];
        [self _updateLocalDocumentsURL:url];
        [self didChangeValueForKey:OFValidateKeyPath(self, propertyList)];
    }
}

- (BOOL)_updateLocalDocumentsURL:(NSURL *)updatedDocumentsURL;
{
    // Speculatively fill out the bookmark
    __autoreleasing NSError *bookmarkError;
    _localDocumentsBookmarkData = bookmarkDataWithURL(updatedDocumentsURL, &bookmarkError);
    if (!_localDocumentsBookmarkData) {
        DEBUG_BOOKMARK(0, @"Error creating bookmark data for %@: %@", updatedDocumentsURL, bookmarkError);
        return NO;
    }

     __autoreleasing NSError *resolveError;
    if (![self _resolveLocalDocumentsURL:&resolveError]) {
        _localDocumentsBookmarkData = nil; // Clear the bookmark data that didn't work.

        DEBUG_BOOKMARK(0, @"Error resolving new bookmark: %@", resolveError);
        return NO;
    }

    return YES;
}

#if !OFX_MAC_STYLE_ACCOUNT
@synthesize nickname = _unmigratedNickname;

- (BOOL)requiresMigration;
{
    return _unmigratedLocalDocumentsURL != nil;
}

- (void)startMigrationWithCompletionHandler:(void (^)(BOOL success, NSError * _Nullable error))completionHandler;
{
    assert([NSThread isMainThread]);

    if (_hasStartedMigration)
        return; // If we scan the account list and try to start migration again, just ignore the redundant attempt

    _hasStartedMigration = YES;
    
    NSURL *updatedDocumentsURL;
    {
        __autoreleasing NSError *documentsError = nil;
        
        NSURL *userDocumentsURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:&documentsError];
        if (!userDocumentsURL) {
            [documentsError log:@"Cannot find user documents directory to migrate OmniPresence account"];
            completionHandler(NO, documentsError);
            return;
        }
        
        NSString *displayName = [[self.displayName stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByReplacingOccurrencesOfString:@"." withString:@"-"];
        NSURL *proposedDocumentsURL = [userDocumentsURL URLByAppendingPathComponent:displayName];
        NSLog(@"proposedDocumentsURL for account %@ is %@", self, proposedDocumentsURL);
        
        // Handle the case of a directory already being there.
        documentsError = nil;
        NSString *updatedDocumentsPath = [[NSFileManager defaultManager] uniqueFilenameFromName:proposedDocumentsURL.absoluteURL.path allowOriginal:YES create:NO error:&documentsError];
        if (!updatedDocumentsPath) {
            [documentsError log:@"Cannot find unique path for %@", proposedDocumentsURL];
            completionHandler(NO, documentsError);
            return;
        }
        
        updatedDocumentsURL = [NSURL fileURLWithPath:updatedDocumentsPath];
        NSLog(@"updatedDocumentsURL for account %@ is %@", self, updatedDocumentsURL);
    }

    NSOperationQueue *originalQueue = NSOperationQueue.currentQueue; // We asserted we're in the main thread already, but...
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.name = @"com.omnigroup.OmniFileExchange.AccountMigration.Move";
    
    // Here we are moving out of our ~/Library and there should be vanishingly few file presenters still watching anything in the moving folder since the account is stopped. But, we might have preview generation going on or maybe some stray thing. We want those file presenters to think the folder has gone way, not get updated to point to the new location.
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
    NSFileAccessIntent *sourceIntent = [NSFileAccessIntent writingIntentWithURL:self.localDocumentsURL options:NSFileCoordinatorWritingForDeleting];
    NSFileAccessIntent *destinationIntent = [NSFileAccessIntent writingIntentWithURL:updatedDocumentsURL options:0];
    
    completionHandler = [completionHandler copy];
    [coordinator coordinateAccessWithIntents:@[sourceIntent, destinationIntent] queue:queue byAccessor:^(NSError * _Nullable error) {
        if (error) {
            [error log:@"Error coordinating file access with source %@ and destination %@", self.localDocumentsURL, updatedDocumentsURL];
            [originalQueue addOperationWithBlock:^{
                completionHandler(NO, error);
            }];
            return;
        }
        
        __autoreleasing NSError *moveError;
        if (![[NSFileManager defaultManager] moveItemAtURL:sourceIntent.URL toURL:destinationIntent.URL error:&moveError]) {
            [error log:@"Error moving account directory from %@ to %@", sourceIntent.URL, destinationIntent.URL];
            completionHandler(NO, error);
        } else {
            [originalQueue addOperationWithBlock:^{
                [self _didMigrateToLocalDocumentsURL:updatedDocumentsURL];
                completionHandler(YES, nil);
            }];
        }
        
    }];
}

- (void)_didMigrateToLocalDocumentsURL:(NSURL *)updatedDocumentsURL;
{
    OBPRECONDITION(_unmigratedLocalDocumentsURL);
    OBPRECONDITION(_accessedLocalDocumentsBookmarkURL == nil);
    OBPRECONDITION(_localDocumentsBookmarkURL == nil);
    OBPRECONDITION(_localDocumentsBookmarkData == nil);

    DEBUG_BOOKMARK(1, @"Did migrate to local documents URL %@", updatedDocumentsURL);

    if (![self _updateLocalDocumentsURL:updatedDocumentsURL]) {
        return;
    }

    // This is a hack to let OFXServerAccountRegistry know that it needs to move the whole metadata directory for this account.
    _didMigrate = YES;
    
    // We've migrated! Tell the account registry to save us -- clearing this will make us stop inserting a "localDocumentsURL" key in the dictionary (but this isn't one of the keys in +keyPathsForValuesAffectingPropertyList
    [self willChangeValueForKey:OFValidateKeyPath(self, propertyList)];
    _unmigratedLocalDocumentsURL = nil;
    [self didChangeValueForKey:OFValidateKeyPath(self, propertyList)];
    
    _didMigrate = NO;
}

#endif

- (NSURL *)localDocumentsURL;
{
    assert(_usageMode == OFXServerAccountUsageModeCloudSync); // We shouldn't be calling this for non-syncing accounts

    NSURL *localDocumentsURL;
    @synchronized(self) {
#if !OFX_MAC_STYLE_ACCOUNT
        if (_unmigratedLocalDocumentsURL != nil) {
            // We are still syncing from with the local documents stored in the application library.
            localDocumentsURL = _unmigratedLocalDocumentsURL;
            OBASSERT(_accessedLocalDocumentsBookmarkURL == nil);
        }
        else
#endif
        {
            localDocumentsURL = _accessedLocalDocumentsBookmarkURL;
#if !OFX_MAC_STYLE_ACCOUNT
            OBASSERT(_unmigratedLocalDocumentsURL == nil);
#endif
        }
    }
    assert(localDocumentsURL); // Must have called -resolveLocalDocumentsURL:.
    return localDocumentsURL;
}

- (void)prepareForRemoval;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (self.hasBeenPreparedForRemoval) {
        OBASSERT_NOT_REACHED("This account shouldn't be visible to the user");
        return;
    }

    DEBUG_ACCOUNT_REMOVAL(1, @"prepareForRemoval");
    
    // We don't currently remove the credentials here. There might be WebDAV operations going on (which should be stopped ASAP), but there is no point provoking weird error conditions. We want to shut down cleanly.
    [self willChangeValueForKey:HasBeenPreparedForRemovalKey];
    _hasBeenPreparedForRemoval = YES;
    [self didChangeValueForKey:HasBeenPreparedForRemovalKey];
}

- (void)reportError:(nullable NSError *)error;
{
    [self reportError:error format:nil];
}

- (void)reportError:(nullable NSError *)error format:(nullable NSString *)format, ...;
{
    if ([error causedByUserCancelling])
        return;

    NSString *reason;
    if (format) {
        va_list args;
        va_start(args, format);
        reason = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
    } else
        reason = nil;
    
    void (^report)(void) = ^{
        if (reason)
            [error logWithReason:reason];
        if (error && [self.lastError hasUnderlyingErrorDomain:ODAVErrorDomain code:ODAVCertificateNotTrusted]) // cert trust errors are sticky and not overridden by following errors
            return;
        self.lastError = error; // Fire KVO
    };

    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
    if ([NSOperationQueue currentQueue] == mainQueue)
        report();
    else
        [mainQueue addOperationWithBlock:report];
}

- (void)clearError;
{
    [self reportError:nil];
}

#pragma mark - Private

- (nullable instancetype)_initWithUUID:(NSString *)uuid propertyList:(NSDictionary *)propertyList error:(NSError **)outError;
{
    OBPRECONDITION(![NSString isEmptyString:uuid]);
    OBPRECONDITION([propertyList isKindOfClass:[NSDictionary class]]);
    
    if (!(self = [super init]))
        return nil;

    NSNumber *version = propertyList[@"version"];
    if (version == nil) {
        OFXError(outError, OFXServerAccountCannotLoad, @"Info.plist has no \"version\".", nil);
        return nil;
    }
    if ([version unsignedIntegerValue] != ServerAccountPropertyListVersion) {
        NSString *reason = [NSString stringWithFormat:@"This account definition uses version %@, but this version of OmniPresence requires version %@", version, [NSNumber numberWithUnsignedInteger:ServerAccountPropertyListVersion]];
        OFXError(outError, OFXServerAccountCannotLoad, @"Incompatible account definition.", reason);
        return nil;
    }

    _uuid = [uuid copy];
        
    NSString *typeIdentifier = propertyList[@"type"];
    _type = [OFXServerAccountType accountTypeWithIdentifier:typeIdentifier];
    if (!_type) {
        OFXError(outError, OFXServerAccountCannotLoad, @"Info.plist has invalid \"type\".", nil);
        return nil;
    }
    
    NSString *URLString = propertyList[@"remoteBaseURL"];
    if (URLString)
        _remoteBaseURL = [[NSURL alloc] initWithString:URLString];
    if (!_remoteBaseURL) {
        OFXError(outError, OFXServerAccountCannotLoad, @"Info.plist has invalid \"remoteBaseURL\".", nil);
        return nil;
    }

    // In this case, the app-scoped bookmark is the 'truth', but we'd like it to be the same was what we wrote in the plist
    // We don't treat errors in unarchiving this as fatal -- the user can reconnect to the account by picking another folder.
    _localDocumentsBookmarkData = [propertyList[@"localDocumentsBookmark"] copy];
    if (_localDocumentsBookmarkData) {
        DEBUG_BOOKMARK(1, @"Loaded bookmark data of %@", _localDocumentsBookmarkData);
    } else {
#if !OFX_MAC_STYLE_ACCOUNT
        // TODO: Not currently required but probably should be.
        URLString = propertyList[@"localDocumentsURL"];
        DEBUG_BOOKMARK(1, @"Unmigrated local URL loaded %@", URLString);

        if (URLString) {
            _unmigratedLocalDocumentsURL = [[NSURL alloc] initWithString:URLString];
            _unmigratedLocalDocumentsURL = [OFXServerAccount _fixLocalDocumentsURL:_unmigratedLocalDocumentsURL];
        } else {
            _unmigratedLocalDocumentsURL = nil;
        }

        DEBUG_BOOKMARK(1, @"Unmigrated local URL adjusted to %@", _unmigratedLocalDocumentsURL);
#endif
    }

    [self _takeValuesFromPropertyList:propertyList];
    
    return self;
}

- (void)_takeValuesFromPropertyList:(NSDictionary *)propertyList;
{
    OBPRECONDITION([NSThread isMainThread]); // KVO should only happen on the main thread, so we should only get the properties there.
    OBPRECONDITION([_type.identifier isEqualToString:propertyList[@"type"]]);
    
    // CANNOT USE SETTERS HERE. The setters flag the account as needing to be written.
    
    // <bug:///107243> (Feature: Completely separate OmniPresence accounts from WebDAV import/export accounts)
    // Convert legacy dual-mode accounts into cloud sync only accounts.
    BOOL isCloudAccount = [propertyList boolForKey:@"cloudSyncEnabled" defaultValue:YES];
    if (isCloudAccount)
        _usageMode = OFXServerAccountUsageModeCloudSync;
    else {
        OBASSERT([propertyList boolForKey:@"importExportEnabled" defaultValue:YES], "Deserialized an account that is neither for cloud sync nor for import/export");
        _usageMode = OFXServerAccountUsageModeImportExport;
    }

    OBASSERT(_lastKnownDisplayName == nil, @"should not have resolved the local documents URL yet");
    _lastKnownDisplayName = [propertyList[@"displayName"] copy];

#if !OFX_MAC_STYLE_ACCOUNT
    _unmigratedNickname = [[propertyList stringForKey:UnmigratedNicknameKey defaultValue:_lastKnownDisplayName] copy];
#endif
    
    _credentialServiceIdentifier = [propertyList[@"serviceIdentifier"] copy];
    
    _hasBeenPreparedForRemoval = [propertyList[@"removed"] boolValue];
}

+ (NSSet *)keyPathsForValuesAffectingPropertyList;
{
    // uuid, type, and remoteBaseURL not included since they can't change.
    return [NSSet setWithObjects:
            // The whole local documents folder can be renamed or moved using the Finder/Files.
            LastKnownDislpayNameKey,
            
            // This can get reset when our bookmark is flagged as 'stale'.
            LocalDocumentsBookmarkDataKey,

            UsageModeKey, CredentialServiceIdentifierKey, HasBeenPreparedForRemovalKey, nil];
}

- (NSDictionary *)propertyList;
{
    OBPRECONDITION([NSThread isMainThread]); // KVO should only happen on the main thread, so we should only get the properties there.

    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    
    // Required keys ... raise if these aren't set
    [plist setObject:@(ServerAccountPropertyListVersion) forKey:@"version"];
    [plist setObject:_type.identifier forKey:@"type"];
    
    // Optional
    if (_remoteBaseURL)
        [plist setObject:[_remoteBaseURL absoluteString] forKey:@"remoteBaseURL"];
    
    if (_localDocumentsBookmarkData)
        [plist setObject:_localDocumentsBookmarkData forKey:@"localDocumentsBookmark"];
    
    if (_lastKnownDisplayName)
        [plist setObject:_lastKnownDisplayName forKey:@"displayName"];
    
#if !OFX_MAC_STYLE_ACCOUNT
    if (_unmigratedNickname) {
        [plist setObject:_unmigratedNickname forKey:UnmigratedNicknameKey];
    }
    if (_unmigratedLocalDocumentsURL) {
        [plist setObject:[_unmigratedLocalDocumentsURL absoluteString] forKey:@"localDocumentsURL"];
    }
#endif

    switch (_usageMode) {
        case OFXServerAccountUsageModeCloudSync:
            plist[@"importExportEnabled"] = @NO;
            break;
        case OFXServerAccountUsageModeImportExport:
            plist[@"cloudSyncEnabled"] = @NO;
    }
    
    if (_credentialServiceIdentifier)
        [plist setObject:_credentialServiceIdentifier forKey:@"serviceIdentifier"];

    if (_hasBeenPreparedForRemoval) {
        DEBUG_ACCOUNT_REMOVAL(1, @"Recording `removed=YES` in account property list");
        plist[@"removed"] = @YES;
    }
    
    return plist;
}

- (NSComparisonResult)compareServerAccount:(OFXServerAccount *)otherAccount;
{
    return [self.displayName localizedStandardCompare:otherAccount.displayName];
}

#pragma mark - Internal

- (void)_storeCredential:(NSURLCredential *)credential forServiceIdentifier:(NSString *)serviceIdentifier;
{
    OBPRECONDITION(credential);
    OBPRECONDITION(![NSString isEmptyString:serviceIdentifier]);
    
    [self willChangeValueForKey:CredentialServiceIdentifierKey];
    {
        __autoreleasing NSError *writeError;
        if (!OFWriteCredentialsForServiceIdentifier(serviceIdentifier, credential.user, credential.password, &writeError)) {
            [writeError log:@"Error storing credentials for service identifier %@", serviceIdentifier];
            _credentialServiceIdentifier = nil;
        } else {
            _credentialServiceIdentifier = [serviceIdentifier copy];
        }
    }
    [self didChangeValueForKey:CredentialServiceIdentifierKey];
}

@end

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
NSString * const OFXAccountTransfersNeededNotification = @"OFXAccountTransfersNeededNotification";
NSString * const OFXAccountTransfersNeededDescriptionKey = @"OFXAccountTransfersNeededDescription";
#endif

NS_ASSUME_NONNULL_END

