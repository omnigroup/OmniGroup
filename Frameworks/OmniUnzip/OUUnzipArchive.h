// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray;
@class NSData;
@class NSError;
@class NSFileWrapper;
@class NSInputStream;
@class OUUnzipEntry;
@protocol OFByteProvider;

extern NSString * const OUUnzipArchiveFilePathErrorKey;

@interface OUUnzipArchive : NSObject

/// Create an OUUnzipArchive from a file on disk. The file opened for reading (not mapped into memory) each time an operation is performed.
- (nullable id)initWithPath:(NSString *)path error:(NSError **)outError;

/// Create an OUUnzipArchive from either a file on disk, or an abstract byte provider (e.g. an NSData).
///
///  @param path  For a disk file, the file's path; otherwise nil.
///  @param store For a byte provider, the provider; otherwise nil.
///  @param displayName   A string describing the origin of the data, for use in error messages. For example, the filesystem path or origin URL. Does not need to be exact; this is only used for generating error text.
- (nullable id)initWithPath:(nullable NSString *)path data:(nullable NSObject <OFByteProvider> *)store description:(NSString *)displayName error:(NSError **)outError NS_DESIGNATED_INITIALIZER;

@property (readonly, nonatomic, nullable) NSString *path;
@property (readonly, nonatomic) NSArray <OUUnzipEntry *> *entries;
@property (readonly, nonatomic) NSString *archiveDescription;

- (nullable OUUnzipEntry *)entryNamed:(NSString *)name;
- (NSArray <OUUnzipEntry *> *)entriesWithNamePrefix:(NSString * _Nullable)prefix;

- (nullable NSData *)dataForEntry:(OUUnzipEntry *)entry raw:(BOOL)raw error:(NSError **)outError;
- (nullable NSData *)dataForEntry:(OUUnzipEntry *)entry error:(NSError **)outError;

- (nullable NSInputStream *)inputStreamForEntry:(OUUnzipEntry *)entry raw:(BOOL)raw error:(NSError **)outError;
- (nullable NSInputStream *)inputStreamForEntry:(OUUnzipEntry *)entry error:(NSError **)outError;

// Convenience methods for unarchiving to disk
- (BOOL)unzipArchiveToURL:(NSURL *)targetURL error:(NSError **)outError;

// Writes all entries prefixed with "name" to temp.
- (nullable NSURL *)URLByWritingTemporaryCopyOfTopLevelEntryNamed:(NSString *)name error:(NSError **)outError;

// Returns a uniqued list of the top level item names, excluding "__MACOSX". Items that represent directories will have a trailing "/".
- (NSArray <NSString *> *)topLevelEntryNames;

- (nullable NSFileWrapper *)fileWrapperWithError:(NSError **)outError;

/// Creates an NSFileWrapper representing the zip archive
///
/// If `shouldIncludeTopLevelWrapper` is YES, then the returned file wrapper will be a directory wrapper which contains all of the items in the archive. Otherwise, the returned wrapper will be the (presumably only) item that would have been contained in that top-level wrapper --- either a single regular-file wrapper, or a directory wrapper representing the common prefix of all of the items in the archive.
- (nullable NSFileWrapper *)fileWrapperWithTopLevelWrapper:(BOOL)shouldIncludeTopLevelWrapper error:(NSError **)outError;

@end

NS_ASSUME_NONNULL_END
