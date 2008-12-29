// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFFileIO.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@implementation NSData (OFFileIO)

/*" Creates a stdio FILE pointer for reading from the receiver via the funopen() BSD facility.  The receiver is automatically retained until the returned FILE is closed. "*/

// Same context used for read and write.
typedef struct _NSDataFileContext {
    NSData *data;
    void   *bytes;
    size_t  length;
    size_t  position;
} NSDataFileContext;

static int _NSData_readfn(void *_ctx, char *buf, int nbytes)
{
    //fprintf(stderr, " read(ctx:%p buf:%p nbytes:%d)\n", _ctx, buf, nbytes);
    NSDataFileContext *ctx = (NSDataFileContext *)_ctx;
    
    nbytes = MIN((unsigned)nbytes, ctx->length - ctx->position);
    memcpy(buf, ctx->bytes + ctx->position, nbytes);
    ctx->position += nbytes;
    return nbytes;
}

static int _NSData_writefn(void *_ctx, const char *buf, int nbytes)
{
    //fprintf(stderr, "write(ctx:%p buf:%p nbytes:%d)\n", _ctx, buf, nbytes);
    NSDataFileContext *ctx = (NSDataFileContext *)_ctx;
    
    // Might be in the middle of a the file if a seek has been done so we can't just append naively!
    if (ctx->position + nbytes > ctx->length) {
        ctx->length = ctx->position + nbytes;
        [(NSMutableData *)ctx->data setLength:ctx->length];
        ctx->bytes = [(NSMutableData *)ctx->data mutableBytes]; // Might have moved after size change
    }
    
    memcpy(ctx->bytes + ctx->position, buf, nbytes);
    ctx->position += nbytes;
    return nbytes;
}

static fpos_t _NSData_seekfn(void *_ctx, off_t offset, int whence)
{
    //fprintf(stderr, " seek(ctx:%p off:%qd whence:%d)\n", _ctx, offset, whence);
    NSDataFileContext *ctx = (NSDataFileContext *)_ctx;
    
    size_t reference;
    if (whence == SEEK_SET)
        reference = 0;
    else if (whence == SEEK_CUR)
        reference = ctx->position;
    else if (whence == SEEK_END)
        reference = ctx->length;
    else
        return -1;
    
    if (reference + offset >= 0 && reference + offset <= ctx->length) {
        // position is a size_t (i.e., memory/vm sized) while the reference and offset are off_t (file system positioned).
        // since we are refering to an NSData, this must be OK (and we checked 'reference + offset' vs. our length above).
        ctx->position = (size_t)(reference + offset);
        return ctx->position;
    }
    return -1;
}

static int _NSData_closefn(void *_ctx)
{
    //fprintf(stderr, "close(ctx:%p)\n", _ctx);
    NSDataFileContext *ctx = (NSDataFileContext *)_ctx;
    [ctx->data release];
    free(ctx);
    
    return 0;
}

- (FILE *)openReadOnlyStandardIOFile;
{
    NSDataFileContext *ctx = calloc(1, sizeof(NSDataFileContext));
    ctx->data = [self retain];
    ctx->bytes = (void *)[self bytes];
    ctx->length = [self length];
    //fprintf(stderr, "open read -> ctx:%p\n", ctx);
    
    FILE *f = funopen(ctx, _NSData_readfn, NULL/*writefn*/, _NSData_seekfn, _NSData_closefn);
    if (f == NULL)
        [self release]; // Don't leak ourselves if funopen fails
    return f;
}

@end

@implementation NSMutableData (OFFileIO)

- (FILE *)openReadWriteStandardIOFile;
{
    NSDataFileContext *ctx = calloc(1, sizeof(NSDataFileContext));
    ctx->data   = [self retain];
    ctx->bytes  = [self mutableBytes];
    ctx->length = [self length];
    //fprintf(stderr, "open write -> ctx:%p\n", ctx);
    
    FILE *f = funopen(ctx, _NSData_readfn, _NSData_writefn, _NSData_seekfn, _NSData_closefn);
    if (f == NULL)
        [self release]; // Don't leak ourselves if funopen fails
    return f;
}

@end
