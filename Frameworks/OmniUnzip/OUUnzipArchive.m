// Copyright 2008, 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUUnzipArchive.h>

#import <OmniUnzip/OUUnzipEntry.h>
#import <OmniUnzip/OUErrors.h>
#import <OmniBase/system.h> // S_IFMT, etc
#import <OmniFoundation/OFByteProviderProtocol.h>
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

@implementation OUUnzipArchive

static id _unzipError(id self, const char *func, int err, NSError **outError)
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
- initWithPath:(NSString *)path data:(NSObject <OFByteProvider> *)store error:(NSError **)outError;
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
    
    NSMutableArray *entries = [NSMutableArray array];
    
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

@synthesize path = _path;
@synthesize entries = _entries;

// TODO: Add case sensitivity control?
- (OUUnzipEntry *)entryNamed:(NSString *)name;
{
    // Looping from the beginning, assuming that the first entry (typically contents.xml) is what we'll usually want.
    for (OUUnzipEntry *entry in _entries)
        if ([[entry name] isEqualToString:name])
            return entry;
    
    return nil;
}

- (NSArray *)entriesWithNamePrefix:(NSString *)prefix;
{
    if (prefix == nil || [prefix isEqualToString:@""])
        return _entries;

    NSMutableArray *matches = [NSMutableArray array];
    
    for (OUUnzipEntry *entry in _entries)
        if ([[entry name] hasPrefix:prefix])
            [matches addObject:entry];
            
    return matches;
}

static id _unzipDataError(id self, OUUnzipEntry *entry, const char *func, int err, NSError **outError)
{
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to read zip data.", @"OmniUnzip", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The zip library function %s returned %d when trying to read the data for entry \"%@\" in \"%@\".", @"OmniUnzip", OMNI_BUNDLE, @"error reason"),  func, err, [entry name], [self path]];
    OmniUnzipError(outError, OmniUnzipUnableToReadZipFileContents, description, reason);
    
    NSLog(@"%s returned %d", func, err);
    return nil;
}
#define UNZIP_DATA_ERROR(f) _unzipDataError(self, entry, #f, err, outError)

// We might want to return a read-stream later, but for now all the callers want a data.  This method should only be called for resources that can be opened on the device.  If you attach a 70MB satellite image and try to open it on your phone, you'll be sad (on many fronts).  So, returning a data here should be OK since we'll not create datas for every entry in the zip file.
- (NSData *)dataForEntry:(OUUnzipEntry *)entry raw:(BOOL)raw error:(NSError **)outError;
{
    OBPRECONDITION(entry);
    
    unzFile unzip;
    if (_store) {
        unzip = unzOpen2((__bridge void *)_store, &OUReadIOImpl);
    } else {
        _store = nil;
        unzip = unzOpen([[NSFileManager defaultManager] fileSystemRepresentationWithPath:_path]);
    }
    
    if (!unzip) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to read zip data.", @"OmniUnzip", OMNI_BUNDLE, @"error reason");
        NSString *reason = [NSString stringWithFormat:@"Unable to open zip file \"%@\".", _path];
        OmniUnzipError(outError, OmniUnzipUnableToOpenZipFile, description, reason);
        return nil;
    }

    NSData *data = nil;
    
    @try {
        int err;
        unz_file_pos position;
        memset(&position, 0, sizeof(position));
        position.pos_in_zip_directory = [entry positionInFile]; // Presuming that if we screw up and pass an entry from the wrong file or otherwise have something past the end of the file, that this will be detected.
        position.num_of_file = [entry fileNumber];
        
        err = unzGoToFilePos(unzip, &position);
        if (err != UNZ_OK)
            return UNZIP_DATA_ERROR(unzGoToFilePos);
        
        unz_file_info fileInfo;
        err = unzGetCurrentFileInfo(unzip, &fileInfo, NULL, 0, // file name & size
                                    NULL, 0, NULL, 0); // extra args for 'extra field' and comment buffer and buffer size
        if (err != UNZ_OK)
            return UNZIP_DATA_ERROR(unzGetCurrentFileInfo);

        int method, level;
        err = unzOpenCurrentFile3(unzip, &method, &level, raw ? 1 : 0, NULL/*password*/);
        if (err != UNZ_OK)
            return UNZIP_DATA_ERROR(unzOpenCurrentFile3);
        
        size_t totalSize = raw ? fileInfo.compressed_size : fileInfo.uncompressed_size;
        
        void *bytes = malloc(totalSize);
        size_t totalBytesRead = 0;
        while (totalBytesRead < totalSize) {
            // wants an unsigned. but then it returns an int; will use INT_MAX instead of UINT_MAX.
            size_t availableBytes = totalSize - totalBytesRead;
            unsigned bytesToRead;
            if (availableBytes > INT_MAX)
                bytesToRead = INT_MAX;
            else
                bytesToRead = (unsigned)availableBytes;
            
            int copied = unzReadCurrentFile(unzip, bytes + totalBytesRead, bytesToRead);
            OBASSERT(copied < 0 || (unsigned)copied >= bytesToRead);
            
            if (copied <= 0) { // Not expecting zero here since we stop before end of file.  Include it in the conditional so we'll error out rather the loop infinitely.
                free(bytes);
                return UNZIP_DATA_ERROR(unzReadCurrentFile);
            }
            totalBytesRead += copied;
        }
        
        // Transfer ownership to a data.
        data = [NSData dataWithBytesNoCopy:bytes length:totalSize freeWhenDone:YES];

        err = unzCloseCurrentFile(unzip);
        if (err != UNZ_OK)
            return UNZIP_DATA_ERROR(unzCloseCurrentFile);
        
    } @finally {
        if (unzip)
            unzClose(unzip);
    }
    
    return data;
    
}
#undef UNZIP_DATA_ERROR

- (NSData *)dataForEntry:(OUUnzipEntry *)entry error:(NSError **)outError;
{
    return [self dataForEntry:entry raw:NO error:outError];
}

- (BOOL)_writeEntriesWithPrefix:(NSString *)prefix toURL:(NSURL *)writeURL error:(NSError **)outError;
{
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    if (![defaultManager createDirectoryAtURL:writeURL withIntermediateDirectories:NO attributes:nil error:outError])
        return NO;

    NSArray *entries = [self entriesWithNamePrefix:prefix];
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

- (NSURL *)URLByWritingTemporaryCopyOfTopLevelEntryNamed:(NSString *)topLevelEntryName error:(NSError **)outError;
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

@end

