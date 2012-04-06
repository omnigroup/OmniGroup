// Copyright 2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXZUtilities.h"
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniBase/rcsid.h>
#include "xz.h"

RCS_ID("$Id$")

static dispatch_once_t xz_crc_once;

static void setErrorInfoFromXZRet(NSMutableDictionary *info, enum xz_ret ret)
{
    NSString *shortname;
    NSString *description;
    switch (ret) {
        case XZ_UNSUPPORTED_CHECK:
            shortname = @"XZ_UNSUPPORTED_CHECK";
            description = NSLocalizedStringWithDefaultValue(@"XZ_UNSUPPORTED_CHECK", @"OmniFoundation", OMNI_BUNDLE, @"Integrity check type is not supported.", nil);
            break;
        
        case XZ_MEMLIMIT_ERROR:
        case XZ_OPTIONS_ERROR:
            description = NSLocalizedStringWithDefaultValue(@"XZ_OPTIONS_ERROR", @"OmniFoundation", OMNI_BUNDLE, @"This LZMA2 implementation doesn't support the neccessary compression options.", nil);
            if (ret == XZ_MEMLIMIT_ERROR) {
                shortname = @"XZ_MEMLIMIT_ERROR";
                description = [NSString stringWithStrings:description, @" [", shortname, @"]", nil];
            } else {
                shortname = @"XZ_OPTIONS_ERROR";
            }
            break;
        
        case XZ_FORMAT_ERROR:
            shortname = @"XZ_FORMAT_ERROR";
            description = NSLocalizedStringWithDefaultValue(@"XZ_FORMAT_ERROR", @"OmniFoundation", OMNI_BUNDLE, @"File format was not recognized (wrong header).", nil);
            break;
        
        case XZ_MEM_ERROR:
            shortname = @"XZ_MEM_ERROR";
            description = NSLocalizedStringWithDefaultValue(@"XZ_MEM_ERROR", @"OmniFoundation", OMNI_BUNDLE, @"Out of memory.", nil);
            break;
            
        default:
            OBASSERT_NOT_REACHED("Unknown enum xz_ret");
            shortname = @"XZ_???";
            goto corrupt;
        case XZ_BUF_ERROR:
            shortname = @"XZ_BUF_ERROR";
            goto corrupt;
        case XZ_DATA_ERROR:
            shortname = @"XZ_DATA_ERROR";
        corrupt:
            description = NSLocalizedStringWithDefaultValue(@"XZ_DATA_ERROR", @"OmniFoundation", OMNI_BUNDLE, @"Compressed data is corrupt.", nil);
            description = [NSString stringWithStrings:description, @" [", shortname, @"]", nil];
            break;
        
        /* The following are not error codes that should be presented to the user, but... */
        case XZ_STREAM_END:
            shortname = @"XZ_STREAM_END";
            description = nil;
            break;
        case XZ_OK:
            shortname = @"XZ_OK";
            description = nil;
    }
    
    [info setObject:shortname forKey:@"xz_ret"];
    if (description)
        [info setObject:description forKey:NSLocalizedFailureReasonErrorKey];
}

void OFXZDecompressToFdAsync(NSData *compressed, int fd, dispatch_queue_t queue, void(^completion_handler)(NSError *))
{
    dispatch_source_t dispatcher = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, fd, 0, queue);
    if (!dispatcher) {
        (completion_handler)([NSError errorWithDomain:OFErrorDomain code:OFUnableToDecompressData userInfo:nil]);
        return;
    }
    
    /* These variables are used for communication between successive invocations of the handler block, and also with the cleanup/cancel block */
    NSData *dataToDecompress = [compressed retain];
    struct xz_dec *decompressor = xz_dec_init(XZ_DYNALLOC, UINT32_MAX);
#define OUT_BUF_SIZE 8u*1024u*1024u
    uint8_t *out_buf = malloc(OUT_BUF_SIZE);       /* Buffer into which we decompress the data */
    size_t __block out_buf_used = 0;               /* How much of out_buf has data in it */
    size_t __block out_buf_written = 0;            /* How much of out_buf has been written to fd */
    size_t __block bytesDecompressed = 0;          /* How much of dataToDecompress has the decompressor consumed */
    BOOL   __block draining = NO;                  /* have we decompressed all the data into out_buf? */
    
    dispatch_source_set_event_handler(dispatcher, ^{
        // NSLog(@"Event handler called: dec=%p buf used=%lu written=%lu decmpr=%lu draining=%d", decompressor, (unsigned long)out_buf_used, (unsigned long)out_buf_written, (unsigned long)bytesDecompressed, (int)draining);
        
        dispatch_once_f(&xz_crc_once, NULL, ( void (*)(void *) )xz_crc32_init);
        
        assert(out_buf_used >= out_buf_written);
        if (out_buf_written == out_buf_used && !draining) {
            out_buf_written = 0;
            out_buf_used = 0;
            
            struct xz_buf xzbuf = {
                .in = [dataToDecompress bytes],
                .in_pos = bytesDecompressed,
                .in_size = [dataToDecompress length],
                
                .out = out_buf,
                .out_pos = 0,
                .out_size = OUT_BUF_SIZE
            };
            
            enum xz_ret xzr = xz_dec_run(decompressor, &xzbuf);
            
            bytesDecompressed = xzbuf.in_pos;
            out_buf_used = xzbuf.out_pos;
            
            if (xzr == XZ_STREAM_END) {
                /* Operation finished successfully */
                draining = YES;
            } else if (xzr == XZ_OK) {
                /* Normal intermediate status */
            } else {
                /* Decompression failure; report the error and quit */
                NSMutableDictionary *errInfo = [NSMutableDictionary dictionary];
                setErrorInfoFromXZRet(errInfo, xzr);
                [errInfo setUnsignedIntegerValue:bytesDecompressed forKey:@"bytesDecompressed"];
                completion_handler([NSError errorWithDomain:OFErrorDomain code:OFUnableToDecompressData userInfo:errInfo]);
                dispatch_source_cancel(dispatcher);
                return;
            }
        }

        /* If we have decompressed data in the buffer, try to write it */
        if (out_buf_used > out_buf_written) {
            size_t amount = ( out_buf_used - out_buf_written );
            ssize_t wrote = write(fd, out_buf + out_buf_written, amount);
            if (wrote < 0) {
                if (errno == EINTR || errno == EWOULDBLOCK || errno == EAGAIN) {
                    /* No biggie */
                    return;
                } else {
                    /* Fail! */
                    completion_handler(_OBErrorWithErrnoObjectsAndKeys(errno, "write", nil, nil));
                    dispatch_source_cancel(dispatcher);
                    return;
                }
            }
            out_buf_written += wrote;
            if ((size_t)wrote < amount)
                return;
        }
        
        /* We only get here if out_buf_used == out_buf_written, that is, the output buffer is empty again */
        if (draining) {
            /* We've reached EOF */
            completion_handler(nil); /* Signal success */
            dispatch_source_cancel(dispatcher);
        }
        
    });
    dispatch_source_set_cancel_handler(dispatcher, ^{
        free(out_buf);
        [dataToDecompress release];
        xz_dec_end(decompressor);
        close(fd);
        dispatch_release((dispatch_object_t)dispatcher);
    });
    
    /* Dispatch sources are created suspended; now that we've set it up, allow it to run */
    dispatch_resume((dispatch_object_t)dispatcher);
}

