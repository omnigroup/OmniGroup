// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

@class ODAVConnection, ODAVFileInfo;

@interface OFXPropertyListCacheEntry : NSObject
@property(nonatomic,readonly,strong) NSDate *serverDate;
@property(nonatomic,readonly,strong) ODAVFileInfo *fileInfo;
@property(nonatomic,readonly,copy) NSDictionary *contents;
@end

@interface OFXPropertyListCache : NSObject

- initWithCacheFileURL:(NSURL *)fileURL remoteTemporaryDirectoryURL:(NSURL *)remoteTemporaryDirectoryURL remoteBaseDirectoryURL:(NSURL *)remoteBaseDirectoryURL;

- (OFXPropertyListCacheEntry *)cacheEntryWithFileInfo:(ODAVFileInfo *)fileInfo serverDate:(NSDate *)serverDate connection:(ODAVConnection *)connection error:(NSError **)outError;
- (NSDictionary *)propertyListWithFileInfo:(ODAVFileInfo *)fileInfo serverDate:(NSDate *)serverDate connection:(ODAVConnection *)connection error:(NSError **)outError;

- (OFXPropertyListCacheEntry *)writePropertyList:(NSDictionary *)plist toURL:(NSURL *)url overwrite:(BOOL)overwrite connection:(ODAVConnection *)connection error:(NSError **)outError;

- (BOOL)removePropertyListWithFileInfo:(ODAVFileInfo *)fileInfo connection:(ODAVConnection *)connection error:(NSError **)outError;

// Removes cache entries that are *not* present in the given file infos (deleted by other clients).
- (void)pruneCacheKeepingEntriesForFileInfos:(NSArray *)fileInfos;

@end
