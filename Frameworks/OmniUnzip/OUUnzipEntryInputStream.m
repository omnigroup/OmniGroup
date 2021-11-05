// Copyright 2016-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUnzip/OUUnzipEntryInputStream.h>

#import <OmniUnzip/OUErrors.h>
#import <OmniUnzip/OUUnzipEntry.h>

@import OmniFoundation;

#include "OUUtilities.h"
#include "unzip.h"

RCS_ID("$Id$");

#pragma mark -

@interface OUUnzipEntryInputStream () <NSStreamDelegate> {
  @private
    __weak id <NSStreamDelegate> _delegate;
    NSStreamStatus _streamStatus;
    NSError *_streamError;
}

@property (nonatomic, nullable, copy, readwrite) NSString *archiveDescription;
@property (nonatomic, nullable, copy, readwrite) NSString *archivePath;
@property (nonatomic, nullable, strong, readwrite) NSObject <OFByteProvider> *dataStore;
@property (nonatomic, strong, readwrite) OUUnzipEntry *unzipEntry;
@property (nonatomic, readwrite) OUUnzipEntryInputStreamOptions options;

@property (nonatomic) NSUInteger totalBytesRead;
@property (nonatomic, readonly) NSUInteger streamLength;
@property (nonatomic, readonly) NSUInteger streamPosition;
@property (nonatomic) unzFile unzipFileHandle;

@end

@interface NSInputStream ()
- (instancetype)init NS_DESIGNATED_INITIALIZER;
@end

@implementation OUUnzipEntryInputStream

- (instancetype)init NS_UNAVAILABLE;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (instancetype)initWithData:(NSData *)data NS_UNAVAILABLE;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (nullable instancetype)initWithURL:(NSURL *)url NS_UNAVAILABLE;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (instancetype)initWithUnzipEntry:(OUUnzipEntry *)unzipEntry inZipArchive:(NSString *)description data:(NSObject <OFByteProvider> *)store options:(OUUnzipEntryInputStreamOptions)options;
{
    OBPRECONDITION(unzipEntry != nil);
    OBPRECONDITION(store != nil);
    
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    _dataStore = store;
    _archiveDescription = [description copy];
    _unzipEntry = unzipEntry;
    _options = options;
    _delegate = self;
    _streamStatus = NSStreamStatusNotOpen;
    
    return self;
}

- (instancetype)initWithUnzipEntry:(OUUnzipEntry *)unzipEntry inZipArchiveAtPath:(NSString *)archivePath options:(OUUnzipEntryInputStreamOptions)options;
{
    OBPRECONDITION(unzipEntry != nil);
    OBPRECONDITION(archivePath != nil);
    
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    _archivePath = [archivePath copy];
    _archiveDescription = _archivePath;
    _unzipEntry = unzipEntry;
    _options = options;
    _delegate = self;
    _streamStatus = NSStreamStatusNotOpen;
    
    return self;
}

- (void)dealloc;
{
    [self _closeIfNeeded];
    
    OBPOSTCONDITION(_unzipFileHandle == NULL);
}

- (void)open;
{
    if (self.streamStatus == NSStreamStatusNotOpen) {
        NSError *error = nil;
        if ([self _open:&error]) {
            self.streamStatus = NSStreamStatusOpen;
            [self _sendDelegateStreamEvent:NSStreamEventOpenCompleted];
        } else {
            self.streamStatus = NSStreamStatusError;
            self.streamError = error;
        }
    } else if (self.streamStatus != NSStreamStatusError) {
        self.streamStatus = NSStreamStatusError;
        self.streamError = [NSError errorWithDomain:OmniUnzipErrorDomain code:OmniUnzipOpenSentToStreamInInvalidState userInfo:nil];
    }
}

- (void)close;
{
    if (self.unzipFileHandle != NULL) {
        NSError *error = nil;
        if ([self _close:&error]) {
            self.streamStatus = NSStreamStatusClosed;
        } else {
            self.streamStatus = NSStreamStatusError;
            self.streamError = error;
        }
    } else if (self.streamStatus != NSStreamStatusError) {
        self.streamStatus = NSStreamStatusError;
        self.streamError = [NSError errorWithDomain:OmniUnzipErrorDomain code:OmniUnzipCloseSentToStreamInInvalidState userInfo:nil];
    }
}

- (id <NSStreamDelegate>)delegate;
{
    return _delegate;
}

- (void)setDelegate:(id <NSStreamDelegate>)delegate;
{
    _delegate = delegate;
}

- (nullable id)propertyForKey:(NSStreamPropertyKey)key;
{
    OBASSERT_NOT_REACHED("Unimplemented");
    return nil;
}

- (BOOL)setProperty:(nullable id)property forKey:(NSStreamPropertyKey)key;
{
    OBASSERT_NOT_REACHED("Unimplemented");
    return NO;
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode;
{
    // Nothing to schedule
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode;
{
    // Nothing to schedule
}

- (NSStreamStatus)streamStatus;
{
    return _streamStatus;
}

- (void)setStreamStatus:(NSStreamStatus)streamStatus;
{
    _streamStatus = streamStatus;
}

- (NSError *)streamError;
{
    return _streamError;
}

- (void)setStreamError:(NSError *)error;
{
    _streamError = [error copy];
}

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)length;
{
    return [self _read:buffer maxLength:length];
}

- (BOOL)getBuffer:(uint8_t * _Nullable * _Nonnull)buffer length:(NSUInteger *)len;
{
    OBASSERT_NOT_REACHED("Unimplemented");
    return NO;
}

- (BOOL)hasBytesAvailable;
{
    if (self.streamStatus == NSStreamStatusOpen) {
        return self.streamPosition < self.streamLength;
    }
    
    return NO;
}

#pragma mark Private

- (NSUInteger)streamLength;
{
    BOOL raw = (self.options & OUUnzipEntryInputStreamOptionRaw) != 0;
    return raw ? self.unzipEntry.compressedSize : self.unzipEntry.uncompressedSize;
}

- (NSUInteger)streamPosition;
{
    return self.totalBytesRead;
}

// This always returns NO, so that callers can 'return UNZIP_DATA_ERROR(...);'
static BOOL _unzipDataError(OUUnzipEntryInputStream *self, const char *func, int err, NSError **outError)
{
    NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to read zip data.", @"OmniUnzip", OMNI_BUNDLE, @"error description");
    NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The zip library function %s returned %d when trying to read the data for entry \"%@\" in \"%@\".", @"OmniUnzip", OMNI_BUNDLE, @"error reason"),  func, err, self.unzipEntry.name, self.archiveDescription];
    OmniUnzipError(outError, OmniUnzipUnableToReadZipFileContents, description, reason);
    
    NSLog(@"%s returned %d", func, err);
    return NO;
}

#define UNZIP_DATA_ERROR(f) _unzipDataError(self, #f, err, outError)

- (BOOL)_open:(NSError **)outError;
{
    OBPRECONDITION(self.streamStatus == NSStreamStatusNotOpen);
    OBPRECONDITION(self.unzipFileHandle == NULL);
    
    __autoreleasing NSError *localError = nil;
    if (outError == NULL) {
        outError = &localError;
    }

    if (self.dataStore != nil) {
        self.unzipFileHandle = unzOpen2((__bridge void *)self.dataStore, &OUReadIOImpl);
    } else {
        self.unzipFileHandle = unzOpen(self.archivePath.fileSystemRepresentation);
    }
    
    if (self.unzipFileHandle == nil) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to open zip archive.", @"OmniUnzip", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"The unzip library failed to open %@.", @"OmniUnzip", OMNI_BUNDLE, @"error reason"), self.archiveDescription];
        OmniUnzipError(outError, OmniUnzipUnableToOpenZipFile, description, reason);
        return NO;
    }
    
    
    int err = 0;
    unz_file_pos position;
    
    // Presuming that if we screw up and pass an entry from the wrong file or otherwise have something past the end of the file, that this will be detected.
    memset(&position, 0, sizeof(position));
    position.pos_in_zip_directory = self.unzipEntry.positionInFile;
    position.num_of_file = self.unzipEntry.fileNumber;
    
    err = unzGoToFilePos(self.unzipFileHandle, &position);
    if (err != UNZ_OK) {
        return UNZIP_DATA_ERROR(unzGoToFilePos);
    }
    
    unz_file_info fileInfo;
    err = unzGetCurrentFileInfo(self.unzipFileHandle, &fileInfo, NULL /* file name */, 0 /* size */, NULL, 0, NULL, 0);
    if (err != UNZ_OK) {
        return UNZIP_DATA_ERROR(unzGetCurrentFileInfo);
    }
    
    int method = 0;
    int level = 0;
    BOOL raw = (self.options & OUUnzipEntryInputStreamOptionRaw) != 0;
    err = unzOpenCurrentFile3(self.unzipFileHandle, &method, &level, raw ? 1 : 0, NULL/*password*/);
    if (err != UNZ_OK) {
        return UNZIP_DATA_ERROR(unzOpenCurrentFile3);
    }

    return YES;
}

- (void)_closeIfNeeded;
{
    if (self.unzipFileHandle != NULL) {
        NSError *error = nil;
        if (![self _close:&error]) {
            NSLog(@"Error closing zip archive: %@", error);
        }
    }
}

- (BOOL)_close:(NSError **)outError;
{
    OBPRECONDITION(self.streamStatus == NSStreamStatusOpen || self.streamStatus == NSStreamStatusAtEnd || self.streamStatus == NSStreamStatusError);
    
    if (self.unzipFileHandle != NULL) {
        int err = unzCloseCurrentFile(self.unzipFileHandle);

        unzClose(self.unzipFileHandle);
        self.unzipFileHandle = NULL;

        if (err != UNZ_OK) {
            return UNZIP_DATA_ERROR(unzCloseCurrentFile);
        }
    }
    
    return YES;
}

- (NSInteger)_read:(uint8_t *)buffer maxLength:(NSUInteger)length;
{
    OBPRECONDITION(buffer != NULL);
    OBPRECONDITION(self.streamStatus == NSStreamStatusOpen || self.streamStatus == NSStreamStatusAtEnd);

    if (self.streamStatus == NSStreamStatusAtEnd) {
        return 0;
    }
    
    if (self.streamStatus == NSStreamStatusOpen && !self.hasBytesAvailable && self.totalBytesRead == 0) {
        // We allow a single read of a 0-byte stream before changing the status to NSStreamStatusAtEnd
        self.streamStatus = NSStreamStatusAtEnd;
        return 0;
    }
    
    if (self.streamStatus != NSStreamStatusOpen) {
        self.streamStatus = NSStreamStatusError;
        self.streamError = [NSError errorWithDomain:OmniUnzipErrorDomain code:OmniUnzipReadSentToStreamInInvalidState userInfo:nil];
        return -1;
    }
    
    size_t totalBytesToRead = MIN(length, self.streamLength - self.streamPosition);
    if (totalBytesToRead == 0) {
        OBASSERT_NOT_REACHED("This should have been handled by the NSStreamStatusAtEnd check above.");
        return 0;
    }
    
    size_t totalBytesRead = 0;
    while (totalBytesRead < totalBytesToRead) {
        // wants an unsigned. but then it returns an int; will use INT_MAX instead of UINT_MAX.
        size_t availableBytes = totalBytesToRead - totalBytesRead;
        unsigned bytesToRead = 0;
        if (availableBytes > INT_MAX) {
            bytesToRead = INT_MAX;
        } else {
            bytesToRead = (unsigned)availableBytes;
        }
        
        int copied = unzReadCurrentFile(self.unzipFileHandle, buffer + totalBytesRead, bytesToRead);
        OBASSERT(copied < 0 || (unsigned)copied >= bytesToRead);
        
        if (copied <= 0) {
            int err = copied;
            __autoreleasing NSError *error = nil;
            __autoreleasing NSError **outError = &error;
            UNZIP_DATA_ERROR(unzReadCurrentFile);
            self.streamStatus = NSStreamStatusError;
            self.streamError = error;
            return 0;
        }
        
        totalBytesRead += copied;
    }

    // Update our book keeping for the overall number of bytes read
    self.totalBytesRead += totalBytesRead;
    
    if (!self.hasBytesAvailable) {
        self.streamStatus = NSStreamStatusAtEnd;
    }

    return totalBytesRead;
}

- (void)_sendDelegateStreamEvent:(NSStreamEvent)event;
{
    id <NSStreamDelegate> delegate = self.delegate;
    if (delegate != nil && [delegate respondsToSelector:@selector(stream:handleEvent:)]) {
        [delegate stream:self handleEvent:event];
    }
}

@end

