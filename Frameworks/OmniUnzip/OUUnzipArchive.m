// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUUnzipArchive.h>

#import <OmniUnzip/OUUnzipEntry.h>
#import <OmniUnzip/OUUnzipEntryInputStream.h>
#import <OmniUnzip/OUErrors.h>
#import <OmniBase/NSError-OBExtensions.h>
#import <OmniBase/system.h> // S_IFMT, etc

@import OmniFoundation;

#include "OUUtilities.h"
#include "unzip.h"

OB_REQUIRE_ARC

#import <OmniFoundation/NSFileManager-OFTemporaryPath.h>

#if 0 && defined(DEBUG)
    #define DEBUG_UNZIP_ENTRY(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_UNZIP_ENTRY(format, ...)
#endif

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

@implementation OUUnzipArchive
{
    NSString *_path;
    NSObject <OFByteProvider> *_store;
    NSArray <OUUnzipEntry *> *_entries;
}

// This always returns nil, so that callers can 'return UNZIP_ERROR(...);'
static _Nullable id _unzipError(id self, const char *func, int err, NSError **outError)
{
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to read zip file.", @"OmniUnzip", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The zip library function %s returned %d", @"OmniUnzip", OMNI_BUNDLE, @"error reason"),  func, err];
    OmniUnzipError(outError, OmniUnzipUnableToReadZipFileContents, description, reason);
    
    NSLog(@"%s returned %d", func, err);
    
    return nil;
}
#define UNZIP_ERROR(f) _unzipError(self, #f, err, outError)

- initWithPath:(NSString *)path error:(NSError **)outError;
{
    return [self initWithPath:path data:nil error:outError];
}

// Zip has no real notion of directories, so we just have a flat list of files, like it does.  Some will have slashes in their names.  Some might end in '/' and have directory flags set in their attributes.  We could probably just ignore those (unless they have interesting properties, like finder info or other custom metadata, once we start handling that).
- initWithPath:(NSString *)path data:(NSObject <OFByteProvider> * _Nullable)store error:(NSError **)outError;
{
    _path = [path copy];
    
    unzFile unzip;
    if (store) {
        _store = store;
        unzip = unzOpen2((__bridge void *)_store, &OUReadIOImpl);
    } else {
        _store = nil;
        unzip = unzOpen([[NSFileManager defaultManager] fileSystemRepresentationWithPath:path]);
    }

    if (!unzip) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to open zip archive.", @"OmniUnzip", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The unzip library failed to open %@.", @"OmniUnzip", OMNI_BUNDLE, @"error reason"), path];
        OmniUnzipError(outError, OmniUnzipUnableToOpenZipFile, description, reason);
        return nil;
    }
    
    NSMutableArray <OUUnzipEntry *> *entries = [NSMutableArray array];
    
    @try {
        while (YES) {
            unz_file_info fileInfo;
            char fileNameBuffer[PATH_MAX+1];
#ifdef DEBUG
            memset(fileNameBuffer, 0xff, sizeof(fileNameBuffer)); // Help make sure we get the size_filename semantics right
#endif

            int err = unzGetCurrentFileInfo(unzip, &fileInfo, fileNameBuffer, sizeof(fileNameBuffer), NULL, 0, NULL, 0); // extra args for 'extra field' and comment buffer and buffer size
            if (err != UNZ_OK)
                return UNZIP_ERROR(unzGetCurrentFileInfo);
            
            NSString *fileName = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:fileNameBuffer length:fileInfo.size_filename];
            if (!fileName) {
                NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to read zip file.", @"OmniUnzip", OMNI_BUNDLE, @"error description");
                NSString *reason = NSLocalizedStringFromTableInBundle(@"An entry in the zip file had a name that couldn't be converted to a filesystem path.", @"OmniUnzip", OMNI_BUNDLE, @"error reason");
                OmniUnzipError(outError, OmniUnzipUnableToReadZipFileContents, description, reason);
            }
            
            unz_file_pos position;
            memset(&position, 0, sizeof(position));
            
            err = unzGetFilePos(unzip, &position);
            if (err != UNZ_OK)
                return UNZIP_ERROR(unzGetFilePos);
                
            DEBUG_UNZIP_ENTRY(@"File '%@':", fileName);
            DEBUG_UNZIP_ENTRY(@"  version:%d", fileInfo.version);
            DEBUG_UNZIP_ENTRY(@"  version_needed:%d", fileInfo.version_needed);
            DEBUG_UNZIP_ENTRY(@"  flag:%d", fileInfo.flag);
            DEBUG_UNZIP_ENTRY(@"  compression_method:%d", fileInfo.compression_method);
            DEBUG_UNZIP_ENTRY(@"  dosDate:%d", fileInfo.dosDate);
            DEBUG_UNZIP_ENTRY(@"  crc:%x", fileInfo.crc);
            DEBUG_UNZIP_ENTRY(@"  compressed_size:%d", fileInfo.compressed_size);
            DEBUG_UNZIP_ENTRY(@"  uncompressed_size:%d", fileInfo.uncompressed_size);
            DEBUG_UNZIP_ENTRY(@"  size_filename:%d", fileInfo.size_filename);
            DEBUG_UNZIP_ENTRY(@"  size_file_extra:%d", fileInfo.size_file_extra);
            DEBUG_UNZIP_ENTRY(@"  size_file_comment:%d", fileInfo.size_file_comment);
            DEBUG_UNZIP_ENTRY(@"  disk_num_start:%d", fileInfo.disk_num_start);
            DEBUG_UNZIP_ENTRY(@"  internal_fa:0x%x", fileInfo.internal_fa);
            DEBUG_UNZIP_ENTRY(@"  external_fa:0x%x", fileInfo.external_fa);
        
            // Don't want to extract the data up front.  May not want to return a data at all, but a NSReadStream...
            
            // Not sure what we should do if this happens.  Also of concern is if a zip file has "a" as a file and "a/b".
#if 0
            if ([children objectForKey:fileName]) {
                NSString *description = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Duplicate zip member name \"%@\".", @"OmniUnzip", OMNI_BUNDLE, @"error description"), fileName];
                NSString *reason = NSLocalizedStringFromTableInBundle(@"An entry in the zip file had a name that couldn't be converted to a filesystem path.", @"OmniUnzip", OMNI_BUNDLE, @"error reason");
                OmniUnzipError(outError, OmniUnzipUnableToReadZipFileContents, description, reason);
                [self release];
                return nil;
            }
#endif
            
            NSString *fileType;
            switch ((fileInfo.external_fa >> 16) & S_IFMT) {
                case S_IFDIR:
                    fileType = NSFileTypeDirectory;
                    break;
                case S_IFLNK:
                    fileType = NSFileTypeSymbolicLink;
                    break;
                default:
                    fileType = NSFileTypeRegular;
                    break;
            }

            NSDateComponents *components = [[NSDateComponents alloc] init];
            [components setYear:fileInfo.tmu_date.tm_year];
            [components setMonth:fileInfo.tmu_date.tm_mon + 1]; // tm_mon is 0-based
            [components setDay:fileInfo.tmu_date.tm_mday];
            [components setHour:fileInfo.tmu_date.tm_hour];
            [components setMinute:fileInfo.tmu_date.tm_min];
            [components setSecond:fileInfo.tmu_date.tm_sec];
            NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:components];

            OUUnzipEntry *entry = [[OUUnzipEntry alloc] initWithName:fileName fileType:fileType date:date positionInFile:position.pos_in_zip_directory fileNumber:position.num_of_file compressionMethod:fileInfo.compression_method compressedSize:fileInfo.compressed_size uncompressedSize:fileInfo.uncompressed_size crc:fileInfo.crc];
            [entries addObject:entry];
            
            err = unzGoToNextFile(unzip);
            if (err == UNZ_END_OF_LIST_OF_FILE)
                break;
            if (err != UNZ_OK)
                return UNZIP_ERROR(unzGoToNextFile);
        }
    } @finally {
        if (unzip)
            unzClose(unzip);
    }
    
    _entries = [[NSArray alloc] initWithArray:entries];
    
    return self;
}
#undef UNZIP_ERROR

// TODO: Add case sensitivity control?
- (OUUnzipEntry * _Nullable)entryNamed:(NSString *)name;
{
    // Looping from the beginning, assuming that the first entry (typically contents.xml) is what we'll usually want.
    for (OUUnzipEntry *entry in _entries)
        if ([[entry name] isEqualToString:name])
            return entry;
    
    return nil;
}

- (NSArray <OUUnzipEntry *> *)entriesWithNamePrefix:(NSString * _Nullable)prefix;
{
    if (prefix == nil || [prefix isEqualToString:@""])
        return _entries;

    NSMutableArray <OUUnzipEntry *> *matches = [NSMutableArray array];
    
    for (OUUnzipEntry *entry in _entries)
        if ([[entry name] hasPrefix:prefix])
            [matches addObject:entry];
            
    return matches;
}

- (nullable NSData *)dataForEntry:(OUUnzipEntry *)entry raw:(BOOL)raw error:(NSError **)outError;
{
    NSInputStream *inputStream = [self inputStreamForEntry:entry raw:raw error:outError];
    if (inputStream == nil) {
        return nil;
    }
    
    [inputStream open];
    if (inputStream.streamStatus != NSStreamStatusOpen) {
        OBASSERT(inputStream.streamStatus == NSStreamStatusError);
        OBASSERT(inputStream.streamError != nil);
        if (outError != nil) {
            *outError = inputStream.streamError;
        }
        
        return nil;
    }
    
    NSUInteger length = raw ? entry.compressedSize : entry.uncompressedSize;
    uint8_t *bytes = malloc(length);

    length = [inputStream read:bytes maxLength:length];
    if (inputStream.streamStatus == NSStreamStatusError) {
        OBASSERT(inputStream.streamError != nil);
        if (outError != nil) {
            *outError = inputStream.streamError;
        }
        
        free(bytes);
        return nil;
    }
    
    [inputStream close];
    
    // Transfer ownership to an NSData
    NSData *data = [[NSData alloc] initWithBytesNoCopy:bytes length:length freeWhenDone:YES];
    return data;
}

- (nullable NSData *)dataForEntry:(OUUnzipEntry *)entry error:(NSError **)outError;
{
    return [self dataForEntry:entry raw:NO error:outError];
}

- (nullable NSInputStream *)inputStreamForEntry:(OUUnzipEntry *)entry raw:(BOOL)raw error:(NSError **)outError;
{
    NSURL *archiveURL = [NSURL fileURLWithPath:_path];
    OUUnzipEntryInputStreamOptions options = raw ? OUUnzipEntryInputStreamOptionRaw : OUUnzipEntryInputStreamOptionNone;

    return [[OUUnzipEntryInputStream alloc] initWithUnzipEntry:entry inZipArchiveAtURL:archiveURL data:_store options:options];
}

- (nullable NSInputStream *)inputStreamForEntry:(OUUnzipEntry *)entry error:(NSError **)outError;
{
    return [self inputStreamForEntry:entry raw:NO error:outError];
}

- (BOOL)_writeEntriesWithPrefix:(NSString * _Nullable)prefix toURL:(NSURL *)writeURL error:(NSError **)outError;
{
    OBPRECONDITION([writeURL isFileURL]);
    
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    NSError *createError = nil;
    if (![defaultManager createDirectoryAtURL:writeURL withIntermediateDirectories:NO attributes:nil error:&createError]) {
        if (![createError hasUnderlyingErrorDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError]) {
            if (outError != NULL) {
                *outError = createError;
            }
            return NO;
        }
    }

    NSArray <OUUnzipEntry *> *entries = [self entriesWithNamePrefix:prefix];
    for (OUUnzipEntry *entry in entries) {
        NSString *entryName = [entry name];
        if ([entryName hasPrefix:@"__MACOSX/"])
            continue; // Skip over any __MACOSX metadata (resource forks, etc.)

        NSURL *entryTempURL = [writeURL URLByAppendingPathComponent:entryName];
        
        // We need to check [entry name] here instead of entryTempPath because the trailing / will be lost when using -stringByAppendingPathComponent:
        if (([entryName hasSuffix:@"/"] && ([entry uncompressedSize] == 0))) {
            // This entry is a folder, let's make sure it exists in our temp path.
            if (![defaultManager fileExistsAtPath:[entryTempURL path]]) {
                if (![defaultManager createDirectoryAtURL:entryTempURL withIntermediateDirectories:YES attributes:nil error:outError])
                    return NO;
            }
        }
        else {
            // Entry is a file, write it to entryTempURL.
            @autoreleasepool {
                NSData *entryData = [self dataForEntry:entry error:outError];
                if (entryData == nil)
                    return NO;

                if (![entryData writeToURL:entryTempURL options:0 error:outError])
                    return NO;
            }
        }
    }
    
    return YES;
}

- (BOOL)unzipArchiveToURL:(NSURL *)targetURL error:(NSError **)outError;
{
    return [self _writeEntriesWithPrefix:nil toURL:targetURL error:outError];
}

- (nullable NSURL *)URLByWritingTemporaryCopyOfTopLevelEntryNamed:(NSString *)topLevelEntryName error:(NSError **)outError;
{
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    NSString *writeFileName = [NSString stringWithFormat:@"%@_temp", [topLevelEntryName stringByDeletingPathExtension]];
    NSString *writePath = [defaultManager temporaryPathForWritingToPath:[NSTemporaryDirectory() stringByAppendingPathComponent:writeFileName] allowOriginalDirectory:YES create:NO error:outError];
    if (writePath == nil)
        return nil;

    NSURL *writeURL = [NSURL fileURLWithPath:writePath];
    if (![self _writeEntriesWithPrefix:topLevelEntryName toURL:writeURL error:outError])
        return nil;

    return [writeURL URLByAppendingPathComponent:topLevelEntryName];
}

- (nullable NSFileWrapper *)_wrapperForUnzipEntry:(OUUnzipEntry *)entry inArchive:(OUUnzipArchive *)unzipArchive error:(NSError **)outError;
{
    NSData *data = [unzipArchive dataForEntry:entry error:outError];
    if (!data) {
        NSLog(@"Unable to find zip entry %@ for attachment %@", entry, self);
        // TODO: Create error
        return nil;
    }
    
    NSString *name = [entry name];
    NSString *fileType = [entry fileType];
#ifdef DEBUG_kc
    NSLog(@"Building file wrapper for %@ (%@)", name, fileType);
#endif
    NSFileWrapper *fileWrapper = nil;
    if ([fileType isEqualToString:NSFileTypeDirectory]) {
        fileWrapper = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:[NSDictionary dictionary]];
        if ([name hasSuffix:@"/"])
            name = [name stringByRemovingSuffix:@"/"];
    } else if ([fileType isEqualToString:NSFileTypeSymbolicLink]) {
        NSURL *fileURL = [NSURL fileURLWithPath:[NSString stringWithData:data encoding:NSUTF8StringEncoding]];
        fileWrapper = [[NSFileWrapper alloc] initSymbolicLinkWithDestinationURL:fileURL];
    } else {
        fileWrapper = [[NSFileWrapper alloc] initRegularFileWithContents:data];
    }
    [fileWrapper setPreferredFilename:[name lastPathComponent]];
    
    return fileWrapper;
}

static NSFileWrapper *_rootWrapperForWrapperWithPath(NSMutableDictionary *wrappers, NSFileWrapper *wrapper, NSString *path)
{
    [wrappers setObject:wrapper forKey:path];

    NSString *parentPath = [path stringByDeletingLastPathComponent];
    if ([NSString isEmptyString:parentPath])
        return wrapper; // No parent, we're done!

    NSFileWrapper *rootWrapper;
    NSFileWrapper *parentWrapper = [wrappers objectForKey:parentPath];
    if (parentWrapper == nil) {
        parentWrapper = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:[NSDictionary dictionary]];
        [parentWrapper setPreferredFilename:[parentPath lastPathComponent]];
        rootWrapper = _rootWrapperForWrapperWithPath(wrappers, parentWrapper, parentPath);
    } else {
        rootWrapper = [wrappers objectForKey:path.pathComponents[0]];
    }

    [parentWrapper addFileWrapper:wrapper];
    return rootWrapper;
}

- (nullable NSFileWrapper *)fileWrapperWithError:(NSError **)outError;
{
    return [self fileWrapperWithTopLevelWrapper:NO error:outError];
}

- (nullable NSFileWrapper *)fileWrapperWithTopLevelWrapper:(BOOL)shouldIncludeTopLevelWrapper error:(NSError **)outError;
{
    NSArray *entries = self.entries;
    if (!entries)
        return nil;

    NSMutableDictionary *wrappers = [NSMutableDictionary dictionary];
    NSMutableDictionary *rootWrappers = [NSMutableDictionary dictionary];
    for (OUUnzipEntry *entry in entries) {
        NSString *path = entry.name;
        if ([path hasSuffix:@"/"])
            path = [path stringByRemovingSuffix:@"/"];
        NSFileWrapper *wrapper = [self _wrapperForUnzipEntry:entry inArchive:self error:outError];
        if (wrapper == nil)
            return nil;
        NSFileWrapper *rootWrapper = _rootWrapperForWrapperWithPath(wrappers, wrapper, path);
        OBASSERT(rootWrapper != nil);
        [rootWrappers setObject:rootWrapper forKey:rootWrapper.preferredFilename];
    }

    if (rootWrappers.count > 1) {
        NSFileWrapper *fileWrapper = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:rootWrappers];
        return fileWrapper;
    } else {
        return [rootWrappers anyObject];
    }
}

@end

NS_ASSUME_NONNULL_END

