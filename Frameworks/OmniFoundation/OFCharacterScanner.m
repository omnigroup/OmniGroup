// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFCharacterScanner.h>

#import <OmniFoundation/OFStringDecoder.h>

RCS_ID("$Id$")

@implementation OFCharacterScanner

const unichar OFCharacterScannerEndOfDataCharacter = '\0';
static OFCharacterSet *endOfLineSet;

// Inlines used when scanning decimal numbers.  We may want to extend these to full Unicode digit support instead of just ASCII.
static inline int unicharIsDecimalDigit(unichar c)
{
    return c >= '0' && c <= '9';
}

static inline int unicharDigitValue(unichar c)
{
    return c - '0';
}


+ (void)initialize;
{
    OBINITIALIZE;

    endOfLineSet = [[OFCharacterSet alloc] initWithString:@"\r\n"];
}

- init;
{
    if ([super init] == nil)
	return nil;

    inputBuffer = NULL;
    scanEnd = inputBuffer;
    scanLocation = scanEnd;
    inputStringPosition = 0;
#define firstNonASCIIOffsetSentinel (~(NSUInteger)0)
    firstNonASCIIOffset = firstNonASCIIOffsetSentinel;
    OFCaseConversionBufferInit(&caseBuffer);
    
    return self;
}

- (void)dealloc;
{
    if (freeInputBuffer) {
        OBASSERT(inputBuffer != NULL);
        NSZoneFree(NULL, inputBuffer);
    }
    OFCaseConversionBufferDestroy(&caseBuffer);
    [super dealloc];
}


// Declared methods

/* This is called by the Scanner when it needs a new bufferful of data. Default implementation is to return NO, which indicates EOF. */
- (BOOL)fetchMoreData;
{
    return NO;
}

/* Calls -fetchMoreDataFromCharacters:length:freeWhenDone: with the contents of the inputString */
- (BOOL)fetchMoreDataFromString:(NSString *)inputString;
{
    NSUInteger length;
    unichar *newBuffer = NULL;

    length = [inputString length];
    if (length)
        newBuffer = NSZoneMalloc(NULL, sizeof(unichar) * length);
    [inputString getCharacters:newBuffer];
    return [self fetchMoreDataFromCharacters:newBuffer length:length offset:inputStringPosition + (scanEnd - inputBuffer) freeWhenDone:YES];
}

- (BOOL)fetchMoreDataFromCharacters:(unichar *)characters length:(NSUInteger)length offset:(NSUInteger)offset freeWhenDone:(BOOL)doFreeWhenDone;
{
    NSUInteger oldScanPosition;

    oldScanPosition = inputStringPosition + (scanLocation - inputBuffer);
    OBASSERT(characters != NULL || length == 0);
    OBASSERT(offset <= oldScanPosition);
    OBASSERT(offset + length >= oldScanPosition || length == 0); // The old scan position may be past the end of all available data (if the user peeked at end-of-data characters and skipped past them), but if so we shouldn't be fetching any more bytes

    if (freeInputBuffer) {
        OBASSERT(inputBuffer != NULL);
        NSZoneFree(NULL, inputBuffer);
    }
    freeInputBuffer = doFreeWhenDone;

    inputStringPosition = offset;

    if (characters == NULL || length == 0) {
        inputBuffer = NULL;
        scanEnd = NULL;
        scanLocation = NULL;
        freeInputBuffer = NO;
        return NO;
    } else {
        if (firstNonASCIIOffset == firstNonASCIIOffsetSentinel) {
            unichar *charactersPtr;
            unichar *charactersEnd = characters + length;
            
            for (charactersPtr = characters; charactersPtr < charactersEnd; charactersPtr++) {
                if (*charactersPtr >= 127) {
                    firstNonASCIIOffset = (charactersPtr - characters) + offset;
                    break;
                }
            }
        }
        
        inputBuffer = characters;
        scanLocation = inputBuffer + (oldScanPosition - inputStringPosition);
        scanEnd = inputBuffer + length;
        return YES;
    }
}

- (void)_rewindCharacterSource
{
    /* This should not happen if the caller is using -setRewindMark, etc. */
    [NSException raise:OFCharacterConversionExceptionName format:@"Attempt to rewind a nonrewindable stream"];
}

- (unichar)peekCharacter;
{
    return scannerPeekCharacter(self);
}

- (void)skipPeekedCharacter;
{
    scannerSkipPeekedCharacter(self);
}

- (unichar)readCharacter;
{
    return scannerReadCharacter(self);
}

- (void)setRewindMark;
{
    // We only have so much room for marks.  In particular, don't try to call this method recursively, it's just not designed for that.
    OBPRECONDITION(rewindMarkCount < OFMaximumRewindMarks);
    // We should never be setting a mark that is earlier in the file than the existing marks
    OBPRECONDITION(rewindMarkCount == 0 || rewindMarkOffsets[rewindMarkCount-1] <= scannerScanLocation(self));

    rewindMarkOffsets[rewindMarkCount++] = scannerScanLocation(self);
}
    
- (void)rewindToMark;
{
    OBPRECONDITION(rewindMarkCount > 0);
    if (rewindMarkCount == 0)
        [NSException raise:OFCharacterConversionExceptionName format:@"Attempt to use nonexistent rewind mark"];
    
    [self setScanLocation:rewindMarkOffsets[rewindMarkCount-1]];
    rewindMarkCount--;
}

- (void)discardRewindMark;
{
    OBPRECONDITION(rewindMarkCount > 0);
    if (rewindMarkCount > 0)
        rewindMarkCount--;
}

- (NSUInteger)scanLocation;
{
    return scannerScanLocation(self);
}

- (void)setScanLocation:(NSUInteger)aLocation;
{
    // You are only allowed to set the new scan location to be between the most recent rewind mark and EOF, or the current position and EOF if there are no rewind marks
    OBPRECONDITION(aLocation >= scannerScanLocation(self) || (rewindMarkCount > 0 && aLocation >= rewindMarkOffsets[rewindMarkCount-1]));
    if (aLocation < scannerScanLocation(self) && (rewindMarkCount == 0 || aLocation < rewindMarkOffsets[rewindMarkCount-1]))
        [NSException raise:OFCharacterConversionExceptionName format:@"You are only allowed to set the new scan location to be between the most recent rewind mark and EOF, or the current position and EOF if there are no rewind marks."];

    if (aLocation >= inputStringPosition) {
	NSUInteger inputLocation = aLocation - inputStringPosition;
	if (inputLocation <= (unsigned)(scanEnd - inputBuffer)) {
	   scanLocation = inputBuffer + inputLocation;
           return;
        }
    }
    
    scanEnd = inputBuffer;
    scanLocation = scanEnd;
    inputStringPosition = aLocation;
    [self _rewindCharacterSource];
}

- (void)skipCharacters:(int)anOffset;
{
    if ( (scanLocation + anOffset < inputBuffer) ||
         (scanLocation + anOffset >= scanEnd) ) {
	[self setScanLocation:(scanLocation - inputBuffer) + anOffset + inputStringPosition];
    } else {
        scanLocation += anOffset;
    }
}

- (BOOL)hasScannedNonASCII;
{
    if (firstNonASCIIOffset != firstNonASCIIOffsetSentinel && firstNonASCIIOffset < scannerScanLocation(self))
        return YES;
    else
        return NO;
}

- (BOOL)scanUpToCharacter:(unichar)aCharacter;
{
    return scannerScanUpToCharacter(self, aCharacter);
}

- (BOOL)scanUpToCharacterInSet:(NSCharacterSet *)delimiterCharacterSet;
{
    return scannerScanUpToCharacterInSet(self, delimiterCharacterSet);
}    

#define SAFE_ALLOCA_SIZE (8 * 8192)

// Returns YES if the string is found, NO otherwise. Positions the scanner immediately before the pattern string, or at the end of the input string, depending.

- (BOOL)scanUpToString:(NSString *)delimiterString;
{
    unichar *buffer, *ptr;
    NSUInteger length;
    BOOL stringFound;
    BOOL useMalloc;

    length = [delimiterString length];
    if (length == 0)
        return YES;

    stringFound = NO;
    useMalloc = length * sizeof(unichar) >= SAFE_ALLOCA_SIZE;
    if (useMalloc) {
        buffer = (unichar *)NSZoneMalloc(NULL, length * sizeof(unichar));
    } else {
        buffer = (unichar *)alloca(length * sizeof(unichar));
    }
    [delimiterString getCharacters:buffer];
    while (scannerScanUpToCharacter(self, *buffer)) {
        int left;

        ptr = buffer;
        left = length;
        [self setRewindMark];
        while (left--) {
            if (scannerPeekCharacter(self) != *ptr++) {
                break;
            }
            scannerSkipPeekedCharacter(self);
        }
        [self rewindToMark];
        if (left == -1) {
            stringFound = YES;
            break;
        } else {
            scannerSkipPeekedCharacter(self);
        }
    }

    if (useMalloc)
        NSZoneFree(NULL, buffer);

    return stringFound;
}

//#warning This breaks when [string lowercaseString] or [string uppercaseString] change string length
// ...which it does in Unicode in some cases.
// ...except that CoreFoundation and Foundation don't support this behavior
// ...although their APIs suggest they might in the future
- (BOOL)scanUpToStringCaseInsensitive:(NSString *)delimiterString;
{
    unichar *lowerBuffer, *upperBuffer;
    NSUInteger length;
    BOOL stringFound;
    BOOL useMalloc;
    OFCharacterSet *delimiterOFCharacterSet;

    length = [delimiterString length];
    if (length == 0)
        return YES;

    stringFound = NO;
    useMalloc = length * sizeof(unichar) >= SAFE_ALLOCA_SIZE;
    if (useMalloc) {
        lowerBuffer = (unichar *)NSZoneMalloc(NULL, length * sizeof(unichar));
        upperBuffer = (unichar *)NSZoneMalloc(NULL, length * sizeof(unichar));
    } else {
        lowerBuffer = (unichar *)alloca(length * sizeof(unichar));
        upperBuffer = (unichar *)alloca(length * sizeof(unichar));
    }
    [[delimiterString lowercaseString] getCharacters:lowerBuffer];
    [[delimiterString uppercaseString] getCharacters:upperBuffer];
    delimiterOFCharacterSet = [[OFCharacterSet alloc] init];
    [delimiterOFCharacterSet addCharacter:*lowerBuffer];
    [delimiterOFCharacterSet addCharacter:*upperBuffer];

    while (scannerScanUpToCharacterInOFCharacterSet(self, delimiterOFCharacterSet)) {
        unichar *lowerPtr = lowerBuffer;
        unichar *upperPtr = upperBuffer;
        NSUInteger left = length;
        
        [self setRewindMark];
        stringFound = YES;
        while (left--) {
            unichar currentCharacter;

            currentCharacter = scannerPeekCharacter(self);
            if ((currentCharacter != *lowerPtr) && (currentCharacter != *upperPtr)) {
                stringFound = NO;
                break;
            }
            scannerSkipPeekedCharacter(self);
            lowerPtr++;
            upperPtr++;
        }
        [self rewindToMark];
        if (stringFound) {
            break;
        } else {
            scannerSkipPeekedCharacter(self);
        }
    }
    [delimiterOFCharacterSet release];
    if (useMalloc) {
        NSZoneFree(NULL, lowerBuffer);
        NSZoneFree(NULL, upperBuffer);
    }

    return stringFound;
}

static inline NSString *
readTokenFragmentWithDelimiterCharacter(
    OFCharacterScanner *self,
    unichar character)
{
    unichar *startLocation;

    if (!scannerHasData(self))
        return nil;
    startLocation = self->scanLocation;
    while (self->scanLocation < self->scanEnd) {
        if (character == *self->scanLocation)
            break;
        self->scanLocation++;
    }
    return [NSString stringWithCharacters:startLocation length:self->scanLocation - startLocation];
}

- (NSString *)readTokenFragmentWithDelimiterCharacter:(unichar)character;
{
    return readTokenFragmentWithDelimiterCharacter(self, character);
}

static inline NSString *
readRetainedTokenFragmentWithDelimiterOFCharacterSet(OFCharacterScanner *self, OFCharacterSet *delimiterOFCharacterSet, BOOL forceLowercase)
{
    unichar *startLocation;
    
    if (!scannerHasData(self))
	return nil;
    startLocation = self->scanLocation;
    while (self->scanLocation < self->scanEnd) {
	if (OFCharacterSetHasMember(delimiterOFCharacterSet, *self->scanLocation))
	    break;
	self->scanLocation++;
    }

    NSUInteger length = self->scanLocation - startLocation;
    if (length == 0)
        return nil;
        
    if (forceLowercase) {
        return (NSString *)OFCreateStringByLowercasingCharacters(&self->caseBuffer, startLocation, length);
    } else {
        return (NSString *)CFStringCreateWithCharacters(kCFAllocatorDefault, startLocation, length);
    }
}

- (NSString *)readTokenFragmentWithDelimiterOFCharacterSet:(OFCharacterSet *)delimiterOFCharacterSet;
{
    return [readRetainedTokenFragmentWithDelimiterOFCharacterSet(self, delimiterOFCharacterSet, NO) autorelease];
}

- (NSString *)readTokenFragmentWithDelimiters:(NSCharacterSet *)delimiterCharacterSet;
{
    OFCharacterSet *delimiterOFCharacterSet;
    
    if (!scannerHasData(self))
	return nil;
    delimiterOFCharacterSet = [[[OFCharacterSet alloc] initWithCharacterSet:delimiterCharacterSet] autorelease];
    return [readRetainedTokenFragmentWithDelimiterOFCharacterSet(self, delimiterOFCharacterSet, NO) autorelease];
}

#ifdef OF_COLLECT_CHARACTER_SCANNER_STATS
struct {
    unsigned int calls;
    unsigned int nils;
    unsigned int fragments;
    unsigned int appends;
    unsigned int lowers;
} OFCharacterScannerStats;
#define INCREMENT_STAT(x) OFCharacterScannerStats.x++
#else
#define INCREMENT_STAT(x)
#endif

static inline NSString *
readFullTokenWithDelimiterOFCharacterSet(OFCharacterScanner *self, OFCharacterSet *delimiterOFCharacterSet, BOOL forceLowercase)
{
    NSString *resultString = nil, *fragment;

    INCREMENT_STAT(calls);
    
    if (!scannerHasData(self)) {
        INCREMENT_STAT(nils);
	return nil;
    }
    
    do {
	fragment = readRetainedTokenFragmentWithDelimiterOFCharacterSet(self, delimiterOFCharacterSet, forceLowercase);
	if (!fragment)
	    break;
            
        INCREMENT_STAT(fragments);
        
        if (resultString) {
            // this case should be uncommon
            NSString *old = resultString;

            INCREMENT_STAT(appends);

            resultString = [[old stringByAppendingString:fragment] retain];
            [old release];
            [fragment release];
        } else {
            resultString = fragment;
        }
    } while (!OFCharacterSetHasMember(delimiterOFCharacterSet, scannerPeekCharacter(self)));

    return [resultString autorelease];
}

- (NSString *)readFullTokenWithDelimiterOFCharacterSet:(OFCharacterSet *)delimiterOFCharacterSet forceLowercase:(BOOL)forceLowercase;
{
    return readFullTokenWithDelimiterOFCharacterSet(self, delimiterOFCharacterSet, forceLowercase);
}

- (NSString *)readFullTokenWithDelimiterOFCharacterSet:(OFCharacterSet *)delimiterOFCharacterSet;
{
    return readFullTokenWithDelimiterOFCharacterSet(self, delimiterOFCharacterSet, NO);
}

static inline NSString *
readFullTokenWithDelimiterCharacter(OFCharacterScanner *self, unichar delimiterCharacter, BOOL forceLowercase)
{
    NSString *resultString = nil, *fragment;

    if (!scannerHasData(self))
	return nil;
    do {
	fragment = readTokenFragmentWithDelimiterCharacter(self, delimiterCharacter);
	if (!fragment)
	    break;
	if (resultString)
	    resultString = [resultString stringByAppendingString:fragment];
	else
	    resultString = fragment;
    } while (delimiterCharacter != scannerPeekCharacter(self));

    if (forceLowercase && resultString)
	resultString = [resultString lowercaseString];
    return resultString;
}

- (NSString *)readFullTokenWithDelimiterCharacter:(unichar)delimiterCharacter forceLowercase:(BOOL)forceLowercase;
{
    return readFullTokenWithDelimiterCharacter(self, delimiterCharacter, forceLowercase);
}

- (NSString *)readFullTokenWithDelimiterCharacter:(unichar)delimiterCharacter;
{
    return readFullTokenWithDelimiterCharacter(self, delimiterCharacter, NO);
}

- (NSString *)readFullTokenWithDelimiters:(NSCharacterSet *)delimiterCharacterSet forceLowercase:(BOOL)forceLowercase;
{
    OFCharacterSet *delimiterOFCharacterSet;

    if (!scannerHasData(self))
	return nil;
    delimiterOFCharacterSet = [[[OFCharacterSet alloc] initWithCharacterSet:delimiterCharacterSet] autorelease];
    return readFullTokenWithDelimiterOFCharacterSet(self, delimiterOFCharacterSet, forceLowercase);
}

- (NSString *)readFullTokenOfSet:(NSCharacterSet *)tokenSet;
{
    return [self readFullTokenWithDelimiters:[tokenSet invertedSet] forceLowercase:NO];
}

- (NSString *)readFullTokenUpToString:(NSString *)delimiterString;
{
    NSUInteger endOfReturnedStringLocation;
    
    [self setRewindMark];
    [self scanUpToString:delimiterString];
    endOfReturnedStringLocation = scannerScanLocation(self);
    [self rewindToMark];
    return [self readCharacterCount:endOfReturnedStringLocation - scannerScanLocation(self)];
}

- (NSString *)readLine;
{
    NSString *line;

    if (!scannerHasData(self))
        return nil;
    line = readFullTokenWithDelimiterOFCharacterSet(self, endOfLineSet, NO);
    if (scannerPeekCharacter(self) == '\r')
	scannerSkipPeekedCharacter(self);
    if (scannerPeekCharacter(self) == '\n')
	scannerSkipPeekedCharacter(self);
    return line != nil ? line : @"";
}

- (NSString *)readCharacterCount:(NSUInteger)count;
{
    NSUInteger bufferedCharacterCount;

    bufferedCharacterCount = scanEnd - scanLocation;
    if (count <= bufferedCharacterCount) {
        NSString *result;

        result = [NSString stringWithCharacters:scanLocation length:count];
	scanLocation += count;
	return result;
    } else {
        NSMutableString *result;
        NSUInteger charactersNeeded;

        result = [NSMutableString string];
        charactersNeeded = count;
        do {
            NSString *substring;

            substring = [[NSString alloc] initWithCharactersNoCopy:scanLocation length:bufferedCharacterCount freeWhenDone:NO];
            [result appendString:substring];
            [substring release];
            charactersNeeded -= bufferedCharacterCount;
            if (![self fetchMoreData])
                return nil;
            bufferedCharacterCount = scanEnd - scanLocation;
        } while (charactersNeeded > bufferedCharacterCount);
        if (charactersNeeded > 0) {
            NSString *substring;

            substring = [[NSString alloc] initWithCharactersNoCopy:scanLocation length:charactersNeeded freeWhenDone:NO];
            [result appendString:substring];
            [substring release];
            scanLocation += charactersNeeded;
        }
        OBASSERT([result length] == count);
        return result;
   }
}

- (unsigned int)scanHexadecimalNumberMaximumDigits:(unsigned int)maximumDigits;
{
    unsigned int resultInt = 0;

    while (maximumDigits-- > 0) {
        unichar nextCharacter;

        nextCharacter = scannerPeekCharacter(self);
        if (nextCharacter >= '0' && nextCharacter <= '9') {
            scannerSkipPeekedCharacter(self);
            resultInt = resultInt * 16 + (nextCharacter - '0');
        } else if (nextCharacter >= 'a' && nextCharacter <= 'f') {
            scannerSkipPeekedCharacter(self);
            resultInt = resultInt * 16 + (nextCharacter - 'a') + 10;
        } else if (nextCharacter >= 'A' && nextCharacter <= 'F') {
            scannerSkipPeekedCharacter(self);
            resultInt = resultInt * 16 + (nextCharacter - 'A') + 10;
        } else
            break;
    }
    return resultInt;
}

- (unsigned int)scanUnsignedIntegerMaximumDigits:(unsigned int)maximumDigits;
{
    unsigned int resultInt = 0;

    while (maximumDigits-- > 0) {
        unichar nextCharacter;

        nextCharacter = scannerPeekCharacter(self);
        if (unicharIsDecimalDigit(nextCharacter)) {
            scannerSkipPeekedCharacter(self);
            resultInt = resultInt * 10 + unicharDigitValue(nextCharacter);
        } else
            break;
    }
    return resultInt;
}

- (int)scanIntegerMaximumDigits:(unsigned int)maximumDigits;
{
    int sign = 1;

    switch (scannerPeekCharacter(self)) {
        case '-':
            sign = -1;
            // no break
        case '+':
            scannerSkipPeekedCharacter(self);
            break;
        default:
            break;
    }
    return sign * (int)[self scanUnsignedIntegerMaximumDigits:maximumDigits];
}

- (BOOL)scanDouble:(double *)outValue maximumLength:(unsigned int)maximumLength exponentLength:(unsigned int)maximumExponentLength
{
    unichar initialSign = 0;
    unichar exponentSign = 0;
    unichar peek;
    unsigned int mantissaDigits, postDecimalDigits;
    BOOL sawDecimal;
    double mantissa;
    int exponent;

    [self setRewindMark];
    
    peek = scannerPeekCharacter(self);
    if (peek == '-' || peek == '+') {
        initialSign = peek;
        scannerSkipPeekedCharacter(self);
        maximumLength --;
        peek = scannerPeekCharacter(self);
    }
    
    // Read the mantissa, possibly with one embedded decimal point. Keep track of the number of digits, and the number of those which were after the d.p. (if any).
    mantissa = 0;
    mantissaDigits = 0;
    sawDecimal = NO;
    postDecimalDigits = 0;
    while((unicharIsDecimalDigit(peek) || (!sawDecimal && peek == '.'))
          && maximumLength > 0) {
        if(peek == '.') {
            sawDecimal = YES;
        } else {
            mantissa = 10 * mantissa + unicharDigitValue(peek);
            if (sawDecimal)
                postDecimalDigits ++;
            mantissaDigits ++;
        }
        scannerSkipPeekedCharacter(self);
        maximumLength --;
        peek = scannerPeekCharacter(self);
    }
    if (initialSign == '-')
        mantissa = -mantissa;
    if (mantissaDigits == 0) {
        [self rewindToMark];
        return NO;
    } else {
        [self discardRewindMark];
    }
    
    // Scan the exponent, if it looks like there is one and if we have a nonzero maximumExponentLength.
    if (maximumLength >= 2 && maximumExponentLength > 0 && ( peek == 'e' || peek == 'E' )) {
        [self setRewindMark];
        
        scannerSkipPeekedCharacter(self);
        maximumLength --;
        peek = scannerPeekCharacter(self);
        if (peek == '+' || peek == '-') {
            exponentSign = peek;
            scannerSkipPeekedCharacter(self);
            maximumLength --;
            peek = scannerPeekCharacter(self);
        }

        if (unicharIsDecimalDigit(peek) && maximumLength > 0) {
            [self discardRewindMark];
            exponent = [self scanUnsignedIntegerMaximumDigits:MIN(maximumLength, maximumExponentLength)];
        
            if (exponentSign == '-')
                exponent = -exponent;
        } else {
            // No exponent --- discard the 'e' and sign, they were probably bogus
            [self rewindToMark];
            exponent = 0;
        }
    } else
        exponent = 0;
    
    // 'mantissa' is an integer at this point. Adjust the position of the d.p. to take into account the explicit exponent as well as any implicit exponent due to the use of a decimal point in the input string.
    exponent -= postDecimalDigits;
    if (exponent != 0)
	mantissa = ldexp( mantissa * pow(5, exponent), exponent );

    // All done. Return success.
    *outValue = mantissa;
    return YES;
}

- (BOOL)scanString:(NSString *)string peek:(BOOL)doPeek;
{
    unichar *buffer, *ptr;
    BOOL stringFound;
    BOOL useMalloc;

    NSUInteger length = [string length];
    useMalloc = length * sizeof(unichar) >= SAFE_ALLOCA_SIZE;
    if (useMalloc) {
	buffer = (unichar *)NSZoneMalloc(NULL, length * sizeof(unichar));
    } else {
        buffer = (unichar *)alloca(length * sizeof(unichar));
    }
    [string getCharacters:buffer];
    [self setRewindMark];
    ptr = buffer;
    stringFound = YES;
    while (length--) {
        if (scannerReadCharacter(self) != *ptr++) {
	    stringFound = NO;
	    break;
	}
    }
    if (useMalloc) {
        NSZoneFree(NULL, buffer);
    }

    if (!stringFound || doPeek)
        [self rewindToMark];
    else
        [self discardRewindMark];

    return stringFound;
}

- (BOOL)scanStringCaseInsensitive:(NSString *)string peek:(BOOL)doPeek;
{
    unichar *lowerBuffer, *upperBuffer;
    unichar *lowerPtr, *upperPtr;
    BOOL stringFound;
    BOOL useMalloc;

    NSUInteger length = [string length];
    if (length == 0)
        return YES;

    useMalloc = length * sizeof(unichar) >= SAFE_ALLOCA_SIZE;
    if (useMalloc) {
        lowerBuffer = (unichar *)NSZoneMalloc(NULL, length * sizeof(unichar));
        upperBuffer = (unichar *)NSZoneMalloc(NULL, length * sizeof(unichar));
    } else {
        lowerBuffer = (unichar *)alloca(length * sizeof(unichar));
        upperBuffer = (unichar *)alloca(length * sizeof(unichar));
    }
    [[string lowercaseString] getCharacters:lowerBuffer];
    [[string uppercaseString] getCharacters:upperBuffer];

    lowerPtr = lowerBuffer;
    upperPtr = upperBuffer;

    [self setRewindMark];

    stringFound = YES;
    while (length--) {
        unichar currentCharacter;

        currentCharacter = scannerPeekCharacter(self);
        if ((currentCharacter != *lowerPtr) && (currentCharacter != *upperPtr)) {
            stringFound = NO;
            break;
        }
        scannerSkipPeekedCharacter(self);
        lowerPtr++;
        upperPtr++;
    }
    
    if (!stringFound || doPeek)
        [self rewindToMark];
    else
        [self discardRewindMark];

    if (useMalloc) {
        NSZoneFree(NULL, lowerBuffer);
        NSZoneFree(NULL, upperBuffer);
    }

    return stringFound;
}


// Debugging methods

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];

    if (inputBuffer) {
        [debugDictionary setObject:[NSString stringWithCharacters:inputBuffer length:scanEnd - inputBuffer] forKey:@"inputString"];
        [debugDictionary setObject:[NSString stringWithFormat:@"%d", scanEnd - inputBuffer] forKey:@"inputStringLength"];
        [debugDictionary setObject:[NSString stringWithFormat:@"%d", scanLocation - inputBuffer] forKey:@"inputScanLocation"];
    }
    [debugDictionary setObject:[NSString stringWithFormat:@"%d", inputStringPosition] forKey:@"inputStringPosition"];

    return debugDictionary;
}

@end

