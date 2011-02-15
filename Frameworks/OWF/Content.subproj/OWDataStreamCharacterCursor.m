// Copyright 2000-2005, 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWDataStreamCharacterCursor.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>

#import "OWDataStreamCursor.h"
#import "OWDataStream.h"
#import "OWDataStreamCharacterProcessor.h"

RCS_ID("$Id$")

@implementation OWDataStreamCharacterCursor

#define OWDataStreamCharacterCursor_EOF (~(unsigned int)0)

static NSCharacterSet *tokenDelimiters;

+ (void)initialize;
{
    OBINITIALIZE;

    tokenDelimiters = [[NSCharacterSet whitespaceAndNewlineCharacterSet] retain];
}

- initForDataCursor:(OWDataStreamCursor *)source encoding:(CFStringEncoding)aStringEncoding;
{
    OBPRECONDITION(source);
    
    if (source == nil)
        [NSException raise:NSInvalidArgumentException format:@"-[%@ %@] called with a nil source", NSStringFromClass(isa), NSStringFromSelector(_cmd)];

    if ([super init] == nil)
        return nil;
        
    byteSource = [source retain];
    
    stringBuffer = nil;
    stringEncodingType = se_simple_Foundation;
    [self setCFStringEncoding:aStringEncoding];
    
    return self;
}

- (void)dealloc
{
    [byteSource release];
    [stringBuffer release];
    [super dealloc];
}

- (void)setCFStringEncoding:(CFStringEncoding)newEncoding
{
    [self discardReadahead];
    
    if (newEncoding == kCFStringEncodingInvalidId)
        newEncoding = [OWDataStreamCharacterProcessor defaultStringEncoding];
    
    stringEncoding = newEncoding;
    if (OFCanScanEncoding(newEncoding)) {
        conversionState = OFInitialStateForEncoding(newEncoding);
        if (OFEncodingIsSimple(newEncoding)) {
            stringEncodingType = se_simple_OF;
        } else {
            stringEncodingType = se_complex_OF;
        }
    } else {
        stringEncodingType = se_complex_Foundation;
    }
}

- (CFStringEncoding)stringEncoding
{
    return stringEncoding;
}

- (void)setEncoding:(NSStringEncoding)newEncoding
{
    [self setCFStringEncoding:CFStringConvertNSStringEncodingToEncoding(newEncoding)];
}

- (void)discardReadahead
{
    NSUInteger peekCount = ( stringBuffer ) ? stringBufferValidRange.length : 0;
    NSInteger seekBack;
    
    if (stringEncodingType == se_simple_OF || stringEncodingType == se_complex_OF) {
        if (OFDecoderContainsPartialCharacters(conversionState)) {
            [NSException raise:NSInvalidArgumentException format:@"Unable to discard readahead containing a partial multibyte character"];
        }
    }
    
    switch(stringEncodingType) {
        case se_simple_Foundation:
        case se_simple_OF:
            seekBack = peekCount;
            break;
        case se_complex_OF:
        case se_complex_Foundation:
            if (peekCount > 0) {
                [NSException raise:NSInvalidArgumentException format:@"Unable to discard readahead with multibyte character encoding"];
                /* NOTREACHED */
                seekBack = 0; /* make the compiler happy */
            } else {
                seekBack = 0;
            }
            break;
        default:
            seekBack = 0; /* make the compiler happy */
    }
    
    if (seekBack > 0) {
        [byteSource seekToOffset: -seekBack fromPosition:OWCursorSeekFromCurrent];
    }
    
    [stringBuffer release];
    stringBuffer = nil;
}

- (NSUInteger)seekToOffset:(NSInteger)offset fromPosition:(OWCursorSeekPosition)position;
{
    [self discardReadahead];
    
    if (!(stringEncodingType == se_simple_Foundation ||
          stringEncodingType == se_simple_OF)) {
            /* Can't seek if we're parsing a non-simple encoding, because we don't know how many bytes correspond to a certain number of characters. */
            
            /* NB We could presumably seek for constant-width encodings such as UCS-16, but none of the code that calls us requires that */
            
            [NSException raise:NSInvalidArgumentException format:@"Unable to seek on a %@ using a non-simple character encoding", NSStringFromClass([self class])];
    }
    
    return [byteSource seekToOffset:offset fromPosition:position];
}

- (OWDataStreamCursor *)dataStreamCursor
{
    return [[byteSource retain] autorelease];
}

/* May raise an exception. May return 0 before EOF, if we get some bytes but not a full character's worth. Will return OWDataStreamCharacterCursor_EOF at EOF. */
static inline NSUInteger _getCharacters(OWDataStreamCharacterCursor *self, unichar *characterBuffer, NSUInteger bufferSize, BOOL updateCursorPosition)
{
    struct OFCharacterScanResult decodeResult;
    void *byteBuffer = NULL;
    NSUInteger byteCount;
            
    byteCount = [self->byteSource peekUnderlyingBuffer:&byteBuffer];
    if (!byteCount) {
        return OWDataStreamCharacterCursor_EOF;
    }
    decodeResult = OFScanCharactersIntoBuffer(self->conversionState, (unsigned char *)byteBuffer, byteCount, characterBuffer, bufferSize);
            
    if (updateCursorPosition) {
        [self->byteSource seekToOffset: decodeResult.bytesConsumed fromPosition:OWCursorSeekFromCurrent];
        self->conversionState = decodeResult.state;
    }
            
    return decodeResult.charactersProduced;
}

static inline const char *NameForTECStatus(OSStatus status)
{
    static char numericErrorBuffer[128];

    switch (status) {
        case noErr: return "noErr";
        case kTextUnsupportedEncodingErr: return "kTextUnsupportedEncodingErr";
        case kTextMalformedInputErr: return "kTextMalformedInputErr";
        case kTextUndefinedElementErr: return "kTextUndefinedElementErr";
        case kTECMissingTableErr: return "kTECMissingTableErr";
        case kTECTableChecksumErr: return "kTECTableChecksumErr";
        case kTECTableFormatErr: return "kTECTableFormatErr";
        case kTECCorruptConverterErr: return "kTECCorruptConverterErr";
        case kTECNoConversionPathErr: return "kTECNoConversionPathErr";
        case kTECBufferBelowMinimumSizeErr: return "kTECBufferBelowMinimumSizeErr";
        case kTECArrayFullErr: return "kTECArrayFullErr";
        case kTECPartialCharErr: return "kTECPartialCharErr";
        case kTECUnmappableElementErr: return "kTECUnmappableElementErr";
        case kTECIncompleteElementErr: return "kTECIncompleteElementErr";
        case kTECDirectionErr: return "kTECDirectionErr";
        case kTECGlobalsUnavailableErr: return "kTECGlobalsUnavailableErr";
        case kTECItemUnavailableErr: return "kTECItemUnavailableErr";
        case kTECUsedFallbacksStatus: return "kTECUsedFallbacksStatus";
        case kTECNeedFlushStatus: return "kTECNeedFlushStatus";
        case kTECOutputBufferFullStatus: return "kTECOutputBufferFullStatus";
        default:
            // Not thread safe, but hopefully rarely (if ever) encountered
            sprintf(numericErrorBuffer, "error code %d", (int)status);
            return numericErrorBuffer;
    }
}

static /* inline */ void TestStatus(OSStatus status, CFStringEncoding stringEncoding, const char *functionName)
{
    switch (status) {
        case noErr:
        case kTECUsedFallbacksStatus:
            break; // Success
        default:
            [NSException raise:NSInvalidArgumentException format:@"Character set conversion failed: %s() returned %s (encoding=%@)", functionName, NameForTECStatus(status), CFStringConvertEncodingToIANACharSetName(stringEncoding)];
    }
}

static /* inline */ NSString *OWCreateStringFromData(NSData *data, CFStringEncoding stringEncoding)
{
    OSStatus status;
    TextToUnicodeInfo textToUnicodeInfo;
    ByteCount sourceSize, bufferSize;
    const unsigned char *sourceBytes, *sourceBytesEnd, *input;
    unichar *buffer, *bufferEnd, *output;

    status = CreateTextToUnicodeInfoByEncoding((TextEncoding)stringEncoding, &textToUnicodeInfo);
    TestStatus(status, stringEncoding, "CreateTextToUnicodeInfoByEncoding");

    sourceBytes = [data bytes];
    sourceSize = [data length];
    sourceBytesEnd = sourceBytes + sourceSize;
    bufferSize = sourceSize * 4;
    buffer = malloc(bufferSize);
    bufferEnd = (void *)buffer + bufferSize;

    input = sourceBytes;
    output = buffer;
    do {
        ByteCount inputUsed, outputUsed;

        status = ConvertFromTextToUnicode(
            textToUnicodeInfo, // TextToUnicodeInfo iTextToUnicodeInfo, 
            sourceBytesEnd - input, // ByteCount iSourceLen, 
            input, // ConstLogicalAddress iSourceStr, 
            kUnicodeUseFallbacksBit, // OptionBits iControlFlags, 
            0, // ItemCount iOffsetCount, 
            NULL, // ByteOffset iOffsetArray[], 
            NULL, // ItemCount *oOffsetCount, 
            NULL, // ByteOffset oOffsetArray[], 
            bufferEnd - output, // ByteCount iOutputBufLen, 
            &inputUsed, // ByteCount *oSourceRead, 
            &outputUsed, // ByteCount *oUnicodeLen, 
            output
        );
        input += inputUsed;
        OBASSERT((outputUsed & 0x1) == 0); // Output is UTF-16, so we should have output an even number of bytes
        output += (outputUsed >> 1); // Right-shifting by one bit is the fastest way to divide our byte count by two
        switch (status) {
            case kTextMalformedInputErr:
            case kTECUnmappableElementErr:
#ifdef DEBUG
                NSLog(@"Skipping byte at offset %ld, value %d ('%c'): ConvertFromTextToUnicode() returned %s (encoding=%@)", (long)(input - sourceBytes), (unsigned int)*input, *input, NameForTECStatus(status), CFStringConvertEncodingToIANACharSetName(stringEncoding));
#endif
                input++;
#ifdef MARK_MALFORMED_INPUT
                if (output + 1 <= bufferEnd)
                    *(output++) = OF_UNICODE_REPLACEMENT_CHARACTER;
#endif
                break;
            default:
                TestStatus(status, stringEncoding, "ConvertFromTextToUnicode");
                OBASSERT(input == sourceBytesEnd); // If not, our status code should have indicated this and we should really process more characters
                break;
        }
    } while (input < sourceBytesEnd);
    return (NSString *)CFStringCreateWithCharactersNoCopy(NULL, buffer, output - buffer, NULL);
}

/* Reads to EOF. Will return nil at EOF. */
static inline NSString *_getAllRemainingCharactersRetained(OWDataStreamCharacterCursor *self)
{
    NSData *allData;
    NSString *allCharacters;
    
    OBASSERT(self->stringEncodingType == se_complex_Foundation);
    
    /* The unhappiest encodings of them all are encodings which we don't understand in OmniFoundation and which aren't simple one-to-one mappings of characters and bytes. These encodings cannot be scanned incrementally. Woe, woe are we. */
    allData = [self->byteSource readAllData];
    if (!allData)
        return nil;

    allCharacters = (NSString *)CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, (CFDataRef)allData, self->stringEncoding);
    if (allCharacters == nil)
        allCharacters = OWCreateStringFromData(allData, self->stringEncoding);
    OBASSERT(allCharacters != nil);
    return allCharacters;
}

- (NSUInteger)readCharactersIntoBuffer:(unichar *)buffer maximum:(NSUInteger)bufferSize peek:(BOOL)doNotUpdateCursorPosition
{
    if (abortException)
        [abortException raise];
    
    if (stringEncodingType == se_complex_Foundation &&
        !(stringBuffer && stringBufferValidRange.length > 0)) {
        if (stringBuffer) {
            [stringBuffer release];
            stringBuffer = nil;  /* set stringBuffer in case _get...() raises */
        }
        stringBuffer = _getAllRemainingCharactersRetained(self);
        stringBufferValidRange.location = 0;
        stringBufferValidRange.length = [stringBuffer length];
    }

    if (stringBuffer && stringBufferValidRange.length > 0) {
        if (stringBufferValidRange.length <= bufferSize) {
            [stringBuffer getCharacters:buffer range:stringBufferValidRange];
            if (!doNotUpdateCursorPosition) {
                [stringBuffer release];	
                stringBuffer = nil;
            }
            return stringBufferValidRange.length;
        } else {
            [stringBuffer getCharacters:buffer range:(NSRange){stringBufferValidRange.location, bufferSize}];
            if (!doNotUpdateCursorPosition) {
                stringBufferValidRange.location += bufferSize;
                stringBufferValidRange.length -= bufferSize;
            }
            return bufferSize;
        }
    }
    
    switch (stringEncodingType) {
        case se_simple_OF:
        case se_complex_OF:
        case se_simple_Foundation:
        {
            NSUInteger count = _getCharacters(self, buffer, bufferSize, !doNotUpdateCursorPosition);
            if (count == OWDataStreamCharacterCursor_EOF)
                count = 0;
            return count;
        }
        case se_complex_Foundation:
            return 0; /* this may happen e.g. on a zero-length stream */
    }
    
    /* not reached */
    return 0;
}

/* returns NO if the data stream is already at EOF. May not actually enlarge the stream, but will do some work (possibly less than a full character's worth) */
- (BOOL)_enlargeBufferedString;
{
    NSString *appendix;
    NSString *new;
    
/* This buffer size is chosen so that one page's worth of characters from the underlying data stream (slightly less than 8192 because of header overhead) can be consumed in one gulp. A smaller buffer size would work but would be less efficient. A larger buffer size is unlikely ever to be fully used because of the way OWDataStream works. */
/* [Wiml October2003: The preceding comment is inaccurate; OWDataStream was rearchitected a while back and now can deal with much larger buffers */
#define UNICHAR_BUF_SIZE 8192

    switch (stringEncodingType) {
        case se_simple_OF:
        case se_complex_OF:
        case se_simple_Foundation:
        {
            unichar *characterBuffer;
            NSUInteger characterCount;
            NSZone *localZone = [self zone];
            
            characterBuffer = NSZoneMalloc(localZone, sizeof(unichar) * UNICHAR_BUF_SIZE);

            NS_DURING {
                characterCount = _getCharacters(self, characterBuffer, UNICHAR_BUF_SIZE, YES);
            } NS_HANDLER {
                NSZoneFree(localZone, characterBuffer);
                [localException raise];
                characterCount = OWDataStreamCharacterCursor_EOF; /* NOTREACHED - compiler pacifier */
            } NS_ENDHANDLER;
            
            if (characterCount == OWDataStreamCharacterCursor_EOF)
                return NO;
            
            if (characterCount > 0) {
                appendix = [[NSString allocWithZone:localZone] initWithCharactersNoCopy:characterBuffer length:characterCount freeWhenDone:YES];
            } else {
                NSZoneFree(localZone, characterBuffer);
                appendix = nil;
            }
            
            break;
        }
        default: /* default case to make compiler happy */
        case se_complex_Foundation:
            /* this call can raise an exception, but that's OK */
            appendix = _getAllRemainingCharactersRetained(self);
            /* returns nil at EOF, but a zero-length string before EOF */
            if (appendix == nil)
                return NO;
            break;
    }
    
    if (appendix && [appendix length] > 0) {
        if (stringBuffer && stringBufferValidRange.length > 0) {
            new = [[[stringBuffer substringWithRange:stringBufferValidRange] stringByAppendingString:appendix] retain];
            [appendix release];
        } else {
            new = appendix;
        }
        if (stringBuffer) [stringBuffer release];
        stringBuffer = new;
        stringBufferValidRange.length = [stringBuffer length];
        stringBufferValidRange.location = 0;
    }
    
    return YES;
}

- (NSString *)readString;
{
    NSString *retval;

    if (abortException != nil)
        [abortException raise];
    
    while (!(stringBuffer && stringBufferValidRange.length > 0))
        if (![self _enlargeBufferedString])
            return nil;
    
    if (stringBufferValidRange.location == 0) {
        retval = [stringBuffer autorelease];
        stringBuffer = nil;
    } else {
        retval = [stringBuffer substringWithRange:stringBufferValidRange];
        [stringBuffer release];
        stringBuffer = nil;
    }
        
    return retval;
}

- (NSString *)readAllAsString;
{
#warning TODO - verify this method
    NSString *initial;
    CFMutableStringRef cfBuffer;
    unichar *unicharBuffer;
    const unsigned int unicharBufferLength = 8192;
    NSUInteger charsRead;
    
    if (abortException != nil)
        [abortException raise];

    if (stringBuffer && stringBufferValidRange.length > 0)
        initial = [self readString];
    else
        initial = nil;

    if ([self isAtEOF])
        return initial;

    cfBuffer = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, (CFStringRef)initial);
    unicharBuffer = malloc(sizeof(*unicharBuffer) * unicharBufferLength);
    NS_DURING {
        do {
            charsRead = [self readCharactersIntoBuffer:unicharBuffer maximum:unicharBufferLength peek:NO];
            if (charsRead > 0) {
                OBASSERT(charsRead <= unicharBufferLength);
                CFStringAppendCharacters(cfBuffer, unicharBuffer, charsRead);
            }
        } while (charsRead > 0 || ![self isAtEOF]);
    } NS_HANDLER {
        free(unicharBuffer);
        CFRelease(cfBuffer);
        [localException raise];
    } NS_ENDHANDLER;

    free(unicharBuffer);
    return [(NSMutableString *)cfBuffer autorelease];
}


- (BOOL)isAtEOF;
{
    OBPRECONDITION(byteSource);
    
    if (!byteSource)
        return YES;
    if (stringBuffer && stringBufferValidRange.length > 0)
        return NO;
    
    switch (stringEncodingType) {
        case se_simple_OF:
        case se_complex_OF:
        case se_simple_Foundation:
            /* NB Some encodings may be able to spit out one last character at EOF. None of the ones we implement do, however, so for now this simple logic is OK. */
            return [byteSource isAtEOF];
        default: /* default case to make compiler happy */
        case se_complex_Foundation:
            return ![self _enlargeBufferedString];
    }
}

- (NSString *)readLineAndAdvance:(BOOL)shouldAdvance
{
    NSRange searchRange, crRange = {0, 0}, lfRange, eolRange, lineRange, newValidRange;
    NSString *line;
    /* This is based on the algorithm in the old OWDataStreamCursor method. It will treat isolated LFCR pairs as two line endings, which may or may not be a bug */
    
    while(1) {
        if (abortException)
            [abortException raise];
    
        if (stringBuffer && stringBufferValidRange.length > 0) {
            searchRange = stringBufferValidRange;
            lfRange = [stringBuffer rangeOfString:@"\n" options:0 range:searchRange];
            if (lfRange.length > 0)
                searchRange.length = NSMaxRange(lfRange) - searchRange.location;
            crRange = [stringBuffer rangeOfString:@"\r" options:0 range:searchRange];
            
            if (crRange.length > 0 && lfRange.length > 0) {
                /* Use the earlier of the two ranges, unless the CR immediately precedes the LF, in which case someone somewhere is actually complying with the RFCs, and we should celebrate by correctly interpreting the pair as a newline indicator */
                if (crRange.location < lfRange.location) {
                    if (NSMaxRange(crRange) == lfRange.location) {
                        eolRange.location = crRange.location;
                        eolRange.length = NSMaxRange(lfRange) - eolRange.location;
                    } else
                    eolRange = crRange;
                } else {
                    eolRange = lfRange;
                }
                
                break;
            }
                
            /* If we have an isolated cr or lf, use it. If the cr is the last character in the buffer, don't use it, since the next buffer might contain its lf. */
            if (crRange.length > 0 &&
                NSMaxRange(crRange) < NSMaxRange(stringBufferValidRange)) {
                eolRange = crRange;
                break;
            }
            if (lfRange.length > 0) {
                eolRange = lfRange;
                break;
            }
            
            /* If we reach this point, either we didn't find a CR or LF, or we found a CR that was suspiciously the last character in the buffer. So, try to get some more characters. */
        }
            
        if (![self _enlargeBufferedString]) {
            /* If we've reached the end of the input, return the (possibly unterminated) last line */
            if (stringBuffer && stringBufferValidRange.length > 0) {
                if (crRange.length > 0)
                    eolRange = crRange;
                else
                    eolRange = NSMakeRange(NSMaxRange(stringBufferValidRange), 0);
                break;
            }
            
            /* we've reached the end of the input, and there's no partial line; return EOF */
            return nil;
        }
    }
    
    /* If we reach this point we have a valid eolRange */
    lineRange.location = stringBufferValidRange.location;
    lineRange.length = eolRange.location - lineRange.location;
    
    newValidRange.location = NSMaxRange(eolRange);
    newValidRange.length = NSMaxRange(stringBufferValidRange) - newValidRange.location;
    
    line = [stringBuffer substringWithRange:lineRange];

/*
#define Qq(x) [OWURL encodeURLString:(x) asQuery:YES leaveSlashes:YES leaveColons:YES]

    NSLog(@"Line=[%@], buffer=[%@]", Qq(line), Qq([stringBuffer substringWithRange:NSMakeRange(lineRange.location, MIN(lineRange.location + lineRange.length + 8, newValidRange.location + newValidRange.length) - lineRange.location)]));
*/
    
    if (shouldAdvance)
        stringBufferValidRange = newValidRange;
    
    return line;
}

- (NSString *)readLine;
{
    return [self readLineAndAdvance:YES];
}

- (NSString *)peekLine;
{
    return [self readLineAndAdvance:NO];
}

- (void)skipLine;
{
    [self readLineAndAdvance:YES];
}

- (NSString *)readTokenAndAdvance:(BOOL)shouldAdvance
{
    NSCharacterSet *tokenSet = [tokenDelimiters invertedSet];
    NSRange tokenStartRange = {0, 0}, tokenEndRange, tokenRange;

    do {
        if (abortException)
            [abortException raise];
    
        tokenStartRange.length = 0;
        tokenStartRange.location = 0;
        
        if (stringBuffer) {
            tokenStartRange = [stringBuffer rangeOfCharacterFromSet:tokenSet options:0 range:stringBufferValidRange];
            if (tokenStartRange.length) {
                NSRange restRange;
                restRange.location = NSMaxRange(tokenStartRange);
                restRange.length = NSMaxRange(stringBufferValidRange) - restRange.location;
                tokenEndRange = [stringBuffer rangeOfCharacterFromSet:tokenSet options:0 range:restRange];
                if (tokenEndRange.length)
                    break;
            }
        }
        
        if (![self _enlargeBufferedString]) {
            if (tokenStartRange.length) {
                /* we started a token, then hit EOF. Return the token */
                tokenEndRange = NSMakeRange(NSMaxRange(stringBufferValidRange), 0);
                break;
            } else {
                /* no token found before EOF */
                [OWDataStreamCursor_UnderflowException raise];
            }
        }
    } while(1);
            
    tokenRange.location = tokenStartRange.location;
    tokenRange.length = tokenEndRange.location - tokenStartRange.location;
    
    if (shouldAdvance) {
        NSRange newValidRange;
        
        newValidRange.location = tokenEndRange.location;
        newValidRange.length = NSMaxRange(stringBufferValidRange) - newValidRange.location;
        
        stringBufferValidRange = newValidRange;
    }
    
    return [stringBuffer substringWithRange:tokenRange];
}

- (NSString *)readToken;
{
    return [self readTokenAndAdvance:YES];
}

- (NSString *)peekToken;
{
    return [self readTokenAndAdvance:NO];
}

// - (unsigned int)scanPastString:(NSString *)stringMatch;
#if 0
- (unsigned)scanUntilStringRead:(NSString *){
    NSString *streamBufferString;
    NSRange testRange;

    streamBufferString = _peekDataAsString(self);
    do {
	testRange = [streamBufferString rangeOfString:stringMatch];
	if (testRange.length == 0) {
	    _getMoreData(self);
	    streamBufferString = _peekDataAsString(self);
	}
    } while (testRange.length == 0);

    dataOffset += testRange.location + testRange.length;
    return testRange.location + testRange.length;
}
#endif

// OBObject subclass

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:[OWDataStreamCharacterProcessor charsetForCFEncoding:stringEncoding] forKey:@"stringEncoding"];
    return debugDictionary;
}

@end
