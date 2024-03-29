// Copyright 2014-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSEncryptingFileManager.h>

#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSIndexSet-OFExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFileStore/OFSDocumentKey.h>
#import <OmniFileStore/OFSSegmentedEncryptionWorker.h>
#import <OmniFileStore/Errors.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniDAV/ODAVOperation.h>
#import <dispatch/dispatch.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC


@interface OFSEncryptingFileManager ()
+ (NSData *)_decryptData:(NSData *)encrypted url:(NSURL *)url documentKey:(OFSDocumentKey *)keyManager error:(NSError **)outError;
@end

@interface _OFSEncryptingFileManagerReadOperation : NSObject <ODAVAsynchronousOperation>

- initWithURL:(NSURL *)url documentKey:(OFSDocumentKey *)keyManager underlyingOperation:(id <ODAVAsynchronousOperation>)operation;
- initWithURL:(NSURL *)url error:(NSError *)error;

@property(nonatomic,readonly) NSURL *url;
@property(nonatomic,readonly) NSMutableData *encryptedData;
@property(nonatomic,readonly) NSData *resultData;

@end

@implementation _OFSEncryptingFileManagerReadOperation
{
    id <ODAVAsynchronousOperation> _operation;
    OFSDocumentKey *_keyManager;
    NSError *_error;
}

- initWithURL:(NSURL *)url documentKey:(OFSDocumentKey *)keyManager underlyingOperation:(id <ODAVAsynchronousOperation>)operation;
{
    _operation = operation;
    _keyManager = [keyManager copy];
    _url = [url copy];

    __weak _OFSEncryptingFileManagerReadOperation *weakSelf = self;
    _operation.didFinish = ^(id<ODAVAsynchronousOperation> _Nonnull op, NSError * _Nullable errorOrNil){
        _OFSEncryptingFileManagerReadOperation *strongSelf = weakSelf;
        [strongSelf _didFinish:errorOrNil];
    };
    _operation.didReceiveData = ^(id<ODAVAsynchronousOperation>  _Nonnull op, NSData * _Nonnull data) {
        _OFSEncryptingFileManagerReadOperation *strongSelf = weakSelf;
        [strongSelf _didReceiveData:data];
    };

    return self;
}

- initWithURL:(NSURL *)url error:(NSError *)error;
{
    _error = [error copy];
    _url = [url copy];

    return self;
}

@synthesize shouldRetry = _shouldRetry;
@synthesize willRetry = _willRetry;
@synthesize didFinish = _didFinish;
@synthesize didReceiveData = _didReceiveData;
@synthesize didReceiveBytes = _didReceiveBytes;
@synthesize didSendBytes = _didSendBytes;

- (long long)expectedLength;
{
    OBPRECONDITION(_operation != nil);
    return _operation.expectedLength;
}

- (long long)processedLength;
{
    OBPRECONDITION(_operation != nil);
    return _operation.processedLength;
}

- (void)cancel;
{
    [_operation cancel];
}

- (void)startWithCallbackQueue:(NSOperationQueue * _Nullable)queue;
{
    if (_operation) {
        [_operation startWithCallbackQueue:queue];
    } else {
        OBASSERT(_error);

        // This is a non-HTTP error which we don't retry.
        typeof(_didFinish) didFinish = _didFinish;
        [self _clearCallbacks];

        if (didFinish) {
            if (!queue) {
                queue = [NSOperationQueue currentQueue];
            }
            [queue addOperationWithBlock:^{
                didFinish(self, _error);
            }];
        }
    }
}

- (void)_clearCallbacks;
{
    _shouldRetry = nil;
    _willRetry = nil;
    _didFinish = nil;
    _didReceiveBytes = nil;
    _didReceiveData = nil;
    _didSendBytes = nil;
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return self;
}

#pragma mark - Private

- (void)_didReceiveData:(NSData *)data;
{
    if (_encryptedData == nil) {
        _encryptedData = [[NSMutableData alloc] init];
    }
    [_encryptedData appendData:data];
}

- (void)_didFinish:(NSError *)errorOrNil;
{
    // NOTE: We aren't bridging the shouldRetry support here, but the only place it is currently used is in this class's -asynchronouslyTasteKeySlot:.

    NSError * __autoreleasing error;

    if (errorOrNil) {
        error = errorOrNil;
    } else {
        OBASSERT(_encryptedData);

        NSData *decrypted = [OFSEncryptingFileManager _decryptData:_encryptedData url:_url documentKey:_keyManager error:&error];

        if (_didReceiveData) {
            // With this block set, we don't "buffer" the data.
            _didReceiveData(self, decrypted);
        } else {
            _resultData = [decrypted copy];
        }
    }

    typeof(_didFinish) didFinish = _didFinish;
    [self _clearCallbacks];

    if (didFinish) {
        // Here we've been called on the callback queue for the underlying operation and can just directly call the didFinish block.
        didFinish(self, error);
    }
}

@end



@interface OFSEncryptingFileManagerTasteOperation (/* Private interfaces */)
- (instancetype)initWithOperation:(id <ODAVAsynchronousOperation>)op;
- (instancetype)initWithResult:(int)policy;
@property (atomic,readwrite) int plaintextSlot;
@property (atomic,readwrite) int keySlot;
@property (atomic,readwrite,copy,nullable) NSError *error;
@end

static BOOL errorIndicatesPlaintext(NSError *err);

@implementation OFSEncryptingFileManager
{
    OFSFileManager <OFSConcreteFileManager> *underlying;
    OFSDocumentKey *keyManager;
    NSMutableArray <OFSEncryptingFileManagerFileMatch> *maskedFiles;
}

- initWithBaseURL:(NSURL *)baseURL delegate:(id <OFSFileManagerDelegate>)delegate error:(NSError **)outError NS_UNAVAILABLE;
{
    /* We could implement this, but we don't want to use it: we want to combine the multiple PROPFINDs of the encrypted info, which means the URL parsing has to happen at a layer above us. */
    OBRejectInvalidCall(self, _cmd, @"This method should not be called directly");
}

- initWithFileManager:(OFSFileManager <OFSConcreteFileManager> *)underlyingFileManager keyStore:(OFSDocumentKey *)keyStore error:(NSError **)outError;
{
    if (!(self = [super initWithBaseURL:[underlyingFileManager baseURL] delegate:[underlyingFileManager delegate] error:outError]))
        return nil;
    
    underlying = underlyingFileManager;
    keyManager = keyStore;
    maskedFiles = [[NSMutableArray alloc] init];
    
    return self;
}

- (void)invalidate
{
    [underlying invalidate];
    underlying = nil;
    keyManager = nil;
    maskedFiles = nil;
    [super invalidate];
}

@synthesize keyStore = keyManager;
@synthesize underlyingFileManager = underlying;

#pragma mark OFSConcreteFileManager

+ (BOOL)shouldHaveHostInURL;
{
    OBRejectInvalidCall(self, _cmd, @"No URL scheme for this OFS class");
}

/* NOTE: The file info we return may have an inaccurate 'size' field (because we return the size of the underlying file, which has a magic number, file keys, IVs, and checksums prepended).  The only place that ODAVFileInfo.size is used right now is producing progress bars, so that isn't really a problem. */

- (ODAVFileInfo *)fileInfoAtURL:(NSURL *)url error:(NSError **)outError;
{
    if ([self maskingFileAtURL:url]) {
        return [[self class] _maskedFileInfoForURL:url];
    } else {
        return [underlying fileInfoAtURL:url error:outError];
    }
}

- (ODAVFileInfo *)fileInfoAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirects error:(NSError **)outError;
{
    // No redirects here, so just return the value from the simpler method.
    return [self fileInfoAtURL:url error:outError];
}

- (NSArray<ODAVFileInfo *> *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension error:(NSError **)outError;
{
    NSArray *result = [underlying directoryContentsAtURL:url havingExtension:extension error:outError];
    result = [result filteredArrayUsingPredicate:[self _stripMaskedFilesPredicate]];
    return result;
}

- (NSArray<ODAVFileInfo *> *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections machineDate:(NSDate **)outMachineDate error:(NSError **)outError;
{
    NSArray *result = [underlying directoryContentsAtURL:url collectingRedirects:redirections machineDate:outMachineDate error:outError];
    result = [result filteredArrayUsingPredicate:[self _stripMaskedFilesPredicate]];
    return result;
}

- (NSMutableArray *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections error:(NSError **)outError;
{
    NSMutableArray *result = [underlying directoryContentsAtURL:url collectingRedirects:redirections error:outError];
    [result filterUsingPredicate:[self _stripMaskedFilesPredicate]];
    return result;
}

- (id <ODAVAsynchronousOperation>)asynchronousReadContentsOfURL:(NSURL *)url;
{
    OBLog(OFSFileManagerLogger, 2, @"ENCRYPTION operation: read %@", url);

    if ([self maskingFileAtURL:url]) {
        OBLog(OFSFileManagerLogger, 1, @"    --> masking");
        NSError * __autoreleasing error;
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to read file.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No such file \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [url absoluteString]];
        OFSError(&error, OFSNoSuchFile, description, reason);
        return [[_OFSEncryptingFileManagerReadOperation alloc] initWithURL:url error:error];
    }

    return [[_OFSEncryptingFileManagerReadOperation alloc] initWithURL:url documentKey:keyManager underlyingOperation:[underlying asynchronousReadContentsOfURL:url]];
}

- (NSData *)dataWithContentsOfURL:(NSURL *)url error:(NSError **)outError;
{
    OBLog(OFSFileManagerLogger, 2, @"ENCRYPTION operation: read %@", url);
    
    if ([self maskingFileAtURL:url]) {
        OBLog(OFSFileManagerLogger, 1, @"    --> masking");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to read file.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No such file \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [url absoluteString]];
        OFSError(outError, OFSNoSuchFile, description, reason);
        return nil;
    }
    
    NSData *encrypted = [underlying dataWithContentsOfURL:url error:outError];
    if (!encrypted)
        return nil;

    return [[self class] _decryptData:encrypted url:url documentKey:keyManager error:outError];
}

+ (NSData *)_decryptData:(NSData *)encrypted url:(NSURL *)url documentKey:(OFSDocumentKey *)keyManager error:(NSError **)outError;
{
    unsigned dispositionFlags = [keyManager flagsForFilename:[url lastPathComponent]];
    if (dispositionFlags & OFSDocKeyFlagAlwaysUnencryptedRead) {
        OBLog(OFSFileManagerLogger, 1, @"    --> always unencrypted read");
        return encrypted;
    }
    
    size_t offset = 0;
    NSRange keyInfoLocation = { 0, 0 };
    NSError * __autoreleasing headerError = nil;
    if (![OFSSegmentDecryptWorker parseHeader:encrypted truncated:NO wrappedInfo:&keyInfoLocation dataOffset:&offset error:&headerError]) {
        OBLog(OFSFileManagerLogger, 1, @"    --> header parse error %@ (flags:%u)", headerError, dispositionFlags);
        if (dispositionFlags & OFSDocKeyFlagAllowUnencryptedRead && errorIndicatesPlaintext(headerError)) {
            return encrypted;
        }
        
        NSString *description = NSLocalizedStringFromTableInBundle(@"Cannot read file", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        NSString *suggestion = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to decrypt contents of file “%@”.", @"OmniFileStore", OMNI_BUNDLE, @"error reason - token is filename"), [url lastPathComponent]];
        OFSErrorWithInfo(outError, OFSCannotRead, description, suggestion, NSUnderlyingErrorKey, headerError, nil);
        return nil;
    }
    
    /* Get a decryption worker. We don't currently cache these, although we could cache them per keyInfo blob value (since that blob both indicates the keyslot, and contains any data needed to derive the file subkey). That cache should live in the DocumentKey class though. */
    NSData *keyInfo = [encrypted subdataWithRange:keyInfoLocation];
    OFSSegmentDecryptWorker *decryptionWorker = [OFSSegmentDecryptWorker decryptorForWrappedKey:keyInfo documentKey:keyManager.keySlots error:outError];
    if (!decryptionWorker)
        return nil;
    
    NSData *result = [decryptionWorker decryptData:encrypted dataOffset:offset error:outError];
    if (!result)
        return nil;
    
    OBLog(OFSFileManagerLogger, 1, @"    --> decrypted data (%tu bytes)", [result length]);
    return result;
}

- (NSURL *)writeData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)outError;
{
    OBLog(OFSFileManagerLogger, 2, @"ENCRYPTION operation: write %@ (%tu bytes, atomic:%@)", url, [data length], atomically ? @"YES" : @"NO");
    
    if ([self maskingFileAtURL:url]) {
        OBLog(OFSFileManagerLogger, 1, @"    --> masking");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to write file.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No such file \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [url absoluteString]];
        OFSError(outError, OFSCannotWrite, description, reason);
        return nil;
    }
    
    unsigned dispositionFlags = [keyManager flagsForFilename:[url lastPathComponent]];
    if (dispositionFlags & OFSDocKeyFlagAlwaysUnencryptedWrite) {
        OBLog(OFSFileManagerLogger, 1, @"    --> always unencrypted write");
        return [underlying writeData:data toURL:url atomically:atomically error:outError];
    }
    
    OFSSegmentEncryptWorker *worker = [keyManager encryptionWorker:outError];
    if (!worker)
        return nil;
    
    NSData *encrypted = [worker encryptData:data error:outError];
    if (!encrypted)
        return nil;
    
    NSURL *wroteTo = [underlying writeData:encrypted toURL:url atomically:atomically error:outError];
    if (!wroteTo)
        return nil;
    
#if 0 // Not implemented yet
    NSDictionary *uinfo = @{
                            OFSFileManagerKeySlotOp: @( OFSFileManagerSlotWrote ),
                            OFSFileManagerKeySlotURL: wroteTo,
                            OFSFileManagerKeySlotNumber: @( worker.keySlot )
                            };
    [[NSNotificationCenter defaultCenter] postNotificationName:OFSFileManagerKeySlotNotificationName object:self userInfo:uinfo];
#endif
    
    OBLog(OFSFileManagerLogger, 1, @"    --> wrote %tu bytes", [encrypted length]);
    return wroteTo;
}

- (NSURL *)createDirectoryAtURL:(NSURL *)url attributes:(NSDictionary *)attributes error:(NSError **)outError;
{
    if ([self maskingFileAtURL:url]) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Cannot create directory.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No such directory \"%@\"", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [url absoluteString]];
        OFSError(outError, OFSCannotCreateDirectory, description, reason);
        return nil;
    }

    return [underlying createDirectoryAtURL:url attributes:attributes error:outError];
}

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL error:(NSError **)outError;
{
    if ([self maskingFileAtURL:sourceURL]) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Cannot move file.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No such file \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [sourceURL absoluteString]];
        OFSError(outError, OFSNoSuchFile, description, reason);
        return nil;
    }
    
    if ([self maskingFileAtURL:destURL]) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Cannot move file.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No such file \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [destURL absoluteString]];
        OFSError(outError, OFSCannotWrite, description, reason);
        return nil;
    }
    
    return [underlying moveURL:sourceURL toURL:destURL error:outError];
}

- (BOOL)deleteURL:(NSURL *)url error:(NSError **)outError;
{
    if ([self maskingFileAtURL:url]) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Cannot delete file.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No such file \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [url absoluteString]];
        OFSError(outError, OFSNoSuchFile, description, reason);
        return NO;
    }
    
    return [underlying deleteURL:url error:outError];
}

- (BOOL)deleteFile:(ODAVFileInfo *)fileInfo error:(NSError **)outError;
{
    if ([self maskingFileAtURL:fileInfo.originalURL]) {
        NSString *description = NSLocalizedStringFromTableInBundle(@"Cannot delete file.", @"OmniFileStore", OMNI_BUNDLE, @"error description");
        NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"No such file \"%@\".", @"OmniFileStore", OMNI_BUNDLE, @"error reason"), [fileInfo.originalURL absoluteString]];
        OFSError(outError, OFSNoSuchFile, description, reason);
        return NO;
    }
    
    return [underlying deleteFile:fileInfo error:outError];
}

- (nullable OFSEncryptingFileManagerTasteOperation *)asynchronouslyTasteKeySlot:(ODAVFileInfo *)file;
{
    if (!file || !file.exists)
        return nil;
    
    int maskSlot = -1;
    unsigned flags = [keyManager.keySlots flagsForFilename:file.name fromSlot:&maskSlot];
    
    if (flags & OFSDocKeyFlagAlwaysUnencryptedRead) {
        return [[OFSEncryptingFileManagerTasteOperation alloc] initWithResult:maskSlot];
    }
    
    id <ODAVAsynchronousOperation> readOp = nil;
    
    /* Attempt to use Range requests for longer files */
    size_t tasteLength = [OFSSegmentDecryptWorker maximumSlotOffset];
    if (file.size > (off_t)(512 + tasteLength) && [underlying respondsToSelector:@selector(asynchronousReadContentsOfFile:range:)]) {
        NSString *range = [NSString stringWithFormat:@"bytes=0-%zu", tasteLength];

        readOp = [underlying asynchronousReadContentsOfFile:file range:range];

        __block NSUInteger retries = 0;

        // See also the notes on -[ODAVConnection asynchronousGetContentsOfURL:withETag:range:] about why we might get a 412 Precondition failure here.
        readOp.shouldRetry = ^id <ODAVAsynchronousOperation>(id <ODAVAsynchronousOperation> op, NSHTTPURLResponse *response){
            if (response.statusCode != ODAV_HTTP_PRECONDITION_FAILED) {
                return nil;
            }

            // Has the source been modified during this second?
            NSString *DateHeader = [response allHeaderFields][@"Date"];
            NSString *ModifiedHeader = [response allHeaderFields][@"Last-Modified"];
            if (![DateHeader isEqual:ModifiedHeader]) {
                return nil;
            }

            // Did the server indicate this by returning a weak validator?
            NSString *ETag = [response allHeaderFields][@"ETag"];
            if (![ETag isEqualToString:[NSString stringWithFormat:@"W/%@", file.ETag]]) {
                return nil;
            }

            // Don't flood the server; wait a bit before trying again.
            if (retries > 5) {
                OBASSERT_NOT_REACHED("Continual modification of the resource, or server Date header not updating?");
                return nil;
            }
            retries++;

            usleep(250000); // Wait a 1/4 second
            return [underlying asynchronousReadContentsOfFile:file range:range];
        };
    }
    
    if (!readOp) {
        readOp = [underlying asynchronousReadContentsOfURL:file.originalURL];
    }
    
    OFSEncryptingFileManagerTasteOperation *tasteOp = [[OFSEncryptingFileManagerTasteOperation alloc] initWithOperation:readOp];
    if (flags & OFSDocKeyFlagAllowUnencryptedRead)
        tasteOp.plaintextSlot = maskSlot;
    return tasteOp;
}

- (NSIndexSet *)unusedKeySlotsOfSet:(NSIndexSet *)slots amongFiles:(NSArray <ODAVFileInfo *> *)files error:(NSError **)outError;
{
    NSMutableArray <ODAVFileInfo *> *byAge = [files mutableCopy];
    
    // Make sure we're not considering directories when tasting later
    [byAge removeObjectsSatisfyingPredicate:^BOOL(ODAVFileInfo *fileInfo) {
        return [fileInfo isDirectory];
    }];

    [byAge sortUsingComparator:^(id a, id b){
        NSDate *aDate = ((ODAVFileInfo *)a).lastModifiedDate;
        NSDate *bDate = ((ODAVFileInfo *)b).lastModifiedDate;
        
        if (aDate && bDate)
            return [aDate compare:bDate];
        else if (!aDate && !bDate)
            return NSOrderedSame;
        else if (!aDate)
            return NSOrderedAscending;
        else
            return NSOrderedDescending;
    }];

    NSMutableIndexSet *unusedSlots = [slots mutableCopy];
    NSOperationQueue *tasteq = [[NSOperationQueue alloc] init];
    // tasteq.maxConcurrentOperationCount = 3; ?
    tasteq.name = NSStringFromSelector(_cmd);
    
    /* Taste the files, oldest-first */
    OFSKeySlots *keys = keyManager.keySlots;
    while (unusedSlots.count && byAge.count) {
        /* TODO: Arrange to have multiple tastes in flight; they're very small so the delay is probably mostly roundtrip delay not transfer delay. However, don't start piling them on until the first one has come back: in the common case, there'll be one slot, the oldest file will be using it, we'll go to 0 immediately, and we should avoid tasting other files. In any case, we should cancel any enqueued requests once we hit 0. */
        
        ODAVFileInfo *finfo = [byAge objectAtIndex:0];
        [byAge removeObjectAtIndex:0];
        
        int maskSlot = -1;
        unsigned flags = [keys flagsForFilename:finfo.name fromSlot:&maskSlot];
        if (flags & OFSDocKeyFlagAlwaysUnencryptedRead) {
            if (maskSlot >= 0)
                [unusedSlots removeIndex:maskSlot];
            continue;
        }
        
        OFSEncryptingFileManagerTasteOperation *op = [self asynchronouslyTasteKeySlot:finfo];
        if (flags & OFSDocKeyFlagAllowUnencryptedRead)
            op.plaintextSlot = maskSlot;
        [tasteq addOperation:op];
        [op waitUntilFinished];
        
        NSError *error = op.error;
        NSError *suberror;
        if (error) {
            /* Need to decide whether this error indicates a garbage file (which we can safely ignore) or a recoverable read error (which we should not ignore) */
            NSString *domain = error.domain;
            if ([domain isEqualToString:OFSErrorDomain]) {
                NSInteger code = error.code;
                if (code == OFSNoSuchFile) {
                    /* We had a successful HTTP transaction which told us that the file doesn't exist. We can continue on: either someone deleted the file out from under us, or PROPFIND returned a file that doesn't actually exist. */
                    continue;
                }
                if (code == OFSEncryptionBadFormat) {
                    /* Garbled file, or file that isn't even encrypted. In neither case does it reference a key slot. */
                    continue;
                }
            }
            if ((suberror = [error underlyingErrorWithDomain:OFSDAVHTTPErrorDomain]) != nil) {
                NSInteger code = suberror.code;
                if (code == OFS_HTTP_NOT_FOUND || code == OFS_HTTP_GONE) {
                    /* See above for our treatment of file-not-found */
                    continue;
                }
            }
            if ((suberror = [error underlyingErrorWithDomain:NSCocoaErrorDomain]) != nil) {
                NSInteger code = suberror.code;
                if (code == NSFileNoSuchFileError || code == NSFileReadNoSuchFileError || code == NSFileReadInvalidFileNameError) {
                    /* See above for our treatment of file-not-found */
                    continue;
                }
            }
            
            // Failure!
            if (outError)
                *outError = error;
            return nil;
        } else {
            [unusedSlots removeIndex:op.keySlot];
        }
    }
    
    return unusedSlots;
}

- (BOOL)maskingFileAtURL:(NSURL *)fileURL;
{
    for (OFSEncryptingFileManagerFileMatch matchBlock in maskedFiles) {
        if (matchBlock(fileURL))
            return YES;
    }
    return NO;
}

- (void)maskFilesMatching:(OFSEncryptingFileManagerFileMatch)matchBlock;

{
    [maskedFiles addObject:matchBlock];
}

#pragma mark Helpers

- (NSPredicate *)_stripMaskedFilesPredicate;
{
    return [NSPredicate predicateWithBlock:^(ODAVFileInfo * _Nonnull fileInfo, NSDictionary<NSString *,id> * _Nullable bindings) {
        if ([self maskingFileAtURL:fileInfo.originalURL])
            return NO;
        else
            return YES;
    }];
}

+ (ODAVFileInfo *)_maskedFileInfoForURL:(NSURL *)URL;
{
    return [[ODAVFileInfo alloc] initWithOriginalURL:URL name:[ODAVFileInfo nameForURL:URL] exists:NO directory:NO size:0 lastModifiedDate:nil];
}

@end

@implementation OFSEncryptingFileManagerTasteOperation
{
    id <NSObject,ODAVAsynchronousOperation> _readerOp;
    NSError *_storedError;
    int _storedKeySlot;      // Our result (the slot number of the tasted file)
    int _plaintextSlot;      // Slot number of any plaintext policy that applies to this file
    BOOL _forcePolicySlot;   // YES if "always read plaintext", NO if "optionally read plaintext"
}

- (instancetype)initWithOperation:(id <ODAVAsynchronousOperation>)op
{
    if (!(self = [super init])) {
        return nil;
    }
    
    OBASSERT([op conformsToProtocol:@protocol(ODAVAsynchronousOperation)]);
    _readerOp = op;
    _storedKeySlot = -1;
    _plaintextSlot = -1;
    _forcePolicySlot = NO;
    
    return self;
}

- (instancetype)initWithResult:(int)policySlot;
{
    if (!(self = [super init])) {
        return nil;
    }
    
    _readerOp = nil;
    _storedKeySlot = policySlot;
    _plaintextSlot = -1;
    _forcePolicySlot = YES;
    
    return self;
}

@synthesize error = _storedError;
@synthesize keySlot = _storedKeySlot;
@synthesize plaintextSlot = _plaintextSlot;

- (void)start;
{
    [super start];
    
    if (self.cancelled) {
        [_readerOp cancel];
        _readerOp = nil;
        if (!_storedError)
            self.error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
        [self finish];
        return;
    }
    
    if (_forcePolicySlot) {
        OBASSERT(!_readerOp);
        OBASSERT(_storedKeySlot >= 0);
        [self finish];
        return;
    }
    
    ODAVOperation *reader = _readerOp;

    reader.willRetry = ^(id <ODAVAsynchronousOperation> __nonnull original, id <ODAVAsynchronousOperation> __nonnull retry){
        OBASSERT(original == _readerOp);

        _readerOp = retry;
        OBASSERT(retry.didFinish != NULL); // The didFinish we assigned to the original should have been copied over.
    };

    reader.didFinish = ^(id <ODAVAsynchronousOperation> op, NSError *errorOrNil){
        [self _didFinish:op error:errorOrNil];
    };

    [reader startWithCallbackQueue:nil];
}

- (void)cancel;
{
    [_readerOp cancel];
    [super cancel];
}

- (void)_didFinish:(id <ODAVAsynchronousOperation>)op error:(NSError *)errorOrNil;
{
    OBINVARIANT(op == _readerOp);
    OBPRECONDITION([self isExecuting]);
    _readerOp = nil;
    BOOL gotSubrange = NO;

    /* Validate the range response */
    if (!errorOrNil && [op respondsToSelector:@selector(statusCode)]) {
        ODAVOperation *davOp = (ODAVOperation *)op;
        NSInteger statusCode = [davOp statusCode];
        if (statusCode == ODAV_HTTP_OK /* 200 */) {
            // OK
        } else if (statusCode == ODAV_HTTP_PARTIAL_CONTENT /* 206 */) {
            NSString *header = [davOp valueForResponseHeader:@"Content-Range"];
            unsigned long long firstByte, lastByte;
            gotSubrange = YES;
            if (ODAVParseContentRangeBytes(header, &firstByte, &lastByte, NULL)) {
                if (firstByte != 0 || lastByte < firstByte || lastByte+1 != [davOp.resultData length]) {
                    errorOrNil = [NSError errorWithDomain:ODAVErrorDomain code:ODAVInvalidPartialResponse userInfo:@{ @"Content-Range": header }];
                }
            } else {
                errorOrNil = [NSError errorWithDomain:ODAVErrorDomain code:ODAVInvalidPartialResponse userInfo:@{ @"Content-Range": (header?header:@"(missing)") }];
            }
        } else {
            errorOrNil = [NSError errorWithDomain:ODAVErrorDomain code:ODAVInvalidPartialResponse userInfo:@{ @"statusCode": @(statusCode) }];
        }
    }

    if (errorOrNil) {
        _storedError = errorOrNil;
    } else {
        NSError * __autoreleasing error = nil;
        NSRange blobLocation = { 0, 0 };
        if (![OFSSegmentDecryptWorker parseHeader:op.resultData truncated:gotSubrange wrappedInfo:&blobLocation dataOffset:NULL error:&error]) {

            // We couldn't parse the encryption header. See if there was a flag indicating that we are allowed to let old plaintext files show through. If so, and this is one such, then we've tasted that slot.
            int maskSlot = self.plaintextSlot;
            if (maskSlot >= 0 && errorIndicatesPlaintext(error)) {
                _storedKeySlot = maskSlot;
            } else {
                _storedError = error;
            }
        } else {
            /* Get the key slot index from this file. This slightly breaks the encapsulation of OFSDocumentKey; elsewhere, the fact that the key blob starts with a key slot index is internal to that class. But the fact that key slots *exist* is part of its API, so this isn't too bad. */
            if (blobLocation.length >= 2) {
                char buf[2];
                [op.resultData getBytes:buf range:(NSRange){blobLocation.location, 2}];
                _storedKeySlot = OSReadBigInt16(buf, 0);
            } else {
                _storedError = [NSError errorWithDomain:OFSErrorDomain code:OFSEncryptionBadFormat userInfo:@{ NSLocalizedFailureReasonErrorKey: @"undersized info field"}];
            }
        }
    }

    [self finish];
}

@end


static BOOL errorIndicatesPlaintext(NSError *err)
{
    err = [err underlyingErrorWithDomain:OFSErrorDomain code:OFSEncryptionBadFormat];
    if (err && [err.userInfo objectForKey:OFSEncryptionBadFormatNotEncryptedKey])
        return YES;
    return NO;
}

