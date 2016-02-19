// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFileStore/OFSEncryptingFileManager.h>

#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <CoreFoundation/CoreFoundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
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

@interface OFSEncryptingFileManagerTasteOperation (/* Private interfaces */)
- (instancetype)initWithOperation:(id <ODAVAsynchronousOperation>)op;
@property (atomic,readwrite) int keySlot;
@property (atomic,readwrite,copy,nullable) NSError *error;
@end

@implementation OFSEncryptingFileManager
{
    OFSFileManager <OFSConcreteFileManager> *underlying;
    OFSDocumentKey *keyManager;
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
    
    return self;
}

- (void)invalidate
{
    [underlying invalidate];
    underlying = nil;
    keyManager = nil;
    [super invalidate];
}

@synthesize keyStore = keyManager;
@synthesize underlyingFileManager = underlying;

#pragma mark OFSConcreteFileManager

+ (BOOL)shouldHaveHostInURL;
{
    OBRejectInvalidCall(self, _cmd, @"No URL scheme for this OFS class");
}

/* NOTE: The file info we return has an inaccurate 'size' field (because we return the size of the underlying file, which has a magic number, file keys, IVs, and checksums prepended).  The only place that ODAVFileInfo.size is used right now is producing progress bars, so that isn't really a problem. */

- (ODAVFileInfo *)fileInfoAtURL:(NSURL *)url error:(NSError **)outError;
{
    return [underlying fileInfoAtURL:url error:outError];
}

/* TODO: Filename masking */

- (NSArray *)directoryContentsAtURL:(NSURL *)url havingExtension:(NSString *)extension error:(NSError **)outError;
{
    return [underlying directoryContentsAtURL:url havingExtension:extension error:outError];
}

- (NSMutableArray *)directoryContentsAtURL:(NSURL *)url collectingRedirects:(NSMutableArray *)redirections error:(NSError **)outError;
{
    return [underlying directoryContentsAtURL:url collectingRedirects:redirections error:outError];
}

- (NSData *)dataWithContentsOfURL:(NSURL *)url error:(NSError **)outError;
{
    NSData *encrypted = [underlying dataWithContentsOfURL:url error:outError];
    if (!encrypted)
        return nil;

    size_t offset = 0;
    OFSSegmentDecryptWorker *decryptionWorker = [OFSSegmentDecryptWorker decryptorForData:encrypted key:keyManager dataOffset:&offset error:outError];
    if (!decryptionWorker)
        return nil;
    
    NSData *result = [decryptionWorker decryptData:encrypted dataOffset:offset error:outError];
    if (!result)
        return nil;
    
    return result;
}

- (NSURL *)writeData:(NSData *)data toURL:(NSURL *)url atomically:(BOOL)atomically error:(NSError **)outError;
{
    OFSSegmentEncryptWorker *worker = keyManager.encryptionWorker;
    
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
    
    return wroteTo;
}

- (NSURL *)createDirectoryAtURL:(NSURL *)url attributes:(NSDictionary *)attributes error:(NSError **)outError;
{
    return [underlying createDirectoryAtURL:url attributes:attributes error:outError];
}

- (NSURL *)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destURL error:(NSError **)outError;
{
    return [underlying moveURL:sourceURL toURL:destURL error:outError];
}

- (BOOL)deleteURL:(NSURL *)url error:(NSError **)outError;
{
    return [underlying deleteURL:url error:outError];
}

- (BOOL)deleteFile:(ODAVFileInfo *)fileInfo error:(NSError **)outError;
{
    return [underlying deleteFile:fileInfo error:outError];
}

- (OFSEncryptingFileManagerTasteOperation *)asynchronouslyTasteKeySlot:(ODAVFileInfo *)file;
{
    if (!file || !file.exists)
        return nil;
    
    id <ODAVAsynchronousOperation> readOp = nil;
    
    /* Attempt to use Range requests for longer files */
    size_t tasteLength = [OFSSegmentDecryptWorker maximumSlotOffset];
    if (file.size > (off_t)(512 + tasteLength) && [underlying respondsToSelector:@selector(asynchronousReadContentsOfFile:range:)]) {
        readOp = [underlying asynchronousReadContentsOfFile:file range:[NSString stringWithFormat:@"bytes=0-%zu", tasteLength]];
    }
    
    if (!readOp) {
        readOp = [underlying asynchronousReadContentsOfURL:file.originalURL];
    }
    
    return [[OFSEncryptingFileManagerTasteOperation alloc] initWithOperation:readOp];
}

- (NSIndexSet *)unusedKeySlotsOfSet:(NSIndexSet *)slots amongFiles:(NSArray <ODAVFileInfo *> *)files error:(NSError **)outError;
{
    NSMutableArray <ODAVFileInfo *> *byAge = [files mutableCopy];

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
    while (unusedSlots.count && byAge.count) {
        /* TODO: Arrange to have multiple tastes in flight; they're very small so the delay is probably mostly roundtrip delay not transfer delay. However, don't start piling them on until the first one has come back: in the common case, there'll be one slot, the oldest file will be using it, we'll go to 0 immediately, and we should avoid tasting other files. In any case, we should cancel any enqueued requests once we hit 0. */
        
        ODAVFileInfo *finfo = [byAge objectAtIndex:0];
        [byAge removeObjectAtIndex:0];
        OFSEncryptingFileManagerTasteOperation *op = [self asynchronouslyTasteKeySlot:finfo];
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

@end

@implementation OFSEncryptingFileManagerTasteOperation
{
    id <NSObject,ODAVAsynchronousOperation> _readerOp;
    NSError *_storedError;
    enum operationState : sig_atomic_t {
        operationState_unstarted,
        operationState_running,
        operationState_finished
    } _state;
    int _storedKeySlot;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)theKey
{
    if ([theKey isEqualToString:@"executing"] || [theKey isEqualToString:@"finished"])
        return NO;
    
    /* It doesn't seem like we should be called with these values, since the property is named w/o the "is"... but we are. Apparently NSOperationQueue observes the key "isExecuting", not "executing". */
    if ([theKey isEqualToString:@"isExecuting"] || [theKey isEqualToString:@"isFinished"])
        return NO;
    
    return [super automaticallyNotifiesObserversForKey:theKey];
}

- (instancetype)initWithOperation:(id <ODAVAsynchronousOperation>)op
{
    if (!(self = [super init])) {
        return nil;
    }
    
    OBASSERT([op conformsToProtocol:@protocol(ODAVAsynchronousOperation)]);
    _readerOp = op;
    _state = operationState_unstarted;
    _storedKeySlot = 0;
    
    return self;
}

@synthesize error = _storedError;
@synthesize keySlot = _storedKeySlot;

- (void)start;
{
    ODAVOperation *reader;
    
    [self willChangeValueForKey:@"executing"];
    [self willChangeValueForKey:@"isExecuting"];
    if (self.cancelled) {
        _state = operationState_finished;
        [_readerOp cancel];
        _readerOp = nil;
        reader = nil;
    } else {
        _state = operationState_running;
        reader = _readerOp;
    }
    [self didChangeValueForKey:@"isExecuting"];
    [self didChangeValueForKey:@"executing"];
    
    if (!reader)
        return;

    reader.didFinish = ^(id <ODAVAsynchronousOperation> op, NSError *errorOrNil){
        OBINVARIANT(op == _readerOp);
        OBPRECONDITION(_state == operationState_running);
        _readerOp = nil;
        
        /* Validate the range response */
        if (!errorOrNil && [op respondsToSelector:@selector(statusCode)]) {
            ODAVOperation *davOp = (ODAVOperation *)op;
            NSInteger statusCode = [davOp statusCode];
            if (statusCode == ODAV_HTTP_OK /* 200 */) {
                // OK
            } else if (statusCode == ODAV_HTTP_PARTIAL_CONTENT /* 206 */) {
                NSString *header = [davOp valueForResponseHeader:@"Content-Range"];
                unsigned long long firstByte, lastByte;
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
            NSError *error = nil;
            int slotnumber = [OFSSegmentDecryptWorker slotForData:op.resultData error:&error];
            if (slotnumber < 1) {
                _storedError = error;
            } else {
                _storedKeySlot = slotnumber;
            }
        }
        [self willChangeValueForKey:@"executing"];
        [self willChangeValueForKey:@"finished"];
        [self willChangeValueForKey:@"isExecuting"];
        [self willChangeValueForKey:@"isFinished"];
        _state = operationState_finished;
        [self didChangeValueForKey:@"isFinished"];
        [self didChangeValueForKey:@"isExecuting"];
        [self didChangeValueForKey:@"finished"];
        [self didChangeValueForKey:@"executing"];
    };

    [reader startWithCallbackQueue:nil];
}

- (void)cancel;
{
    [_readerOp cancel];
}

- (BOOL)isAsynchronous
{
    return YES;
}

- (BOOL)isExecuting
{
    return ( _state == operationState_running );
}

- (BOOL)isFinished
{
    return ( _state == operationState_finished );
}
@end




