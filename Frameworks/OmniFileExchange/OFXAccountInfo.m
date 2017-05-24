// Copyright 2013-2015,2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXAccountInfo.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniDAV/ODAVOperation.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFileExchange/OFXAccountClientParameters.h>
#import <OmniBase/macros.h>

#import "OFXDAVUtilities.h"
#import "OFXPropertyListCache.h"
#import "OFXSyncClient.h"
#import "OFXPersistentPropertyList.h"

RCS_ID("$Id$")

static OFDeclareDebugLogLevel(OFXAccountInfoDebug);
#define DEBUG_CLIENT(level, format, ...) do { \
    if (OFXAccountInfoDebug >= (level)) \
        NSLog(@"ACCT INFO %@: " format, [self shortDescription], ## __VA_ARGS__); \
} while (0)

static NSString * const LocalStatePropertyListName = @"LocalState.plist";
static NSString * const LocalState_LastRemoteTemporaryFileCleanupDate = @"LastTemporaryFileCleanupDate";

@implementation OFXAccountInfo
{
    OFXPropertyListCache *_propertyListCache;
    OFXPersistentPropertyList *_localStatePropertyList;
    
    NSURL *_temporaryDirectoryURL;
    ODAVFileInfo *_accountFileInfo;
    NSDictionary *_accountPropertyList;
    OFVersionNumber *_accountVersion;
    
    OFXAccountClientParameters *_clientParameters;
    OFXSyncClient *_ourClient;
    
    NSDictionary <NSString *, OFXSyncClient *> *_clientByIdentifier;
}

static OFVersionNumber *MinimumCompatibleAccountVersionNumber;

+ (void)initialize;
{
    OBINITIALIZE;
    
    MinimumCompatibleAccountVersionNumber = [[OFVersionNumber alloc] initWithVersionString:@"2"];
}

- initWithLocalAccountDirectory:(NSURL *)localAccountDirectoryURL remoteAccountURL:(NSURL *)remoteAccountURL temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL clientParameters:(OFXAccountClientParameters *)clientParameters error:(NSError **)outError;
{
    OBPRECONDITION([localAccountDirectoryURL isFileURL]);
    OBPRECONDITION(remoteAccountURL);
    OBPRECONDITION(![remoteAccountURL isFileURL]);
    OBPRECONDITION(temporaryDirectoryURL);
    OBPRECONDITION(!OFURLEqualsURL(remoteAccountURL, temporaryDirectoryURL));
    OBPRECONDITION(clientParameters);
    
    if (!(self = [super init]))
        return nil;
    
    NSURL *accountInfoCacheURL = [localAccountDirectoryURL URLByAppendingPathComponent:@"InfoCache.plist"];
    _propertyListCache = [[OFXPropertyListCache alloc] initWithCacheFileURL:accountInfoCacheURL remoteTemporaryDirectoryURL:temporaryDirectoryURL remoteBaseDirectoryURL:remoteAccountURL];
    
    NSURL *localStateURL = [localAccountDirectoryURL URLByAppendingPathComponent:LocalStatePropertyListName];
    _localStatePropertyList = [[OFXPersistentPropertyList alloc] initWithFileURL:localStateURL];
    
    _remoteAccountURL = [remoteAccountURL copy];
    
    _temporaryDirectoryURL = [temporaryDirectoryURL copy];
    _clientParameters = clientParameters;

    // Set up clients from the cache w/o fetching (connection == nil, server date == nil)
    NSString *ourClientIdentifier = _clientParameters.defaultClientIdentifier;
    NSURL *ourClientURL = [_remoteAccountURL URLByAppendingPathComponent:[ourClientIdentifier stringByAppendingPathExtension:OFXClientPathExtension]];
    _ourClient = [[OFXSyncClient alloc] initWithURL:ourClientURL previousClient:_ourClient parameters:clientParameters error:outError];
    if (!_ourClient) {
        OBChainError(outError);
        return nil;
    }
    
    return self;
}

NSString * const OFXInfoFileName = @"Info.plist";
NSString * const OFXClientPathExtension = @"client";

NSString * const OFXAccountInfo_Group = @"NetStateGroup";
NSString * const OFXAccountInfo_Version = @"Version";

static NSTimeInterval _fileInfoAge(ODAVFileInfo *fileInfo, NSDate *serverDateNow)
{
    // Do a slightly better job of calculating the file item's age than assuming that our local clock and the server clock agree.
    return [serverDateNow timeIntervalSinceReferenceDate] - [fileInfo.lastModifiedDate timeIntervalSinceReferenceDate];
}

- (BOOL)_updateAccountInfo:(ODAVFileInfo *)accountFileInfo serverDate:(NSDate *)serverDate withConnection:(ODAVConnection *)connection error:(NSError **)outError;
{
    __block NSDictionary *infoDictionary;
    
    if (accountFileInfo) {
        __autoreleasing NSError *fetchError;
        infoDictionary = [_propertyListCache propertyListWithFileInfo:accountFileInfo serverDate:serverDate connection:connection error:&fetchError];
        if (!infoDictionary && ![fetchError hasUnderlyingErrorDomain:ODAVErrorDomain code:ODAV_HTTP_NOT_FOUND]) {
            if (outError)
                *outError = fetchError;
            OBChainError(outError);
            return NO;
        }
    }

    // _remoteAccountURL is our cannonical URL, but we might be redirected
    NSURL *infoURL = [connection suggestRedirectedURLForURL:[_remoteAccountURL URLByAppendingPathComponent:OFXInfoFileName]];
    
    if (!infoDictionary) {
        // There doesn't seem to be a remote file -- create it.
        infoDictionary = [self _makeInfoDictionary];

        __autoreleasing NSError *writeError;
        if (![_propertyListCache writePropertyList:infoDictionary toURL:infoURL overwrite:NO connection:connection error:&writeError]) {
            // Maybe we are racing and some other client uploaded an info file.
            if ([writeError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_PRECONDITION_FAILED]) {
                // Maybe we are racing and some other client uploaded an info file.
            } else {
                if (outError)
                    *outError = writeError;
                OBChainError(outError);
                return NO;
            }
        }
    }
    
    // Try refetching one more time if we were racing with a writer
    if (!infoDictionary) {
        __block ODAVFileInfo *resultFileInfo;
        __block NSDate *resultServerDate;
        __block NSError *resultError;
        
        ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done) {
            [connection fileInfoAtURL:infoURL ETag:nil completionHandler:^(ODAVSingleFileInfoResult *result, NSError *error) {
                resultFileInfo = result.fileInfo;
                resultServerDate = result.serverDate;
                resultError = error;
                done();
            }];
        });
        
        if (!resultFileInfo) {
            if (outError)
                *outError = resultError;
            OBChainError(outError);
            return NO;
        }
        
        accountFileInfo = resultFileInfo;
        serverDate = resultServerDate;
        
        if (!(infoDictionary = [_propertyListCache propertyListWithFileInfo:accountFileInfo serverDate:serverDate connection:connection error:outError])) {
            OBChainError(outError);
            return NO;
        }
    }
    
    // We don't currently validate the Info.plist and rewrite another if invalid (except for it not being a dictionary). The issue is that all we'd really be able to check is the OFXAccountInfo_Version (since the other keys might change) and the account info comes from the _clientParameters (an instance variable for testing), while we have a single cache for all account infos.
    // So, if an account gets an invalid Info.plist written, we just wedge on syncing and the user will need to manually intervene if there is something legitimately wrong (better than clobbering some valid but newer version plist).

    if (![infoDictionary[OFXAccountInfo_Group] isKindOfClass:[NSString class]]) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Cannot sync with account.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        OFXError(outError, OFXAccountRepositoryCorrupt, description, @"Info dictionary has no group identifier");
        return NO;
    }
    if (![infoDictionary[OFXAccountInfo_Version] isKindOfClass:[NSString class]]) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Cannot sync with account.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        OFXError(outError, OFXAccountRepositoryCorrupt, description, @"Info dictionary has no version string");
        return NO;
    }

    _accountPropertyList = [infoDictionary copy];
    _accountFileInfo = accountFileInfo;
    _accountVersion = [[OFVersionNumber alloc] initWithVersionString:infoDictionary[OFXAccountInfo_Version]];
    if (!_accountVersion) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Cannot sync with account.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        OFXError(outError, OFXAccountRepositoryCorrupt, description, @"Info dictionary has bad version string");
        return NO;
    }

    return YES;
}

- (BOOL)updateWithConnection:(ODAVConnection *)connection accountFileInfo:(ODAVFileInfo *)accountFileInfo clientFileInfos:(NSArray <ODAVFileInfo *> *)clientFileInfos remoteTemporaryDirectoryFileInfo:(ODAVFileInfo *)remoteTemporaryDirectoryFileInfo serverDate:(NSDate *)serverDate error:(NSError **)outError;
{
    if (![self _updateAccountInfo:accountFileInfo serverDate:serverDate withConnection:connection error:outError])
        return NO;

    // Check if the account repository is too new for us and bail right away if so.
    OBASSERT(_accountVersion);
    OBASSERT(_ourClient.currentFrameworkVersion);
    if ([_ourClient.currentFrameworkVersion compareToVersionNumber:_accountVersion] == NSOrderedAscending) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Sync failed: OmniPresence upgrade required.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The cloud account requires OmniPresence format %@, but this device is using format %@. Please upgrade this copy of OmniPresence.", @"OmniFileExchange", OMNI_BUNDLE, @"error reason"), [_accountVersion originalVersionString], [_ourClient.currentFrameworkVersion originalVersionString]];
        OFXErrorWithInfo(outError, OFXAccountRepositoryTooNew, description, reason, @"client", _ourClient.propertyList, @"server", _accountPropertyList, nil);
        return NO;
    }

    // Similarly, check whether the account repository is too old for us.
    if ([_accountVersion compareToVersionNumber:MinimumCompatibleAccountVersionNumber] == NSOrderedAscending) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Sync failed: cloud account needs to be upgraded.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"This app requires OmniPresence format %@, but the cloud account is using format %@. Please upgrade the cloud account.", @"OmniFileExchange", OMNI_BUNDLE, @"error reason"), [MinimumCompatibleAccountVersionNumber originalVersionString], [_accountVersion originalVersionString]];
        OFXErrorWithInfo(outError, OFXAccountRepositoryTooOld, description, reason, @"minimumRequiredVersion", [MinimumCompatibleAccountVersionNumber originalVersionString], @"server", _accountPropertyList, nil);
        return NO;
    }
    
    // Unlike OmniFocus, our client files do change over time (OmniFocus uses transaction identifiers in the clients to peg them in time, we just step the sync date forward).
            
    NSString *ourClientIdentifier = _clientParameters.defaultClientIdentifier;
    OBASSERT_NOTNULL(ourClientIdentifier); // help out clang-sa
    OBASSERT(![NSString isEmptyString:ourClientIdentifier]);
    
    NSMutableDictionary <NSString *, OFXSyncClient *> *clientByIdentifier = [[self class] _updatedClientByIdentifierWithOriginal:_clientByIdentifier
                                                                                 propertyListCache:_propertyListCache
                                                                              cachingFromFileInfos:clientFileInfos serverDate:serverDate
                                                                               ourClientIdentifier:ourClientIdentifier
                                                                                     staleInterval:_clientParameters.staleInterval
                                                                                        connection:connection];

    // Clean up entries that were deleted by some other device.
    NSArray *allFileInfos = clientFileInfos;
    if (accountFileInfo)
        allFileInfos = [allFileInfos arrayByAddingObject:accountFileInfo];
    [_propertyListCache pruneCacheKeepingEntriesForFileInfos:allFileInfos];
    
    // Make sure our client file exists and is up to date. Make sure to compare server dates to server dates to avoid clock skew issues.
    _ourClient = clientByIdentifier[ourClientIdentifier];
    OBASSERT(!_ourClient || OFISEQUAL(_ourClient.identifier, ourClientIdentifier));

    if (!_ourClient || -[_ourClient.fileInfo.lastModifiedDate timeIntervalSinceDate:serverDate] > _clientParameters.writeInterval) {
        // We use the same 'domain' for all our sync accounts -- this just controls the host id.
        NSURL *clientURL = [_remoteAccountURL URLByAppendingPathComponent:[ourClientIdentifier stringByAppendingPathExtension:OFXClientPathExtension]];
        
        // _remoteAccountURL is our cannonical URL, but we might be redirected
        clientURL = [connection suggestRedirectedURLForURL:clientURL];
        
        OFXSyncClient *updatedClient = [[OFXSyncClient alloc] initWithURL:clientURL previousClient:_ourClient parameters:_clientParameters error:outError];
        if (!updatedClient) {
            OBChainError(outError);
            return NO;
        }
        
        DEBUG_CLIENT(1, @"Updating local client to %@", [updatedClient shortDescription]);
        
        __autoreleasing NSError *error;
        OFXPropertyListCacheEntry *cacheEntry = [_propertyListCache writePropertyList:updatedClient.propertyList toURL:clientURL overwrite:YES connection:connection error:&error];
        if (!cacheEntry) {
            [error log:@"Error writing client property list to %@", clientURL];
            
            if (outError) {
                *outError = error;
                NSString *description = NSLocalizedStringFromTableInBundle(@"Sync failed: unable to update device registration.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
                NSString *reason = NSLocalizedStringFromTableInBundle(@"Unable to update device registration on the cloud server.", @"OmniFileExchange", OMNI_BUNDLE, @"error reason");
                OFXErrorWithInfo(&error, OFXAccountUnableToStoreClientInfo, description, reason, nil);
            }
            return NO;
        }

        updatedClient.fileInfo = cacheEntry.fileInfo;
        
        clientByIdentifier[ourClientIdentifier] = updatedClient;
        _ourClient = updatedClient;
    }
    
    _clientByIdentifier = [clientByIdentifier copy];
    DEBUG_CLIENT(2, @"Client by identifier now %@", _clientByIdentifier);
    
    // Periodically clean up leaked remote temporary files
    if (remoteTemporaryDirectoryFileInfo)
        [self _cleanupRemoteTemporaryDirectory:remoteTemporaryDirectoryFileInfo connection:connection];
    
    return YES;
}

- (NSString *)groupIdentifier;
{
    NSString *group = _accountPropertyList[OFXAccountInfo_Group];
    OBASSERT(![NSString isEmptyString:group]);
    return group;
}

#pragma mark - Private

- (NSDictionary *)_makeInfoDictionary;
{
    return @{OFXAccountInfo_Group:OFXMLCreateID(), OFXAccountInfo_Version:[_clientParameters.currentFrameworkVersion cleanVersionString]};
}

+ (NSMutableDictionary <NSString *, OFXSyncClient *> *)_updatedClientByIdentifierWithOriginal:(NSDictionary <NSString *, OFXSyncClient *> *)previousClientByIdentifier
                                              propertyListCache:(OFXPropertyListCache *)propertyListCache
                                           cachingFromFileInfos:(NSArray <ODAVFileInfo *> *)clientFileInfos
                                                     serverDate:(NSDate *)serverDate
                                            ourClientIdentifier:(NSString *)ourClientIdentifier
                                                  staleInterval:(NSTimeInterval)staleInterval
                                                     connection:(ODAVConnection *)connection;
{
    NSMutableDictionary *resultClientByIdentifier = [NSMutableDictionary new];

    for (ODAVFileInfo *clientFileInfo in clientFileInfos) {
        NSURL *clientURL = clientFileInfo.originalURL;
        if (OFNOTEQUAL([clientURL pathExtension], OFXClientPathExtension)) {
            OBASSERT_NOT_REACHED("Non-client file info in clientFileInfos");
            continue;
        }

        NSString *clientIdentifier = [[clientURL lastPathComponent] stringByDeletingPathExtension];
        OBASSERT_NOTNULL(clientIdentifier); // help clang-sa
        
        // If this is some other client and is old enough, prune it. We don't delete our client file if it is old since we assume we'll overwrite it below anyway (if we've launched after a long absence and somehow someone else hasn't deleted it -- maybe we are the only client).
        if (OFNOTEQUAL(ourClientIdentifier, clientIdentifier) && _fileInfoAge(clientFileInfo, serverDate) > staleInterval) {
            ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done) {
                DEBUG_CLIENT(1, @"Client is stale %@", clientURL);
                
                __autoreleasing NSError *removeError;
                if (![propertyListCache removePropertyListWithFileInfo:clientFileInfo connection:connection error:&removeError]) {
                    [removeError log:@"Error removing stale client at %@", clientURL];
                }
                done();
            });
            continue;
        }
        
        __autoreleasing NSError *cacheError;
        OFXPropertyListCacheEntry *cacheEntry = [propertyListCache cacheEntryWithFileInfo:clientFileInfo serverDate:serverDate connection:connection error:&cacheError];
        if (!cacheEntry) {
            [cacheError log:@"Error fetching client data from %@", clientURL];
            continue;
        }
        
        OFXSyncClient *client = previousClientByIdentifier[clientIdentifier];
        
        if (cacheEntry.fileInfo != client.fileInfo) {
            // New contents cached --  update our client object
            __autoreleasing NSError *clientError;
            if (!(client = [[OFXSyncClient alloc] initWithURL:cacheEntry.fileInfo.originalURL propertyList:cacheEntry.contents error:&clientError])) {
                [clientError log:@"Error creating client from dictionary at %@", clientURL];
                continue;
            }
            client.fileInfo = cacheEntry.fileInfo;
        }
        resultClientByIdentifier[clientIdentifier] = client;
    }

    return resultClientByIdentifier;
}

- (void)_cleanupRemoteTemporaryDirectory:(ODAVFileInfo *)remoteTemporaryDirectoryFileInfo connection:(ODAVConnection *)connection;
{
    OBPRECONDITION(remoteTemporaryDirectoryFileInfo);
    
    // Only need to do this once in a while
    NSDate *lastCleanup = _localStatePropertyList[LocalState_LastRemoteTemporaryFileCleanupDate];
    if (lastCleanup) {
        NSTimeInterval timeSinceLastCleanup = -[lastCleanup timeIntervalSinceNow];
        DEBUG_CLIENT(2, @"Remove temporary cleanup last happened %f seconds ago", timeSinceLastCleanup);
        if (timeSinceLastCleanup < _clientParameters.remoteTemporaryFileCleanupInterval) {
            DEBUG_CLIENT(2, @"  ... which is more recent than the cleanup interval of %f seconds", _clientParameters.remoteTemporaryFileCleanupInterval);
            return;
        }
    }
    
    __autoreleasing NSError *fileInfoError;
    ODAVMultipleFileInfoResult *result = [connection synchronousDirectoryContentsAtURL:remoteTemporaryDirectoryFileInfo.originalURL withETag:nil error:&fileInfoError];
    if (!result) {
        [fileInfoError log:@"Error checking remote temporary directory contents at %@", remoteTemporaryDirectoryFileInfo.originalURL];
        return;
    }
    
    // Update our last-tried time no matter whether we delete anything or not.
    _localStatePropertyList[LocalState_LastRemoteTemporaryFileCleanupDate] = [NSDate date];
    
    NSTimeInterval staleInterval = _clientParameters.remoteTemporaryFileCleanupInterval; // We use this for both the check interval and the stale age
    NSDate *serverDate = result.serverDate;
    for (ODAVFileInfo *fileInfo in result.fileInfos) {
        if ([serverDate timeIntervalSinceDate:fileInfo.lastModifiedDate] > staleInterval) {
            // Removing stale files should be relatively rare since during normal operations we should clean up after ourselves. Log when we do this.
            NSLog(@"Removing stale temporary file at %@ with modification date %@ vs server date of %@", fileInfo.originalURL, fileInfo.lastModifiedDate, serverDate);
            [connection deleteURL:fileInfo.originalURL withETag:nil completionHandler:nil];
        }
    }
}

@end
