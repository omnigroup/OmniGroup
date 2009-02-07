// Copyright 1998-2005,2007,2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSData-OFEncoding.h>

#import <OmniFoundation/OFDataBuffer.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <OmniFoundation/OFErrors.h>

RCS_ID("$Id$")

@implementation NSData (OFEncoding)

// Returns 0x0 through 0xf if the digit is valid, or 0xff if not valid.
static inline uint8_t _fromhex(unichar hexDigit)
{
    if (hexDigit >= '0' && hexDigit <= '9')
        return hexDigit - '0';
    if (hexDigit >= 'a' && hexDigit <= 'f')
        return hexDigit - 'a' + 10;
    if (hexDigit >= 'A' && hexDigit <= 'F')
        return hexDigit - 'A' + 10;
    return 0xff;
}

+ (id)dataWithHexString:(NSString *)hexString error:(NSError **)outError;
{
    return [[[self alloc] initWithHexString:hexString error:outError] autorelease];
}

// Interprets strings of the form (0[xX])?[0-9a-fA-F]* as hexadecimal byte sequences. Any deviation from this pattern should result in nil being returned with an error supplied.
- initWithHexString:(NSString *)hexString error:(NSError **)outError;
{
    NSUInteger length = [hexString length];

    // -getCharacters: doesn't append a NUL; leave room for one and we'll append it.
    unichar *inputBase = malloc((length + 1) * sizeof(unichar));
    [hexString getCharacters:inputBase];
    inputBase[length] = 0;

    NSUInteger inputPosition = 0;
    if (inputBase[0] == '0' && (inputBase[1] == 'x' || inputBase[1] == 'X'))
        inputPosition += 2;
    
    // Account for half bytes in our output buffer and parsing so that 0xf08 is interpreted as 0x0f08
    const NSUInteger digitCount = length - inputPosition;
    const NSUInteger outputLength = (digitCount + 1) / 2;
    uint8_t *outputBytes = malloc(outputLength);

    NSData *result = nil;
#define READ_DIGIT(v) do { \
    unichar c = inputBase[inputPosition++]; \
    v = _fromhex(c); \
    if (v == 0xff) { \
        if (outError) \
	    OBError(outError, OFInvalidHexDigit, ([NSString stringWithFormat:@"The character '%C' (0x%x) is not a valid hexadecimal digit.", c, c])); \
        goto cleanup; \
    } \
} while(0)

    NSUInteger outputPosition = 0;
    uint8_t digit0, digit1;
    
    if (digitCount & 0x01) {
        READ_DIGIT(digit0);
        outputBytes[outputPosition++] = digit0;
    }
    OBASSERT((length - inputPosition) % 2 == 0);
    
    while (inputPosition < length) {
        READ_DIGIT(digit0);
        READ_DIGIT(digit1);
        outputBytes[outputPosition++] = (digit0 << 4) | digit1;
    }
    
    result = [self initWithBytesNoCopy:outputBytes length:outputLength];
    OBASSERT(outputPosition == outputLength);
    
cleanup:
    free(inputBase);
    return result;
}

- (NSString *)_lowercaseHexStringWithPrefix:(const unichar *)prefix
                                     length:(unsigned int)prefixLength
{
    const OFByte *inputBytes, *inputBytesPtr;
    unsigned int inputBytesLength, outputBufferLength;
    unichar *outputBuffer, *outputBufferEnd;
    unichar *outputBufferPtr;
    const char _tohex[] = "0123456789abcdef";
    NSString *hexString;
    
    inputBytes = [self bytes];
    inputBytesLength = [self length];
    outputBufferLength = prefixLength + inputBytesLength * 2;
    outputBuffer = NSZoneMalloc(NULL, outputBufferLength * sizeof(unichar));
    outputBufferEnd = outputBuffer + outputBufferLength;
    
    inputBytesPtr = inputBytes;
    outputBufferPtr = outputBuffer;
    
    while(prefixLength--)
        *outputBufferPtr++ = *prefix++;
    while (outputBufferPtr < outputBufferEnd) {
        unsigned char inputByte;
        
        inputByte = *inputBytesPtr++;
        *outputBufferPtr++ = _tohex[(inputByte & 0xf0) >> 4];
        *outputBufferPtr++ = _tohex[inputByte & 0x0f];
    }
    
    hexString = [[NSString allocWithZone:[self zone]] initWithCharacters:outputBuffer length:outputBufferLength];
    
    NSZoneFree(NULL, outputBuffer);
    
    return [hexString autorelease];
}

- (NSString *)lowercaseHexString;
{
    /* For backwards compatibility, this method has a leading "0x" */
    static const unichar hexPrefix[2] = { '0', 'x' };
    
    return [self _lowercaseHexStringWithPrefix:hexPrefix length:2];
}

- (NSString *)unadornedLowercaseHexString;
{
    return [self _lowercaseHexStringWithPrefix:NULL length:0];
}

// This is based on decode85.c.  The only major difference is that this doesn't deal with newlines in the file and doesn't deal with the '<~' and '~>' beginning and end of stirng markers.

static inline void ascii85put(OFDataBuffer *buffer, unsigned long tuple, int bytes)
{
    switch (bytes) {
        case 4:
            OFDataBufferAppendByte(buffer, tuple >> 24);
            OFDataBufferAppendByte(buffer, tuple >> 16);
            OFDataBufferAppendByte(buffer, tuple >>  8);
            OFDataBufferAppendByte(buffer, tuple);
            break;
        case 3:
            OFDataBufferAppendByte(buffer, tuple >> 24);
            OFDataBufferAppendByte(buffer, tuple >> 16);
            OFDataBufferAppendByte(buffer, tuple >>  8);
            break;
        case 2:
            OFDataBufferAppendByte(buffer, tuple >> 24);
            OFDataBufferAppendByte(buffer, tuple >> 16);
            break;
        case 1:
            OFDataBufferAppendByte(buffer, tuple >> 24);
            break;
    }
}

- initWithASCII85String:(NSString *)ascii85String;
{
    static const unsigned long pow85[] = {
        85 * 85 * 85 * 85, 85 * 85 * 85, 85 * 85, 85, 1
    };
    OFDataBuffer buffer;
    const unsigned char *string;
    unsigned long tuple = 0, length;
    int c, count = 0;
    NSData *ascii85Data, *decodedData;
    NSData *returnValue;
    
    OBPRECONDITION([ascii85String canBeConvertedToEncoding:NSASCIIStringEncoding]);
    
    ascii85Data = [ascii85String dataUsingEncoding:NSASCIIStringEncoding];
    string = [ascii85Data bytes];
    length = [ascii85Data length];
    
    OFDataBufferInit(&buffer);
    while (length--) {
        c = (int)*string;
        string++;
        
        switch (c) {
            default:
                if (c < '!' || c > 'u')
                    [NSException raise:@"ASCII85Error" format:@"ASCII85: bad character in ascii85 string: %#o", c];
                
                tuple += (c - '!') * pow85[count++];
                if (count == 5) {
                    ascii85put(&buffer, tuple, 4);
                    count = 0;
                    tuple = 0;
                }
                break;
                case 'z':
                if (count != 0)
                    [NSException raise:@"ASCII85Error" format:@"ASCII85: z inside ascii85 5-tuple"];
                OFDataBufferAppendByte(&buffer, '\0');
                OFDataBufferAppendByte(&buffer, '\0');
                OFDataBufferAppendByte(&buffer, '\0');
                OFDataBufferAppendByte(&buffer, '\0');
                break;
        }
    }
    
    if (count > 0) {
        count--;
        tuple += pow85[count];
        ascii85put(&buffer, tuple, count);
    }
    
    decodedData = [OFDataBufferData(&buffer) retain];
    OFDataBufferRelease(&buffer);
    
    returnValue = [self initWithData:decodedData];
    [decodedData release];
    
    return returnValue;
}

static inline void encode85(OFDataBuffer *dataBuffer, unsigned long tuple, int count)
{
    int i;
    char buf[5], *s = buf;
    i = 5;
    do {
        *s++ = tuple % 85;
        tuple /= 85;
    } while (--i > 0);
    i = count;
    do {
        OFDataBufferAppendByte(dataBuffer, *--s + '!');
    } while (i-- > 0);
}

- (NSString *)ascii85String;
{
    OFDataBuffer dataBuffer;
    const unsigned char *byte;
    unsigned int length, count = 0, tuple = 0;
    NSData *data;
    NSString *string;
    
    OFDataBufferInit(&dataBuffer);
    
    byte = [self bytes];
    length = [self length];
    
    // This is based on encode85.c.  The only major difference is that this doesn't put newlines in the file to keep the output line(s) as some maximum width.  Also, this doesn't put the '<~' at the beginning and '
    
    while (length--) {
        unsigned int c;
        
        c = (unsigned int)*byte;
        byte++;
        
        switch (count++) {
            case 0:
                tuple |= (c << 24);
                break;
            case 1:
                tuple |= (c << 16);
                break;
            case 2:
                tuple |= (c <<  8);
                break;
            case 3:
                tuple |= c;
                if (tuple == 0)
                    OFDataBufferAppendByte(&dataBuffer, 'z');
                else
                    encode85(&dataBuffer, tuple, count);
                tuple = 0;
                count = 0;
                break;
        }
    }
    
    if (count > 0)
        encode85(&dataBuffer, tuple, count);
    
    data = OFDataBufferData(&dataBuffer);
    string = [NSString stringWithData:data encoding:NSASCIIStringEncoding];
    OFDataBufferRelease(&dataBuffer);
    
    return string;
}

//
// Base-64 (RFC-1521) support.  The following is based on mpack-1.5 (ftp://ftp.andrew.cmu.edu/pub/mpack/)
//

#define XX 127
static char index_64[256] = {
XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,62, XX,XX,XX,63,
52,53,54,55, 56,57,58,59, 60,61,XX,XX, XX,XX,XX,XX,
XX, 0, 1, 2,  3, 4, 5, 6,  7, 8, 9,10, 11,12,13,14,
15,16,17,18, 19,20,21,22, 23,24,25,XX, XX,XX,XX,XX,
XX,26,27,28, 29,30,31,32, 33,34,35,36, 37,38,39,40,
41,42,43,44, 45,46,47,48, 49,50,51,XX, XX,XX,XX,XX,
XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX, XX,XX,XX,XX,
};
#define CHAR64(c) (index_64[(unsigned char)(c)])

#define BASE64_GETC (length > 0 ? (length--, bytes++, (unsigned int)(bytes[-1])) : (unsigned int)EOF)
#define BASE64_PUTC(c) OFDataBufferAppendByte(buffer, (c))

+ (id)dataWithBase64String:(NSString *)base64String;
{
    return [[[self alloc] initWithBase64String:base64String] autorelease];
}

- initWithBase64String:(NSString *)base64String;
{
    NSData *base64Data;
    const char *bytes;
    unsigned int length;
    OFDataBuffer dataBuffer, *buffer;
    NSData *decodedData;
    NSData *returnValue;
    BOOL suppressCR = NO;
    unsigned int c1, c2, c3, c4;
    int DataDone = 0;
    char buf[3];
    
    OBPRECONDITION([base64String canBeConvertedToEncoding:NSASCIIStringEncoding]);
    
    buffer = &dataBuffer;
    OFDataBufferInit(buffer);
    
    base64Data = [base64String dataUsingEncoding:NSASCIIStringEncoding];
    bytes = [base64Data bytes];
    length = [base64Data length];
    
    while ((c1 = BASE64_GETC) != (unsigned int)EOF) {
        if (c1 != '=' && CHAR64(c1) == XX)
            continue;
        if (DataDone)
            continue;
        
        do {
            c2 = BASE64_GETC;
        } while (c2 != (unsigned int)EOF && c2 != '=' && CHAR64(c2) == XX);
        do {
            c3 = BASE64_GETC;
        } while (c3 != (unsigned int)EOF && c3 != '=' && CHAR64(c3) == XX);
        do {
            c4 = BASE64_GETC;
        } while (c4 != (unsigned int)EOF && c4 != '=' && CHAR64(c4) == XX);
        if (c2 == (unsigned int)EOF || c3 == (unsigned int)EOF || c4 == (unsigned int)EOF) {
            [NSException raise:@"Base64Error" format:@"Premature end of Base64 string"];
            break;
        }
        if (c1 == '=' || c2 == '=') {
            DataDone=1;
            continue;
        }
        c1 = CHAR64(c1);
        c2 = CHAR64(c2);
        buf[0] = ((c1<<2) | ((c2&0x30)>>4));
        if (!suppressCR || buf[0] != '\r') BASE64_PUTC(buf[0]);
        if (c3 == '=') {
            DataDone = 1;
        } else {
            c3 = CHAR64(c3);
            buf[1] = (((c2&0x0F) << 4) | ((c3&0x3C) >> 2));
            if (!suppressCR || buf[1] != '\r') BASE64_PUTC(buf[1]);
            if (c4 == '=') {
                DataDone = 1;
            } else {
                c4 = CHAR64(c4);
                buf[2] = (((c3&0x03) << 6) | c4);
                if (!suppressCR || buf[2] != '\r') BASE64_PUTC(buf[2]);
            }
        }
    }
    
    decodedData = [OFDataBufferData(buffer) retain];
    OFDataBufferRelease(buffer);
    
    returnValue = [self initWithData:decodedData];
    [decodedData release];
    
    return returnValue;
}

static char basis_64[] =
"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static inline void output64chunk(int c1, int c2, int c3, int pads, OFDataBuffer *buffer)
{
    BASE64_PUTC(basis_64[c1>>2]);
    BASE64_PUTC(basis_64[((c1 & 0x3)<< 4) | ((c2 & 0xF0) >> 4)]);
    if (pads == 2) {
        BASE64_PUTC('=');
        BASE64_PUTC('=');
    } else if (pads) {
        BASE64_PUTC(basis_64[((c2 & 0xF) << 2) | ((c3 & 0xC0) >>6)]);
        BASE64_PUTC('=');
    } else {
        BASE64_PUTC(basis_64[((c2 & 0xF) << 2) | ((c3 & 0xC0) >>6)]);
        BASE64_PUTC(basis_64[c3 & 0x3F]);
    }
}

- (NSString *)base64String;
{
    NSString *string;
    NSData *data;
    const OFByte *bytes;
    unsigned int length;
    OFDataBuffer dataBuffer, *buffer;
    unsigned int c1, c2, c3;
    
    buffer = &dataBuffer;
    OFDataBufferInit(buffer);
    
    bytes = [self bytes];
    length = [self length];
    
    while ((c1 = BASE64_GETC) != (unsigned int)EOF) {
        c2 = BASE64_GETC;
        if (c2 == (unsigned int)EOF) {
            output64chunk(c1, 0, 0, 2, buffer);
        } else {
            c3 = BASE64_GETC;
            if (c3 == (unsigned int)EOF) {
                output64chunk(c1, c2, 0, 1, buffer);
            } else {
                output64chunk(c1, c2, c3, 0, buffer);
            }
        }
    }
    
    data = OFDataBufferData(&dataBuffer);
    string = [NSString stringWithData:data encoding:NSASCIIStringEncoding];
    OFDataBufferRelease(&dataBuffer);
    
    return string;
}

//
// Omni's custom base-26 support.  This is based on the ascii85 implementation above.
//
// Input strings are characters (either upper or lowercase).  Dashes are ignored.
// Anything else, including whitespace, is illegal.
//
// Output strings are four-character tuples separated by dashes.  The last
// tuple might have fewer than four characters.
//
// Unlike most encodings in this file, a partially-filled 4-octet group has the data
// packed into the less-significant bytes, instead of the more-significant bytes.
//

#define POW4_26_COUNT (7)   // Four base 256 digits take 7 base 26 digits
#define POW3_26_COUNT (6)   // Three base 256 digits take 6 base 26 digits
#define POW2_26_COUNT (4)   // Two base 256 digits take 4 base 26 digits
#define POW1_26_COUNT (2)   // One base 256 digit taks 2 base 26 digits

static unsigned int log256_26[] = {
POW1_26_COUNT,
POW2_26_COUNT,
POW3_26_COUNT,
POW4_26_COUNT
};

static unsigned int log26_256[] = {
0, // invalid
1, // two base 26 digits gives one base 256 digit
0, // invalid
2, // four base 26 digits gives two base 256 digits
0, // invalid
3, // six base 26 digits gives three base 256 digits
4, // seven base 26 digits gives three base 256 digits
};

static inline void ascii26put(OFDataBuffer *buffer, unsigned long tuple, int count26)
{
    switch (log26_256[count26-1]) {
        case 4:
            OFDataBufferAppendByte(buffer, (tuple >> 24) & 0xff);
            OFDataBufferAppendByte(buffer, (tuple >> 16) & 0xff);
            OFDataBufferAppendByte(buffer, (tuple >>  8) & 0xff);
            OFDataBufferAppendByte(buffer, (tuple >>  0) & 0xff);
            break;
        case 3:
            OFDataBufferAppendByte(buffer, (tuple >> 16) & 0xff);
            OFDataBufferAppendByte(buffer, (tuple >>  8) & 0xff);
            OFDataBufferAppendByte(buffer, (tuple >>  0) & 0xff);
            break;
        case 2:
            OFDataBufferAppendByte(buffer, (tuple >>  8) & 0xff);
            OFDataBufferAppendByte(buffer, (tuple >>  0) & 0xff);
            break;
        case 1:
            OFDataBufferAppendByte(buffer, (tuple >>  0) & 0xff);
            break;
        default: // ie, zero
            [NSException raise:@"IllegalBase26String" format:@"Malformed base26 string -- last block is %d long", count26];
            break;
    }
}

- initWithASCII26String:(NSString *)ascii26String;
{
    OFDataBuffer buffer;
    const unsigned char *string;
    unsigned long tuple = 0, length;
    unsigned char c, count = 0;
    NSData *ascii26Data, *decodedData;
    NSData *returnValue;
    
    OBPRECONDITION([ascii26String canBeConvertedToEncoding:NSASCIIStringEncoding]);
    
    ascii26Data = [ascii26String dataUsingEncoding:NSASCIIStringEncoding];
    string = [ascii26Data bytes];
    length = [ascii26Data length];
    
    OFDataBufferInit(&buffer);
    while (length--) {
        c = *string;
        string++;
        
        if (c == '-') {
            // Dashes are ignored
            continue;
        }
        
        count++;
        
        // 'shift' up
        tuple *= 26;
        
        // 'or' in the new digit
        if (c >= 'a' && c <= 'z') {
            tuple += (c - 'a');
        } else if (c >= 'A' && c <= 'Z') {
            tuple += (c - 'A');
        } else {
            // Illegal character
            [NSException raise:@"ASCII26Error"
                        format:@"ASCII26: bad character in ascii26 string: %#o", c];
        }
        
        if (count == POW4_26_COUNT) {
            // If we've filled up a full tuple, output it
            ascii26put(&buffer, tuple, count);
            count = 0;
            tuple = 0;
        }
    }
    
    if (count)
        // flush remaining digits
        ascii26put(&buffer, tuple, count);
    
    decodedData = [OFDataBufferData(&buffer) retain];
    OFDataBufferRelease(&buffer);
    
    returnValue = [self initWithData:decodedData];
    [decodedData release];
    
    return returnValue;
}

static inline void encode26(OFDataBuffer *dataBuffer, unsigned long tuple, int count256)
{
    int  i, count26;
    char buf[POW4_26_COUNT], *s = buf;
    
    // Compute the number of base 26 digits necessary to represent
    // the number of base 256 digits we've been given.
    count26 = log256_26[count256-1];
    
    i = count26;
    while (i--) {
        *s = tuple % 26;
        tuple /= 26;
        s++;
    }
    i = count26;
    while (i--) {
        s--;
        OFDataBufferAppendByte(dataBuffer, *s + 'A');
    }
}

- (NSString *) ascii26String;
{
    OFDataBuffer dataBuffer;
    const unsigned char *byte;
    unsigned int length, count = 0, tuple = 0;
    NSData *data;
    NSString *string;
    
    OFDataBufferInit(&dataBuffer);
    
    byte   = [self bytes];
    length = [self length];
    
    while (length--) {
        unsigned int c;
        
        c = (unsigned int)*byte;
        tuple <<= 8;
        tuple += c;
        byte++;
        count++;
        
        if (count == 4) {
            encode26(&dataBuffer, tuple, count);
            tuple = 0;
            count = 0;
        }
    }
    
    if (count)
        encode26(&dataBuffer, tuple, count);
    
    data = OFDataBufferData(&dataBuffer);
    string = [NSString stringWithData:data encoding:NSASCIIStringEncoding];
    OFDataBufferRelease(&dataBuffer);
    
    return string;
}

@end
