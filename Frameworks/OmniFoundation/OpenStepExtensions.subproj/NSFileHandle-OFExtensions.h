// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSFileHandle.h>
#import <dispatch/data.h>

@interface NSFileHandle (OFExtensions)

/**
 Creates a read/write file handle to an anonymous file (an unlinked file on the filesystem used by NSTemporaryDirectory()).
 */
+ (NSFileHandle * __nullable)toAnonymousTemporaryFile;

/**
 Returns a writable file handle. Bytes written to this file handle will be read and passed to the supplied callbacks.
 
 For details on the callback semantics, see `OFReadFDToBlock()`.
 */
+ (NSFileHandle * __nullable)toBlock:(void (^ __nonnull)(dispatch_data_t __nonnull))dataCb eof:(void (^ __nullable)(NSError * __nullable))endCb queue:(dispatch_queue_t __nullable)invocationQueue error:(NSError * __nullable * __nullable)outError;

@end

/**
 Attaches a dispatch_source to the supplied file descriptor which will read data as it becomes available and pass it to the supplied block.
 
 @param reader_fd The file descriptor from which to read. The descriptor will be closed when the source is cancelled.
 @param dataCb Invoked when data has been read from the file descriptor. The `dispatch_data_t` argument can be toll-free bridged to `NSData`.
 @param endCb Invoked when error or EOF has been reached on the descriptor, or when the source has been cancelled. Optional.
 @param invocationQueue The queue on which to invoke the supplied blocks, or NULL.
 @return A dispatch data source. The source must be activated with `dispatch_activate()` before the callbacks will be called.
 */
dispatch_source_t __nonnull OFReadFDToBlock(int reader_fd, void (^ __nonnull /* escaping */ dataCb)(dispatch_data_t __nonnull), void (^ __nullable /* escaping */ endCb)(NSError * __nullable), dispatch_queue_t __nullable invocationQueue);

