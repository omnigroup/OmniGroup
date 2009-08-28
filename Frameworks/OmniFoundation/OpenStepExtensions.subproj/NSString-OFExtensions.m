// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSString-OFExtensions.h>

#import <math.h>

#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSMutableString-OFExtensions.h>
#import <OmniFoundation/NSThread-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/OFRegularExpression.h>
#import <OmniFoundation/OFRegularExpressionMatch.h>
#import <OmniFoundation/OFStringDecoder.h>
#import <OmniFoundation/OFStringScanner.h>
#import <OmniFoundation/OFUtilities.h>

RCS_ID("$Id$")

/* Character sets used for mail header encoding */
static NSCharacterSet *nonNonCTLChars = nil;
static NSCharacterSet *nonAtomChars = nil;
static NSCharacterSet *nonAtomCharsExceptLWSP = nil;

@implementation NSString (OFExtensions)

+ (void)didLoad;
{
    // Mail header encoding according to RFCs 822 and 2047
    NSCharacterSet *nonCTLChars = [NSCharacterSet characterSetWithRange:(NSRange){32, 95}];
    nonNonCTLChars = [[nonCTLChars invertedSet] retain];

    NSMutableCharacterSet *workSet = [nonNonCTLChars mutableCopy];
    [workSet addCharactersInString:@"()<>@,;:\\\".[] "];
    nonAtomChars = [workSet copy];
    
    [workSet removeCharactersInString:@" \t"];
    nonAtomCharsExceptLWSP = [workSet copy];
    
    [workSet release];
}

+ (CFStringEncoding)cfStringEncodingForDefaultValue:(NSString *)encodingName;
{
    NSStringEncoding stringEncoding;
    CFStringEncoding cfEncoding;

    // Note that this default can be either a string or an integer. Integers refer to NSStringEncoding values. Strings consist of a prefix, a space, and a string whose meaning depends on the prefix. Currently understood prefixes are "ietf" (indicating an IETF charset name) and "cf" (indicating a CoreFoundation encoding number). Previously understood prefixes were the names of OWStringDocoder-conformant classes, but we don't do that any more.

    cfEncoding = kCFStringEncodingInvalidId;
    if ([encodingName hasPrefix:@"iana "]) {
        NSString *ietfName = [encodingName substringFromIndex:5];
        cfEncoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)ietfName);
    } else if ([encodingName hasPrefix:@"cf "]) {
        cfEncoding = [[encodingName substringFromIndex:3] intValue];
    } else if ([encodingName hasPrefix:@"omni "]) {
        return kCFStringEncodingInvalidId;
    }

    if (cfEncoding != kCFStringEncodingInvalidId)
        return cfEncoding;

    stringEncoding = [encodingName intValue];
    // Note that 0 is guaranteed never to be a valid encoding by the semantics of +[NSString availableStringEncodings]. (0 used to be used for the Unicode string encoding.)
    if (stringEncoding != 0)
        return CFStringConvertNSStringEncodingToEncoding(stringEncoding);

    return kCFStringEncodingInvalidId;
}

+ (NSString *)defaultValueForCFStringEncoding:(CFStringEncoding)anEncoding;
{
    switch(anEncoding) {
        case kCFStringEncodingInvalidId:
            return @"0";
        default:
            break;
    }

    // On 10.5 this returned uppercase, but that might not always be the case.
    NSString *encodingName = [(NSString *)CFStringConvertEncodingToIANACharSetName(anEncoding) lowercaseString];
    if (encodingName != nil && ![encodingName hasPrefix:@"x-"])
        return [@"iana " stringByAppendingString:encodingName];

    return [NSString stringWithFormat:@"cf %d", anEncoding];
}

+ (NSString *)abbreviatedStringForBytes:(unsigned long long)bytes;
{
    double kb, mb, gb, tb, pb;
    
    // We can't use [self bundle] or [NSString bundle], since that would try to load from Foundation, where NSString is defined. So we use [OFObject bundle]. If this file is ever moved to a bundle other than the one containing OFObject, that will have to be changed.
    
    if (bytes < 1000)
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%d bytes", @"OmniFoundation", [OFObject bundle], @"abbreviated string for bytes format"), (int)bytes];
    kb = bytes / 1024.0;
    if (kb < 1000.0)
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%0.1f kB", @"OmniFoundation", [OFObject bundle], @"abbreviated string for bytes format"), kb];
    mb = kb / 1024.0;
    if (mb < 1000.0)
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%0.1f MB", @"OmniFoundation", [OFObject bundle], @"abbreviated string for bytes format"), mb];
    gb = mb / 1024.0;
    if (gb < 1000.0)
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%0.1f GB", @"OmniFoundation", [OFObject bundle], @"abbreviated string for bytes format"), gb];
    tb = gb / 1024.0;
    if (tb < 1000.0)
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%0.1f TB", @"OmniFoundation", [OFObject bundle], @"abbreviated string for bytes format"), tb];
    pb = tb / 1024.0;
    return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%0.1f PB", @"OmniFoundation", [OFObject bundle], @"abbreviated string for bytes format"), pb];
}

+ (NSString *)abbreviatedStringForHertz:(unsigned long long)hz;
{
    if (hz <= 990ULL)
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%u Hz", @"OmniFoundation", [OFObject bundle], @"abbreviated string for hertz format"), (unsigned)hz];
    if (hz <= 999900ULL)
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%0.1f KHz", @"OmniFoundation", [OFObject bundle], @"abbreviated string for kilohertz format"), rint((double)hz/100.0f)/10.0f];
    if (hz <= 999999000ULL)
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%0.1f MHz", @"OmniFoundation", [OFObject bundle], @"abbreviated string for megahertz format"), rint((double)hz/100000.0f)/10.0f];
    if (hz <= 999999990000ULL)
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%0.1f GHz", @"OmniFoundation", [OFObject bundle], @"abbreviated string for gigahertz format"), rint((double)hz/100000000.0f)/10.0f];

    return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%0.1f THz", @"OmniFoundation", [OFObject bundle], @"abbreviated string for terahertz format"), rint((double)hz/100000000000.0f)/10.0f];
}

+ (NSString *)humanReadableStringForTimeInterval:(NSTimeInterval)timeInterval;
{
    NSString *intervalString;
    unsigned long int days, hours, minutes, seconds;
    BOOL inThePast = NO;

    timeInterval = rint(timeInterval);
    if (timeInterval < 0) {
        inThePast = YES;
        timeInterval = -timeInterval;
    }
    days = (unsigned long int)(timeInterval / (24 * 60 * 60));
    timeInterval -= days * (24 * 60 * 60);
    hours = (unsigned long int)(timeInterval / (60 * 60));
    timeInterval -= hours * (60 * 60);
    minutes = (unsigned long int)(timeInterval / 60);
    timeInterval -= minutes * 60;
    seconds = (unsigned long int)timeInterval;
    
    if (days > 1)
        intervalString = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%ld days, %ld:%02ld:%02ld", @"OmniFoundation", [OFObject bundle], @"humanReadableStringForTimeInterval"), days, hours, minutes, seconds];
    else if (days == 1)
        intervalString = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%ld day, %ld:%02ld:%02ld", @"OmniFoundation", [OFObject bundle], @"humanReadableStringForTimeInterval"), days, hours, minutes, seconds];
    else if (hours > 0)
        intervalString = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%ld:%02ld:%02ld", @"OmniFoundation", [OFObject bundle], @"humanReadableStringForTimeInterval"), hours, minutes, seconds];
    else if (minutes > 0)
        intervalString = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%ld:%02ld", @"OmniFoundation", [OFObject bundle], @"humanReadableStringForTimeInterval"), minutes, seconds];
    else if (seconds > 0)
        intervalString = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%ld seconds", @"OmniFoundation", [OFObject bundle], @"humanReadableStringForTimeInterval"), seconds];
    else
        intervalString = NSLocalizedStringFromTableInBundle(@"right now", @"OmniFoundation", [OFObject bundle], @"humanReadableStringForTimeInterval");

    if (!inThePast)
        return intervalString;
    else
        return [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%@ ago", @"OmniFoundation", [OFObject bundle], @"humanReadableStringForTimeInterval"), intervalString];
}

+ (NSString *)spacesOfLength:(unsigned int)aLength;
{
    static NSMutableString *spaces = nil;
    static NSLock *spacesLock;
    static unsigned int spacesLength;

    if (!spaces) {
	spaces = [@"                " mutableCopy];
	spacesLength = [spaces length];
        spacesLock = [[NSLock alloc] init];
    }
    if (spacesLength < aLength) {
        [spacesLock lock];
        while (spacesLength < aLength) {
            [spaces appendString:spaces];
            spacesLength += spacesLength;
        }
        [spacesLock unlock];
    }
    return [spaces substringToIndex:aLength];
}

+ (NSString *)stringWithStrings:(NSString *)first, ...
{
    NSMutableString *buffer;
    NSString *prev;
    NSString *returnValue;
    va_list argList;

    buffer = [[NSMutableString alloc] init];

    va_start(argList, first);
    prev = first;
    while(prev != nil) {
        [buffer appendString:prev];
        prev = va_arg(argList, NSString *);
    }
    va_end(argList);

    returnValue = [buffer copy];
    [buffer release];
    return [returnValue autorelease];
}

- (BOOL)isPercentage;
{
    unsigned int characterIndex, characterCount;
    unichar c;
    
    characterCount = [self length];
    for (characterIndex = 0; characterIndex < characterCount; characterIndex++) {
        c = [self characterAtIndex:characterIndex];
        if (c == '%')
            return YES;
        else if ((c >= '0' && c <= '9') || c == '.')
            continue;
        else
            break;
    }        
    return NO;
}

+ (NSString *)stringWithFourCharCode:(FourCharCode)code;
{
    union {
        uint32_t i;
        UInt8 c[4];
    } buf;
    
    buf.i = CFSwapInt32HostToBig(code);
    
    // UTCreateStringForOSType()/UTGetOSTypeFromString() uses MacOSRoman encoding, so we'll do that too.
    NSString *string = [[NSString alloc] initWithBytes:buf.c length:4 encoding:NSMacOSRomanStringEncoding];
    [string autorelease];
    return string;
}

- (FourCharCode)fourCharCodeValue;
{
    FourCharCode code;
    
    if (OFGet4CCFromPlist(self, (uint32_t *)&code))
        return code;
    else
        return 0; // sigh.
}

- (NSString *)stringByUppercasingAndUnderscoringCaseChanges;
{
    static OFCharacterSet *lowercaseOFCharacterSet, *uppercaseOFCharacterSet, *numberOFCharacterSet, *currentOFCharacterSet;
    NSMutableArray *words;
    OFStringScanner *scanner;
    unsigned int wordStartIndex = 0;
    static BOOL hasInitialized = NO;

    if (![self length])
        return nil;
    
    if (!hasInitialized) {
        // Potential minor memory leak here due to multithreading
        lowercaseOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:[NSCharacterSet lowercaseLetterCharacterSet]];
        uppercaseOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:[NSCharacterSet uppercaseLetterCharacterSet]];
        numberOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:[NSCharacterSet decimalDigitCharacterSet]];

        hasInitialized = YES;
    }

    words = [NSMutableArray array];
    scanner = [[[OFStringScanner alloc] initWithString:self] autorelease];
    
    while (scannerHasData(scanner)) {
        unichar peekedChar;

        peekedChar = scannerPeekCharacter(scanner);
        if ([lowercaseOFCharacterSet characterIsMember:peekedChar])
            currentOFCharacterSet = lowercaseOFCharacterSet;
        else if ([uppercaseOFCharacterSet characterIsMember:peekedChar])
            currentOFCharacterSet = uppercaseOFCharacterSet;
        else if ([numberOFCharacterSet characterIsMember:peekedChar])
            currentOFCharacterSet = numberOFCharacterSet;
        else {
            [NSException raise:NSInvalidArgumentException format:@"Character: %@, at index: %d, not found in lowercase, uppercase, or decimal digit character sets", [NSString stringWithCharacter:peekedChar], scannerScanLocation];
        }

        if (scannerScanUpToCharacterNotInOFCharacterSet(scanner, currentOFCharacterSet)) {
            unsigned int scanLocation;

            scanLocation = scannerScanLocation(scanner);
            if (currentOFCharacterSet == lowercaseOFCharacterSet || currentOFCharacterSet == numberOFCharacterSet) {
                [words addObject:[self substringWithRange:NSMakeRange(wordStartIndex, scanLocation - wordStartIndex)]];
                wordStartIndex = scanLocation;
            } else if (currentOFCharacterSet == uppercaseOFCharacterSet) {
                if (scanLocation - wordStartIndex == 1) {
                    continue;
                } else if ([numberOFCharacterSet characterIsMember:scannerPeekCharacter(scanner)]) {
                    [words addObject:[self substringWithRange:NSMakeRange(wordStartIndex, scanLocation - wordStartIndex)]];
                    wordStartIndex = scanLocation;
                } else {
                    scanLocation--;
                    [scanner setScanLocation:scanLocation];
                    [words addObject:[self substringWithRange:NSMakeRange(wordStartIndex, scanLocation - wordStartIndex)]];
                    wordStartIndex = scanLocation;
                }
            } else {
                OBASSERT(NO);
            }
        }
    }

    [words addObject:[self substringWithRange:NSMakeRange(wordStartIndex, scannerScanLocation(scanner) - wordStartIndex)]];

    return [[words componentsJoinedByString:@"_"] uppercaseString];
}

- (NSString *)stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace;
{
    OFCharacterSet *whitespaceOFCharacterSet;
    OFStringScanner *stringScanner;
    NSMutableString *collapsedString;
    BOOL firstSubstring;
    unsigned int length;

    whitespaceOFCharacterSet = [OFCharacterSet whitespaceOFCharacterSet];
    length = [self length];
    if (length == 0)
        return @""; // Trivial optimization

    stringScanner = [[OFStringScanner alloc] initWithString:self];
    collapsedString = [[NSMutableString alloc] initWithCapacity:length];
    firstSubstring = YES;
    while (scannerScanUpToCharacterNotInOFCharacterSet(stringScanner, whitespaceOFCharacterSet)) {
        NSString *nonWhitespaceSubstring;

        nonWhitespaceSubstring = [stringScanner readFullTokenWithDelimiterOFCharacterSet:whitespaceOFCharacterSet forceLowercase:NO];
        if (nonWhitespaceSubstring) {
            if (firstSubstring) {
                firstSubstring = NO;
            } else {
                [collapsedString appendString:@" "];
            }
            [collapsedString appendString:nonWhitespaceSubstring];
        }
    }
    [stringScanner release];
    return [collapsedString autorelease];
}

- (NSString *)stringByRemovingWhitespace;
{
    return [self stringByRemovingCharactersInOFCharacterSet:[OFCharacterSet whitespaceOFCharacterSet]];
}

- (NSString *)stringByRemovingCharactersInOFCharacterSet:(OFCharacterSet *)removeSet;
{
    OFStringScanner *stringScanner;
    NSMutableString *strippedString;
    unsigned int length;

    length = [self length];
    if (length == 0)
        return @""; // Trivial optimization

    stringScanner = [[OFStringScanner alloc] initWithString:self];
    strippedString = [[NSMutableString alloc] initWithCapacity:length];
    while (scannerScanUpToCharacterNotInOFCharacterSet(stringScanner, removeSet)) {
        NSString *nonWhitespaceSubstring;

        nonWhitespaceSubstring = [stringScanner readFullTokenWithDelimiterOFCharacterSet:removeSet forceLowercase:NO];
        if (nonWhitespaceSubstring != nil)
            [strippedString appendString:nonWhitespaceSubstring];
    }
    [stringScanner release];
    return [strippedString autorelease];
}

- (NSString *)stringByRemovingReturns;
{
    static OFCharacterSet *newlineCharacterSet = nil;
    
    if (newlineCharacterSet == nil)
        newlineCharacterSet = [[OFCharacterSet characterSetWithString:@"\r\n"] retain];
    
    return [self stringByRemovingCharactersInOFCharacterSet:newlineCharacterSet];
}

- (NSString *)stringByRemovingRegularExpression:(OFRegularExpression *)regularExpression;
{
    OFRegularExpressionMatch *match = [regularExpression matchInString:self];
        
    if (match == nil)
       return self;
    return [[self stringByRemovingString:[match matchString]] stringByRemovingRegularExpression:regularExpression];
}

- (NSString *)stringByPaddingToLength:(unsigned int)aLength;
{
    unsigned int currentLength;

    currentLength = [self length];

    if (currentLength == aLength)
	return [[self retain] autorelease];
    if (currentLength > aLength)
	return [self substringToIndex:aLength];
    return [self stringByAppendingString:[[self class] spacesOfLength:aLength - currentLength]];
}

- (NSString *)stringByNormalizingPath;
{
    NSArray *pathElements;
    NSMutableArray *newPathElements;
    unsigned int preserveCount;
    unsigned int elementIndex, elementCount;

    // Split on slashes and chop out '.' and '..' correctly.

    pathElements = [self componentsSeparatedByString:@"/"];
    elementCount = [pathElements count];
    newPathElements = [NSMutableArray arrayWithCapacity:elementCount];
    if (elementCount > 0 && [[pathElements objectAtIndex:0] isEqualToString:@""])
	preserveCount = 1;
    else
        preserveCount = 0;
    for (elementIndex = 0; elementIndex < elementCount; elementIndex++) {
	NSString *pathElement;

	pathElement = [pathElements objectAtIndex:elementIndex];
	if ([pathElement isEqualToString:@".."]) {
	    if ([pathElements count] > preserveCount)
		[newPathElements removeLastObject];
	} else if (![pathElement isEqualToString:@"."])
	    [newPathElements addObject:pathElement];
    }
    return [newPathElements componentsJoinedByString:@"/"];
}

- (unichar)firstCharacter;
{
    if ([self length] == 0)
	return '\0';
    return [self characterAtIndex:0];
}

- (unichar)lastCharacter;
{
    unsigned int length;

    length = [self length];
    if (length == 0)
        return '\0';
    return [self characterAtIndex:length - 1];
}

- (NSString *)lowercaseFirst;
{
    return [[[self substringToIndex:1] lowercaseString] stringByAppendingString:[self substringFromIndex:1]];
}

- (NSString *)uppercaseFirst;
{
    return [[[self substringToIndex:1] uppercaseString] stringByAppendingString:[self substringFromIndex:1]];
}

- (NSString *)stringByApplyingDeferredCFEncoding:(CFStringEncoding)newEncoding;
{
    if (!OFStringContainsDeferredEncodingCharacters(self)) {
        return [[self copy] autorelease];
    } else {
        return OFApplyDeferredEncoding(self, newEncoding);
    }
}

- (NSString *)stringByReplacingAllOccurrencesOfRegularExpressionString:(NSString *)matchString withString:(NSString *)newString;
{
    OFRegularExpression *matchExpression = [[OFRegularExpression alloc] initWithString:matchString];
    OFStringScanner *scanner = [[OFStringScanner alloc] initWithString:self];
    OFRegularExpressionMatch *match = [matchExpression matchInScanner:scanner];

    if (match == nil) {
        [scanner release];
        [matchExpression release];
        return self;
    }

    NSMutableString *replacementString = [NSMutableString string];
    unsigned int lastPosition = 0, noProgressCount = 0;
    do {
        NSRange nextMatchRange = [match matchRange];
        NSRange copyRange = NSMakeRange(lastPosition, nextMatchRange.location - lastPosition);
        [replacementString appendString:[self substringWithRange:copyRange]];
        [replacementString appendString:newString];
        unsigned int newPosition = NSMaxRange(nextMatchRange);
        if (newPosition == lastPosition)
            noProgressCount++;
        else
            noProgressCount = 0;
        lastPosition = newPosition;
    } while ([match findNextMatch] && noProgressCount < 3);

    [replacementString appendString:[self substringFromIndex:lastPosition]];
    [scanner release];
    [matchExpression release];

    return replacementString;
}

- (NSString *)stringByReplacingOccurancesOfString:(NSString *)targetString withObjectsFromArray:(NSArray *)sourceArray;
{
    NSMutableString *resultString;
    OFStringScanner *replacementScanner;
    unsigned int occurranceIndex = 0;
    unsigned int lastAppendedIndex = 0;
    unsigned int sourceCount;
    unsigned int targetStringLength;

    replacementScanner = [[[OFStringScanner alloc] initWithString:self] autorelease];
    resultString = [NSMutableString string];

    targetStringLength = [targetString length];
    sourceCount = [sourceArray count];
    
    while ([replacementScanner scanUpToString:targetString]) {
        NSRange beforeMatchRange;
        NSString *itemDescription;
        unsigned int scanLocation;

        scanLocation = [replacementScanner scanLocation];
        beforeMatchRange = NSMakeRange(lastAppendedIndex, scanLocation - lastAppendedIndex);
        if (beforeMatchRange.length > 0)
            [resultString appendString:[self substringWithRange:beforeMatchRange]];

        if (occurranceIndex >= sourceCount) {
            [NSException raise:NSInvalidArgumentException format:@"The string being scanned has more occurrances of the target string than the source array has items (scannedString = %@, targetString = %@, sourceArray = %@)."];
        }
        
        itemDescription = [[sourceArray objectAtIndex:occurranceIndex] description];
        [resultString appendString:itemDescription];

        occurranceIndex++;
        [replacementScanner setScanLocation:scanLocation + targetStringLength];
        lastAppendedIndex = [replacementScanner scanLocation];
    }

    if (lastAppendedIndex < [self length])
        [resultString appendString:[self substringFromIndex:lastAppendedIndex]];

    return [[resultString copy] autorelease];
}

- (NSString *) stringBySeparatingSubstringsOfLength:(unsigned int)substringLength                                          withString:(NSString *)separator startingFromBeginning:(BOOL)startFromBeginning;
{
    unsigned int     lengthLeft, offset = 0;
    NSMutableString *result;

    lengthLeft = [self length];
    if (lengthLeft <= substringLength)
        // Use <= since you have to have more than one group to need a separator.
        return [[self retain] autorelease];

    if (!substringLength)
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %@], substringLength must be non-zero.",
            NSStringFromClass(isa), NSStringFromSelector(_cmd), substringLength];
    
    result = [NSMutableString string];
    if (!startFromBeginning) {
        unsigned int mod;
        
        // We'll still really start from the beginning, but first we'll trim off
        // whatever the extra count is that would have gone on the end.  This
        // produces the same effect.

        mod = lengthLeft % substringLength;
        if (mod) {
            [result appendString: [self substringWithRange: NSMakeRange(offset, mod)]];
            [result appendString: separator];
            offset     += mod;
            lengthLeft -= mod;
        }
    }

    while (lengthLeft) {
        unsigned int lengthToCopy;

        lengthToCopy = MIN(lengthLeft, substringLength);
        [result appendString: [self substringWithRange: NSMakeRange(offset, lengthToCopy)]];
        lengthLeft -= lengthToCopy;
        offset     += lengthToCopy;

        if (lengthLeft)
            [result appendString: separator];
    }

    return result;
}

- (NSString *)substringStartingWithString:(NSString *)startString;
{
    NSRange startRange;

    startRange = [self rangeOfString:startString];
    if (startRange.length == 0)
        return nil;
    return [self substringFromIndex:startRange.location];
}

- (NSString *)substringStartingAfterString:(NSString *)aString;
{
    NSRange aRange;

    aRange = [self rangeOfString:aString];
    if (aRange.length == 0)
        return nil;
    return [self substringFromIndex:aRange.location + aRange.length];
}

- (NSArray *)componentsSeparatedByString:(NSString *)separator maximum:(unsigned)atMost;
{
    NSRange tailRange;
    NSMutableArray *components;
    NSArray *result;

    tailRange.location = 0;
    tailRange.length = [self length];

    components = [[NSMutableArray alloc] initWithCapacity:atMost];

    for(;;) {
        NSRange separatorRange;
        NSRange componentRange;
        
        if (atMost < 2)
            break;

        if (tailRange.length == 0)
            break;

        separatorRange = [self rangeOfString:separator options:0 range:tailRange];
        if (separatorRange.location == NSNotFound)
            break;

        componentRange.location = tailRange.location;
        componentRange.length = ( separatorRange.location - tailRange.location );
        [components addObject:[self substringWithRange:componentRange]];

        tailRange = NSMakeRange(NSMaxRange(separatorRange), NSMaxRange(tailRange) - NSMaxRange(separatorRange));
        atMost --;
    }
    
    if ([components count] == 0) {
        NSString *immutable;

        // Short-circuit.
        [components release];
        immutable = [self copy];
        result = [NSArray arrayWithObject:immutable];
        [immutable release];
    } else {
        [components addObject:[self substringWithRange:tailRange]];
        result = [components autorelease];
    }

    return result;
}

- (NSArray *)componentsSeparatedByCharactersFromSet:(NSCharacterSet *)delimiterSet;
{
    NSArray *result;
    NSRange tailRange = NSMakeRange(0, [self length]);
    NSMutableArray *components = [[NSMutableArray alloc] init];
    
    for(;;) {
        NSRange separatorRange;
        NSRange componentRange;
        
        if (tailRange.length == 0)
            break;
        
        separatorRange = [self rangeOfCharacterFromSet:delimiterSet options:0 range:tailRange];
        if (separatorRange.location == NSNotFound)
            break;
        
        componentRange.location = tailRange.location;
        componentRange.length = ( separatorRange.location - tailRange.location );
        [components addObject:[self substringWithRange:componentRange]];
        
        tailRange = NSMakeRange(NSMaxRange(separatorRange), NSMaxRange(tailRange) - NSMaxRange(separatorRange));
        while (tailRange.length > 0 && [delimiterSet characterIsMember:[self characterAtIndex:tailRange.location]]) {
            tailRange.location++;
            tailRange.length--;
        };
    }
    
    if ([components count] == 0) {
        NSString *immutable;
        
        // Short-circuit.
        [components release];
        immutable = [self copy];
        result = [NSArray arrayWithObject:immutable];
        [immutable release];
    } else {
        [components addObject:[self substringWithRange:tailRange]];
        result = [components autorelease];
    }
    
    return result;
}

- (NSString *)stringByIndenting:(int)spaces;
{
    return [self stringByIndenting:spaces andWordWrapping:999999 withFirstLineIndent:spaces];
}

- (NSString *)stringByWordWrapping:(int)columns;
{
    return [self stringByIndenting:0 andWordWrapping:columns withFirstLineIndent:0];
}

- (NSString *)stringByIndenting:(int)spaces andWordWrapping:(int)columns;
{
    return [self stringByIndenting:spaces andWordWrapping:columns withFirstLineIndent:spaces];
}

- (NSString *)stringByIndenting:(int)spaces andWordWrapping:(int)columns withFirstLineIndent:(int)firstLineSpaces;
{
    NSMutableString *result;
    NSString *indent;
    NSCharacterSet *whitespace;
    NSRange remainingRange, lineRange, breakRange, spaceRange;
    NSUInteger start, end, contentEnd, available, length;
    BOOL isFirstLine;
    
    if (columns <= 0)
        return nil;
    if (spaces > columns)
        spaces = columns - 1;
    
    available = columns - firstLineSpaces;
    indent = [NSString spacesOfLength:firstLineSpaces];
    isFirstLine = YES;
    
    result = [NSMutableString string];
    whitespace = [NSCharacterSet whitespaceCharacterSet];
    length = [self length];
    remainingRange = NSMakeRange(0, [self length]);
    
    while (remainingRange.length) {
        [self getLineStart:&start end:&end contentsEnd:&contentEnd forRange:remainingRange];
        lineRange = NSMakeRange(start, contentEnd - start);
        while (lineRange.length > available) {
            breakRange = NSMakeRange(lineRange.location, available);
            spaceRange = [self rangeOfCharacterFromSet:whitespace options:NSBackwardsSearch range:breakRange];
            if (spaceRange.length) {
                breakRange = NSMakeRange(lineRange.location, spaceRange.location - lineRange.location);
                lineRange.length = NSMaxRange(lineRange) - NSMaxRange(spaceRange);
                lineRange.location = NSMaxRange(spaceRange);
            } else {
                lineRange.length = NSMaxRange(lineRange) - NSMaxRange(breakRange);
                lineRange.location = NSMaxRange(breakRange);
            }
            [result appendFormat:@"%@%@\n", indent, [self substringWithRange:breakRange]];
            if (isFirstLine) {	
                isFirstLine = NO;
                available = columns - spaces;
                indent = [NSString spacesOfLength:spaces];
            }
        }
        [result appendFormat:@"%@%@\n", indent, [self substringWithRange:lineRange]];
        if (isFirstLine) {	
            isFirstLine = NO;
            available = columns - spaces;
            indent = [NSString spacesOfLength:spaces];
        }
        remainingRange = NSMakeRange(end, length - end);
    }
    return result;
}

- (NSRange)findString:(NSString *)string selectedRange:(NSRange)selectedRange options:(unsigned int)options wrap:(BOOL)wrap;
{
    BOOL forwards;
    unsigned int length;
    NSRange searchRange, range;

    length = [self length];
    forwards = (options & NSBackwardsSearch) == 0;
    if (forwards) {
	searchRange.location = NSMaxRange(selectedRange);
	searchRange.length = length - searchRange.location;
	range = [self rangeOfString:string options:options range:searchRange];
        if ((range.length == 0) && wrap) {
            // If not found look at the first part of the string
	    searchRange.location = 0;
            searchRange.length = selectedRange.location;
            range = [self rangeOfString:string options:options range:searchRange];
        }
    } else {
	searchRange.location = 0;
	searchRange.length = selectedRange.location;
        range = [self rangeOfString:string options:options range:searchRange];
        if ((range.length == 0) && wrap) {
            searchRange.location = NSMaxRange(selectedRange);
            searchRange.length = length - searchRange.location;
            range = [self rangeOfString:string options:options range:searchRange];
        }
    }
    return range;
}        

- (NSRange)rangeOfCharactersAtIndex:(unsigned)pos delimitedBy:(NSCharacterSet *)delim;
{
    unsigned int myLength;
    NSRange searchRange, foundRange;
    unsigned int first, after;

    myLength = [self length];
    searchRange.location = 0;
    searchRange.length = pos;
    foundRange = [self rangeOfCharacterFromSet:delim options:NSBackwardsSearch range:searchRange];
    if (foundRange.length > 0)
      first = foundRange.location + foundRange.length;
    else
      first = 0;

    searchRange.location = pos;
    searchRange.length = myLength - pos;
    foundRange = [self rangeOfCharacterFromSet:delim options:0 range:searchRange];
    if (foundRange.length > 0)
      after = foundRange.location;
    else
      after = myLength;

    foundRange.location = first;
    foundRange.length = after - first;
    return foundRange;
}

- (NSRange)rangeOfWordContainingCharacter:(unsigned int)pos;
{
    NSCharacterSet *wordSep;
    unichar ch;

    // XXX TODO: This should depend on what your notion of a "word" is.
    wordSep = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    ch = [self characterAtIndex:pos];
    if ([wordSep characterIsMember:ch])
        return [self rangeOfCharactersAtIndex:pos delimitedBy:[wordSep invertedSet]];
    else
        return [self rangeOfCharactersAtIndex:pos delimitedBy:wordSep];
}

- (NSRange)rangeOfWordsIntersectingRange:(NSRange)range;
{
    unsigned int first, last;
    NSRange firstRange, lastRange;

    if (range.length == 0)
        return NSMakeRange(0, 0);

    first = range.location;
    last = NSMaxRange(range) - 1;
    firstRange = [self rangeOfWordContainingCharacter:first];
    lastRange = [self rangeOfWordContainingCharacter:last];
    return NSMakeRange(firstRange.location, NSMaxRange(lastRange) - firstRange.location);
}

// Needs encoding and out error; don't enable until it has them
#if 0
#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile createDirectories:(BOOL)shouldCreateDirectories;
    // Will raise an exception if it can't create the required directories.
{
    if (shouldCreateDirectories) {
        // TODO: We ought to make the attributes configurable
        [[NSFileManager defaultManager] createPathToFile:path attributes:nil];
    }

    return [self writeToFile:path atomically:useAuxiliaryFile];
}
#endif
#endif

- (NSString *)htmlString;
{
    unichar *ptr, *begin, *end;
    NSMutableString *result;
    NSString *string;
    int length;
    
#define APPEND_PREVIOUS() \
    string = [[NSString alloc] initWithCharacters:begin length:(ptr - begin)]; \
    [result appendString:string]; \
    [string release]; \
    begin = ptr + 1;
    
    length = [self length];
    ptr = alloca(length * sizeof(unichar));
    end = ptr + length;
    [self getCharacters:ptr];
    result = [NSMutableString stringWithCapacity:length];
    
    begin = ptr;
    while (ptr < end) {
        if (*ptr > 127) {
            APPEND_PREVIOUS();
            [result appendFormat:@"&#%d;", (int)*ptr];
        } else if (*ptr == '&') {
            APPEND_PREVIOUS();
            [result appendString:@"&amp;"];
        } else if (*ptr == '\"') {
            APPEND_PREVIOUS();
            [result appendString:@"&quot;"];
        } else if (*ptr == '<') {
             APPEND_PREVIOUS();
            [result appendString:@"&lt;"];
        } else if (*ptr == '>') {
            APPEND_PREVIOUS();
            [result appendString:@"&gt;"];
        } else if (*ptr == '\n') {
            APPEND_PREVIOUS();
            [result appendString:@"<br/>"];
        }
        ptr++;
    }
    APPEND_PREVIOUS();
    return result;
}


// Regular expression encoding

- (NSString *)regularExpressionForLiteralString;
{
    OFStringScanner *scanner;
    NSMutableString *result;
    static OFCharacterSet *regularExpressionLiteralDelimiterSet = nil;
    
    if (regularExpressionLiteralDelimiterSet == nil)
        regularExpressionLiteralDelimiterSet = [[OFCharacterSet alloc] initWithString:@"^$.[()|\\?*+"];

    result = [NSMutableString stringWithCapacity:[self length]];
    scanner = [[OFStringScanner alloc] initWithString:self];
    while (scannerHasData(scanner)) {
        unichar character;
        NSString *nextLiteralFragment;

        character = scannerPeekCharacter(scanner);
        if (OFCharacterSetHasMember(regularExpressionLiteralDelimiterSet, character)) {
            [result appendString:@"\\"];
            [result appendString:[NSString stringWithCharacter:character]];
            scannerSkipPeekedCharacter(scanner);
        } else {
            nextLiteralFragment = [scanner readFullTokenWithDelimiterOFCharacterSet:regularExpressionLiteralDelimiterSet];
            [result appendString:nextLiteralFragment];
        }
    }
    [scanner release];
    return result;
}

// Encoding mail headers

- (NSString *)asRFC822Word
{
    if ([self length] > 0 &&
        [self rangeOfCharacterFromSet:nonAtomChars].length == 0 &&
        !([self hasPrefix:@"=?"] && [self hasSuffix:@"?="])) {
        /* We're an atom. */
        return [[self copy] autorelease];
    }

    /* The nonNonCTLChars set has a wacky name, but what the heck. It contains all the characters that we are not willing to represent in a quoted-string. Technically, we're allowed to have qtext, which is "any CHAR excepting <">, "\" & CR, and including linear-white-space" (RFC822 3.3); CHAR means characters 0 through 127 (inclusive), and so a qtext may contain arbitrary ASCII control characters. But to be on the safe side, we don't include those. */
    /* TODO: Consider adding a few specific control characters, perhaps HTAB */

    if ([self rangeOfCharacterFromSet:nonNonCTLChars].length == 0) {
        /* We don't contain any characters that aren't "nonCTLChars", so we can be represented as a quoted-string. */
        NSMutableString *buffer = [self mutableCopy];
        NSString *result;
        unsigned int chIndex = [buffer length];

        while(chIndex > 0) {
            unichar ch = [buffer characterAtIndex:(-- chIndex)];
            OBASSERT( !( ch < 32 || ch >= 127 ) ); // guaranteed by definition of nonNonCTLChars
            if (ch == '"' || ch == '\\' /* || ch < 32 || ch >= 127 */) {
                [buffer replaceCharactersInRange:(NSRange){chIndex, 0} withString:@"\\"];
            }
        }

        [buffer replaceCharactersInRange:(NSRange){0, 0} withString:@"\""];
        [buffer appendString:@"\""];

        result = [[buffer copy] autorelease];
        [buffer release];

        return result;
    }

    /* Otherwise, we cannot be represented as an RFC822 word (atom or quoted-string). If appropriate, the caller can use the RFC2047 encoded-word format. */
    return nil;
}

/* Preferred encodings as alluded in RFC2047 */
static const CFStringEncoding preferredEncodings[] = {
    kCFStringEncodingISOLatin1,
    kCFStringEncodingISOLatin2,
    kCFStringEncodingISOLatin3,
    kCFStringEncodingISOLatin4,
    kCFStringEncodingISOLatinCyrillic,
    kCFStringEncodingISOLatinArabic,
    kCFStringEncodingISOLatinGreek,
    kCFStringEncodingISOLatinHebrew,
    kCFStringEncodingISOLatin5,
    kCFStringEncodingISOLatin6,
    kCFStringEncodingISOLatinThai,
    kCFStringEncodingISOLatin7,
    kCFStringEncodingISOLatin8,
    kCFStringEncodingISOLatin9,
    kCFStringEncodingInvalidId /* sentinel */
};

/* Some encodings we like, which we try out if preferredEncodings fails */
static const CFStringEncoding desirableEncodings[] = {
    kCFStringEncodingUTF8,
    kCFStringEncodingUnicode,
    kCFStringEncodingHZ_GB_2312,
    kCFStringEncodingISO_2022_JP_1,
    kCFStringEncodingInvalidId /* sentinel */
};


/* Characters which do not need to be quoted in an RFC2047 quoted-printable-encoded word.
   Note that 0x20 is treated specially by the routine that uses this bitmap. */
static const char qpNonSpecials[128] = {
    0, 0, 0, 0, 0, 0, 0, 0,   //  
    0, 0, 0, 0, 0, 0, 0, 0,   //  
    0, 0, 0, 0, 0, 0, 0, 0,   //  
    0, 0, 0, 0, 0, 0, 0, 0,   //  
    1, 1, 0, 0, 0, 0, 0, 0,   //  SP and !
    0, 0, 1, 1, 0, 1, 0, 1,   //    *+ - /
    1, 1, 1, 1, 1, 1, 1, 1,   //  01234567
    1, 1, 0, 0, 0, 0, 0, 0,   //  89
    0, 1, 1, 1, 1, 1, 1, 1,   //   ABCDEFG
    1, 1, 1, 1, 1, 1, 1, 1,   //  HIJKLMNO
    1, 1, 1, 1, 1, 1, 1, 1,   //  PQRSTUVW
    1, 1, 1, 0, 0, 0, 0, 0,   //  XYZ
    0, 1, 1, 1, 1, 1, 1, 1,   //   abcdefg
    1, 1, 1, 1, 1, 1, 1, 1,   //  hijklmno
    1, 1, 1, 1, 1, 1, 1, 1,   //  pqrstuvw
    1, 1, 1, 0, 0, 0, 0, 0    //  xyz
};


static inline unichar hex(int i)
{
    static const char hexDigits[16] = {
        '0', '1', '2', '3', '4', '5', '6', '7',
        '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'
    };
    
    return (unichar)hexDigits[i];
}

/* TODO: RFC2047 requires us to break up encoded-words so that each one is no longer than 75 characters. We don't do that, which means it's possible for us to produce non-conforming tokens if called on a long string. */
- (NSString *)asRFC2047EncodedWord
{
    CFStringEncoding fastestEncoding, bestEncoding;
    int encodingIndex, byteIndex, byteCount, qpSize, b64Size;
    CFStringRef cfSelf = (CFStringRef)self;
    CFDataRef convertedBytes;
    const UInt8 *bytePtr;
    NSString *encodedWord;

    bestEncoding = kCFStringEncodingInvalidId;
    convertedBytes = NULL;

    fastestEncoding = CFStringGetFastestEncoding(cfSelf);
    for(encodingIndex = 0; preferredEncodings[encodingIndex] != kCFStringEncodingInvalidId; encodingIndex ++) {
        if (fastestEncoding == preferredEncodings[encodingIndex]) {
            bestEncoding = fastestEncoding;
            break;
        }
    }

    if (bestEncoding == kCFStringEncodingInvalidId) {
        // The fastest encoding is not in the preferred encodings list. Check whether any of the preferred encodings are possible at all.

        for(encodingIndex = 0; preferredEncodings[encodingIndex] != kCFStringEncodingInvalidId; encodingIndex ++) {
            convertedBytes = CFStringCreateExternalRepresentation(kCFAllocatorDefault, cfSelf, preferredEncodings[encodingIndex], 0);
            if (convertedBytes != NULL) {
                bestEncoding = preferredEncodings[encodingIndex];
                break;
            }
        }
    }

    if (bestEncoding == kCFStringEncodingInvalidId) {
        // We can't use any of the preferred encodings, so use the smallest one.
        bestEncoding = CFStringGetSmallestEncoding(cfSelf);
    }

    if (convertedBytes == NULL)
        convertedBytes = CFStringCreateExternalRepresentation(kCFAllocatorDefault, cfSelf, bestEncoding, 0);
    
    // CFStringGetSmallestEncoding() doesn't always return the smallest encoding, so try out a few others on our own
    {
        CFStringEncoding betterEncoding = kCFStringEncodingInvalidId;
        CFDataRef betterBytes = NULL;
        
        for(encodingIndex = 0; desirableEncodings[encodingIndex] != kCFStringEncodingInvalidId; encodingIndex ++) {
            CFDataRef alternateBytes;
            CFStringEncoding trialEncoding;
            if (desirableEncodings[encodingIndex] == bestEncoding)
                continue;
            trialEncoding = desirableEncodings[encodingIndex];
            alternateBytes = CFStringCreateExternalRepresentation(kCFAllocatorDefault, cfSelf, trialEncoding, 0);
            if (alternateBytes != NULL) {                
                if (betterBytes == NULL) {
                    betterEncoding = trialEncoding;
                    betterBytes = alternateBytes;
                } else if(CFDataGetLength(betterBytes) > CFDataGetLength(alternateBytes)) {
                    CFRelease(betterBytes);
                    betterEncoding = trialEncoding;
                    betterBytes = alternateBytes;
                } else {
                    CFRelease(alternateBytes);
                }
            }
        }

        if (betterBytes != NULL) {
            if (CFDataGetLength(betterBytes) < CFDataGetLength(convertedBytes)) {
                CFRelease(convertedBytes);
                convertedBytes = betterBytes;
                bestEncoding = betterEncoding;
            } else {
                CFRelease(betterBytes);
            }
        }
    }

    OBASSERT(bestEncoding != kCFStringEncodingInvalidId);
    OBASSERT(convertedBytes != NULL);

    // On 10.5 this returned uppercase, but it might not always.
    NSString *charsetName = [(NSString *)CFStringConvertEncodingToIANACharSetName(bestEncoding) lowercaseString];
    
    // Hack for UTF16BE/UTF16LE.
    // Note that this doesn't screw up our byte count because we remove two bytes here but add two bytes in the encoding name.
    // We might still come out ahead because BASE64 is like that.
    if ([charsetName isEqualToString:@"utf-16"] && CFDataGetLength(convertedBytes) >= 2) {
        UInt8 maybeBOM[2];
        BOOL stripBOM = NO;
        
        CFDataGetBytes(convertedBytes, (CFRange){0,2},maybeBOM);
        if (maybeBOM[0] == 0xFE && maybeBOM[1] == 0xFF) {
            charsetName = @"utf-16be";
            stripBOM = YES;
        } else if (maybeBOM[0] == 0xFF && maybeBOM[1] == 0xFE) {
            charsetName = @"utf-16le";
            stripBOM = YES;
        }
        
        if (stripBOM) {
            CFMutableDataRef stripped = CFDataCreateMutableCopy(kCFAllocatorDefault, CFDataGetLength(convertedBytes), convertedBytes);
            CFDataDeleteBytes(stripped, (CFRange){0,2});
            CFRelease(convertedBytes);
            convertedBytes = stripped;
        }
    }

    byteCount = CFDataGetLength(convertedBytes);
    bytePtr = CFDataGetBytePtr(convertedBytes);
    
    // Now decide whether to use quoted-printable or base64 encoding. Again, we choose the smallest size.
    qpSize = 0;
    for(byteIndex = 0; byteIndex < byteCount; byteIndex ++) {
        if (bytePtr[byteIndex] < 128 && qpNonSpecials[bytePtr[byteIndex]])
            qpSize += 1;
        else
            qpSize += 3;
    }

    b64Size = (( byteCount + 2 ) / 3) * 4;

    if (b64Size < qpSize) {
        // Base64 is smallest. Use it.
        encodedWord = [NSString stringWithFormat:@"=?%@?B?%@?=", charsetName, [(NSData *)convertedBytes base64String]];
    } else {
        NSMutableString *encodedContent;
        // Quoted-Printable is smallest (or, at least, not larger than Base64).
        // (Ties go to QP because it's more readable.)
        encodedContent = [[NSMutableString alloc] initWithCapacity:qpSize];
        for(byteIndex = 0; byteIndex < byteCount; byteIndex ++) {
            UInt8 byte = bytePtr[byteIndex];
            if (byte < 128 && qpNonSpecials[byte]) {
                if (byte == 0x20) /* RFC2047 4.2(2) */
                    byte = 0x5F;
                [encodedContent appendLongCharacter:byte];
            } else {
                unichar highNybble, lowNybble;

                highNybble = hex((byte & 0xF0) >> 4);
                lowNybble = hex(byte & 0x0F);
                [encodedContent appendLongCharacter:'='];
                [encodedContent appendLongCharacter:highNybble];
                [encodedContent appendLongCharacter:lowNybble];
            }
        }
        encodedWord = [NSString stringWithFormat:@"=?%@?Q?%@?=", charsetName, encodedContent];
        [encodedContent release];
    }

    CFRelease(convertedBytes);

    return encodedWord;
}

- (NSString *)asRFC2047Phrase
{
    NSString *result;

    if ([self rangeOfCharacterFromSet:nonAtomCharsExceptLWSP].length == 0) {
        /* We look like a sequence of atoms. However, we need to check for strings like "foo =?bl?e?gga?= bar", which have special semantics described in RFC2047. (This test is a little over-cautious but that's OK.) */

        if (!([self rangeOfString:@"=?"].length > 0 &&
              [self rangeOfString:@"?="].length > 0))
            return self;
    }

    /* -asRFC822Word will produce a single double-quoted string for all our text; e.g. if called with [John Q. Public] we'll return ["John Q. Public"] rather than [John "Q." Public]. */
    result = [self asRFC822Word];

    /* If we can't be represented as an RFC822 word, use the extended syntax from RFC2047. */
    if (result == nil)
        result = [self asRFC2047EncodedWord];

    return result;
}

/* Routines for generating non-exponential decimal representations of floats. */

/* The C-style malloc() version. This used to be static, but it turns out to be useful here and there not to have to convert to an NSString and immediately back to an NSData. */
char *OFASCIIDecimalStringFromDouble(double value)
{
    /* Algorithm: Format the value using %g, then adjust the location of the decimal point. */
    
    char *buf;
    char *expptr, *decptr, *digptr;
    char *result;
    int ret;
    
    if (!finite(value))
        return nil;
    
    buf = NULL;
    ret = asprintf(&buf, "%.*g", DBL_DIG, value);
    if (ret < 0 || buf == NULL)
        return nil;
    
    expptr = strchr(buf, 'e');
    if (expptr != NULL) {
        long exponent;
        
        for(digptr = buf; *digptr != 0 && !isdigit(*digptr); digptr ++)
            ;
        OBASSERT(digptr < expptr);
        
        exponent = strtol(expptr+1, NULL, 10);
        *expptr = (char)0;
        
        decptr = strchr(digptr, '.');
        if (decptr != NULL) {
            int tail = (expptr - decptr) - 1;
            exponent -= tail;
            memmove(decptr, decptr+1, expptr - decptr); // this memmove() includes the NUL
        }
        
        int curlen = strlen(buf);
        /* Four possibilities: we might need to append zeroes, prepend zeroes, do nothing, or reinsert the decimal point. */
        if (exponent > 0) {
            /* Append zeroes */
            result = realloc(buf, curlen + exponent + 1);
            memset(result + curlen, '0', exponent);
            result[curlen+exponent] = (char)0;
        } else if (exponent == 0) {
            // Do nothing.
            // notreached, since we use %g instead of %e.
            result = buf;
        } else {
            // Must insert a decimal point
            int prepend = - exponent - strlen(digptr);
            int pfxlen = digptr - buf;
            char *trail;
            if (prepend >= 0) {
                result = realloc(buf, curlen + prepend + 3);
                memmove(result + pfxlen + 2 + prepend, result + pfxlen, 1 + (curlen - pfxlen));
                result[pfxlen] = '0';
                result[pfxlen+1] = '.';
                memset(result + pfxlen + 2, '0', prepend);
            } else {
                /* prepend is negative */
                // notreached, since we use %g instead of %e.
                result = realloc(buf, curlen + 2);
                memmove(result + pfxlen + 1 - prepend, result + pfxlen - prepend, 1 + (curlen + prepend - pfxlen));
                result[pfxlen - prepend] = '.';
            }
            
            trail = result + strlen(result) - 1;
            while (*trail == '0') {
                *trail-- = (char)0;
            }
            if (*trail == '.')
                *trail = (char)0;
        }
    } else {
        result = buf;
    }
    
    return result;
}

// This routine performs a similar service to OFASCIIDecimalStringFromDouble(), but does it in a different way. 
// AFACT it's always superior; we might want to eliminate OFASCIIDecimalStringFromDouble() in favor of this one.
char *OFShortASCIIDecimalStringFromDouble(double value, double eDigits, BOOL allowExponential, BOOL forceLeadingZero)
{
    BOOL negative;
    
    // printf("\nvalue:%g allowExponential=%s forceLeadingZero=%s\n", value, allowExponential?"YES":"NO", forceLeadingZero?"YES":"NO");
    
    if (value < 0) {
        negative = YES;
        value = fabs(value);
    } else if (value > 0) {
        negative = NO;
    } else {
        return strdup("0");
    }
    
    /* Convert the floating-point number into a decimal-floating-point format: value = mantissa * 10 ^ shift */  
    double eDigitsLeftOfDecimal = log(value);
    double digitsRightOfDecimal = ( eDigits - eDigitsLeftOfDecimal ) / log(10);
    double fltShift = ceil(digitsRightOfDecimal);
    int shift = (int)fltShift;  // Integer version of fltShift
    double mantissa = value * pow(10.0, fltShift);
    double mAcceptableSlop = pow(10.0, fltShift - digitsRightOfDecimal);
    OBINVARIANT(mAcceptableSlop >= 1.0);
    OBINVARIANT(mAcceptableSlop < 10.0);
    
    /* Round to the nearest *decimal* digit within the precision of the original number */
    unsigned long decimalMantissaL, decimalMantissaU, decimalMantissaV;
    decimalMantissaL = (unsigned long)ceil(mantissa - 0.5 * mAcceptableSlop);
    decimalMantissaU = (unsigned long)floor(mantissa + 0.5 * mAcceptableSlop);
    
    /* Any mantissa in the range [decimalMantissaL ... decimalMantissaU] inclusive will produce an acceptable result. Check to see if one of them has a shorter representation than the others. */
    unsigned int lastDigit = decimalMantissaL % 10;
    if (lastDigit == 0) {
        decimalMantissaV = decimalMantissaL;
    } else if ( (10 - lastDigit) <= (unsigned int)(decimalMantissaU - decimalMantissaL) ) {
        decimalMantissaV = decimalMantissaL + ( 10 - lastDigit );
    } else {
        decimalMantissaV = (unsigned long)nearbyint(mantissa);
    }
    // printf("\t%lu\t%lu\t%lu\n", decimalMantissaL, decimalMantissaV, decimalMantissaU);
    
    /* Convert to a string of ASCII decimal digits. */
    char *decimalMantissa;
    int decimalMantissaDigits;
    decimalMantissaDigits = asprintf(&decimalMantissa, "%lu", decimalMantissaV);
    
    // printf("e-digits left of dp: %f\ntotal e-digits precision: %f\ndecimal digits right of point: %f (shift=%d)\nmantissa chopped to decimal: \"%s\" (%d chars)\n", eDigitsLeftOfDecimal, eDigits, digitsRightOfDecimal, shift, decimalMantissa, decimalMantissaDigits);
    
    /* Normalize the representation by trimming trailing zeroes */
    while(decimalMantissaDigits > 1 && decimalMantissa[decimalMantissaDigits-1] == '0') {
        decimalMantissaDigits --;
        shift --;
    }
    decimalMantissa[decimalMantissaDigits] = (char)0;
    
    // printf("normalized to: \"%s\" (%d chars) shift=%d\n", decimalMantissa, decimalMantissaDigits, shift);
    
    /* The above is the hard part. The code below is more straightforward, but has to cover a bunch of different cases, so it's long ... */
    
    char *result;
    result = NULL;
    
    if (shift == 0)
        result = decimalMantissa;
    else if (shift < 0) {
        if (allowExponential && shift < -2) {
            /* The exponential representation (which requires at least two more characters, e.g. '477e3') will be shorter than the decimal representation */
            asprintf(&result, "%se%ld", decimalMantissa, -shift);
            free(decimalMantissa);
        } else {
            /* Decimal representation is shorter, or exponential is not allowed */
            result = malloc(decimalMantissaDigits + (-shift) + 1);  // Mantissa, plus trailing zeroes, plus NUL
            memcpy(result, decimalMantissa, decimalMantissaDigits);
            while(shift < 0) {
                result[decimalMantissaDigits++] = '0';
                shift++;
            }
            result[decimalMantissaDigits] = (char)0;
            free(decimalMantissa);
        }
    } else if (shift < decimalMantissaDigits) {
        result = malloc(decimalMantissaDigits + 2);  // Mantissa, infix decimal, trailing NUL
        int digitsLeftOfDecimal = decimalMantissaDigits - shift;
        if (digitsLeftOfDecimal > 0)
            memcpy(result, decimalMantissa, digitsLeftOfDecimal);
        result[digitsLeftOfDecimal] = '.';
        memcpy(result + digitsLeftOfDecimal + 1, decimalMantissa + digitsLeftOfDecimal, decimalMantissaDigits - digitsLeftOfDecimal);
        result[decimalMantissaDigits+1] = (char)0;
        free(decimalMantissa);
    } else {
        int leadingZeroes = shift - decimalMantissaDigits;
        if (allowExponential && (leadingZeroes >= 3 || (forceLeadingZero && leadingZeroes >= 2))) {
            /* Exponential representation (e.g. 43e-5) is shorter than decimal (e.g. .00043) */
            asprintf(&result, "%se%d", decimalMantissa, ( - shift ));
            free(decimalMantissa);
        } else {
            /* Decimal representation is shorter, or exponential is not allowed */
            result = malloc(2 + leadingZeroes + decimalMantissaDigits + 1); // Leading zero, decimal point, leading zeroes, matissa, trailing NUL
            char *cp = result;
            if (forceLeadingZero)
                *(cp++) = '0';
            *(cp++) = '.';
            memset(cp, '0', leadingZeroes);
            memcpy(cp + leadingZeroes, decimalMantissa, decimalMantissaDigits);
            *(cp + leadingZeroes + decimalMantissaDigits) = (char)0;
            free(decimalMantissa);
        }
    }
    
    if (negative) {
        // Prepend a minus sign
        int poslen = strlen(result);
        result = realloc(result, poslen+2);
        memmove(result+1, result, poslen+1);
        result[0] = '-';
    }
    
    return result;
}


NSString *OFCreateDecimalStringFromDouble(double value)
{
    char *buf = OFASCIIDecimalStringFromDouble(value);
    CFStringRef result = CFStringCreateWithCStringNoCopy(kCFAllocatorDefault, buf, kCFStringEncodingASCII, kCFAllocatorMalloc);
    return (NSString *)result;
}

@end
