// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXServerAccount-Internal.h"

#import <OmniFileExchange/OFXFeatures.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/NSURL-OFExtensions.h>

RCS_ID("$Id$")

static NSString * const RemoteBaseURLKey = @"remoteBaseURL";
static NSString * const DisplayNameKey = @"displayName";
#if OFX_MAC_STYLE_ACCOUNT
static NSString * const LastKnownDislpayNameKey = @"lastKnownDisplayName";
#else
static NSString * const NicknameKey = @"nickname";
#endif
static NSString * const IsCloudSyncEnabledKey = @"isCloudSyncEnabled";
static NSString * const CredentialServiceIdentifierKey = @"credentialServiceIdentifier";
static NSString * const HasBeenPreparedForRemovalKey = @"hasBeenPreparedForRemoval";

NSString * const OFXAccountPropertListKey = @"propertyList";

static const NSUInteger ServerAccountPropertyListVersion = 1;

@interface OFXServerAccount ()
@property(nonatomic,readwrite,strong) NSError *lastError;
#if OFX_MAC_STYLE_ACCOUNT
@property(nonatomic,copy) NSString *lastKnownDisplayName;
#endif
@end

#if OFX_MAC_STYLE_ACCOUNT
static NSInteger OFXBookmarkDebug = 0;
#define DEBUG_BOOKMARK(level, format, ...) do { \
    if (OFXBookmarkDebug >= (level)) \
        NSLog(@"BOOKMARK %@: " format, [self shortDescription], ## __VA_ARGS__); \
    } while (0)
#endif

@implementation OFXServerAccount
{
#if OFX_MAC_STYLE_ACCOUNT
    // We access these from the account agent queue, but set them up on the main queue (at least currently). We avoid races where we'd temporarily have a nil _accessedLocalDocumentsBookmarkURL via @synchronized in the 'resolve' method and the lookup method. All other access is required to by on the main thread (other than initializers, since no one can be asking yet there).
    NSData *_localDocumentsBookmarkData; // The archived bookmark, which is what we store in our archived plist.
    NSURL *_localDocumentsBookmarkURL; // The security scoped bookmark (with the ?applesecurityscope=BAG_OF_HEX needed to gain access).
    NSURL *_accessedLocalDocumentsBookmarkURL; // The result of -startAccessingSecurityScopedResource.
    NSString *_lastKnownDisplayName;
#else
    // We just store the local documents URL directly. This gets set once and never changed, so no locking is needed.
    NSURL *_localDocumentsURL;
#endif
}

+ (void)initialize;
{
    OBINITIALIZE;

#if OFX_MAC_STYLE_ACCOUNT
    OBInitializeDebugLogLevel(OFXBookmarkDebug);
#endif
}

+ (BOOL)validateLocalDocumentsURL:(NSURL *)documentsURL reason:(OFXServerAccountLocalDirectoryValidationReason)reason error:(NSError **)outError;
{
    if (reason == OFXServerAccountValidateLocalDirectoryForAccountCreation) {
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
            if (OFSShouldIgnoreURLDuringScan(existingURL))
                continue;
            
            NSString *description = NSLocalizedStringFromTableInBundle(@"Local documents folder cannot be used.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
            NSString *reason = NSLocalizedStringFromTableInBundle(@"The proposed local documents folder already contains files. Please specify an empty folder or one that doesn't yet exist.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
            OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
            return NO;
        }
    } else {
        OBASSERT(reason == OFXServerAccountValidateLocalDirectoryForSyncing);
    }
    
    // Make sure the proposed URL isn't located inside other synchronized folders.
    NSArray *components = [documentsURL pathComponents];
    if ([components containsObject:@"Dropbox"]) { // Dropbox allows you to move your folder, but not to rename it.
        NSString *description = NSLocalizedStringFromTableInBundle(@"Local documents folder cannot be used.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"The proposed local documents folder appears to be inside a Dropbox folder. Using two file synchronization systems on the same folder can result in data loss.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
        return NO;
    }
    
    
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    struct statfs fs_info = {0};
    if (statfs([[documentsURL path] UTF8String], &fs_info) < 0) {
        OBErrorWithErrno(outError, errno, "statfs", [documentsURL path], @"statfs failed for proposed local documents URL");
        
        NSString *description = NSLocalizedStringFromTableInBundle(@"Local documents folder cannot be used.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Unable to determine the filesystem properties of the proposed documents folder.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
        return NO;
    }
    
    // Require local filesystems so that we don't have cache coherency issues between clients over NFS/AFP/webdav_fs (making it look like files are missing that really should be there, leading to us deleting them from the server). Also, we don't want network issues to cause us to think files have gone missing, possibly leading to us issuing deletes.
    if ((fs_info.f_flags & MNT_LOCAL) == 0) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Local documents folder cannot be used.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"The proposed local documents folder is not on a local volume. Please pick a location that is local to your computer.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        OFXError(outError, OFXLocalAccountDirectoryNotUsable, description, reason);
        return NO;
    }
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

+ (NSURL *)signinURLFromWebDAVString:(NSString *)webdavString;
{
    NSURL *url = [NSURL URLWithString:webdavString];

    if (url == nil)
        url = [NSURL URLWithString:[webdavString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];

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

+ (NSString *)suggestedDisplayNameForAccountType:(OFXServerAccountType *)accountType url:(NSURL *)url username:(NSString *)username excludingAccount:(OFXServerAccount *)excludeAccount;
{
    OFXServerAccountRegistry *registry = [OFXServerAccountRegistry defaultAccountRegistry];
    NSMutableArray *similarAccounts = [NSMutableArray array];
    for (OFXServerAccount *account in [registry allAccounts]) {
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
        for (OFXServerAccount *account in similarAccounts)
            if ((sameUser = OFISEQUAL(account.credential.user, username)))
                break;
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

+ (NSURL *)_localDocumentsArea:(NSError **)outError;
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
+ (NSURL *)generateLocalDocumentsURLForNewAccount:(NSError **)outError;
{
    NSURL *localDocumentsArea = [self _localDocumentsArea:outError];
    if (!localDocumentsArea)
        return nil;
    
    // Add a per-account random ID.
    NSURL *documentsURL = [localDocumentsArea URLByAppendingPathComponent:OFXMLCreateID() isDirectory:YES];
    
    // Currently has to end in "Documents" for OFSDocumentStoreScopeCacheKeyForURL().
    documentsURL = [documentsURL URLByAppendingPathComponent:@"Documents" isDirectory:YES];
    
    return documentsURL;
}

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

+ (BOOL)deleteGeneratedLocalDocumentsURL:(NSURL *)documentsURL error:(NSError **)outError;
{
    NSURL *localDocumentsArea = [self _localDocumentsArea:outError];
    if (!localDocumentsArea)
        return NO;
    
    if (![[documentsURL lastPathComponent] isEqual:@"Documents"]) {
        NSLog(@"Refusing to delete local documents URL %@ because it doesn't end in \"Documents\".", documentsURL);
        OFXError(outError, OFXAccountLocalDocumentsDirectoryInvalidForDeletion, @"Error attempting to delete local account documentts", @"The passed in URL doesn't end in \"Documents\"");
        return NO;
    }
    
    documentsURL = [documentsURL URLByDeletingLastPathComponent]; // Remove 'Documents', leaving the per-account random ID

    if (![[documentsURL URLByDeletingLastPathComponent] isEqual:localDocumentsArea]) {
        NSLog(@"Refusing to delete local documents URL %@ because it isn't in the local documents area %@.", documentsURL, localDocumentsArea);
        OFXError(outError, OFXAccountLocalDocumentsDirectoryInvalidForDeletion, @"Error attempting to delete local account documentts", @"The passed in URL is not inside the local documents area.");
        return NO;
    }
    
    // Looks good!
    __autoreleasing NSError *removeError;
    if (![[NSFileManager defaultManager] atomicallyRemoveItemAtURL:documentsURL error:&removeError]) {
        NSLog(@"Error removing local account documents at %@: %@", documentsURL, [removeError toPropertyList]);
        if (outError)
            *outError = removeError;
        return NO;
    }
    
    return YES;
}

#endif

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- initWithType:(OFXServerAccountType *)type remoteBaseURL:(NSURL *)remoteBaseURL localDocumentsURL:(NSURL *)localDocumentsURL error:(NSError **)outError;
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
    
#if OFX_MAC_STYLE_ACCOUNT
    __autoreleasing NSError *bookmarkError;
    _localDocumentsBookmarkData = [localDocumentsURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:nil relativeToURL:nil/*app scoped*/ error:&bookmarkError];
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
#else
    _localDocumentsURL = [[localDocumentsURL absoluteURL] copy];
    _nickname = nil;
#endif
    
    _isCloudSyncEnabled = YES;
    
    OBPOSTCONDITION([[self.localDocumentsURL absoluteString] hasSuffix:@"/"]);
    return self;
}

#if OFX_MAC_STYLE_ACCOUNT
- (void)dealloc;
{
    if (_localDocumentsBookmarkURL) {
        DEBUG_BOOKMARK(1, @"Stopping security scoped access of %@", _localDocumentsBookmarkURL);
        [_localDocumentsBookmarkURL stopAccessingSecurityScopedResource];
        _localDocumentsBookmarkURL = nil;
    }
}
#endif

+ (NSSet *)keyPathsForValuesAffectingDisplayName;
{
    // uuid, type, and remoteBaseURL not included since they can't change.
    return [NSSet setWithObjects:
#if OFX_MAC_STYLE_ACCOUNT
            LastKnownDislpayNameKey, // On Mac, the display name is derived from the local folder name
#else
            // On iOS, the display name is derived from the nickname
            NicknameKey,
            RemoteBaseURLKey,
#endif
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
#if OFX_MAC_STYLE_ACCOUNT
    OBPRECONDITION([NSThread isMainThread], "Not synchronizing here, but this should only be called for UI on the main thread.");
    
    // On Mac, the display name is derived from the local folder name.
    OBASSERT(_lastKnownDisplayName, "Should have resolved the local documents URL once");
    return _lastKnownDisplayName;
#else
    // On iOS, the nickname is an editable property of the account
    if (![NSString isEmptyString:_nickname])
        return _nickname;

    return [OFXServerAccount suggestedDisplayNameForAccountType:_type url:self.remoteBaseURL username:self.credential.user excludingAccount:self];
#endif
}

- (NSURLCredential *)credential;
{
    if (!_credentialServiceIdentifier)
        return nil;
    return OFReadCredentialsForServiceIdentifier(_credentialServiceIdentifier);
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

#if OFX_MAC_STYLE_ACCOUNT

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
        [_localDocumentsBookmarkURL stopAccessingSecurityScopedResource];
        _localDocumentsBookmarkURL = nil;
        _accessedLocalDocumentsBookmarkURL = nil;
    }
        
    BOOL stale;
    _localDocumentsBookmarkURL = [NSURL URLByResolvingBookmarkData:_localDocumentsBookmarkData options:NSURLBookmarkResolutionWithoutUI|NSURLBookmarkResolutionWithSecurityScope relativeToURL:nil/*app-scoped*/ bookmarkDataIsStale:&stale error:outError];
    DEBUG_BOOKMARK(1, @"Resolved bookmark data to %@", _localDocumentsBookmarkURL);
    if (!_localDocumentsBookmarkURL) {
        OFXError(outError, OFXCannotResolveLocalDocumentsURL,
                 ERROR_DESCRIPTION,
                 NSLocalizedStringFromTableInBundle(@"Could not resolve archived bookmark for synchronized documents folder.", @"OmniFileExchange", OMNI_BUNDLE, @"error reason"));
        return NO;
    }
    
    if (stale) {
        NSLog(@"Archived bookmark data was flagged as stale");
        OBFinishPortingLater("What does this mean? Original URL moved?");
    }
    
    DEBUG_BOOKMARK(1, @"Starting security scoped access of %@", _localDocumentsBookmarkURL);
    if (![_localDocumentsBookmarkURL startAccessingSecurityScopedResource]) {
        OFXError(outError, OFXCannotResolveLocalDocumentsURL,
                 ERROR_DESCRIPTION,
                 NSLocalizedStringFromTableInBundle(@"Could not access synchronized documents folder.", @"OmniFileExchange", OMNI_BUNDLE, @"error reason"));
        return NO;
    }

    // The security scoped bookmark has file://path/?applesecurityscope=BAG_OF_HEX
    // Use whatever the bookmark said, but strip the query.
    _accessedLocalDocumentsBookmarkURL = [[NSURL fileURLWithPath:[[_localDocumentsBookmarkURL absoluteURL] path]] URLByStandardizingPath];
    DEBUG_BOOKMARK(1, @"Resolved local documents URL to %@", _accessedLocalDocumentsBookmarkURL);

    NSString *displayName = [_accessedLocalDocumentsBookmarkURL lastPathComponent];
    if (OFNOTEQUAL(_lastKnownDisplayName, displayName))
        self.lastKnownDisplayName = displayName;
    
    return YES;
}

- (BOOL)resolveLocalDocumentsURL:(NSError **)outError; // Decodes the bookmark and attempts to start accessing the security scoped bookmark
{
    __autoreleasing NSError *resolveError;
    BOOL success;
    
    @synchronized(self) {
        success = [self _resolveLocalDocumentsURL:&resolveError];
    }
    
    if (!success) {
        [resolveError log:@"Error resolving local documents URL"];
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
        [_localDocumentsBookmarkURL stopAccessingSecurityScopedResource];
        _localDocumentsBookmarkURL = nil;
        _localDocumentsBookmarkData = nil;
        [self didChangeValueForKey:OFValidateKeyPath(self, localDocumentsURL)];
    }
}

#endif

- (NSURL *)localDocumentsURL;
{
    assert(_isCloudSyncEnabled); // We shouldn't be calling this for non-syncing accounts
#if OFX_MAC_STYLE_ACCOUNT
    NSURL *localDocumentsURL;
    @synchronized(self) {
        localDocumentsURL = _accessedLocalDocumentsBookmarkURL;
    }
    assert(localDocumentsURL); // Must have called -resolveLocalDocumentsURL:.
    return localDocumentsURL;
#else
    OBPRECONDITION(_localDocumentsURL);
    return _localDocumentsURL;
#endif
}

- (BOOL)isImportExportEnabled;
{
    return YES;
}

- (void)prepareForRemoval;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (self.hasBeenPreparedForRemoval) {
        OBASSERT_NOT_REACHED("This account shouldn't be visible to the user");
        return;
    }

    // We don't currently remove the credentials here. There might be WebDAV operations going on (which should be stopped ASAP), but there is no point provoking weird error conditions. We want to shut down cleanly.
    [self willChangeValueForKey:HasBeenPreparedForRemovalKey];
    _hasBeenPreparedForRemoval = YES;
    [self didChangeValueForKey:HasBeenPreparedForRemovalKey];
}

- (void)reportError:(NSError *)error;
{
    if ([error causedByUserCancelling])
        return;
    
    void (^report)(void) = ^{
        if (error && [self.lastError hasUnderlyingErrorDomain:OFSErrorDomain code:OFSCertificateNotTrusted]) // cert trust errors are sticky and not overridden by following errors
            return;
        self.lastError = error; // Fire KVO
    };
    
    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
    if ([NSOperationQueue currentQueue] == mainQueue)
        report();
    else
        [mainQueue addOperationWithBlock:report];
}

- (void)reportError:(NSError *)error format:(NSString *)format, ...;
{
    va_list args;
    va_start(args, format);
    NSString *reason = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    void (^report)(void) = ^{
        [error logWithReason:reason];
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

- _initWithUUID:(NSString *)uuid propertyList:(NSDictionary *)propertyList error:(NSError **)outError;
{
    OBPRECONDITION(![NSString isEmptyString:uuid]);
    OBPRECONDITION([propertyList isKindOfClass:[NSDictionary class]]);
    
    if (!(self = [super init]))
        return nil;

    NSNumber *version = propertyList[@"version"];
    if (!version) {
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

#if OFX_MAC_STYLE_ACCOUNT
    // In this case, the app-scoped bookmark is the 'truth', but we'd like it to be the same was what we wrote in the plist
    // We don't treat errors in unarchiving this as fatal -- the user can reconnect to the account by picking another folder.
    _localDocumentsBookmarkData = [propertyList[@"localDocumentsBookmark"] copy];
    DEBUG_BOOKMARK(1, @"Loaded bookmark data of %@", _localDocumentsBookmarkData);
#else
    // TODO: Not currently required but probably should be.
    URLString = propertyList[@"localDocumentsURL"];
    if (URLString)
        _localDocumentsURL = [[NSURL alloc] initWithString:URLString];
    else
        _localDocumentsURL = nil;
    
    _localDocumentsURL = [OFXServerAccount _fixLocalDocumentsURL:_localDocumentsURL];
#endif

    [self _takeValuesFromPropertyList:propertyList];
    
    return self;
}

- (void)_takeValuesFromPropertyList:(NSDictionary *)propertyList;
{
    OBPRECONDITION([NSThread isMainThread]); // KVO should only happen on the main thread, so we should only get the properties there.
    OBPRECONDITION([_type.identifier isEqualToString:propertyList[@"type"]]);
    
    // CANNOT USE SETTERS HERE. The setters flag the account as needing to be written.
        
    _isCloudSyncEnabled = [propertyList boolForKey:@"cloudSyncEnabled" defaultValue:YES];

#if OFX_MAC_STYLE_ACCOUNT
    OBASSERT(_lastKnownDisplayName == nil, @"should not have resolved the local documents URL yet");
    _lastKnownDisplayName = [propertyList[@"displayName"] copy];
#else
    _nickname = [propertyList[@"displayName"] copy];
#endif

    _credentialServiceIdentifier = [propertyList[@"serviceIdentifier"] copy];
    
    _hasBeenPreparedForRemoval = [propertyList[@"removed"] boolValue];
}

+ (NSSet *)keyPathsForValuesAffectingPropertyList;
{
    // uuid, type, and remoteBaseURL not included since they can't change.
    return [NSSet setWithObjects:
#if OFX_MAC_STYLE_ACCOUNT
            // On Mac, the whole local documents folder can be renamed or moved using the Finder. But we don't change the bookmark data, so this doesn't need to be re-archived.
            LastKnownDislpayNameKey,
#else
            NicknameKey, // On iOS, the nickname can be changed by the user
#endif
            IsCloudSyncEnabledKey, CredentialServiceIdentifierKey, HasBeenPreparedForRemovalKey, nil];
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
    
#if OFX_MAC_STYLE_ACCOUNT
    if (_localDocumentsBookmarkData)
        [plist setObject:_localDocumentsBookmarkData forKey:@"localDocumentsBookmark"];
    if (_lastKnownDisplayName)
        [plist setObject:_lastKnownDisplayName forKey:@"displayName"];
#else
    if (_localDocumentsURL)
        [plist setObject:[_localDocumentsURL absoluteString] forKey:@"localDocumentsURL"];
    if (_nickname)
        [plist setObject:_nickname forKey:@"displayName"];
#endif

    if (!_isCloudSyncEnabled)
        plist[@"cloudSyncEnabled"] = @NO;
    
    if (_credentialServiceIdentifier)
        [plist setObject:_credentialServiceIdentifier forKey:@"serviceIdentifier"];

    if (_hasBeenPreparedForRemoval)
        plist[@"removed"] = @YES;
    
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
        _credentialServiceIdentifier = [serviceIdentifier copy];
        
        OFWriteCredentialsForServiceIdentifier(_credentialServiceIdentifier, credential.user, credential.password);
    }
    [self didChangeValueForKey:CredentialServiceIdentifierKey];
}

@end
