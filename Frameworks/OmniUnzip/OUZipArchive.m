// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUZipArchive.h>

#import <OmniUnzip/OUErrors.h>
#import <OmniUnzip/OUZipMember.h>
#import <OmniBase/system.h> // S_IFDIR, etc.
#import <OmniFoundation/OFByteProviderProtocol.h>
#import "zip.h"
#import "OUUtilities.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OUZipArchive
{
    struct TagzipFile__ *_zip;
}

+ (BOOL)createZipFile:(NSString *)zipPath fromFilesAtPaths:(NSArray <NSString *> *)paths error:(NSError **)outError;
{
    OUZipArchive *zip = [[OUZipArchive alloc] initWithPath:zipPath error:outError];
    if (!zip) {
        OBASSERT(outError == NULL || *outError != nil);
        return NO;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *path in paths) {
        OB_AUTORELEASING NSError *error = nil;
        OUZipMember *zipMember = [[OUZipMember alloc] initWithPath:path fileManager:fileManager outError:&error];
        if (zipMember == nil || ![zipMember appendToZipArchive:zip fileNamePrefix:@"" error:&error]) {
            // Unable to add one of the files to the zip archive. Log the reason and skip it.
            NSLog(@"Unable to archive path %@: %@", path, [error toPropertyList]);
            continue;
        }
    }

    return [zip close:outError];
}

+ (BOOL)createZipFile:(NSString *)zipPath fromFileWrappers:(NSArray <NSFileWrapper *> *)fileWrappers error:(NSError **)outError;
{
    OUZipArchive *zip = [[OUZipArchive alloc] initWithPath:zipPath error:outError];
    if (!zip) {
        OBASSERT(outError == NULL || *outError != nil);
        return NO;
    }
    for (NSFileWrapper *fileWrapper in fileWrappers) {
        OUZipMember *zipMember = [[OUZipMember alloc] initWithFileWrapper:fileWrapper];
        if (zipMember == nil)
            continue;
        OB_AUTORELEASING NSError *error = nil;
        if (![zipMember appendToZipArchive:zip fileNamePrefix:@"" error:&error]) {
            // Unable to add one of the files to the zip archive.  Just skipping it for now.
        }
    }

    return [zip close:outError];
}

+ (NSData * _Nullable)zipDataFromFileWrappers:(NSArray <NSFileWrapper *> *)fileWrappers error:(NSError **)outError;
{
    NSString *temporaryZipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    
    @try {
        if (![self createZipFile:temporaryZipPath fromFileWrappers:fileWrappers error:outError])
            return nil;

        NSData *zipData = [NSData dataWithContentsOfFile:temporaryZipPath options:0 error:outError];
        return zipData;
    }
    @finally {
        // Remove the temporary file we created
        [[NSFileManager defaultManager] removeItemAtPath:temporaryZipPath error:NULL];
    }
    
    OBASSERT_NOT_REACHED("unreachable");
    return nil;
}

- (instancetype _Nullable)initWithPath:(NSString *)path error:(NSError **)outError;
{
    OBPRECONDITION(![NSString isEmptyString:path]);
    
    if (!(self = [super init]))
        return nil;

    _zip = zipOpen([[NSFileManager defaultManager] fileSystemRepresentationWithPath:path], 0/*append*/);
    if (!_zip) {
        NSString *reason = @"zipOpen returned NULL.";
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to create zip file.", @"OmniUnzip", OMNI_BUNDLE, @"error reason");
        OmniUnzipError(outError, OmniUnzipUnableToCreateZipFile, description, reason);
        return nil;
    }
    
    return self;
}

- (instancetype _Nullable)initWithByteAcceptor:(NSObject <OFByteAcceptor> *)fh error:(NSError **)outError;
{
    if (!fh)
        OBRejectInvalidCall(self, _cmd, @"Byte acceptor must not be nil");
    
    if (!(self = [super init]))
        return nil;
    
    _zip = zipOpen2((__bridge void *)fh,
                    0 /* append */,
                    NULL /* globalComment */,
                    &OUWriteIOImpl);
    if (!_zip) {
        NSString *reason = @"zipOpen returned NULL.";
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to create zip file.", @"OmniUnzip", OMNI_BUNDLE, @"error reason");
        OmniUnzipError(outError, OmniUnzipUnableToCreateZipFile, description, reason);
        return nil;
    }
    
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(_zip == NULL); // Owner should have closed it, even if there is an error appending.
    
    if (_zip) {
        OB_AUTORELEASING NSError *error = nil;
        if (![self close:&error])
            NSLog(@"Error closing zip file: %@", [error toPropertyList]);
    }
}

static BOOL _zipError(id self, const char *func, int err, NSError **outError)
{
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to write zip file.", @"OmniUnzip", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The zip library function %s returned %d", @"OmniUnzip", OMNI_BUNDLE, @"error reason"),  func, err];
    OmniUnzipError(outError, OmniUnzipUnableToCreateZipFile, description, reason);
    
    NSLog(@"%s returned %d", func, err);
    return NO;
}
#define ZIP_ERROR(f) _zipError(self, #f, err, outError)

- (BOOL)appendEntryNamed:(NSString *)name fileType:(NSString *)fileType contents:(NSData *)contents raw:(BOOL)raw compressionMethod:(unsigned long)comparessionMethod uncompressedSize:(size_t)uncompressedSize crc:(unsigned long)crc date:(NSDate * _Nullable)date error:(NSError **)outError;
{
    if (date == nil)
        date = [NSDate date];

    NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:date];
    
    zip_fileinfo info;
    memset(&info, 0, sizeof(info));
    
    OBASSERT([components month] >= 1); // We expect this to have 1-based

    unsigned short fileMode;
    if ([fileType isEqualToString:NSFileTypeDirectory])
        fileMode = S_IFDIR | 0755;
    else if ([fileType isEqualToString:NSFileTypeSymbolicLink])
        fileMode = S_IFLNK | 0644;
    else
        fileMode = S_IFREG | 0644;
    info.external_fa = ((uLong)fileMode) << 16; // UNIX mode is stored in the upper word.  (The lowest byte is for DOS attributes.)
    info.tmz_date.tm_year = (uInt)[components year];
    info.tmz_date.tm_mon = (uInt)([components month] - 1); // Wants 0-based
    info.tmz_date.tm_mday = (uInt)[components day];
    info.tmz_date.tm_hour = (uInt)[components hour];
    info.tmz_date.tm_min = (uInt)[components minute];
    info.tmz_date.tm_sec = (uInt)[components second];

    int err = zipOpenNewFileInZip3(_zip, [[NSFileManager defaultManager] fileSystemRepresentationWithPath:name],
                                   &info,
                                   NULL, 0, // extra field ptr and length
                                   NULL, 0, // global extra field ptr and length
                                   NULL, // comment
                                   (unsigned)comparessionMethod,
                                   Z_DEFAULT_COMPRESSION,
                                   raw ? 1 : 0,
                                   -MAX_WBITS, DEF_MEM_LEVEL, Z_DEFAULT_STRATEGY,
                                   NULL, 0); // Password/crypt crc
    if (err != ZIP_OK)
        return ZIP_ERROR(zipOpenNewFileInZip3);
    
    // Not going to handle large files this way.  Unclear if zip even handles them at all.
    OBASSERT([contents length] < UINT_MAX);

    err = zipWriteInFileInZip(_zip, [contents bytes], (unsigned)[contents length]);
    if (err != ZIP_OK)
        return ZIP_ERROR(zipWriteInFileInZip);
    
    if (raw) {
        err = zipCloseFileInZipRaw(_zip, uncompressedSize, crc);
        if (err != ZIP_OK)
            return ZIP_ERROR(zipCloseFileInZipRaw);
    } else {
        err = zipCloseFileInZip(_zip);
        if (err != ZIP_OK)
            return ZIP_ERROR(zipCloseFileInZip);
    }
    
    return YES;
}

- (BOOL)appendEntryNamed:(NSString *)name fileType:(NSString *)fileType contents:(NSData *)contents date:(NSDate * _Nullable)date error:(NSError **)outError;
{
    // This forces everything to be compressed, even if doing so would make it bigger or yield little gain...
    return [self appendEntryNamed:name fileType:fileType contents:contents raw:NO compressionMethod:Z_DEFLATED uncompressedSize:0 crc:0 date:date error:outError];
}

- (BOOL)close:(NSError **)outError;
{
    OBPRECONDITION(_zip);
    
    if (!_zip) {
        NSString *reason = @"Zip file already closed.";
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to close zip file.", @"OmniUnzip", OMNI_BUNDLE, @"error reason");
        OmniUnzipError(outError, OmniUnzipUnableToCreateZipFile, description, reason);
        return NO;
    }

    int err = zipClose(_zip, NULL/*global comment*/);
    _zip = NULL;
    
    if (err != ZIP_OK) {
        NSString *reason = [NSString stringWithFormat:@"zipClose returned %d.", err];
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to close zip data.", @"OmniUnzip", OMNI_BUNDLE, @"error reason");
        OmniUnzipError(outError, OmniUnzipUnableToCreateZipFile, description, reason);
        return NO;
    }
    
    return YES;
}

@end

NS_ASSUME_NONNULL_END
