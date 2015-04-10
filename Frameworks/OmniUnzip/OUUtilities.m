// Copyright 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import "OUUtilities.h"

#import <OmniFoundation/OFByteProviderProtocol.h>
#import "unzip.h"

RCS_ID("$Id$");

/* We mostly live in minizip's C-based world, so ARC is more of a pain than a help here. Could turn it on if needed. */
#if OB_ARC
#error This file is not ARC-compatible
#endif

// #define DEBUG_BUFFERING

#define OUZ_BUFFER_SIZE 128
#define OUZ_UNBUFFER_THRESHOLD 16

#define UNLK(x) __builtin_expect(x, 0)

struct ouzProviderBuffer {
    id <NSObject,OFByteProvider,OFByteAcceptor> __unsafe_unretained storage;
    
    NSUInteger position;
    NSUInteger cachedProviderLength;
    BOOL canRead;
    BOOL hadError;
    enum {
        ouz_noBuffer,
        ouz_readBuffer,
        ouz_writeBuffer
    } __attribute__((packed)) bufferState;
    
    char *buffer;  /* If releaseBuffer is NULL, then this is a buffer we allocated, and is of length OUZ_BUFFER_SIZE (but may contain less data; see bufferLength). Otherwise, it is a buffer owned by the provider. */
    NSUInteger bufferStart, bufferLength;
    OFByteProviderBufferRelease releaseBuffer;
};

/* Open for reading */
static void *ouzDataOpenRead(voidpf opaque, const char* filename, int mode)
{
    struct ouzProviderBuffer *st = malloc(sizeof(*st));
    
    st->storage = (id __unsafe_unretained)[(id)filename retain];
    st->position = 0;
    st->cachedProviderLength = [(st->storage) length];
    st->canRead = YES;
    st->hadError = NO;
    st->bufferState = ouz_noBuffer;
    st->buffer = NULL;
    st->releaseBuffer = NULL;
    
    return st;
}

/* Open for writing */
static void *ouzDataOpenWrite(voidpf opaque, const char* filename, int mode)
{
    struct ouzProviderBuffer *st = malloc(sizeof(*st));
    
    id <NSObject,OFByteProvider,OFByteAcceptor> __unsafe_unretained storage = [(id)filename retain];
    st->storage = storage;
    st->position = 0;
    
    BOOL canRead;
    if ([storage respondsToSelector:@selector(length)]) {
        st->cachedProviderLength = [storage length];
        if ([storage respondsToSelector:@selector(getBytes:range:)]) {
            canRead = YES;
        } else {
            canRead = NO;
        }
    } else {
        st->cachedProviderLength = 0;
        canRead = NO;
    }
    st->canRead = canRead;
    
    st->hadError = NO;
    st->bufferState = ouz_noBuffer;
    st->buffer = NULL;
    st->releaseBuffer = NULL;

    return st;
}

static void output(struct ouzProviderBuffer *st, NSUInteger position, NSUInteger length, const char *buf, const char *opn)
{
    if (UNLK(length == 0))
        return;
    
    NSUInteger end = position + length;
    
    if (st->cachedProviderLength < end) {
        [st->storage setLength:end];
        st->cachedProviderLength = end;
    }
    
#ifdef DEBUG_BUFFERING
    printf("OBP %s %4" PRIuNS " at %5" PRIuNS "\n", opn, length, position);
#endif
    
    [st->storage replaceBytesInRange:(NSRange){ position, length } withBytes:buf];
}

static void ouzDiscardBuffer(struct ouzProviderBuffer *st)
{
    if (st->releaseBuffer) {
        OBASSERT(st->bufferState == ouz_readBuffer);
        
        st->releaseBuffer();
        st->buffer = NULL;
        Block_release(st->releaseBuffer);
        st->releaseBuffer = NULL;
        
        st->bufferState = ouz_noBuffer;
    }
    
    if (st->bufferState == ouz_readBuffer) {
        /* We've released the provider's buffer if any; if we have a local buffer we actually want to keep it around for possible reuse, just remember that it's empty. */
        st->bufferState = ouz_noBuffer;
    } else if (st->bufferState == ouz_writeBuffer) {
        /* Write-back */
        output(st, st->bufferStart, st->bufferLength, st->buffer, "flush");
        st->bufferState = ouz_noBuffer;
    }
    
    OBPOSTCONDITION(st->bufferState == ouz_noBuffer);
}

static uLong ouzRead(voidpf opaque, voidpf stream, void* buf, uLong size)
{
    struct ouzProviderBuffer *st = (struct ouzProviderBuffer *)stream;
    
    /* First, the common case */
    if (st->bufferState == ouz_readBuffer && st->bufferStart <= st->position && ( st->bufferLength + st->bufferStart ) >= ( st->position + size )) {
        memcpy(buf, st->buffer + (st->position - st->bufferStart), size);
        st->position += size;
        return size;
    }
    
    if (UNLK(st->hadError))
        return 0;
    if (UNLK(!st->canRead)) {
        st->hadError = YES;
        return 0;
    }
    
    /* Truncate reads at EOF */
    NSUInteger eof = st->cachedProviderLength;
    if (UNLK(st->position + size > eof)) {
        if (st->position >= eof)
            return 0;
        size = eof - st->position;
    }
    
    /* We couldn't satisfy the request from our buffer, so discard it */
    ouzDiscardBuffer(st);
    
    if (size < OUZ_UNBUFFER_THRESHOLD) {
        /* A small read: do some readahead */
        OBASSERT(st->releaseBuffer == NULL);  // Any provider buffer should have been discarded by ouzDiscardBuffer() already
        if (st->buffer == NULL) {
            st->buffer = malloc(OUZ_BUFFER_SIZE);
        }
        
        if (st->cachedProviderLength <= OUZ_BUFFER_SIZE) {
            st->bufferStart = 0;
            st->bufferLength = st->cachedProviderLength;
        } else if (st->cachedProviderLength - st->position <= OUZ_BUFFER_SIZE) {
            st->bufferStart = st->cachedProviderLength - OUZ_BUFFER_SIZE;
            st->bufferLength = OUZ_BUFFER_SIZE;
        } else {
            st->bufferStart = st->position;
            st->bufferLength = OUZ_BUFFER_SIZE;
        }
        
#ifdef DEBUG_BUFFERING
        printf("OBP fill %5" PRIuNS " at %5" PRIuNS "\n", st->bufferLength, st->bufferStart);
#endif
        [st->storage getBytes:st->buffer range:(NSRange){ .location = st->bufferStart, .length = st->bufferLength }];
        st->bufferState = ouz_readBuffer;
        memcpy(buf, st->buffer + (st->position - st->bufferStart), size);
    } else {
        /* Pass large reads through to the provider */
        
#ifdef DEBUG_BUFFERING
        printf("OBP read %5lu at %5" PRIuNS "\n", size, st->position);
#endif
        
        [(st->storage) getBytes:buf range:(NSRange){ .location = st->position, .length = size }];
    }
    
    st->position += size;
    return size;
}

static uLong ouzWrite(voidpf opaque, voidpf stream, const void *buf, uLong size)
{
    struct ouzProviderBuffer *st = (struct ouzProviderBuffer *)stream;
    
    NSUInteger start = st->position;
    NSUInteger end = start + size;
    uLong sizeRemaining;
    
    /* First, the common case--- a small write that we can just append to the buffered data */
    if (st->bufferState == ouz_writeBuffer && st->bufferStart + st->bufferLength == start) {
        /* Just append it to the write buffer */
        if(st->bufferLength + size < OUZ_BUFFER_SIZE) {
            st->bufferLength += size;
            memcpy(st->buffer + (start - st->bufferStart), buf, size);
            st->position = end;
            return size;
        } else {
            uLong amount = OUZ_BUFFER_SIZE - st->bufferLength;
            memcpy(st->buffer + (start - st->bufferStart), buf, amount);
            st->bufferLength = OUZ_BUFFER_SIZE; /* == st->bufferLength + amount */
            buf += amount;
            sizeRemaining = size - amount;
            start += amount;
            /* Fall through: flush out our (now-complete) buffer, and continue with a buffer miss */
        }
    } else {
        sizeRemaining = size;
    }
    
    ouzDiscardBuffer(st);
    
    if (sizeRemaining < OUZ_UNBUFFER_THRESHOLD) {
        /* A small write: do some buffering */
        if (st->buffer == NULL) {
            OBASSERT(st->releaseBuffer == NULL);
            st->buffer = malloc(OUZ_BUFFER_SIZE);
        }
        memcpy(st->buffer, buf, sizeRemaining);
        st->bufferStart = start;
        st->bufferLength = sizeRemaining;
        st->bufferState = ouz_writeBuffer;
        
        OBINVARIANT(start + sizeRemaining == end);
        st->position = end;
        return size;
    } else {
        /* Otherwise, just pass the write through to our backing store */
        output(st, start, sizeRemaining, buf, "write");
        
        st->position = end;
        return size;
    }
}

static long ouzTellPosition(voidpf opaque, voidpf stream)
{
    struct ouzProviderBuffer *st = (struct ouzProviderBuffer *)stream;
    if (st->position > LONG_MAX) {
        return -1;
    } else {
        return (long)(st->position);
    }
}

static long ouzSeek(voidpf opaque, voidpf stream, uLong offset, int origin)
{
    struct ouzProviderBuffer *st = (struct ouzProviderBuffer *)stream;
    
    switch (origin) {
        case ZLIB_FILEFUNC_SEEK_SET:
            st->position = offset;
            break;
        case ZLIB_FILEFUNC_SEEK_CUR:
            st->position += offset;
            break;
        case ZLIB_FILEFUNC_SEEK_END:
        {
            /* This isn't very useful in general, since offset is an unsigned value (unlike lseek/fseek). Fortunately the unzip library never calls it with any offset other than 0. */
            st->position = st->cachedProviderLength + offset;
            break;
        }
    }
    
    return 0;  // Like fseek(), we just return 0 to indicate success or nonzero to indicate failure.
}

static int ouzClose(voidpf opaque, voidpf stream)
{
    struct ouzProviderBuffer *st = (struct ouzProviderBuffer *)stream;
    
    ouzDiscardBuffer(st);
    
    [st->storage release];
    st->storage = NULL;
    
    if (st->buffer)
        free(st->buffer);
    
    free(st);
    
    return 0;
}

static int ouzStatus(voidpf opaque, voidpf stream)
{
    struct ouzProviderBuffer *st = (struct ouzProviderBuffer *)stream;
    return ( st->hadError ? -1 : 0 );
}

const zlib_filefunc_def OUReadIOImpl =
{
    .zopen_file     = ouzDataOpenRead,
    .zclose_file    = ouzClose,
    
    .zread_file     = ouzRead,
    .zwrite_file    = NULL,
    
    .ztell_file     = ouzTellPosition,
    .zseek_file     = ouzSeek,
    .zerror_file    = ouzStatus,
    .opaque         = NULL
};

const zlib_filefunc_def OUWriteIOImpl =
{
    .zopen_file     = ouzDataOpenWrite,
    .zclose_file    = ouzClose,
    
    .zread_file     = ouzRead,
    .zwrite_file    = ouzWrite,
    
    .ztell_file     = ouzTellPosition,
    .zseek_file     = ouzSeek,
    .zerror_file    = ouzStatus,
    .opaque         = NULL
};


