// Copyright 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCompressionStream.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");

NSString * const OFStreamCompressionLevelKey = @"OFStream Conmpression Level";
NSString * const OFStreamBzipSmallSizeHintKey = @"OFStream bzip2 small size hint";


@implementation OFBzip2DecompressTransform

- (void)dealloc
{
    if (streamInit) {
        BZ2_bzDecompressEnd(&bz2);
        streamInit = NO;
    }
    [super dealloc];
}

- (NSArray *)allKeys
{
    return [NSArray arrayWithObjects:OFStreamBzipSmallSizeHintKey, nil];
}

- propertyForKey:(NSString *)aKey
{
    if ([aKey isEqualToString:NSStreamFileCurrentOffsetKey]) {
        unsigned long long offset = (((unsigned long long)(bz2.total_out_hi32)) << 32) | ((unsigned long long)(bz2.total_out_lo32));
        if (offset < INT_MAX) // Not UINT_MAX, because of RADAR #3513632
            return [NSNumber numberWithUnsignedInt:(unsigned int)offset];
        else
            return [NSNumber numberWithUnsignedLongLong:offset];
    } else if ([aKey isEqualToString:OFStreamBzipSmallSizeHintKey]) {
        return [NSNumber numberWithBool:bzSmallSizeHint];
    }
    
    return nil;
}

- (void)setProperty:prop forKey:(NSString *)aKey
{
    if (streamInit)
        OBRejectInvalidCall(self, _cmd, @"Stream is already open");
    
    if ([aKey isEqualToString:OFStreamBzipSmallSizeHintKey]) {
        bzSmallSizeHint = [prop boolValue];
        return;
    }
    
    OBRejectInvalidCall(self, _cmd, @"Unknown key %@", aKey);
}

- (struct OFTransformStreamBuffer *)inputBuffer;
{
    return &buf;
}

- (unsigned int)goodBufferSize;
{
    return 0;
}

- (void)open
{
    OBPRECONDITION(!streamInit);
    if (streamInit)
        return;
    
    int ok = BZ2_bzDecompressInit(&bz2, bzVerbosity, bzSmallSizeHint? 1 : 0);
    streamInit = YES;
}

- (void)noMoreInput
{
}

- (enum OFStreamTransformerResult)transform:(struct OFTransformStreamBuffer *)into error:(NSError **)errOut;
{
    int errcode;
    
    if (!streamInit) {
        errcode = BZ2_bzDecompressInit(&bz2, bzVerbosity, bzSmallSizeHint? 1 : 0);
        if (errcode != BZ_OK) {
       //     *errOut = [NSError errorWithDomain:... code:... userInfo:...];
            return OFStreamTransformerError;
        }
        streamInit = YES;
    }
    
    unsigned bufEnd = into->dataStart + into->dataLength;
    bz2.next_out = (void *)(into->buffer + bufEnd);
    bz2.avail_out = into->bufferSize - bufEnd;
    
    do {
        bz2.next_in = (void *)(buf.buffer + buf.dataStart);
        bz2.avail_in = buf.dataLength;
        errcode = BZ2_bzDecompress(&bz2);
        unsigned consumed = ((uint8_t *)bz2.next_in) - (buf.buffer + buf.dataStart);
        buf.dataLength -= consumed;
        buf.dataStart += consumed;
    } while (errcode == BZ_OK && bz2.avail_in > 0 && bz2.avail_out > 0);
    
    unsigned bytesProduced = ((uint8_t *)bz2.next_out) - (into->buffer + bufEnd);
    into->dataLength += bytesProduced;
    
    if (errcode == BZ_STREAM_END)
        return OFStreamTransformerFinished;
    else if (errcode == BZ_OK) {
        if (bz2.avail_in == 0)
            return OFStreamTransformerNeedInput;
        else
            return OFStreamTransformerNeedOutputSpace;
    } else {
   //     *errOut = [NSError errorWithDomain:... code:... userInfo:...];
        return OFStreamTransformerError;
    }
}

@end


@implementation OFBzip2CompressTransform

enum {
    bzcompress_Idle = 0,      // Have not initialized the compressor
    bzcompress_Running,       // Have initialized
    bzcompress_PreFinishing,  // No more data will be given to the compressor
    bzcompress_Finishing,
    bzcompress_Ended          // No more data will be extracted from the compressor
};

- init
{
    [super init];
    bzCompressionLevel = 9;
    bzVerbosity = 0;
    streamState = bzcompress_Idle;
    return self;
}

- (void)dealloc
{
    if (streamState != bzcompress_Idle) {
        BZ2_bzCompressEnd(&bz2);
        streamState = bzcompress_Idle;
    }
    [super dealloc];
}

- (NSArray *)allKeys
{
    return [NSArray arrayWithObjects:OFStreamCompressionLevelKey, nil];
}

- propertyForKey:(NSString *)aKey
{
    if ([aKey isEqualToString:NSStreamFileCurrentOffsetKey]) {
        unsigned long long offset = (((unsigned long long)(bz2.total_out_hi32)) << 32) | ((unsigned long long)(bz2.total_out_lo32));
        if (offset < INT_MAX) // Not UINT_MAX, because of RADAR #3513632
            return [NSNumber numberWithUnsignedInt:(unsigned int)offset];
        else
            return [NSNumber numberWithUnsignedLongLong:offset];
    } else if ([aKey isEqualToString:OFStreamCompressionLevelKey]) {
        return [NSNumber numberWithInt:bzCompressionLevel];
    }
    
    return nil;
}

- (void)setProperty:prop forKey:(NSString *)aKey
{
    if (streamState != bzcompress_Idle)
        OBRejectInvalidCall(self, _cmd, @"Stream is already open");
    
    if ([aKey isEqualToString:OFStreamCompressionLevelKey]) {
        int newLevel = [prop intValue];
        if (newLevel < 1 || newLevel > 9)
            OBRejectInvalidCall(self, _cmd, @"Bzip2 key \"%@\" must be in the range 1..9", OFStreamCompressionLevelKey);
        bzCompressionLevel = newLevel;
        return;
    }
    
    OBRejectInvalidCall(self, _cmd, @"Unknown key %@", aKey);
}

- (struct OFTransformStreamBuffer *)inputBuffer;
{
    return &buf;
}

- (unsigned int)goodBufferSize;
{
    return ( 1024 * 100 * bzCompressionLevel );
}

- (void)open
{
    OBPRECONDITION(streamState == bzcompress_Idle);
    if (streamState != bzcompress_Idle)
        return;
    
    int ok = BZ2_bzCompressInit(&bz2, bzCompressionLevel, bzVerbosity, 0);
    NSLog(@"BZ2_bzCompressInit -> %d", ok);
    // ...;
    streamState = bzcompress_Running;
}

- (void)noMoreInput
{
    short oldState = streamState;
    OBPRECONDITION(streamState != bzcompress_Idle);
    if (streamState == bzcompress_Running)
        streamState = bzcompress_PreFinishing;
    NSLog(@"%s: state %d -> %d", _cmd, oldState, streamState);
}

- (enum OFStreamTransformerResult)transform:(struct OFTransformStreamBuffer *)into error:(NSError **)errOut;
{
    int errcode;
    int op;
    
    NSLog(@"On entry: state=%d", streamState);
    
    switch(streamState) {
        case bzcompress_Idle:
            errcode = BZ2_bzCompressInit(&bz2, bzCompressionLevel, bzVerbosity, 0);
            NSLog(@"BZ2_bzCompressInit -> %d", errcode);
            if (errcode != BZ_OK) {
                //     *errOut = [NSError errorWithDomain:... code:... userInfo:...];
                return OFStreamTransformerError;
            }
            streamState = bzcompress_Running;
            /* FALL THROUGH */
        case bzcompress_Running:
            op = BZ_RUN;
            break;
        case bzcompress_PreFinishing:
        case bzcompress_Finishing:
            op = BZ_FINISH;
            break;
        default:
            OBASSERT_NOT_REACHED("OFBzip2CompressTransform in invalid state");
            //     *errOut = [NSError errorWithDomain:... code:... userInfo:...];
            return OFStreamTransformerError;
    }
    
    unsigned bufEnd = into->dataStart + into->dataLength;
    bz2.next_out = (void *)(into->buffer + bufEnd);
    bz2.avail_out = into->bufferSize - bufEnd;
    
    do {
        bz2.next_in = (void *)(buf.buffer + buf.dataStart);
        bz2.avail_in = buf.dataLength;
        errcode = BZ2_bzCompress(&bz2, op);
        NSLog(@"Invoked op=%d, got result=%d", op, errcode);
        unsigned consumed = ((uint8_t *)bz2.next_in) - (buf.buffer + buf.dataStart);
        buf.dataLength -= consumed;
        buf.dataStart += consumed;
        
        if (errcode == BZ_FINISH_OK)
            streamState = bzcompress_Finishing;
        else if (errcode == BZ_STREAM_END)
            break;
        else if (errcode != BZ_RUN_OK)
            break;
        
    } while ((bz2.avail_in > 0 || streamState == bzcompress_Finishing) && bz2.avail_out > 0);
    
    unsigned bytesProduced = ((uint8_t *)bz2.next_out) - (into->buffer + bufEnd);
    NSLog(@"Compressor produced %d bytes", bytesProduced);
    into->dataLength += bytesProduced;
    
    if (errcode == BZ_STREAM_END) {
        streamState = bzcompress_Ended;
        return OFStreamTransformerFinished;
    } else if (errcode == BZ_RUN_OK && bz2.avail_in == 0) {
        OBASSERT(streamState == bzcompress_Running);
        return OFStreamTransformerNeedInput;
    } else if (errcode == BZ_RUN_OK || errcode == BZ_FINISH_OK) {
        OBASSERT(bz2.avail_out == 0);
        return OFStreamTransformerNeedOutputSpace;
    } else {
        //     *errOut = [NSError errorWithDomain:... code:... userInfo:...];
        streamState = bzcompress_Ended;
        return OFStreamTransformerError;
    }
}


@end
