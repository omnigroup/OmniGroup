// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXAccountInfo.h"

#import <OmniFileExchange/OFXAccountClientParameters.h>
#import <OmniFileStore/OFSDAVFileManager.h>
#import <OmniFileStore/OFSFileInfo.h>
#import <OmniFileStore/OFSURL.h>
#import <OmniFileStore/Errors.h>
#import <OmniBase/macros.h>

#import "OFXDAVUtilities.h"

RCS_ID("$Id$")

static NSInteger OFXAccountInfoDebug = INT_MAX;
#define DEBUG_CLIENT(level, format, ...) do { \
    if (OFXAccountInfoDebug >= (level)) \
        NSLog(@"ACCT INFO %@: " format, [self shortDescription], ## __VA_ARGS__); \
} while (0)

@implementation OFXAccountInfo
{
    NSDate *_lastServerDate;
    
    NSURL *_temporaryDirectoryURL;
    OFSFileInfo *_accountFileInfo;
    NSDictionary *_accountPropertyList;
    OFVersionNumber *_accountVersion;
    
    OFXAccountClientParameters *_clientParameters;
    OFSyncClient *_localClient;
    NSDate *_localClientWriteDate;
    
    NSDate *_lastUpdateDate;
    NSDate *_lastUpdateServerDate;
    NSDictionary *_clientByIdentifier;
}

static OFVersionNumber *MinimumCompatibleAccountVersionNumber;

+ (void)initialize;
{
    OBINITIALIZE;
    
    OBInitializeDebugLogLevel(OFXAccountInfoDebug);
    MinimumCompatibleAccountVersionNumber = [[OFVersionNumber alloc] initWithVersionString:@"2"];
}

- initWithAccountURL:(NSURL *)accountURL temporaryDirectoryURL:(NSURL *)temporaryDirectoryURL clientParameters:(OFXAccountClientParameters *)clientParameters error:(NSError **)outError;
{
    OBPRECONDITION(accountURL);
    OBPRECONDITION(temporaryDirectoryURL);
    OBPRECONDITION(!OFURLEqualsURL(accountURL, temporaryDirectoryURL));
    OBPRECONDITION(clientParameters);
    
    if (!(self = [super init]))
        return nil;
    
    _accountURL = [accountURL copy];
    _temporaryDirectoryURL = [temporaryDirectoryURL copy];
    _clientParameters = clientParameters;
    
    NSString *localClientIdentifier = _clientParameters.defaultClientIdentifier;
    NSURL *localClientURL = [_accountURL URLByAppendingPathComponent:[localClientIdentifier stringByAppendingPathExtension:OFXClientPathExtension]];
    _localClient = [[OFSyncClient alloc] initWithURL:localClientURL previousClient:_localClient parameters:clientParameters error:outError];
    if (!_localClient) {
        OBChainError(outError);
        return nil;
    }

    return self;
}

NSString * const OFXInfoFileName = @"Info.plist";
NSString * const OFXClientPathExtension = @"client";

NSString * const OFXAccountInfo_Group = @"NetStateGroup";
NSString * const OFXAccountInfo_Version = @"Version";

static NSTimeInterval _fileInfoAge(OFSFileInfo *fileInfo, NSDate *serverDateNow)
{
    // Do a slightly better job of calculating the file item's age than assuming that our local clock and the server clock agree.
    return [serverDateNow timeIntervalSinceReferenceDate] - [fileInfo.lastModifiedDate timeIntervalSinceReferenceDate];
}

- (BOOL)_updateAccountInfo:(OFSFileInfo *)accountFileInfo withFileManager:(OFSDAVFileManager *)fileManager error:(NSError **)outError;
{
    if (_accountFileInfo && _lastServerDate && [_accountFileInfo isSameAsFileInfo:accountFileInfo asOfServerDate:_lastServerDate])
        // We've fetched this version before -- all done
        return YES;
    
    NSURL *infoURL = [_accountURL URLByAppendingPathComponent:OFXInfoFileName];
    NSData *infoData;
    if (accountFileInfo) {
        // There is a remote file -- fetch it.
        if (!(infoData = [fileManager dataWithContentsOfURL:infoURL error:outError]))
            return NO;
    } else {
        // There doesn't seem to be a remote file -- create it.
        __autoreleasing NSError *writeError;
        if (!(infoData = [self _writeInfoDictionary:fileManager toURL:infoURL error:&writeError])) {
            if (![writeError hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_PRECONDITION_FAILED]) {
                if (outError)
                    *outError = writeError;
                return NO;
            }
            // Try fetching again since our MOVE presumably failed due another client writing the Info.plist
            if (!(infoData = [fileManager dataWithContentsOfURL:infoURL error:outError]))
                return NO;
        }
    }
    
    // TODO: If we fail to validate the Info.plist, we could write a new one.
    NSDictionary *infoDictionary = [NSPropertyListSerialization propertyListWithData:infoData options:0 format:NULL error:outError];
    if (!infoDictionary)
        return NO;
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

- (BOOL)updateWithFileManager:(OFSDAVFileManager *)fileManager accountFileInfo:(OFSFileInfo *)accountFileInfo clientFileInfos:(NSArray *)clientFileInfos serverDate:(NSDate *)serverDate error:(NSError **)outError;
{
    if (![self _updateAccountInfo:accountFileInfo withFileManager:fileManager error:outError])
        return NO;

    // Check if the account repository is too new for us and bail right away if so.
    OBASSERT(_accountVersion);
    OBASSERT(_localClient.currentFrameworkVersion);
    if ([_localClient.currentFrameworkVersion compareToVersionNumber:_accountVersion] == NSOrderedAscending) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Sync failed: OmniPresence upgrade required.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The cloud account requires OmniPresence format %@, but this device is using format %@. Please upgrade this copy of OmniPresence.", @"OmniFileExchange", OMNI_BUNDLE, @"error reason"), [_accountVersion originalVersionString], [_localClient.currentFrameworkVersion originalVersionString]];
        OFXErrorWithInfo(outError, OFXAccountRepositoryTooNew, description, reason, @"client", _localClient.propertyList, @"server", _accountPropertyList, nil);
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
            
    NSString *localClientIdentifier = _localClient.identifier;
    OBASSERT(![NSString isEmptyString:localClientIdentifier]);
    
    // ETag is of questionable utility, but we could use it too. Right now we are just using the server timestamp to detect if the client info has changed.
    NSMutableDictionary *clientByIdentifier = [NSMutableDictionary new];
    for (OFSFileInfo *clientFileInfo in clientFileInfos) {
        NSURL *clientURL = clientFileInfo.originalURL;
        if (OFNOTEQUAL([clientURL pathExtension], OFXClientPathExtension)) {
            OBASSERT_NOT_REACHED("Non-client file info in clientFileInfos");
            continue;
        }
        
        NSString *clientIdentifier = [[clientURL lastPathComponent] stringByDeletingPathExtension];
        OBASSERT_NOTNULL(clientIdentifier); // help clang-sa
        
        // If this is some other client and is old enough, prune it. We don't delete our client file if it is old since we assume we'll overwrite it below anyway (if we've launched after a long absence and somehow someone else hasn't deleted it -- maybe we are the only client).
        if (OFNOTEQUAL(localClientIdentifier, clientIdentifier) && _fileInfoAge(clientFileInfo, serverDate) > _clientParameters.staleInterval) {
            DEBUG_CLIENT(1, @"Client is stale %@", clientURL);
            
            __autoreleasing NSError *removeError;
            if (![fileManager deleteURL:clientURL withETag:clientFileInfo.ETag error:&removeError]) {
                if ([removeError hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_NOT_FOUND] ||
                    [removeError hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_PRECONDITION_FAILED]) {
                    // Someone else removed it, or it got updated *just* now.
                } else {
                    [removeError log:@"Error removing stale client at %@", clientURL];
                }
            }
            OBFinishPortingLater("Prune stale client");
        }
        
        // Use the previously cached contents of this client state if we have one and it hasn't changed on the server
        OFSyncClient *client;
        if (_lastUpdateServerDate && [_lastUpdateServerDate isAfterDate:clientFileInfo.lastModifiedDate]) {
            client = _clientByIdentifier[clientIdentifier];
        }
        
        if (!client) {
            __autoreleasing NSError *error;
            NSData *clientData = [fileManager dataWithContentsOfURL:clientURL withETag:nil error:&error];
            if (!clientData) {
                [error log:@"Error fetching client data from %@", clientURL];
                continue;
            }
            
            NSDictionary *clientState = [NSPropertyListSerialization propertyListWithData:clientData options:NSPropertyListImmutable format:NULL error:&error];
            if (!clientState) {
                [error log:@"Error unarchiving client data from %@", clientURL];
                continue;
            }
            
            if (![clientState isKindOfClass:[NSDictionary class]]) {
                [error log:@"Error client data is not a dictionary at %@", clientURL];
                continue;
            }
            
            if (!(client = [[OFSyncClient alloc] initWithURL:clientURL propertyList:clientState error:&error])) {
                [error log:@"Error creating client from dictionary at %@", clientURL];
                continue;
            }
        }
        
        // Don't log redundant GETs of clients (which happens a bunch in tests since they run quickly and so our timestamps are often w/in one second of the server date).
        OFSyncClient *oldClient = _clientByIdentifier[clientIdentifier];
        if (OFNOTEQUAL(oldClient.propertyList, client.propertyList)) {
            DEBUG_CLIENT(1, @"Updated state for client %@ to %@", clientIdentifier, [client shortDescription]);
        }
        
        clientByIdentifier[clientIdentifier] = client;
    }
    _lastUpdateServerDate = serverDate;

    if (!_localClientWriteDate || -[_localClientWriteDate timeIntervalSinceNow] > _clientParameters.writeInterval) {
        // We use the same 'domain' for all our sync accounts -- this just controls the host id.
        OFSyncClient *localClient = [[OFSyncClient alloc] initWithURL:_localClient.clientURL previousClient:_localClient parameters:_clientParameters error:outError];
        if (!localClient) {
            OBChainError(outError);
            return NO;
        }
        
        _localClient = localClient;
        DEBUG_CLIENT(1, @"Local client now %@", [_localClient shortDescription]);
        
        clientByIdentifier[localClientIdentifier] = _localClient;
        
        __autoreleasing NSError *error;
        NSData *clientData = [NSPropertyListSerialization dataWithPropertyList:_localClient.propertyList format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        if (!clientData) {
            [error log:@"Error serializing client property list %@", _localClient.propertyList];
        } else {
            NSURL *clientURL = _localClient.clientURL;
            if (!OFXWriteDataToURLAtomically(fileManager, clientData, clientURL, _temporaryDirectoryURL, YES/*overwrite*/, outError)) {
                if (outError)
                    [*outError log:@"Error writing client property list to %@", clientURL];

                NSString *description = NSLocalizedStringFromTableInBundle(@"Sync failed: unable to update device registration.", @"OmniFileExchange", OMNI_BUNDLE, @"error description");
                NSString *reason = NSLocalizedStringFromTableInBundle(@"Unable to update device registration on the cloud server.", @"OmniFileExchange", OMNI_BUNDLE, @"error reason");

                OFXErrorWithInfo(outError, OFXAccountUnableToStoreClientInfo, description, reason, nil);
                return NO;
            }
        }
        _localClientWriteDate = [NSDate date];
    }
    
    _clientByIdentifier = [clientByIdentifier copy];
    DEBUG_CLIENT(2, @"Client by identifier now %@", _clientByIdentifier);
    
    return YES;
}

- (NSString *)groupIdentifier;
{
    NSString *group = _accountPropertyList[OFXAccountInfo_Group];
    OBASSERT(![NSString isEmptyString:group]);
    return group;
}


- (NSData *)_writeInfoDictionary:(OFSDAVFileManager *)fileManager toURL:(NSURL *)infoURL error:(NSError **)outError;
{
    NSString *groupIdentifier = OFXMLCreateID();
    
    NSDictionary *infoDictionary = @{OFXAccountInfo_Group:groupIdentifier, OFXAccountInfo_Version:[_clientParameters.currentFrameworkVersion cleanVersionString]};
    
    NSData *infoData = [NSPropertyListSerialization dataWithPropertyList:infoDictionary format:NSPropertyListXMLFormat_v1_0 options:0 error:outError];
    if (!infoData) {
        OBChainError(outError);
        return nil;
    }
    
    // Make sure we don't clobber another Info.plist that has been written in the mean time.
    if (!OFXWriteDataToURLAtomically(fileManager, infoData, infoURL, _temporaryDirectoryURL, NO/*overwrite*/, outError))
        return nil;
    return infoData;
}

@end
