// Copyright 1997-2010, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/CFData-OFFileIO.h>

#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>
#import <Foundation/NSData.h>

#include <stdlib.h>
#include <string.h>
#include <errno.h>

RCS_ID("$Id$")

/*" Creates a stdio FILE pointer for reading from the receiver via the funopen() BSD facility.  The receiver is automatically retained until the returned FILE is closed. "*/

// Same context used for read and write.
typedef struct _CFDataFileContext {
    CFDataRef data; // Mutable iff this file is opened for writing
    void *bytes; // Only writable if created via OFDataCreateReadWriteStandardIOFile.
    size_t length;
    size_t position;
} CFDataFileContext;

static int _CFData_readfn(void *_ctx, char *buf, int nbytes)
{
    //fprintf(stderr, " read(ctx:%p buf:%p nbytes:%d)\n", _ctx, buf, nbytes);
    CFDataFileContext *ctx = (CFDataFileContext *)_ctx;
    
    if (nbytes <= 0)
        return 0;
    
    size_t sizeToRead = MIN((size_t)nbytes, ctx->length - ctx->position);
    memcpy(buf, ctx->bytes + ctx->position, sizeToRead);
    ctx->position += sizeToRead;

    OBASSERT(sizeToRead <= INT_MAX); // since we did a MIN above with nbytes, which is an int and positive due to our check up top.
    return (int)sizeToRead;
}

static int _CFData_writefn(void *_ctx, const char *buf, int nbytes)
{
    //fprintf(stderr, "write(ctx:%p buf:%p nbytes:%d)\n", _ctx, buf, nbytes);
    CFDataFileContext *ctx = (CFDataFileContext *)_ctx;
    
    // Might be in the middle of a the file if a seek has been done so we can't just append naively!
    if (ctx->position + nbytes > ctx->length) {
        ctx->length = ctx->position + nbytes;
        CFDataSetLength((CFMutableDataRef)ctx->data, ctx->length);
        ctx->bytes = CFDataGetMutableBytePtr((CFMutableDataRef)ctx->data); // Might have moved after size change
    }
    
    memcpy(ctx->bytes + ctx->position, buf, nbytes);
    ctx->position += nbytes;
    return nbytes;
}

static fpos_t _CFData_seekfn(void *_ctx, off_t offset, int whence)
{
    //fprintf(stderr, " seek(ctx:%p off:%qd whence:%d)\n", _ctx, offset, whence);
    CFDataFileContext *ctx = (CFDataFileContext *)_ctx;
    
    off_t reference;
    if (whence == SEEK_SET)
        reference = 0;
    else if (whence == SEEK_CUR)
        reference = ctx->position;
    else if (whence == SEEK_END)
        reference = ctx->length;
    else
        return -1;
    
    if (reference + offset >= 0 && reference + offset <= (off_t)ctx->length) {
        // position is a size_t (i.e., memory/vm sized) while the reference and offset are off_t (file system positioned).
        // since we are refering to an CFData, this must be OK (and we checked 'reference + offset' vs. our length above).
        ctx->position = (size_t)(reference + offset);
        return ctx->position;
    }
    return -1;
}

static int _CFData_closefn(void *_ctx)
{
    //fprintf(stderr, "close(ctx:%p)\n", _ctx);
    CFDataFileContext *ctx = (CFDataFileContext *)_ctx;
    CFRelease(ctx->data);
    free(ctx);
    
    return 0;
}

FILE *OFDataCreateReadOnlyStandardIOFile(CFDataRef data, CFErrorRef *outError)
{
    CFDataFileContext *ctx = calloc(1, sizeof(CFDataFileContext));
    ctx->data = CFRetain(data);
    ctx->bytes = (void *)CFDataGetBytePtr(data);
    ctx->length = CFDataGetLength(data);
    //fprintf(stderr, "open read -> ctx:%p\n", ctx);
    
    FILE *f = funopen(ctx, _CFData_readfn, NULL/*writefn*/, _CFData_seekfn, _CFData_closefn);
    if (f == NULL) {
        if (outError)
            *outError = CFErrorCreate(kCFAllocatorDefault, kCFErrorDomainPOSIX, errno, NULL);
        CFRelease(data);
        free(ctx);
    }
    
    return f;
}

FILE *OFDataCreateReadWriteStandardIOFile(CFMutableDataRef data, CFErrorRef *outError)
{
    CFDataFileContext *ctx = calloc(1, sizeof(CFDataFileContext));
    ctx->data = CFRetain(data);
    ctx->bytes = CFDataGetMutableBytePtr(data);
    ctx->length = CFDataGetLength(data);
    //fprintf(stderr, "open write -> ctx:%p\n", ctx);
    
    FILE *f = funopen(ctx, _CFData_readfn, _CFData_writefn, _CFData_seekfn, _CFData_closefn);
    if (f == NULL) {
        if (outError)
            *outError = CFErrorCreate(kCFAllocatorDefault, kCFErrorDomainPOSIX, errno, NULL);
        CFRelease(data);
        free(ctx);
    }
    return f;
}

