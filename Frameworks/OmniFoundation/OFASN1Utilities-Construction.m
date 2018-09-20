// Copyright 2014-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFASN1Utilities.h>
#import <OmniFoundation/OFASN1-Internal.h>
#import <OmniFoundation/OFSecurityUtilities.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import "GeneratedOIDs.h"
#import <OmniBase/rcsid.h>

#import <dispatch/dispatch.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC

static dispatch_data_t dispatch_of_NSData(NSData *buf);

/* Given a pointer to a DER tag, return the object's total length (including the tag). This should only be used for known-good objects, e.g., statically allocated OIDs. */
static size_t derObjectLength(const uint8_t *buf)
{
    uint8_t tag = buf[0] & 0x1F;
    if (tag == 0x1F) {
        // Punt: High tag number.
        [NSException raise:NSGenericException format:@"derObjectLength() called with bad input"];
    }
    
    if ((buf[1] & 0x80) == 0) {
        // Common case: short, definite-length object
        return (size_t)(buf[1]) + 2;
    } else {
        // Long or indefinite object
        unsigned lengthLength = buf[1] & 0x7F;
        
        if (lengthLength == 0) {
            // Indefinite length, invalid in DER.
            [NSException raise:NSGenericException format:@"derObjectLength() called with bad input"];
        }
        
        size_t extractedLength = 0;
        for (unsigned i = 0; i < lengthLength; i++) {
            extractedLength = ( extractedLength << 8 ) | ( buf[2 + i] );
        }
        
        return extractedLength + 2 + lengthLength;
    }
}

#pragma mark Construction helpers

void OFASN1AppendInteger(NSMutableData *buf, uint64_t i)
{
    unsigned char valueBuf[8];
    bzero(valueBuf, sizeof(valueBuf)); // Arguably shouldn't be needed; RADAR 27875387
    OSWriteBigInt64(valueBuf, 0, i);
    
    unsigned firstNonzero = 0;
    /* A special case in the DER encoding of integers is that the zero integer still contains one byte of zeroes (instead of being a zero-length integer). So the largest we want firstNonzero to be is 7. */
    while (firstNonzero < 7 && valueBuf[firstNonzero] == 0)
        firstNonzero ++;
    
    // ASN.1 integers are signed, so we may need to stuff an extra byte of 0s if the integer is an even number of bytes long.
    unsigned extra = ( (valueBuf[firstNonzero] & 0x80) == 0 )? 0 : 1;
    
    OFASN1AppendTagLength(buf, BER_TAG_INTEGER, (8 - firstNonzero) + extra);
    if (extra)
        [buf appendBytes:"" length:1];
    [buf appendBytes:valueBuf + firstNonzero length:8 - firstNonzero];
}

/*" Formats the tag byte and length field of an ASN.1 item and appends the result to the passed-in buffer. Currently the 'tag' is the whole tag+class+constructed field--- we don't handle multibyte tags at all (since they don't appear in any PKIX structures). "*/
void OFASN1AppendTagLength(NSMutableData *buffer, uint8_t tag, NSUInteger byteCount)
{
    uint8_t buf[ 2 + sizeof(NSUInteger) ];
    unsigned int bufUsed;
    
    buf[0] = tag;
    bufUsed = 1;
    
    if (byteCount < 128) {
        /* Short lengths have a 1-byte direct representation */
        buf[1] = (uint8_t)byteCount;
        bufUsed = 2;
    } else {
        /* Longer lengths have a count-and-value representation */
        uint_fast8_t n;
        uint8_t bytebuf[ sizeof(NSUInteger) ];
        NSUInteger value = byteCount;
        for(n = 0; n < sizeof(NSUInteger); n++) {
            bytebuf[n] = ( value & 0xFF );
            value >>= 8;
        }
        while(bytebuf[n-1] == 0)
            n--;
        buf[bufUsed++] = 0x80 | n;
        while (n--) {
            buf[bufUsed++] = bytebuf[n];
        };
    }
    
    OBASSERT(bufUsed == OFASN1SizeOfTagLength(tag, byteCount));
    
    [buffer appendBytes:buf length:bufUsed];
}

/*" Formats the tag byte and length field of an ASN.1 item and appends the result to the passed-in buffer. Currently the 'tag' is the whole tag+class+constructed field--- we don't handle multibyte tags at all (since they don't appear in any PKIX structures). "*/
void OFASN1AppendTagIndefinite(NSMutableData *buffer, uint8_t tag)
{
    uint8_t buf[ 2 ];
    
    buf[0] = tag;
    buf[1] = 0x80;
    
    [buffer appendBytes:buf length:2];
}

/* Ordering function for members of a DER-encoded SET. */
static NSInteger lexicographicCompareData(id a, id b, void *dummy)
{
    const void *aBytes = [(NSData *)a bytes];
    const void *bBytes = [(NSData *)b bytes];
    NSUInteger aLength = [(NSData *)a length];
    NSUInteger bLength = [(NSData *)b length];
    
    int cmp = memcmp(aBytes, bBytes, MIN(aLength, bLength));
    if (cmp < 0) {
        return NSOrderedAscending;
    } else if (cmp > 0) {
        return NSOrderedDescending;
    } else {
        /* This branch should never be taken: DER-encoded objects are self-delimiting, i.e., one cannot be a prefix of another unless they are identical. */
        OBASSERT_NOT_REACHED("Equal or prefix-equal items in a SET?");
        if (aLength < bLength) {
            return NSOrderedAscending;
        } else if (aLength > bLength) {
            return NSOrderedDescending;
        } else {
            return NSOrderedSame;
        }
    }
}

void OFASN1AppendSet(NSMutableData *buffer, unsigned char tagByte, NSArray *derElements)
{
    /* For DER encoding, the SET items must be sorted according to their DER representation. */
    NSArray *sortedElements = [derElements sortedArrayUsingFunction:lexicographicCompareData context:NULL];
    
    /* Compute length */
    NSUInteger elementCount = [sortedElements count];
    NSUInteger totalLength = 0;
    for (NSUInteger eltIndex = 0; eltIndex < elementCount; eltIndex ++)
        totalLength += [[sortedElements objectAtIndex:eltIndex] length];
    
    /* And write the SET */
    OFASN1AppendTagLength(buffer, tagByte, totalLength);
    for (NSUInteger eltIndex = 0; eltIndex < elementCount; eltIndex ++)
        [buffer appendData:[sortedElements objectAtIndex:eltIndex]];
}

unsigned int OFASN1SizeOfTagLength(uint8_t tag, NSUInteger byteCount)
{
    unsigned int bufUsed;
    
    bufUsed = 1;
    
    if (byteCount < 128) {
        /* Short lengths have a 1-byte direct representation */
        return bufUsed + 1;
    } else {
        /* Longer lengths have a count-and-value representation */
        uint_fast8_t n;
        uint8_t bytebuf[8];
        memset(bytebuf, 0, sizeof(bytebuf)); /// Redundant memset, but apparently clang analyze doesn't understand OSWriteLittleInt64()
        OSWriteLittleInt64(bytebuf, 0, byteCount);
        n = 7;
        while (bytebuf[n] == 0) {
            n--;
        }
        return bufUsed + 2 + n;
    }
}

/* Each piece is one of:
    - An object header (if tagAndClass is nonnegative), for an object of length 'contentLength', optionally with one byte of content stuffing
    - Some raw bytes, either an NSData (in obj) or in a byte buffer (rawBytes + length)
    - A placeholder, which would be an NSData, but we're not inserting it yet
 
    In all cases, 'length+stuffing' indicates the amount of space occupied by this piece in the final NSData.
 */
struct piece {
    unsigned short tagAndClass;  // Tag-and-class byte, or 0 for other kinds of pieces
    unsigned short stuffing;     // >0 if we should insert extra bytes from stuffData[] after the tagAndClass before the next piece.
    size_t contentLength;        // If this is an object header, the total length of any other pieces "contained" by this one
    
    const uint8_t *rawBytes;            // A pointer to 'length' bytes
    id <NSObject> __unsafe_unretained obj; // Or an NSData or NSArray
    uint8_t stuffData[sizeof(uint32_t)];
    
    size_t *placeholder;  // Caller wants to know the location of this piece in the output data.
    size_t length;        // Logical size of this piece. (For placeholders, sometimes we have a nonzero logical size but don't insert it in the output data.)
    
    // These are used internally by ofASN1ComputePieceSizes()
    int container;     // The index of the containing container, or -1 if none
    int lastContent;   // This is patched up to be the index of the last piece in the container
};

struct computedSizes {
    struct piece *pieces;
    int pieceCount;
    size_t totalPlaceholderLength;
    size_t totalLength;
};

static struct computedSizes ofASN1ComputePieceSizes(const char *fmt, va_list argList)
{
    /* As an upper bound, there are as many pieces as characters in the format string */
    struct piece *pieces = malloc(sizeof(*pieces) * strlen(fmt));
    
    int lastOpen = -1;
    int pieceCount = 0;
    size_t totalPlaceholderLength = 0;
    const char *cp = fmt;
    
    for (;;) {
        int tag;
        BOOL stuffByte;
        
        if (!*cp)
            break;
        
        /* '!' allows the caller to override the tag+class value of the next object. (This is mostly useful for implicit context tagging.) */
        if (*cp == '!') {
            tag = va_arg(argList, int);
            cp++;
        } else {
            tag = -1;
        }
        
        switch(*cp) {
            case ' ':
                break;
            
            /* Raw bytes, as an NSData */
            case 'd':
            {
                NSData * __unsafe_unretained obj = va_arg(argList, NSData * __unsafe_unretained);
                OBASSERT([obj isKindOfClass:[NSData class]]);
                pieces[pieceCount++] = (struct piece){
                    .tagAndClass = 0,
                    .length = [obj length],
                    .rawBytes = NULL,
                    .obj = obj,
                    .placeholder = NULL,
                    
                    .container = -1,
                    .lastContent = -1
                };
            }
                break;
                
            /* Raw bytes, as an array of NSDatas */
            case 'a':
            {
                NSArray <NSData *> * __unsafe_unretained arr = va_arg(argList, NSArray <NSData *> * __unsafe_unretained);
                OBASSERT([arr isKindOfClass:[NSArray class]]);
                NSUInteger totalLength = 0;
                NSUInteger count = [arr count];
                for (NSUInteger i = 0; i < count; i++)
                    totalLength += [[arr objectAtIndex:i] length];
                pieces[pieceCount++] = (struct piece){
                    .tagAndClass = 0,
                    .length = totalLength,
                    .rawBytes = NULL,
                    .obj = arr,
                    .placeholder = NULL,
                    
                    .container = -1,
                    .lastContent = -1
                };
            }
                break;
                
            /* Raw bytes, as a (size_t, const uint8_t *) pair of arguments */
            case '*':
            {
                size_t len = va_arg(argList, size_t);
                const uint8_t *buf = va_arg(argList, const uint8_t *);
                
                pieces[pieceCount++] = (struct piece){
                    .tagAndClass = 0,
                    .length = len,
                    .rawBytes = buf,
                    .obj = NULL,
                    .placeholder = NULL,
                    
                    .container = -1,
                    .lastContent = -1
                };
            }
                break;
                
            /* Similar to '*', but we read the object's length from its DER tag */
            case '+':
            {
                const uint8_t *buf = va_arg(argList, const uint8_t *);
                size_t len = derObjectLength(buf);
                
                pieces[pieceCount++] = (struct piece){
                    .tagAndClass = 0,
                    .length = len,
                    .rawBytes = buf,
                    .obj = NULL,
                    .placeholder = NULL,
                    
                    .container = -1,
                    .lastContent = -1
                };
            }
                break;

            /* A placeholder. The first arg is a size_t indicating the length of the data which will be inserted. The second arg is a (size_t *) into which we will store the offset at which the placeholder data should be inserted in the returned buffer to produce the final value. */
            case 'p':
            {
                size_t len = va_arg(argList, size_t);
                size_t *outPosition = va_arg(argList, size_t *);
                
                totalPlaceholderLength += len;
                
                pieces[pieceCount++] = (struct piece){
                    .tagAndClass = 0,
                    .length = len,
                    .rawBytes = NULL,
                    .obj = NULL,
                    .placeholder = outPosition,
                    
                    .container = -1,
                    .lastContent = -1
                };
            }
                
            /* An unsigned integer. We format it into stuffData[]. */
            /* We can currently hold numbers up to 2^31-1; it's the caller's responsibility to make sure the number is in that range. */
            case 'u':
            {
                unsigned value = va_arg(argList, unsigned int);
                uint8_t buf[sizeof(uint32_t)];
                unsigned byteIndex;
                bzero(buf, sizeof(buf)); // Arguably shouldn't be needed; RADAR 27875387
                OSWriteBigInt32(buf, 0, value);
                for (byteIndex = 0; byteIndex < (int)(sizeof(uint32_t)-1); byteIndex++) {
                    if (buf[byteIndex] != 0)
                        break;
                }
                /* Avoid our high bit being misinterpreted as a sign bit */
                if (byteIndex > 0 && (buf[byteIndex] & 0x80))
                    byteIndex --;
                
                pieces[pieceCount] = (struct piece){
                    .tagAndClass = ( tag > 0 )? tag : BER_TAG_INTEGER,
                    .stuffing = (sizeof(uint32_t)) - byteIndex,
                    .rawBytes = NULL,
                    .obj = NULL,
                    .placeholder = NULL,
                    
                    .container = -1,
                    .lastContent = -1
                };
                for (int j = 0; byteIndex < (int)sizeof(uint32_t); byteIndex++, j++) {
                    pieces[pieceCount].stuffData[j] = buf[byteIndex];
                }
                
                pieceCount ++;
            }
                break;
                
            /* Container types, whose length field depends on other pieces */
                
            case '(':
                if (tag < 0)
                    tag = BER_TAG_SEQUENCE | FLAG_CONSTRUCTED;
                stuffByte = NO;
                goto beginConstructed;
            case '{':
                if (tag < 0)
                    tag = BER_TAG_SET | FLAG_CONSTRUCTED;
                stuffByte = NO;
                goto beginConstructed;
            case '[':
                if (tag < 0)
                    tag = BER_TAG_OCTET_STRING;
                stuffByte = NO;
                goto beginConstructed;
            case '<':
                if (tag < 0)
                    tag = BER_TAG_BIT_STRING;
                stuffByte = YES;
                goto beginConstructed;
                
            beginConstructed:
                pieces[pieceCount] = (struct piece){
                    .tagAndClass = tag,
                    .length = 0,
                    .rawBytes = NULL,
                    .obj = nil,
                    .placeholder = NULL,
                    
                    .container = lastOpen,
                    .lastContent = -1,
                    .stuffing = stuffByte? 1 : 0
                };
                pieces[pieceCount].stuffData[0] = 0;
                lastOpen = pieceCount;
                pieceCount ++;
                break;

            case ')':
            case '}':
            case ']':
            case '>':
                assert(lastOpen >= 0);
                assert(pieceCount > lastOpen);
                pieces[lastOpen].lastContent = pieceCount-1;
                lastOpen = pieces[lastOpen].container;
                break;
                
            default:
                abort();
        }
        
        cp++;
    }

    assert(lastOpen == -1); // Assert that the open/close parens are balanced
    
    /* Run through backwards to compute lengths */
    size_t totalLength = 0;
    for (int pieceIndex = pieceCount-1; pieceIndex >= 0; pieceIndex --) {
        if (pieces[pieceIndex].tagAndClass) {
            size_t summedLength = 0;
            for (int ci = pieceIndex+1; ci <= pieces[pieceIndex].lastContent; ci++) {
                summedLength += pieces[ci].length;
            }
            pieces[pieceIndex].contentLength = summedLength;
            pieces[pieceIndex].length = OFASN1SizeOfTagLength((uint8_t)pieces[pieceIndex].tagAndClass, summedLength + pieces[pieceIndex].stuffing) + pieces[pieceIndex].stuffing;
        }
        totalLength += pieces[pieceIndex].length;
    }
    
    return (struct computedSizes){
        .pieces = pieces,
        .pieceCount = pieceCount,
        .totalLength = totalLength,
        .totalPlaceholderLength = totalPlaceholderLength
    };
}

NSMutableData *OFASN1AppendStructure(NSMutableData * _Nullable buffer, const char *fmt, ...)
{
    /* Parse the format string and compute offsets */
    va_list argList;
    va_start(argList, fmt);
    struct computedSizes sizes = ofASN1ComputePieceSizes(fmt, argList);
    va_end(argList);
    
    /* Accumulate everything into the supplied buffer */
    if (!buffer)
        buffer = [NSMutableData dataWithCapacity:sizes.totalLength - sizes.totalPlaceholderLength];
    
#ifdef OMNI_ASSERTIONS_ON
    size_t previousBufferLength = buffer.length;
#endif
    
    for (int pieceIndex = 0; pieceIndex < sizes.pieceCount; pieceIndex ++) {
        const struct piece *piece = &sizes.pieces[pieceIndex];
        if (piece->placeholder) {
            *(piece->placeholder) = buffer.length;
        }
        if (piece->tagAndClass) {
            OFASN1AppendTagLength(buffer, (uint8_t)(piece->tagAndClass), piece->contentLength + piece->stuffing);
            if (piece->stuffing)
                [buffer appendBytes:piece->stuffData length:piece->stuffing];
        } else if (piece->rawBytes) {
            [buffer appendBytes:piece->rawBytes length:piece->length];
        } else if (piece->obj) {
            if ([piece->obj isKindOfClass:[NSData class]]) {
                [buffer appendData:(NSData *)piece->obj];
            } else {
                NSUInteger count = [(NSArray <NSData *> *)(piece->obj) count];
                for (NSUInteger i = 0; i < count; i++) {
                    [buffer appendData:[(NSArray <NSData *> *)(piece->obj) objectAtIndex:i]];
                }
            }
        } else {
            OBASSERT_NOT_REACHED("?");
        }
    }

    free(sizes.pieces);
    
    OBASSERT(buffer.length + sizes.totalPlaceholderLength == previousBufferLength + sizes.totalLength);
    
    return buffer;
}

static inline dispatch_data_t accumulatePiece(dispatch_data_t accum, NSMutableData *buffer, NSData *piece)
{
    size_t pieceLength = piece.length;
    if (pieceLength < 256) {
        // It's not worth creating a separate segment for this.
        [buffer appendData:piece];
        return accum;
    }
    
    size_t bufferLength = buffer.length;
    if (pieceLength + bufferLength < 16384) {
        // Or this.
        [buffer appendData:piece];
        return accum;
    }
    
    dispatch_data_t segment = dispatch_of_NSData(piece);
    if (bufferLength > 0) {
        dispatch_data_t chunk = dispatch_data_create(buffer.bytes, bufferLength, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
        segment = dispatch_data_create_concat(chunk, segment);
        [buffer setLength:0];
    }
    
    return dispatch_data_create_concat(accum, segment);
}

dispatch_data_t _Nonnull OFASN1MakeStructure(const char *fmt, ...)
{
    /* Parse the format string and compute offsets */
    va_list argList;
    va_start(argList, fmt);
    struct computedSizes sizes = ofASN1ComputePieceSizes(fmt, argList);
    va_end(argList);
    
    /* Accumulate everything into buffers */
    dispatch_data_t accum = dispatch_data_empty;
    NSMutableData *buffer = [NSMutableData data];
    
    for (int pieceIndex = 0; pieceIndex < sizes.pieceCount; pieceIndex ++) {
        const struct piece *piece = &sizes.pieces[pieceIndex];
        if (piece->placeholder) {
            *(piece->placeholder) = buffer.length + dispatch_data_get_size(accum);
        }
        if (piece->tagAndClass) {
            OFASN1AppendTagLength(buffer, (uint8_t)(piece->tagAndClass), piece->contentLength + piece->stuffing);
            if (piece->stuffing)
                [buffer appendBytes:piece->stuffData length:piece->stuffing];
        } else if (piece->rawBytes) {
            [buffer appendBytes:piece->rawBytes length:piece->length];
        } else if (piece->obj) {
            if ([piece->obj isKindOfClass:[NSData class]]) {
                accum = accumulatePiece(accum, buffer, (NSData *)piece->obj);
            } else {
                NSUInteger count = [(NSArray <NSData *> *)(piece->obj) count];
                for (NSUInteger i = 0; i < count; i++) {
                    accum = accumulatePiece(accum, buffer, [(NSArray <NSData *> *)(piece->obj) objectAtIndex:i]);
                }
            }
        } else {
            OBASSERT_NOT_REACHED("?");
        }
    }
    
    free(sizes.pieces);
    
    {
        size_t bufferLength = buffer.length;
        if (bufferLength > 0) {
            dispatch_data_t chunk = dispatch_data_create(buffer.bytes, bufferLength, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            accum = dispatch_data_create_concat(accum, chunk);
        }
    }
    
    OBASSERT(dispatch_data_get_size(accum) + sizes.totalPlaceholderLength == sizes.totalLength);
    
    return accum;
}

static dispatch_data_t dispatch_of_NSData(NSData *buf)
{
    if ([buf conformsToProtocol:@protocol(OS_dispatch_data)]) {
        return (dispatch_data_t)buf;
    } else {
        CFDataRef retainedBuf = CFBridgingRetain([buf copy]);
        return dispatch_data_create(CFDataGetBytePtr(retainedBuf), CFDataGetLength(retainedBuf), NULL, ^{ CFRelease(retainedBuf); });
    }
}


