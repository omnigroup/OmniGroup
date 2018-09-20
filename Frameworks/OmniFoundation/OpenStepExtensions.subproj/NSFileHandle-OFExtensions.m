// Copyright 2017-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSFileHandle-OFExtensions.h>

RCS_ID("$Id$")

#include <unistd.h>
#include <fcntl.h>
#include <err.h>

static id closeAndError(int fds[2], NSError **outError, NSString *errfunc);
static id posixError(NSError **outError, int errcode, NSString *errfunc);

@implementation NSFileHandle (OFExtensions)

+ (NSFileHandle *)toAnonymousTemporaryFile;
{
    NSMutableData * __attribute__((objc_precise_lifetime)) tmplate = [[[NSTemporaryDirectory() stringByAppendingPathComponent:@"fXXXXXX"] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    char *buf = tmplate.mutableBytes;
    int fd = mkstemp(buf);
    if (fd < 0) {
        warn("mkstemp");
        return nil;
    }
    
    unlink(buf);
    
    return [[self alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
}

+ (NSFileHandle *)toBlock:(void (^)(dispatch_data_t))dataCb eof:(void (^)(NSError *))endCb queue:(dispatch_queue_t)invocationQueue error:(NSError **)outError;
{
    int fds[2];
    if (pipe(fds)) {
        return posixError(outError, errno, @"pipe");
    }
    
    int oldfd0, oldfd1;
    if ((oldfd0 = fcntl(fds[0], F_GETFD, 0) < 0) ||
        (oldfd1 = fcntl(fds[1], F_GETFD, 0) < 0)) {
        return closeAndError(fds, outError, @"fcntl(F_GETFD)");
    }
    if (fcntl(fds[0], F_SETFD, oldfd0 | FD_CLOEXEC) < 0 ||
        fcntl(fds[1], F_SETFD, oldfd1 | FD_CLOEXEC) < 0) {
        return closeAndError(fds, outError, @"fcntl(F_SETFD)");
    }
    
    dispatch_source_t reader = OFReadFDToBlock(fds[0], dataCb, endCb, invocationQueue);
    dispatch_activate(reader);
    
    return [[NSFileHandle alloc] initWithFileDescriptor:fds[1] closeOnDealloc:YES];
    
};

@end

dispatch_source_t OFReadFDToBlock(int readableFd, void (^dataCb)(dispatch_data_t), void (^endCb)(NSError *), dispatch_queue_t invocationQueue)
{
#define SMALL_BUF_SIZE 2048
    
    int oldfl = fcntl(readableFd, F_GETFL, 0);
    if (oldfl < 0) {
        warn("fcntl(F_GETFL)");
    } else {
        if (fcntl(readableFd, F_SETFL, (oldfl | O_NONBLOCK) & ~(O_ASYNC)) < 0) {
            warn("fcntl(F_SETFL)");
        }
    }
    
    dispatch_source_t reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, readableFd, 0, invocationQueue);
    NSError * __block __strong storedError = nil;
    dispatch_source_set_event_handler(reader, ^{
        unsigned long amountReady = dispatch_source_get_data(reader);
        ssize_t amountRead;
        if (amountReady <= SMALL_BUF_SIZE) {
            char buf[SMALL_BUF_SIZE];
            amountRead = read(readableFd, buf, SMALL_BUF_SIZE);
            if (amountRead > 0) {
                // Ideally, we would use DISPATCH_DATA_DESTRUCTOR_INLINE here, or libdispatch would do that automatically for short enough buffers, but it looks like that optimization isn't available to us yet
                dispatch_data_t blk = dispatch_data_create(buf, amountRead, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                dataCb(blk);
                return;
            }
        } else {
            size_t bufSize = ((amountReady - 1) | 0x3FFF) + 1;
            char *buf = malloc(bufSize);
            amountRead = read(readableFd, buf, bufSize);
            if (amountRead > 0) {
                dispatch_data_t blk = dispatch_data_create(buf, amountRead, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
                dataCb(blk);
                return;
            } else {
                free(buf);
            }
        }
        
        if (amountRead == 0) {
            // This signals EOF. We shouldn't ever get this--- the dispatch source should just call the cancel/finish block.
            dispatch_source_cancel(reader);
        } else {
            // This indicates an error.
            int readErrno = errno;
            switch (readErrno) {
                case EAGAIN:
                case EINTR:
                case ENOBUFS:
                    // Recoverable error.
                    return;
                    
                default:
                    // For other errors, we go ahead and fail.
                    storedError = [NSError errorWithDomain:NSPOSIXErrorDomain code:readErrno userInfo:nil];
                    dispatch_source_cancel(reader);
                    return;
            }
        }
    });
    
    dispatch_source_set_cancel_handler(reader, ^{
        if (close(readableFd))
            warn("read");
        if (endCb)
            endCb(storedError);
    });
    
    return reader;
}

static id closeAndError(int fds[2], NSError **outError, NSString *errfunc)
{
    close(fds[0]);
    close(fds[1]);
    return posixError(outError, errno, errfunc);
}

static id posixError(NSError **outError, int errcode, NSString *errfunc)
{
    if (outError) {
        NSDictionary *userInfo = errfunc ? @{ @"function": errfunc } : nil;
        *outError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errcode userInfo:userInfo];
    }
    return nil;
}
