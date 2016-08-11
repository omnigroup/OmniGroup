// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import "OFSFileByteAcceptor.h"
#import <OmniBase/macros.h>
#import <OmniBase/rcsid.h>
#include <unistd.h>
#include <string.h>
#include <sys/stat.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

static NSError *wrapErrno(NSString *fun);

@implementation OFSFileByteAcceptor
{
    int      _fd;
    size_t   _presentedLength;
    NSError *_storedError;
    BOOL     _closefd;
    BOOL     _lengthSet;
}

- (instancetype)initWithFileDescriptor:(int)fd closeOnDealloc:(BOOL)closeopt;
{
    if (self = [super init]) {
        _fd = fd;
        _closefd = closeopt;
        
        struct stat sbuf;
        if (fstat(_fd, &sbuf) != 0) {
#if 0
            if (!_storedError)
                _storedError = wrapErrno(@"fstat");
#endif
            if (closeopt) {
                close(fd);
                _fd = -1;
            }
            return nil;
        }
#if SIZE_T_MAX < UINT64_MAX
        if (sbuf.st_size >= SIZE_T_MAX) {
            if (closeopt) {
                close(fd);
                _fd = -1;
            }
            return nil;
        }
#endif
        _presentedLength = (size_t)sbuf.st_size;

    }
    return self;
}

- (void)dealloc
{
    if (_closefd && _fd >= 0) {
        close(_fd);
        _fd = -1;
    }
}

/* This is a very simple implementation of the byte provider/acceptor protocol */

- (NSUInteger)length;
{
    return _presentedLength;
}

- (void)getBytes:(void *)buffer range:(NSRange)range;
{
    if (NSMaxRange(range) > _presentedLength)
        OBRejectInvalidCall(self, _cmd, @"Read past EOF");
    
    ssize_t r = pread(_fd, buffer, range.length, range.location);
    
    if (r >= 0) {
        if ((size_t)r == range.length)
            return;
        
        OBRejectInvalidCall(self, _cmd, @"Read past EOF");
    } else {
        if (!_storedError)
            _storedError = wrapErrno(@"read");
        memset(buffer, 0, range.length);
    }
}

- (NSError *)error;
{
    return _storedError;
}

- (void)setLength:(NSUInteger)length;
{
    if (length < _presentedLength) {
        ftruncate(_fd, _presentedLength);
        _presentedLength = length;
        _lengthSet = NO;
        return;
    }
    _presentedLength = length;
    _lengthSet = YES;
}

- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes;
{
    /* This is often valid for a file; the filesystem will grow the file automatically for us. It's not valid for an NSData, which is what we're imitating. */
    if (NSMaxRange(range) > _presentedLength)
        OBRejectInvalidCall(self, _cmd, @"Write past EOF");
    
    ssize_t r = pwrite(_fd, bytes, range.length, range.location);
    
    if (r < 0) {
        if (!_storedError)
            _storedError = wrapErrno(@"write");
    }
}

- (void)flushByteAcceptor;
{
    if (_lengthSet) {
        ftruncate(_fd, _presentedLength);
        _lengthSet = NO;
    }
}

@end


static NSError *wrapErrno(NSString *fun)
{
    int e = errno;
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:e
                           userInfo:@{ @"function" : fun }];
}
