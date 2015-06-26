// Copyright 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXPropertyListCache.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniDAV/ODAVOperation.h>
#import <OmniFoundation/OFPreference.h>

#import "OFXDAVUtilities.h"

RCS_ID("$Id$")

static OFDeclareDebugLogLevel(OFXPropertyListCacheDebug);
#define DEBUG_CACHE(level, format, ...) do { \
    if (OFXPropertyListCacheDebug >= (level)) \
        NSLog(@"PLIST CACHE %@: " format, [self shortDescription], ## __VA_ARGS__); \
} while (0)

@interface OFXPropertyListCacheEntry ()
@property(nonatomic,readwrite,strong) NSDate *serverDate;
@property(nonatomic,readwrite,strong) ODAVFileInfo *fileInfo;
@property(nonatomic,readwrite,copy) NSDictionary *contents;
@end

static NSString * const ServerDateKey = @"serverDate";
static NSString * const ContentsKey = @"contents";
static NSString * const FileInfoKey = @"fileInfo";
static NSString * const   FileInfoSizeKey = @"size";
static NSString * const   FileInfoETagKey = @"ETag";
static NSString * const   FileInfoLastModifiedDateKey = @"lastModifiedDate";

@implementation OFXPropertyListCacheEntry

#define GET_ENTRY(var, plist, key, cls) do { \
    id value = [(plist) objectForKey:(key)]; \
    if (![value isKindOfClass:[cls class]]) \
        return nil; \
    var = value; \
} while(0)

- initWithURLString:(NSString *)urlString propertyList:(NSDictionary *)plist;
{
    if (!(self = [super init]))
        return nil;
    
    if (![plist isKindOfClass:[NSDictionary class]])
        return nil;
    
    GET_ENTRY(_serverDate, plist, ServerDateKey, NSDate);
    GET_ENTRY(_contents, plist, ContentsKey, NSDictionary);
    
    NSDictionary *fileInfoPlist;
    GET_ENTRY(fileInfoPlist, plist, FileInfoKey, NSDictionary);
    
    NSNumber *fileSize;
    GET_ENTRY(fileSize, fileInfoPlist, FileInfoSizeKey, NSNumber);

    NSString *ETag;
    GET_ENTRY(ETag, fileInfoPlist, FileInfoETagKey, NSString);
    if ([NSString isEmptyString:ETag])
        ETag = nil;

    NSDate *lastModifiedDate;
    GET_ENTRY(lastModifiedDate, fileInfoPlist, FileInfoLastModifiedDateKey, NSDate);

    NSURL *originalURL = [NSURL URLWithString:urlString];
    if (!originalURL)
        return nil;
    
    _fileInfo = [[ODAVFileInfo alloc] initWithOriginalURL:originalURL name:nil exists:YES directory:NO size:[fileSize unsignedLongLongValue] lastModifiedDate:lastModifiedDate ETag:ETag];

    return self;
}

- (NSDictionary *)toPropertyList;
{
    NSString *ETag = _fileInfo.ETag;
    NSDictionary *fileInfoPlist = @{FileInfoSizeKey:@(_fileInfo.size),
                                    FileInfoETagKey:ETag != nil ? ETag : @"",
                                    FileInfoLastModifiedDateKey:_fileInfo.lastModifiedDate};
    return @{ServerDateKey:_serverDate, FileInfoKey:fileInfoPlist, ContentsKey:_contents};
}

@end

@implementation OFXPropertyListCache
{
    NSURL *_cacheFileURL;
    NSURL *_remoteTemporaryDirectoryURL;
    NSURL *_remoteBaseDirectoryURL;

    NSMutableDictionary *_cacheEntryByKey;
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

static NSString *_cacheKeyForFileInfo(ODAVFileInfo *fileInfo)
{
    return fileInfo.originalURL.absoluteString;
}

- initWithCacheFileURL:(NSURL *)fileURL remoteTemporaryDirectoryURL:(NSURL *)remoteTemporaryDirectoryURL remoteBaseDirectoryURL:(NSURL *)remoteBaseDirectoryURL;
{
    // This fileURL is expected to be in a non-shared area since we don't lock vs. any other accessor (though we do atomic writes).
    OBPRECONDITION(fileURL);
    OBPRECONDITION([fileURL isFileURL]);
    OBPRECONDITION(remoteTemporaryDirectoryURL);
    OBPRECONDITION(![remoteTemporaryDirectoryURL isFileURL]);
    OBPRECONDITION(remoteBaseDirectoryURL);
    OBPRECONDITION(![remoteBaseDirectoryURL isFileURL]);
    OBPRECONDITION(!OFURLEqualsURL(remoteTemporaryDirectoryURL, remoteBaseDirectoryURL));
    
    if (!(self = [super init]))
        return nil;
    
    _remoteTemporaryDirectoryURL = remoteTemporaryDirectoryURL;
    _remoteBaseDirectoryURL = remoteBaseDirectoryURL;
    
    // Load the cache. At the first sign of trouble, drop the current contents and start from scratch.
    _cacheFileURL = [fileURL copy];
    NSDictionary *cachePlist;
    {
        __autoreleasing NSError *dataError;
        NSData *cacheData = [[NSData alloc] initWithContentsOfURL:fileURL options:0 error:&dataError];
        if (!cacheData) {
            if (![dataError causedByMissingFile])
                [dataError log:@"Error reading cache file at %@", fileURL];
        } else {
            __autoreleasing NSError *plistError;
            cachePlist = [NSPropertyListSerialization propertyListWithData:cacheData options:0 format:NULL error:&plistError];
            if (!cachePlist)
                [plistError log:@"Error deserializing cache at %@", fileURL];
            if (![cachePlist isKindOfClass:[NSDictionary class]]) {
                NSLog(@"Cache at %@ is not a dictionary but a %@: %@", fileURL, [cachePlist class], cachePlist);
                cachePlist = nil;
            }
        }
    }
    
    // Decode the entries, dropping any that don't appear to be valid.
    _cacheEntryByKey = [NSMutableDictionary new];
    [cachePlist enumerateKeysAndObjectsUsingBlock:^(NSString *cacheKey, NSDictionary *entryPropertyList, BOOL *stop) {
        OFXPropertyListCacheEntry *entry = [[OFXPropertyListCacheEntry alloc] initWithURLString:cacheKey propertyList:entryPropertyList];
        OBASSERT([[entry toPropertyList] isEqual:entryPropertyList]);
        
        if (!entry)
            NSLog(@"Ignoring invalid cache entry in %@: %@ -> %@", fileURL, cacheKey, entryPropertyList);
        else
            _cacheEntryByKey[cacheKey] = entry;
    }];
    
    DEBUG_CACHE(1, @"Initialized from file at %@ with contents: %@", fileURL, _cacheEntryByKey);
    
    return self;
}

- (NSDictionary *)propertyListWithFileInfo:(ODAVFileInfo *)fileInfo serverDate:(NSDate *)serverDate connection:(ODAVConnection *)connection error:(NSError **)outError;
{
    OFXPropertyListCacheEntry *cacheEntry = [self cacheEntryWithFileInfo:fileInfo serverDate:serverDate connection:connection error:outError];
    return cacheEntry.contents;
}

- (OFXPropertyListCacheEntry *)cacheEntryWithFileInfo:(ODAVFileInfo *)fileInfo serverDate:(NSDate *)serverDate connection:(ODAVConnection *)connection error:(NSError **)outError;
{
    OBPRECONDITION(fileInfo);
    OBPRECONDITION(serverDate);
    OBPRECONDITION(connection);
    
    NSString *cacheKey = _cacheKeyForFileInfo(fileInfo);
    OFXPropertyListCacheEntry *cacheEntry = _cacheEntryByKey[cacheKey];
    
    if (cacheEntry && [cacheEntry.fileInfo isSameAsFileInfo:fileInfo asOfServerDate:serverDate]) {
        // Cache entry is valid!
        DEBUG_CACHE(1, @"Hit cache on lookup of %@ with date %@ -> %@", fileInfo, serverDate, cacheEntry);
        return cacheEntry;
    }
    
    __block NSData *data;
    __block NSError *error;
    
    ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done){
        [connection getContentsOfURL:fileInfo.originalURL ETag:nil completionHandler:^(ODAVOperation *op) {
            if (op.error)
                error = op.error;
            else
                data = op.resultData;
            done();
        }];
    });
    
    // We were passed in a file info, so the expectation is that a PROPFIND returned it just a bit ago and we should find it. If not, we might be racing with something deleting it, or with the network going offline. Either way, we're done.
    if (!data) {
        if (outError)
            *outError = error;
        return nil;
    }
    
    // Make sure it is a valid property list. If it isn't log the issue and pretend it doesn't exist.
    __autoreleasing NSError *plistError;
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&plistError];
    if (!plist) {
        [plistError log:@"Expected file at %@ to be a property list", fileInfo.originalURL];
        if (outError)
            *outError = [NSError errorWithDomain:ODAVErrorDomain code:ODAV_HTTP_NOT_FOUND userInfo:@{NSUnderlyingErrorKey:plistError}];
        return nil;
    }
    if (![plist isKindOfClass:[NSDictionary class]]) {
        NSLog(@"Expected file at %@ to be a dictionary, but it is a %@", fileInfo.originalURL, [plist class]);
        if (outError)
            *outError = [NSError errorWithDomain:ODAVErrorDomain code:ODAV_HTTP_NOT_FOUND userInfo:@{NSUnderlyingErrorKey:plistError}];
        return nil;
    }
    
    // Populate our cache if needed
    cacheEntry = [OFXPropertyListCacheEntry new];
    cacheEntry.serverDate = serverDate;
    cacheEntry.fileInfo = fileInfo;
    cacheEntry.contents = plist;
    
    if (_cacheEntryByKey[cacheKey] == nil)
        DEBUG_CACHE(1, @"Added cache entry for fetch of %@ with server date %@ -> %@", fileInfo, serverDate, cacheEntry);
    else
        DEBUG_CACHE(1, @"Updated cache entry for fetch of %@ with server date %@ -> %@", fileInfo, serverDate, cacheEntry);
    _cacheEntryByKey[cacheKey] = cacheEntry;
    [self _writeCache];
    
    return cacheEntry;
}

- (OFXPropertyListCacheEntry *)writePropertyList:(NSDictionary *)plist toURL:(NSURL *)url overwrite:(BOOL)overwrite connection:(ODAVConnection *)connection error:(NSError **)outError;
{
    __autoreleasing NSError *plistError;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:&plistError];
    if (!plistData) {
        if (outError)
            *outError = plistError;
        return nil;
    }
    
    __block NSURL *resultURL;
    __block NSError *resultError;
    ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done){
        OFXWriteDataToURLAtomically(connection, plistData, url, _remoteTemporaryDirectoryURL, _remoteBaseDirectoryURL, overwrite, ^(NSURL *writtenURL, NSError *writeError){
            resultURL = writtenURL;
            resultError = writeError;
            done();
        });
    });
    if (!resultURL) {
        if (outError)
            *outError = resultError;
        return nil;
    }
    
    // TODO: Delay for a bit to let the server date step forward. We should write client infos rarely. Without this we'll likely refetch the client file later since we treat 'serverDate == modificationDate' as possibly needing to be refreshed.
    
    __block ODAVFileInfo *resultFileInfo;
    __block NSDate *resultServerDate;
    ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done) {
        [connection fileInfoAtURL:resultURL ETag:nil completionHandler:^(ODAVSingleFileInfoResult *result, NSError *error) {
            resultFileInfo = result.fileInfo;
            resultServerDate = result.serverDate;
            resultError = error;
            done();
        }];
    });
    
    if (!resultFileInfo)
        return nil;
    if (!resultFileInfo.exists) {
        // We just wrote it, so something goofy is going on...
        if (outError)
            *outError = [NSError errorWithDomain:ODAVErrorDomain code:ODAV_HTTP_NOT_FOUND userInfo:nil];
        OBChainError(outError);
        return nil;
    }
    
    // Populate our cache
    OFXPropertyListCacheEntry *cacheEntry = [OFXPropertyListCacheEntry new];
    cacheEntry.serverDate = resultServerDate;
    cacheEntry.fileInfo = resultFileInfo;
    cacheEntry.contents = plist;

    NSString *cacheKey = _cacheKeyForFileInfo(resultFileInfo);

    if (_cacheEntryByKey[cacheKey] == nil)
        DEBUG_CACHE(1, @"Added cache entry for write of %@ with server date %@ -> %@", resultFileInfo, resultServerDate, cacheEntry);
    else
        DEBUG_CACHE(1, @"Updated cache entry for write of %@ with server date %@ -> %@", resultFileInfo, resultServerDate, cacheEntry);
    _cacheEntryByKey[cacheKey] = cacheEntry;
    [self _writeCache];
    
    return cacheEntry;
}

- (BOOL)removePropertyListWithFileInfo:(ODAVFileInfo *)fileInfo connection:(ODAVConnection *)connection error:(NSError **)outError;
{
    __block NSError *removeError;
    ODAVSyncOperation(__FILE__, __LINE__, ^(ODAVOperationDone done) {
        [connection deleteURL:fileInfo.originalURL withETag:fileInfo.ETag completionHandler:^(NSError *error) {
            removeError =  error;
            done();
        }];
    });
    
    if (removeError) {
        if ([removeError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND] ||
            [removeError hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_PRECONDITION_FAILED]) {
            // Someone else removed it, or it got updated *just* now.
            // In the case of it being updated *just* now, we have a small bug in that we don't re-fetch the plist until our next sync. Our default stale interval is so large that this is very unlikely, but its worth mentioning.
        } else {
            if (*outError)
                *outError = removeError;
            return NO;
        }
    }
    
    DEBUG_CACHE(1, @"Removed cache entry for %@", fileInfo);
    [_cacheEntryByKey removeObjectForKey:_cacheKeyForFileInfo(fileInfo)];
    [self _writeCache];
    
    return YES;
}

- (void)pruneCacheKeepingEntriesForFileInfos:(NSArray *)fileInfos;
{
    NSMutableSet *cacheKeys = [NSMutableSet new];
    
    for (ODAVFileInfo *fileInfo in fileInfos)
        [cacheKeys addObject:_cacheKeyForFileInfo(fileInfo)];
    
    NSMutableArray *keysToRemove = [NSMutableArray new];
    [_cacheEntryByKey enumerateKeysAndObjectsUsingBlock:^(NSString *cacheKey, OFXPropertyListCacheEntry *cacheEntry, BOOL *stop) {
        if ([cacheKeys member:cacheKey] == nil)
            [keysToRemove addObject:cacheKey];
    }];
    
    if ([keysToRemove count] > 0) {
        for (NSString *cacheKey in keysToRemove) {
            [_cacheEntryByKey removeObjectForKey:cacheKey];
            DEBUG_CACHE(1, @"Pruned cache entry for %@", cacheKey);
        }
        [self _writeCache];
    }
}

#pragma mark - Private

// We could do this on a background queue, but this cache is intended to be read-heavy, write-light.
- (void)_writeCache;
{
    OBPRECONDITION(_cacheEntryByKey);
    
    NSMutableDictionary *cachePlist = [NSMutableDictionary new];
    [_cacheEntryByKey enumerateKeysAndObjectsUsingBlock:^(NSString *cacheKey, OFXPropertyListCacheEntry *cacheEntry, BOOL *stop) {
        NSDictionary *entryPlist = [cacheEntry toPropertyList];
        cachePlist[cacheKey] = entryPlist;
    }];
    
    __autoreleasing NSError *plistError;
    NSData *cacheData = [NSPropertyListSerialization dataWithPropertyList:cachePlist format:NSPropertyListXMLFormat_v1_0 options:0 error:&plistError];
    if (!cacheData && [_cacheEntryByKey count] > 0) {
        [plistError log:@"Error serializing plist cache for %@", _cacheFileURL];
        
        // Reset the cache in this case.
        [_cacheEntryByKey removeAllObjects];
        [self _writeCache];
        return;
    }
    
    __autoreleasing NSError *writeError;
    if (![cacheData writeToURL:_cacheFileURL options:NSDataWritingAtomic error:&writeError]) {
        [writeError log:@"Error writing plist cache to %@", _cacheFileURL];
    }
}

@end
