// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSString-OFURLEncoding.h>

#import <OmniFoundation/OFCharacterSet.h>
#import <OmniFoundation/OFStringDecoder.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/NSString-OFUnicodeCharacters.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSString-OFConversion.h>

RCS_ID("$Id$");

/* To set up character set used for deferred string decoding (see OFStringDecoder.[hm]) */
__private_extern__ CFCharacterSetRef OFDeferredDecodingCharacterSet(void);
__private_extern__ unichar OFCharacterForDeferredDecodedByte(unsigned int byte);
__private_extern__ unsigned int OFByteForDeferredDecodedCharacter(unichar uchar);

/* Character sets & variables used for URI encoding */
static OFCharacterSet *AcceptableCharacterSet(void)
{
    static OFCharacterSet *set = nil;
    if (!set)
        set = [[OFCharacterSet alloc] initWithString:@"*-.0123456789@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"];
    return set;
}

static OFCharacterSet *SafeCharacterSet(void)
{
    static OFCharacterSet *set = nil;

    // SafeCharacterSet is approximately the set of characters that may appear in a URI according to RFC2396.  Note that it's a bit different from AcceptableCharacterSet; it has a different purpose.
    if (!set) {
        set = [[OFCharacterSet alloc] initWithString:@"!$%&'()*+,-./0123456789:;=?@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"];
        
        // Note: RFC2396 requires us to escape backslashes, carets, and pipes, which we don't do because this prevents us from interoperating with some web servers which don't correctly decode their requests.  See <bug://bugs/4467>: Should we stop escaping the pipe | char in URLs? (breaks counters, lycos.de).
        [set addCharactersInString:@"\\^|"];
        
    }
    return set;
}

static NSCharacterSet *PercentSignSet(void)
{
    static NSCharacterSet *set = nil;
    if (!set)
        set = [[NSCharacterSet characterSetWithRange:(NSRange){ .location = '%', .length = 1 }] retain];
    return set;
}

static CFStringEncoding urlEncoding = kCFStringEncodingUTF8;

@implementation NSString (OFURLEncoding)

//
// URL encoding
//

+ (void)setURLEncoding:(CFStringEncoding)newURLEncoding;
{
    urlEncoding = newURLEncoding;
    if (urlEncoding == kCFStringEncodingInvalidId)
        urlEncoding = kCFStringEncodingUTF8;
}

+ (CFStringEncoding)urlEncoding
{
    return urlEncoding;
}

static inline unichar hexDigit(unichar digit)
{
    if (isdigit(digit))
	return digit - '0';
    else if (isupper(digit))
	return 10 + digit - 'A';
    else 
	return 10 + digit - 'a';
}

static inline int_fast16_t valueOfHexPair(unichar highNybble, unichar lowNybble)
{
    uint_fast8_t hnValue, lnValue;
    
    static const uint_fast8_t hexValues[103] =
    {
#define XX 0x81   /* Must be distinct from any valid entry. used to use -1, but 0x81 fits in a char. */
        XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,
        XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,
        XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,
        0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,0x88,0x99,  XX,  XX,  XX,  XX,  XX,  XX,
        XX,0xAA,0xBB,0xCC,0xDD,0xEE,0xFF,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,
        XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,  XX,
        XX,0xAA,0xBB,0xCC,0xDD,0xEE,0xFF
    };
    
    if (highNybble > 'f' || lowNybble > 'f')
        return -1;
    
    hnValue = hexValues[highNybble];
    lnValue = hexValues[lowNybble];
    if (hnValue == XX || lnValue == XX)
        return -1;
#undef XX
    return ( hnValue & 0xF0 ) | ( lnValue & 0x0F );
}


static NSString *hexPairReplacer(NSString *string, NSRange *pairRange, void *context)
{
    if ([string length] <= (pairRange->location + 2))
        return nil;
    
    unichar digit1 = [string characterAtIndex:pairRange->location+1];
    unichar digit2 = [string characterAtIndex:pairRange->location+2];
    int hexValue = valueOfHexPair(digit1, digit2);
    if (hexValue != -1) {
        pairRange->length = 3;
        return [NSString stringWithCharacter:OFCharacterForDeferredDecodedByte(hexValue)];
    }
    return nil;
}

static NSString *hexPairInserter(NSString *string, NSRange *defRange, void *context)
{
    unichar deferential = [string characterAtIndex:defRange->location];
    defRange->length = 1;
    return [NSString stringWithFormat:@"%%02X", OFByteForDeferredDecodedCharacter(deferential)];
}

+ (NSString *)decodeURLString:(NSString *)encodedString encoding:(CFStringEncoding)thisUrlEncoding;
{
    NSString *decodedString;
    
    if (!encodedString)
        return nil;
    
    /* Optimize for the common case */
    if ([encodedString rangeOfString:@"%"].location == NSNotFound)
        return encodedString;
    
    decodedString = [encodedString stringByPerformingReplacement:hexPairReplacer onCharacters:PercentSignSet() context:NULL options:0 range:(NSRange){0, [encodedString length]}];
    
    if (thisUrlEncoding == kCFStringEncodingInvalidId)
        thisUrlEncoding = urlEncoding;
    
    decodedString = OFMostlyApplyDeferredEncoding(decodedString, thisUrlEncoding);
    
    return [decodedString stringByPerformingReplacement:hexPairInserter onCharacters:(NSCharacterSet *)OFDeferredDecodingCharacterSet() context:NULL options:0 range:(NSRange){0, [decodedString length]}];
}

+ (NSString *)decodeURLString:(NSString *)encodedString;
{
    return [self decodeURLString:encodedString encoding:urlEncoding];
}

- (NSData *)dataUsingCFEncoding:(CFStringEncoding)anEncoding allowLossyConversion:(BOOL)lossy hexEscapes:(NSString *)escapePrefix;
{
    unsigned int stringLength = [self length];
    if (stringLength == 0)
        return [NSData data];
    
    NSMutableData *buffer = nil;
    NSRange remaining = NSMakeRange(0, stringLength);
    while (remaining.length > 0) {
        NSRange prefix;
        CFRange escapelessRange;
        CFDataRef appendage;
        
        if (1) {
            prefix = [self rangeOfString:escapePrefix options:0 range:remaining];
        } else {
        continueAndSkipBogusEscapePrefix:
            prefix = [self rangeOfString:escapePrefix options:0 range:(NSRange){ remaining.location + 1, remaining.length - 1}];
        }
        
        escapelessRange.location = remaining.location;
        if (prefix.length == 0)
            escapelessRange.length = remaining.length;
        else
            escapelessRange.length = prefix.location - escapelessRange.location;
        remaining.length -= escapelessRange.length;
        remaining.location += escapelessRange.length;
        
        if (escapelessRange.length > 0) {
            appendage = OFCreateDataFromStringWithDeferredEncoding((CFStringRef)self, escapelessRange, anEncoding, lossy?'?':0);
            if (buffer == nil && remaining.length == 0)
                return [(NSData *)appendage autorelease];
            else if (buffer == nil)
                buffer = [[(NSData *)appendage mutableCopy] autorelease];
            else
                [buffer appendData:(NSData *)appendage];
            CFRelease(appendage);
        } else if (buffer == nil) {
            buffer = [NSMutableData data];
        }
        
        if (prefix.length > 0) {
            unichar highNybble, lowNybble;
            int byteValue;
            unsigned char buf[1];
            
            if (prefix.length+2 > remaining.length)
                goto continueAndSkipBogusEscapePrefix;
            
            highNybble = [self characterAtIndex: NSMaxRange(prefix)];
            lowNybble =  [self characterAtIndex: NSMaxRange(prefix)+1];
            byteValue = valueOfHexPair(highNybble, lowNybble);
            if (byteValue < 0)
                goto continueAndSkipBogusEscapePrefix;
            buf[0] = byteValue;
            [buffer appendBytes:buf length:1];
            
            remaining.location += prefix.length+2;
            remaining.length   -= prefix.length+2;
        }
    }
    
    return buffer;
}

static inline unichar hex(int i)
{
    static const char hexDigits[16] = {
        '0', '1', '2', '3', '4', '5', '6', '7',
        '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'
    };
    
    return (unichar)hexDigits[i];
}

+ (NSString *)encodeURLString:(NSString *)unencodedString asQuery:(BOOL)asQuery leaveSlashes:(BOOL)leaveSlashes leaveColons:(BOOL)leaveColons;
{
    return [self encodeURLString:unencodedString encoding:urlEncoding asQuery:asQuery leaveSlashes:leaveSlashes leaveColons:leaveColons];
}

#define USE_GENERIC_QP_DECODER 0

#if USE_GENERIC_QP_DECODER

#define EIGHT_OF(x) x,x,x,x,x,x,x,x
#define ONE_HUNDRED_TWENTY_EIGHT_OF(x)  EIGHT_OF(EIGHT_OF(x,x)) 

#define TEMPLATE(S,C,V) {	\
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,       /* 0x control characters	*/ \
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,       /* 1x control characters	*/ \
S,1,1,1,1,1,1,1,1,1,0,1,1,0,0,V,	   /* 2x   !"#$%&'()*+,-./	*/ \
0,0,0,0,0,0,0,0,0,0,C,1,1,1,1,1,	   /* 3x  0123456789:;<=>?	*/ \
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,	   /* 4x  @ABCDEFGHIJKLMNO	*/ \
0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,	   /* 5X  PQRSTUVWXYZ[\]^_	*/ \
1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,	   /* 6x  `abcdefghijklmno	*/ \
0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,	   /* 7X  pqrstuvwxyz{|}~  DEL	*/ \
ONE_HUNDRED_TWENTY_EIGHT_OF(1)         /* 8x through FF       	*/ \
}

static const OFQuotedPrintableMapping urlCodingVariants[8] = {
{ TEMPLATE(1,1,1), { '%', '+' } },
{ TEMPLATE(1,1,0), { '%', '+' } },
{ TEMPLATE(1,0,1), { '%', '+' } },
{ TEMPLATE(1,0,0), { '%', '+' } },
{ TEMPLATE(2,1,1), { '%', '+' } },
{ TEMPLATE(2,1,0), { '%', '+' } },
{ TEMPLATE(2,0,1), { '%', '+' } },
{ TEMPLATE(2,0,0), { '%', '+' } }
};

#endif  /* USE_GENERIC_QP_DECODER */

+ (NSString *)encodeURLString:(NSString *)unencodedString encoding:(CFStringEncoding)thisUrlEncoding asQuery:(BOOL)asQuery leaveSlashes:(BOOL)leaveSlashes leaveColons:(BOOL)leaveColons;
{
    // TJW: This line here is why these are class methods, not instance methods.  If these were instance methods, we wouldn't do this check and would get a nil instead.  Maybe later this can be revisited.
    if (unencodedString == nil)
	return @"";
    
    // This is actually a pretty common occurrence
    if (![unencodedString containsCharacterInOFCharacterSet:AcceptableCharacterSet()])
        return unencodedString;
    
    if (thisUrlEncoding == kCFStringEncodingInvalidId)
        thisUrlEncoding = urlEncoding;
    NSData *sourceData = [unencodedString dataUsingCFEncoding:thisUrlEncoding allowLossyConversion:YES];
    
#if USE_GENERIC_QP_DECODER
    
    int variantIndex = ( asQuery ? 4 : 0 ) | ( leaveColons ? 2 : 0 ) | ( leaveSlashes ? 1 : 0 );
    NSString *escapedString = [sourceData quotedPrintableStringWithMapping:&(urlCodingVariants[variantIndex]) lengthHint:0];
    
#else
    
    unsigned const char *sourceBuffer = [sourceData bytes];
    int sourceLength = [sourceData length];
    
    int destinationBufferSize = sourceLength + (sourceLength >> 2) + 12;
    unichar *destinationBuffer = NSZoneMalloc(NULL, (destinationBufferSize) * sizeof(unichar));
    int destinationIndex = 0;
    
    int sourceIndex;
    for (sourceIndex = 0; sourceIndex < sourceLength; sourceIndex++) {
	unsigned char ch;
	
	ch = sourceBuffer[sourceIndex];
	
	if (destinationIndex >= destinationBufferSize - 3) {
	    destinationBufferSize += destinationBufferSize >> 2;
	    destinationBuffer = NSZoneRealloc(NULL, destinationBuffer, (destinationBufferSize) * sizeof(unichar));
	}
	
        if (OFCharacterSetHasMember(AcceptableCharacterSet(), ch)) {
	    destinationBuffer[destinationIndex++] = ch;
	} else if (asQuery && ch == ' ') {
	    destinationBuffer[destinationIndex++] = '+';
	} else if (leaveSlashes && ch == '/') {
	    destinationBuffer[destinationIndex++] = '/';
	} else if (leaveColons && ch == ':') {
	    destinationBuffer[destinationIndex++] = ':';
	} else {
	    destinationBuffer[destinationIndex++] = '%';
	    destinationBuffer[destinationIndex++] = hex((ch & 0xF0) >> 4);
	    destinationBuffer[destinationIndex++] = hex(ch & 0x0F);
	}
    }
    
    NSString *escapedString = [[[NSString alloc] initWithCharactersNoCopy:destinationBuffer length:destinationIndex freeWhenDone:YES] autorelease];
    
#endif
    
    return escapedString;
}


- (NSString *)fullyEncodeAsIURI;
{
    NSData *utf8BytesData;
    NSString *resultString;
    const unsigned char *sourceBuffer;
    unsigned char *destinationBuffer;
    int destinationBufferUsed, destinationBufferSize;
    int sourceBufferIndex, sourceBufferSize;
    
    if (![self containsCharacterInOFCharacterSet:SafeCharacterSet()])
        return [[self copy] autorelease];
    
    utf8BytesData = [self dataUsingCFEncoding:kCFStringEncodingUTF8 allowLossyConversion:NO];
    sourceBufferSize = [utf8BytesData length];
    sourceBuffer = [utf8BytesData bytes];
    
    destinationBufferSize = sourceBufferSize;
    if (destinationBufferSize < 20)
        destinationBufferSize *= 3;
    else
        destinationBufferSize += ( destinationBufferSize >> 1 );
    
    destinationBuffer = NSZoneMalloc(NULL, destinationBufferSize);
    destinationBufferUsed = 0;
    
    for (sourceBufferIndex = 0; sourceBufferIndex < sourceBufferSize; sourceBufferIndex++) {
        unsigned char ch = sourceBuffer[sourceBufferIndex];
        
        // Headroom: we may insert up to three bytes into destinationBuffer.
        if (destinationBufferUsed + 3 >= destinationBufferSize) {
            int newSize = destinationBufferSize + ( destinationBufferSize >> 1 );
            destinationBuffer = NSZoneRealloc(NULL, destinationBuffer, newSize);
            destinationBufferSize = newSize;
        }
        
        if (OFCharacterSetHasMember(SafeCharacterSet(), ch)) {
            destinationBuffer[destinationBufferUsed++] = ch;
        } else {
            destinationBuffer[destinationBufferUsed++] = '%';
            destinationBuffer[destinationBufferUsed++] = hex((ch & 0xF0) >> 4);
            destinationBuffer[destinationBufferUsed++] = hex( ch & 0x0F      );
        }
    }
    
    resultString = (NSString *)CFStringCreateWithBytes(kCFAllocatorDefault, destinationBuffer, destinationBufferUsed, kCFStringEncodingASCII, FALSE);
    NSZoneFree(NULL, destinationBuffer);
    
    return [resultString autorelease];
}

- (NSString *)fullyEncodeAsIURIReference;
{
    NSArray *stringsSeparatedByNumberSign = [self componentsSeparatedByString:@"#"];
    NSMutableString *encodedString = [[NSMutableString alloc] init];
    unsigned int stringsSeparatedByNumberSignCount = 0;
    for (stringsSeparatedByNumberSignCount = 0; stringsSeparatedByNumberSignCount < [stringsSeparatedByNumberSign count]; stringsSeparatedByNumberSignCount++) {
	if (stringsSeparatedByNumberSignCount > 0)
	    [encodedString appendString:@"#"];
	
	NSString *nextSegment = [stringsSeparatedByNumberSign objectAtIndex:stringsSeparatedByNumberSignCount];
	NSString *nextSegmentEncoded = [nextSegment fullyEncodeAsIURI];
	[encodedString appendString:nextSegmentEncoded];
    }
    
    return [encodedString autorelease];
}

@end
