// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXServerAccount-Internal.h"

#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFileExchange/OFXFeatures.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>

RCS_ID("$Id$")

static NSString * const DisplayNameKey = @"displayName";
static NSString * const IsCloudSyncEnabledKey = @"isCloudSyncEnabled";
static NSString * const CredentialServiceIdentifierKey = @"credentialServiceIdentifier";
static NSString * const HasBeenPreparedForRemovalKey = @"hasBeenPreparedForRemoval";

NSString * const OFXAccountPropertListKey = @"propertyList";

static const NSUInteger ServerAccountPropertListVersion = 0;

@implementation OFXServerAccount
{
    NSURL *_localDocumentsURL;
#if OFX_USE_SECURITY_SCOPED_BOOKMARKS
    // The security scoped bookmark (with the ?applesecurityscope=BAG_OF_HEX needed to gain access).
    NSURL *_localDocumentsBookmarkURL;
#endif
    NSString *_displayName;
}

+ (BOOL)isValidLocalDocumentsURL:(NSURL *)documentsURL error:(NSError **)outError;
{
    // The call above will not error out if the directory already exists. If the directory does exist, it needs to be empty since we don't want to spuriously generate conflicts/deletions when attaching a folder with gunk in it.
    NSError *contentsError;
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
        
        NSString *description = NSLocalizedStringFromTableInBundle(@"Account could not be added.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        NSString *reason = NSLocalizedStringFromTableInBundle(@"The proposed local documents folder already contains files. Please specify an empty folder or one that doesn't yet exist.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        OFXError(outError, OFXAccountCannotBeAdded, description, reason);
        return NO;
    }
    return YES;
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

+ (NSURL *)_localDocumentsArea:(NSError **)outError;
{
    static NSURL *localDocumentsArea = nil;
    static NSError *localDocumentsError = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // We don't have the server account's uuid yet the local documents directory has its own uuid.
        // Can't be directly in $HOME since that'll hit a sandbox violation.
        NSError *error;
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
    NSError *removeError;
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

- initWithType:(OFXServerAccountType *)type remoteBaseURL:(NSURL *)remoteBaseURL localDocumentsURL:(NSURL *)localDocumentsURL;
{
    OBPRECONDITION(type);
    OBPRECONDITION(remoteBaseURL);
    OBPRECONDITION(![remoteBaseURL isFileURL]);
    OBPRECONDITION(localDocumentsURL);
    OBPRECONDITION([localDocumentsURL isFileURL]);
    OBPRECONDITION([[localDocumentsURL absoluteString] hasSuffix:@"/"]);
    
    if (!(self = [super init]))
        return nil;
    
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    CFStringRef uuidString = CFUUIDCreateString(kCFAllocatorDefault, uuid);
    _uuid = CFBridgingRelease(uuidString);
    CFRelease(uuid);
    
    _type = type;
    _remoteBaseURL = [[remoteBaseURL absoluteURL] copy];
    _localDocumentsURL = [[localDocumentsURL absoluteURL] copy];
    _displayName = nil;
    _isCloudSyncEnabled = YES;
    
    return self;
}

- (NSString *)displayName;
{
    if (![NSString isEmptyString:_displayName])
        return _displayName;
    
    OFXServerAccountRegistry *registry = [OFXServerAccountRegistry defaultAccountRegistry];
    NSMutableArray *similarAccounts = [NSMutableArray array];
    for (OFXServerAccount *account in [registry allAccounts]) {
        if (account.type != _type || account == self)
            continue;
        [similarAccounts addObject:account];
    }
    if (!similarAccounts.count)
        return _type.displayName;
    
    BOOL sameUser = NO;
    for (OFXServerAccount *account in similarAccounts)
        if ((sameUser = [account.credential.user isEqualToString:self.credential.user]))
            break;
    if (!sameUser)
        return [NSString stringWithFormat:@"%@ (%@)", _type.displayName, self.credential.user];
    
    BOOL sameHost = NO;
    for (OFXServerAccount *account in similarAccounts)
        if ((sameHost = [account.remoteBaseURL.host isEqualToString:self.remoteBaseURL.host]))
            break;
    if (!sameHost)
        return [NSString stringWithFormat:@"%@ %@", self.remoteBaseURL.host, _type.displayName];
    
    BOOL sameUserAndHost = NO;
    for (OFXServerAccount *account in similarAccounts) {
        if ([account.credential.user isEqualToString:self.credential.user] && [account.remoteBaseURL.host isEqualToString:self.remoteBaseURL.host]) {
            sameUserAndHost = YES;
            break;
        }
    }
    if (!sameUserAndHost)
        return [NSString stringWithFormat:@"%@ %@ (%@)", self.remoteBaseURL.host, _type.displayName, self.credential.user];
    
    NSString *commonRoot = [_remoteBaseURL path];
    for (OFXServerAccount *account in similarAccounts) {
        if ([account.remoteBaseURL.host isEqualToString:self.remoteBaseURL.host])
            commonRoot = [NSString commonRootPathOfFilename:commonRoot andFilename:account.remoteBaseURL.path];
    }
    NSString *displayPath = [_remoteBaseURL path];
    if (commonRoot.length == displayPath.length)
        displayPath = @"";
    else if (commonRoot.length)
        displayPath = [[NSString horizontalEllipsisString] stringByAppendingString:[displayPath substringFromIndex:commonRoot.length]];
    return [NSString stringWithFormat:@"%@ %@ %@", self.remoteBaseURL.host, displayPath, _type.displayName];
}

- (void)setDisplayName:(NSString *)displayName;
{    
    if (OFISEQUAL(_displayName, displayName))
        return;
    
    [self willChangeValueForKey:DisplayNameKey];
    _displayName = [displayName copy];
    [self didChangeValueForKey:DisplayNameKey];
}

- (NSURLCredential *)credential;
{
    if (!_credentialServiceIdentifier)
        return nil;
    return OFReadCredentialsForServiceIdentifier(_credentialServiceIdentifier);
}

- (NSString *)importTitle;
{
    return [_type importTitleForDisplayName:_displayName];
}

- (NSString *)exportTitle;
{
    return [_type exportTitleForDisplayName:_displayName];
}

- (NSString *)accountDetailsString;
{
    return [_type accountDetailsStringForAccount:self];
}

- (NSURL *)localDocumentsURL;
{
    assert(_isCloudSyncEnabled); // We shouldn't be calling this for non-syncing accounts
    return _localDocumentsURL;
}

- (BOOL)isImportExportEnabled;
{
    return YES; // Or possibly !_isCloudSyncEnabled, or possibly store its own attribute
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
    if ([version unsignedIntegerValue] != ServerAccountPropertListVersion) {
        OFXError(outError, OFXServerAccountCannotLoad, @"Info.plist has unknown \"version\".", nil);
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

    // TODO: Not currently required but probably should be.
    URLString = propertyList[@"localDocumentsURL"];
    if (URLString)
        _localDocumentsURL = [[NSURL alloc] initWithString:URLString];
    else
        _localDocumentsURL = nil;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    _localDocumentsURL = [OFXServerAccount _fixLocalDocumentsURL:_localDocumentsURL];
#endif

#if OFX_USE_SECURITY_SCOPED_BOOKMARKS
    // In this case, the app-scoped bookmark is the 'truth', but we'd like it to be the same was what we wrote in the plist
    NSData *bookmark = propertyList[@"localDocumentsBookmark"];
    if (bookmark) {
        NSError *error;
        BOOL stale;
        _localDocumentsBookmarkURL = [NSURL URLByResolvingBookmarkData:bookmark options:NSURLBookmarkResolutionWithoutUI|NSURLBookmarkResolutionWithSecurityScope relativeToURL:nil/*app-scoped*/ bookmarkDataIsStale:&stale error:&error];
        if (!_localDocumentsBookmarkURL) {
            NSLog(@"Error resolving local documents bookmark data: %@", [error toPropertyList]);
        } else if (stale) {
            OBFinishPortingLater("What does this mean? Original URL moved?");
        } else {
            OBASSERT([[[_localDocumentsURL absoluteURL] path] isEqual:[[_localDocumentsBookmarkURL absoluteURL] path]]); // Resolving yields file://path/?applesecurityscope=BAG_OF_HEX
            _localDocumentsURL = [NSURL fileURLWithPath:[[_localDocumentsBookmarkURL absoluteURL] path]]; // Use whatever the bookmark said, but strip the query.
        }
    } else {
        OBASSERT(_localDocumentsURL == nil); // But, really, this should be required
    }
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

    _displayName = [propertyList[@"displayName"] copy];
    
    _credentialServiceIdentifier = [propertyList[@"serviceIdentifier"] copy];
    
    _hasBeenPreparedForRemoval = [propertyList[@"removed"] boolValue];
}

+ (NSSet *)keyPathsForValuesAffectingPropertyList;
{
    // uuid, type, remoteBaseURL, and localDocumentsURL not included since they can't change.
    return [NSSet setWithObjects:DisplayNameKey, IsCloudSyncEnabledKey, CredentialServiceIdentifierKey, HasBeenPreparedForRemovalKey, nil];
}

- (NSDictionary *)propertyList;
{
    OBPRECONDITION([NSThread isMainThread]); // KVO should only happen on the main thread, so we should only get the properties there.

    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    
    // Required keys ... raise if these aren't set
    [plist setObject:@(ServerAccountPropertListVersion) forKey:@"version"];
    [plist setObject:_type.identifier forKey:@"type"];
    
    // Optional
    if (_remoteBaseURL)
        [plist setObject:[_remoteBaseURL absoluteString] forKey:@"remoteBaseURL"];
    if (_localDocumentsURL) {
        [plist setObject:[_localDocumentsURL absoluteString] forKey:@"localDocumentsURL"];
#if OFX_USE_SECURITY_SCOPED_BOOKMARKS
        NSError *error;
        NSData *bookmarkData = [_localDocumentsURL bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:nil relativeToURL:nil/*app scoped*/ error:&error];
        if (!bookmarkData) {
            NSLog(@"Error creating app-scoped bookmark data for %@: %@", _localDocumentsURL, [error toPropertyList]);
        } else {
            [plist setObject:bookmarkData forKey:@"localDocumentsBookmark"];
        }
#endif
    }

    if (!_isCloudSyncEnabled)
        plist[@"cloudSyncEnabled"] = @NO;
    
    if (_credentialServiceIdentifier)
        [plist setObject:_credentialServiceIdentifier forKey:@"serviceIdentifier"];
    if (_displayName)
        [plist setObject:_displayName forKey:@"displayName"];
    
    if (_hasBeenPreparedForRemoval)
        plist[@"removed"] = @YES;
    
    return plist;
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
