// Copyright 1997-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFReadWriteFileBuffer.h>

#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>
#import <objc/objc.h>
#import <Foundation/NSObjCRuntime.h>

RCS_ID("$Id$")


struct _OFReadWriteFileBuffer {
    FILE *file;
    BOOL closed;
    
    void *bytes;
    size_t length; // The current end-of-file location
    size_t capacity; // The size of the available bytes buffer
    size_t position; // The seek position
};

static int _OFReadWriteFileBuffer_readfn(void *_ctx, char *ptr, int nbytes)
{
    //fprintf(stderr, " read(buffer:%p ptr:%p nbytes:%d)\n", _ctx, ptr, nbytes);
    OFReadWriteFileBuffer *buffer = (OFReadWriteFileBuffer *)_ctx;
    
    if (nbytes <= 0)
        return 0;
    
    size_t sizeToRead = MIN((size_t)nbytes, buffer->length - buffer->position);
    memcpy(ptr, buffer->bytes + buffer->position, sizeToRead);
    buffer->position += sizeToRead;
    
    OBASSERT(sizeToRead <= INT_MAX); // since we did a MIN above with nbytes, which is an int and positive due to our check up top.
    return (int)sizeToRead;
}

static int _OFReadWriteFileBuffer_writefn(void *_ctx, const char *ptr, int nbytes)
{
    //fprintf(stderr, "write(buffer:%p ptr:%p nbytes:%d)\n", _ctx, ptr, nbytes);
    OFReadWriteFileBuffer *buffer = (OFReadWriteFileBuffer *)_ctx;
    
    // Might be in the middle of a the file if a seek has been done so we can't just append naively!
    if (buffer->position + nbytes > buffer->capacity) {
        buffer->capacity = MAX(2*buffer->capacity, buffer->position + nbytes);
        buffer->bytes = realloc(buffer->bytes, buffer->capacity);
    }
    
    memcpy(buffer->bytes + buffer->position, ptr, nbytes);
    buffer->position += nbytes;
    
    // The write might extend the file
    buffer->length = MAX(buffer->length, buffer->position);
    OBASSERT(buffer->length <= buffer->capacity);
    
    return nbytes;
}

static fpos_t _OFReadWriteFileBuffer_seekfn(void *_ctx, off_t offset, int whence)
{
    //fprintf(stderr, " seek(buffer:%p off:%qd whence:%d)\n", _ctx, offset, whence);
    OFReadWriteFileBuffer *buffer = (OFReadWriteFileBuffer *)_ctx;
    
    off_t reference;
    if (whence == SEEK_SET)
        reference = 0;
    else if (whence == SEEK_CUR)
        reference = buffer->position;
    else if (whence == SEEK_END)
        reference = buffer->length;
    else
        return -1;
    
    if (reference + offset >= 0 && reference + offset <= (off_t)buffer->length) {
        // position is a size_t (i.e., memory/vm sized) while the reference and offset are off_t (file system positioned).
        // since we are refering to an CFData, this must be OK (and we checked 'reference + offset' vs. our length above).
        buffer->position = (size_t)(reference + offset);
        return buffer->position;
    }
    return -1;
}

static int _OFReadWriteFileBuffer_closefn(void *_ctx)
{
    //fprintf(stderr, "close(buffer:%p)\n", _ctx);
    
    // We don't actually free anything here, but just mark the buffer as closed.
    OFReadWriteFileBuffer *buffer = (OFReadWriteFileBuffer *)_ctx;
    OBASSERT(!buffer->closed);
    buffer->closed = YES;
    
    return 0;
}

OFReadWriteFileBuffer *OFCreateReadWriteFileBuffer(FILE **outFile, CFErrorRef *outError)
{
    OBPRECONDITION(outFile);
    
    OFReadWriteFileBuffer *buffer = calloc(1, sizeof(*buffer));
    //fprintf(stderr, "buffer create -> %p\n", buffer);
    
    buffer->file = funopen(buffer, _OFReadWriteFileBuffer_readfn, _OFReadWriteFileBuffer_writefn, _OFReadWriteFileBuffer_seekfn, _OFReadWriteFileBuffer_closefn);
    if (buffer->file == NULL) {
        if (outError)
            *outError = CFErrorCreate(kCFAllocatorDefault, kCFErrorDomainPOSIX, errno, NULL);
        free(buffer);
        return NULL;
    }
    *outFile = buffer->file;
    return buffer;
}

void OFDestroyReadWriteFileBuffer(OFReadWriteFileBuffer *buffer, CFAllocatorRef dataAllocator, CFDataRef *outData)
{
    //fprintf(stderr, "buffer destroy %p, outData %p\n", buffer, outData);

    // Close it if the caller didn't already
    if (!buffer->closed) {
        fclose(buffer->file);
    }
    
    if (outData) {
        // The caller would like the data.  Give them ownership of the bytes buffer, returning an immutable data that uses the malloc deallocator for the bytes.  This preserves the non-scanned behavior, which can be important for performance, as well as avoiding copying the buffer, which is also important.  Using an NSMutableData internally would avoid the copy, but would result in scanned memory.
        if (buffer->length > 0)
            *outData = CFDataCreateWithBytesNoCopy(dataAllocator, buffer->bytes, buffer->length, kCFAllocatorMalloc);
        else
            *outData = CFDataCreate(dataAllocator, NULL, 0);
    } else {
        if (buffer->bytes)
            free(buffer->bytes);
    }
    free(buffer);
}



