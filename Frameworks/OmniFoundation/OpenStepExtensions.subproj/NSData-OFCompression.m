// Copyright 1998-2005,2007,2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFCompression.h>

#import <OmniFoundation/NSData-OFFileIO.h>
#import <OmniFoundation/NSException-OFExtensions.h>
#import <bzlib.h>
#import <zlib.h>

RCS_ID("$Id$")

@implementation NSData (OFCompression)

/*" Compression/decompression.
 We support both bz2 and gzip compression.  We default to using gzip; bz2 compresses better, but its worst-case performance is much, much worse (and we don't want to make users wait when saving).
 "*/

static inline BOOL _OFMightBeBzipCompressedData(const unsigned char *bytes, unsigned int length)
{
    return (length >= 2 && bytes[0] == 'B' && bytes[1] == 'Z');
}

static inline BOOL _OFMightBeGzipCompressedData(const unsigned char *bytes, unsigned int length)
{
    return (length >= 10 && bytes[0] == 0x1F && bytes[1] == 0x8B);
}

/*" Returns YES if the receiver looks like it might be compressed data that -decompressedData can handle.  Note that if this returns YES, it merely looks like the receiver is compressed, not that it is.  This is a simply intended to be a quick check to filter out obviously uncompressed data. "*/
- (BOOL)mightBeCompressed;
{
    const unsigned char *bytes = [self bytes];
    unsigned int length = [self length];
    return _OFMightBeGzipCompressedData(bytes, length) || _OFMightBeBzipCompressedData(bytes, length);
}

- (NSData *)compressedData;
{
    return [self compressedDataWithGzipHeader:YES compressionLevel:9];
}

- (NSData *)decompressedData;
{
    const unsigned char *initial;
    unsigned dataLength;
    
    initial = [self bytes];
    dataLength = [self length];
    if (_OFMightBeBzipCompressedData(initial, dataLength))
        return [self decompressedBzip2Data];
    
    if (_OFMightBeGzipCompressedData(initial, dataLength))
        return [self decompressedGzipData];
    
    [NSException raise:NSInvalidArgumentException reason:NSLocalizedStringFromTableInBundle(@"Unable to decompress data: unrecognized compression format", @"OmniFoundation", OMNI_BUNDLE, @"decompression exception format")];
    return nil; /* NOTREACHED */
}


/*" Compresses the receiver using the bz2 library algorithm and returns the compressed data.   The compressed data is a full bz2 file, not just a headerless compressed blob.  This is very useful if you are including this compressed data in a larger file wrapper and want users to be able to read it with standard tools. "*/
- (NSData *)compressedBzip2Data;
{
#if defined(MAC_OS_X_VERSION_10_4) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4
    NSMutableData *output = [NSMutableData data];
    FILE *dataFile = [output openReadWriteStandardIOFile];
    
    int err;
    BZFILE *bzFile = NULL;
    if (dataFile)
        bzFile = BZ2_bzWriteOpen(&err, dataFile,
                                 6,  // blockSize100k from 1-9, 9 best compression, slowest speed
                                 0,  // verbosity
                                 0); // workFactor, 0-250, 0==default of 30
    if (!bzFile) {
        fclose(dataFile);
        [NSException raise:NSInvalidArgumentException reason:NSLocalizedStringFromTableInBundle(@"Unable to initialize compression", @"OmniFoundation", OMNI_BUNDLE, @"compression exception format")];
    }
    
    // BZ2_bzWrite fails with BZ_PARAM_ERROR when passed length==0; allow compressing empty data by just not doing a write.
    unsigned int length = [self length];
    if (length) {
        BZ2_bzWrite(&err, bzFile, (void  *)[self bytes], [self length]);
        if (err != BZ_OK) {
            // Create exception before closing file since we read from the file
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to compress data (bzip2 rc:%d '%s')", @"OmniFoundation", OMNI_BUNDLE, @"compression exception format"), err, BZ2_bzerror(bzFile, &err)];
            NSException *exc = [NSException exceptionWithName:NSInvalidArgumentException reason:reason userInfo:nil];
            fclose(dataFile);
            BZ2_bzWriteClose(&err, bzFile, 0, NULL, NULL);
            [exc raise];
        }
    }
    
    BZ2_bzWriteClose(&err, bzFile, 0, NULL, NULL);
    if (err != BZ_OK) {
        fclose(dataFile);
        [NSException raise:NSInvalidArgumentException reason:NSLocalizedStringFromTableInBundle(@"Unable to finish compressing data", @"OmniFoundation", OMNI_BUNDLE, @"compression exception format")];
    }
    
    fclose(dataFile);
    return output;
#else
    return [self filterDataThroughCommandAtPath:@"/usr/bin/bzip2" withArguments:[NSArray arrayWithObjects:@"--compress", nil]];
#endif
}

/*" Decompresses the receiver using the bz2 library algorithm and returns the decompressed data.   The receiver must represent a full bz2 file, not just a headerless compressed blob.  This is very useful if you are including this compressed data in a larger file wrapper and want users to be able to read it with standard tools.  Throws an exception if the receiver does not contain valid compressed data. "*/
- (NSData *)decompressedBzip2Data;
{
#if defined(MAC_OS_X_VERSION_10_4) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4
    FILE *dataFile = [self openReadOnlyStandardIOFile];
    
    int err;
    BZFILE *bzFile = NULL;
    if (dataFile)
        bzFile = BZ2_bzReadOpen(&err, dataFile,
                                [self length] < 4*1024,  // small; set to 1 for things that are 'small' to use less memory
                                0,  // verbosity
                                NULL, 0); // unused
    if (!bzFile) {
        fclose(dataFile);
        [NSException raise:NSInvalidArgumentException reason:NSLocalizedStringFromTableInBundle(@"Unable to initialize decompression", @"OmniFoundation", OMNI_BUNDLE, @"decompression exception format")];
    }
    
    size_t pageSize  = NSPageSize();
    unsigned int totalBytesRead = 0;
    NSMutableData *output = [NSMutableData dataWithLength:4*pageSize];
    do {
        unsigned int avail = [output length] - totalBytesRead;
        if (avail < pageSize) {
            [output setLength:[output length] + 4*pageSize];
            avail = [output length] - totalBytesRead;
        }
        void *ptr = [output mutableBytes] + totalBytesRead;
        
        
        int bytesRead = BZ2_bzRead(&err, bzFile, ptr, avail);
        if (err != BZ_OK && err != BZ_STREAM_END) {
            // Create exception before closing file since we read from the file
            NSString *reason = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Unable to decompress data (bzip2 rc:%d '%s')", @"OmniFoundation", OMNI_BUNDLE, @"decompression exception format"), err, BZ2_bzerror(bzFile, &err)];
            NSException *exc = [NSException exceptionWithName:NSInvalidArgumentException reason:reason userInfo:nil];
            fclose(dataFile);
            BZ2_bzReadClose(&err, bzFile);
            [exc raise];
        }
        
        totalBytesRead += bytesRead;
    } while (err != BZ_STREAM_END);
    
    [output setLength:totalBytesRead];
    
    BZ2_bzReadClose(&err, bzFile);
    fclose(dataFile);
    
    return output;
#else
    return [self filterDataThroughCommandAtPath:@"/usr/bin/bzip2" withArguments:[NSArray arrayWithObjects:@"--decompress", nil]];
#endif
}

/* Support for RFC 1952 gzip formatting. This is a simple wrapper around the data produced by zlib. */

#define OF_ZLIB_BUFFER_SIZE (2 * 64 * 1024)
#define OFZlibExceptionName (@"OFZlibException")

static NSMutableData *makeRFC1952MemberHeader(time_t modtime,
                                              NSString *orig_filename,
                                              NSString *file_comment,
                                              BOOL withCRC16,
                                              BOOL isText,
                                              u_int8_t xfl)
{
    u_int8_t *header;
    uLong headerCRC;
    NSData *filename_bytes, *comment_bytes;
    NSMutableData *result;
    
    if (orig_filename)
        filename_bytes = [orig_filename dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES];
    else
        filename_bytes = nil;
    if (file_comment)
        comment_bytes = [file_comment dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES];
    else
        comment_bytes = nil;
    
    /* Allocate the result buffer */
    result = [NSMutableData dataWithLength: 10 +
              (filename_bytes? [filename_bytes length] + 1 : 0) +
              (comment_bytes? [comment_bytes length] + 1 : 0) +
              (withCRC16 ? 2 : 0)];
    
    header = [result mutableBytes];
    
    /* GZIP file magic */
    header[0] = 0x1F;
    header[1] = 0x8B;
    
    /* Indicates use of the GZIP compression method */
    header[2] = Z_DEFLATED;
    
    /* Flag field #1 */
    header[3] = (isText? 1 : 0) | (withCRC16? 2 : 0) | (filename_bytes? 8 : 0) | (comment_bytes? 16 : 0);
    
    /* Modification time stamp */
    header[4] = ( modtime & 0x000000FF );
    header[5] = ( modtime & 0x0000FF00 ) >> 8;
    header[6] = ( modtime & 0x00FF0000 ) >> 16;
    header[7] = ( modtime & 0xFF000000 ) >> 24;
    
    /* Indicates file was written on a Unixlike system; we're being more Unixy than traditional-Mac-like */
    header[8] = 3;
    
    /* Flag field #2 */
    /* The XFLAG field is documented to have some bits set according to the compression level used by the compressor, but nobody actually reads it; it's not necessary to decompress the data, and RFC1952 doesn't really specify when each bit should be set anyway. So we don't worry about it overmuch. */    
    header[9] = xfl;
    
    /* Initialize the header CRC */
    headerCRC = crc32(0L, Z_NULL, 0);
    
    /* Update the CRC as we go */
    headerCRC = crc32(headerCRC, header, 10);
    header += 10;
    
    /* Filename, if we have one, with terminating NUL */
    if (filename_bytes) {
        int length = [filename_bytes length];
        [filename_bytes getBytes:header];
        header[length] = (char)0;
        headerCRC = crc32(headerCRC, header, length+1);
        header += length+1;
    }
    
    /* File comment, if we have one, with terminating NUL */
    if (comment_bytes) {
        int length = [comment_bytes length];
        [comment_bytes getBytes:header];
        header[length] = (char)0;
        headerCRC = crc32(headerCRC, header, length+1);
        header += length+1;
    }
    
    /* Header CRC */
    if (withCRC16) {
        header[0] = ( headerCRC & 0x00FF );
        header[1] = ( headerCRC & 0xFF00 ) >> 8;
        //header += 2; clang hates the dead increment.
    }
    
    OBPOSTCONDITION( (unsigned)((char *)header - (char *)[result bytes]) == [result length] );
    
    return result;
}

static BOOL readNullTerminatedString(FILE *fp,
                                     NSStringEncoding encoding,
                                     NSString **into,
                                     uLong *runningCRC)
{
    CFMutableDataRef buffer;
    int ch;
    
    buffer = CFDataCreateMutable(kCFAllocatorDefault, 0);
    
    do {
        UInt8 chBuf[1];
        
        ch = getc(fp);
        if (ch == EOF) {
            CFRelease(buffer);
            return NO;
        }
        
        chBuf[0] = ch;
        CFDataAppendBytes(buffer, chBuf, 1);
    } while (ch != 0);
    
    *runningCRC = crc32(*runningCRC, CFDataGetBytePtr(buffer), CFDataGetLength(buffer));
    
    if (into) {
        *into = [[[NSString alloc] initWithData:(NSData *)buffer encoding:encoding] autorelease];
    }
    
    CFRelease(buffer);
    return YES;
}


static BOOL checkRFC1952MemberHeader(FILE *fp,
                                     NSString **orig_filename,
                                     NSString **file_comment,
                                     BOOL *isText)
{
    u_int8_t header[10];
    size_t count;
    uLong runningCRC;
    
    count = fread(header, 1, 10, fp);
    if (count != 10)
        return NO;
    
    /* File magic */
    if (header[0] != 0x1F || header[1] != 0x8B)
        return NO;
    
    /* Compression algorithm: only Z_DEFLATED is valid */
    if (header[2] != Z_DEFLATED)
        return NO;
    
    /* Flags field */
    if (isText)
        *isText = ( header[3] & 1 ) ? YES : NO;
    
    /* Ignore modification time, XFL, and OS fields for now */
    
    runningCRC = crc32( crc32(0L, NULL, 0), header, 10 );
    
    /* We don't handle the FEXTRA field, which means we're not actually RFC1952-conformant. It's pretty rare, but we really should at least skip it. TODO. */
    if (header[3] & 0x04)
        return NO;
    
    /* Skip/read the filename. */
    if (header[3] & 0x08) {
        if (!readNullTerminatedString(fp, NSISOLatin1StringEncoding, orig_filename, &runningCRC))
            return NO;
    }
    
    /* Skip/read the file comment. */
    if (header[3] & 0x10) {
        if (!readNullTerminatedString(fp, NSISOLatin1StringEncoding, file_comment, &runningCRC))
            return NO;
    }
    
    /* Verify the CRC, if present. */
    if (header[3] & 0x02) {
        u_int8_t crc_buffer[2];
        unsigned storedCRC;
        
        if (fread(crc_buffer, 1, 2, fp) != 2)
            return NO;
        storedCRC = ( (unsigned)crc_buffer[0] ) | ( 256 * (unsigned)crc_buffer[1] );
        if (storedCRC != ( runningCRC & 0xFFFF ))
            return NO;
    }
    
    /* We've successfuly run the gauntlet. */
    return YES;
}


static NSException *OFZlibException(int errorCode, z_stream *state)
{
    if (state && state->msg) {
        return [NSException exceptionWithName:OFZlibExceptionName reason:[NSString stringWithCString:state->msg encoding:NSASCIIStringEncoding] userInfo:nil];
    } else {
        return [NSException exceptionWithName:OFZlibExceptionName reason:[NSString stringWithFormat:@"zlib: error code %d", errorCode] userInfo:nil];
    }
}

static void writeLE32(u_int32_t le32, FILE *fp)
{
    putc( (le32 & 0x000000FF)      , fp );
    putc( (le32 & 0x0000FF00) >>  8, fp );
    putc( (le32 & 0x00FF0000) >> 16, fp );
    putc( (le32 & 0xFF000000) >> 24, fp );
}

static u_int32_t unpackLE32(const u_int8_t *from)
{
    return ( (u_int32_t)from[0] ) |
    ( (u_int32_t)from[1] << 8 ) |
    ( (u_int32_t)from[2] << 16 ) |
    ( (u_int32_t)from[3] << 24 );
}

static NSException *handleRFC1952MemberBody(FILE *fp,
                                            NSData *data,
                                            NSRange sourceRange,
                                            int compressionLevel,
                                            BOOL withTrailer,
                                            BOOL compressing)
{
    uLong dataCRC;
    z_stream compressionState;
    Bytef *outputBuffer;
    unsigned outputBufferSize;
    int ok;
    
    dataCRC = crc32(0L, Z_NULL, 0);
    
    if (compressionLevel < 0)
        compressionLevel = Z_DEFAULT_COMPRESSION;
    bzero(&compressionState, sizeof(compressionState));
    if (compressing) {
        /* Annoyingly underdocumented parameter: must pass windowBits = -MAX_WBITS to suppress the zlib header. */
        ok = deflateInit2(&compressionState, compressionLevel,
                          Z_DEFLATED, -MAX_WBITS, 9, Z_DEFAULT_STRATEGY);
        /* compressionState.data_type = dataType; */
    } else {
        ok = inflateInit2(&compressionState, -MAX_WBITS);
    }
    if (ok != Z_OK)
        return OFZlibException(ok, &compressionState);
    
    outputBuffer = malloc(outputBufferSize = OF_ZLIB_BUFFER_SIZE);
    
    compressionState.next_in = (Bytef *)[data bytes] + sourceRange.location;
    compressionState.avail_in = sourceRange.length;
    if (withTrailer && !compressing) {
        /* Subtract 8 bytes for the CRC and length which are stored after the compressed data. */
        if (sourceRange.length < 8) {
            return [NSException exceptionWithName:OFZlibExceptionName reason:@"zlib stream is too short" userInfo:nil];
        }
    }
    
    for(;;) {
        compressionState.next_out = outputBuffer;
        compressionState.avail_out = outputBufferSize;
        // printf("before: in = %u @ %p, out = %u @ %p\n", compressionState.avail_in, compressionState.next_in, compressionState.avail_out, compressionState.next_out);
        if (compressing) {
            const Bytef *last_in = compressionState.next_in;
            ok = deflate(&compressionState, Z_FINISH);
            if (compressionState.next_in > last_in)
                dataCRC = crc32(dataCRC, last_in, compressionState.next_in - last_in);
        } else {
            ok = inflate(&compressionState, Z_SYNC_FLUSH);
            if (compressionState.next_out > outputBuffer)
                dataCRC = crc32(dataCRC, outputBuffer, compressionState.next_out - outputBuffer);
        }
        // printf("after : in = %u @ %p, out = %u @ %p, ok = %d\n", compressionState.avail_in, compressionState.next_in, compressionState.avail_out, compressionState.next_out, ok);
        if (compressionState.next_out > outputBuffer)
            fwrite(outputBuffer, compressionState.next_out - outputBuffer, 1, fp);
        if (ok == Z_STREAM_END)
            break;
        else if (ok != Z_OK) {
            NSException *error = OFZlibException(ok, &compressionState);
            deflateEnd(&compressionState);
            free(outputBuffer);
            return error;
        }
    }

    if (compressing) {
#ifdef OMNI_ASSERTIONS_ON
        ok = 
#endif
        deflateEnd(&compressionState);
    } else {
#ifdef OMNI_ASSERTIONS_ON
        ok = 
#endif
        inflateEnd(&compressionState);
    }
    OBASSERT(ok == Z_OK);
    if (compressing || !withTrailer) {
        OBASSERT(compressionState.avail_in == 0);
    } else {
        /* Assert that there's space for the CRC and length at the end of the buffer */
        OBASSERT(compressionState.avail_in == 8);
    }
    
    free(outputBuffer);
    
    if (withTrailer && compressing) {
        writeLE32(dataCRC, fp);
        writeLE32((0xFFFFFFFFUL & sourceRange.length), fp);
    }
    if (withTrailer && !compressing) {
        u_int32_t storedCRC, storedLength;
        const u_int8_t *trailerStart;
        
        trailerStart = [data bytes] + sourceRange.location + sourceRange.length - 8;
        storedCRC = unpackLE32(trailerStart);
        storedLength = unpackLE32(trailerStart + 4);
        
        if (dataCRC != storedCRC)
            return [NSException exceptionWithName:OFZlibExceptionName reason:[NSString stringWithFormat:@"CRC error: stored CRC (%08X) does not match computed CRC (%08X)", storedCRC, dataCRC] userInfo:nil];
        if (storedLength != (0xFFFFFFFFUL & compressionState.total_out))
            return [NSException exceptionWithName:OFZlibExceptionName reason:[NSString stringWithFormat:@"Gzip error: stored length (%lu) does not match decompressed length (%lu)", (unsigned long)storedLength, (unsigned long)(0xFFFFFFFFUL & compressionState.total_out)] userInfo:nil];
    }
    
    
    return nil;
}

- (NSData *)compressedDataWithGzipHeader:(BOOL)includeHeader compressionLevel:(int)level
{
    NSException *error;
    NSMutableData *result;
    FILE *writeStream;
    
    if (includeHeader)
        result = makeRFC1952MemberHeader((time_t)0, nil, nil, NO, NO, 0);
    else
        result = [NSMutableData data];
    
    writeStream = [result openReadWriteStandardIOFile];
    fseek(writeStream, 0, SEEK_END);
    error = handleRFC1952MemberBody(writeStream, self, (NSRange){0, [self length]}, level, includeHeader, YES);
    fclose(writeStream);
    
    if (error)
        [error raise];
    
    return result;
}

- (NSData *)decompressedGzipData;
{
    FILE *readMe, *writeMe;
    BOOL ok;
    long headerLength;
    NSException *error;
    NSMutableData *result;
    
    readMe = [self openReadOnlyStandardIOFile];
    ok = checkRFC1952MemberHeader(readMe, NULL, NULL, NULL);
    headerLength = ftell(readMe);
    fclose(readMe);
    if (!ok) {
        [[NSException exceptionWithName:OFZlibExceptionName reason:NSLocalizedStringFromTableInBundle(@"Unable to decompress gzip data: invalid header", @"OmniFoundation", OMNI_BUNDLE, @"decompression exception format") userInfo:nil] raise];
    }
    
    result = [NSMutableData data];
    writeMe = [result openReadWriteStandardIOFile];
    error = handleRFC1952MemberBody(writeMe, self,
                                    (NSRange){ headerLength, [self length] - headerLength },
                                    Z_DEFAULT_COMPRESSION, YES, NO);
    fclose(writeMe);
    
    if (error)
        [error raise];
    
    return result;
}

@end
