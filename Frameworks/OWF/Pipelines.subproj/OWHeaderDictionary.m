// Copyright 1997-2005, 2010-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWHeaderDictionary.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "OWContentType.h"
#import "OWDataStreamCharacterCursor.h"
#import "OWParameterizedContentType.h"
#import "OWUnknownDataStreamProcessor.h"

RCS_ID("$Id$")

@interface OWHeaderDictionary (Private)
- (void)_locked_parseParameterizedContentType;
@end

@implementation OWHeaderDictionary

static NSCharacterSet *TSpecialsSet;
static NSCharacterSet *TokenSet;
static NSCharacterSet *NonTokenSet;
static NSCharacterSet *QuotedStringSet;
static NSCharacterSet *NonQuotedStringSet;
static NSString *ContentTypeHeaderKey = @"content-type";
static NSString *ContentDispositionHeaderKey = @"content-disposition";
static BOOL debugHeaderDictionary = NO;

+ (void)initialize;
{
    NSMutableCharacterSet *tmpSet;
    
    OBINITIALIZE;

    // These are from the MIME standard, RFC 1521
    // http://www.oac.uci.edu/indiv/ehood/MIME/1521/04_Content-Type.html

    TSpecialsSet = [[NSCharacterSet characterSetWithCharactersInString:@"()<>@,;:\\\"/[]?="] retain];

    // This is a bit richer than the standard: I'm including non-ASCII.
    tmpSet = [[TSpecialsSet invertedSet] mutableCopy];
    [tmpSet removeCharactersInString:@" "];
    [tmpSet formIntersectionWithCharacterSet:[[NSCharacterSet controlCharacterSet] invertedSet]];
    
    NonTokenSet = [[tmpSet invertedSet] retain];
    
    [tmpSet addCharactersInString:@"/"];

    // Make it non-mutable
    TokenSet = [tmpSet copy];
    [tmpSet release];
    
    NonQuotedStringSet = [[NSCharacterSet characterSetWithCharactersInString:@"\"\n\\"] retain];
    QuotedStringSet = [[NonQuotedStringSet invertedSet] retain];
}

+ (void)setDebug:(BOOL)debugMode;
{
    debugHeaderDictionary = debugMode;
}

- init;
{
    if (!(self = [super init]))
	return nil;

    headerDictionary = [[OFMultiValueDictionary alloc] initWithCaseInsensitiveKeys: YES];
    parameterizedContentTypeLock = [[NSLock alloc] init];
    parameterizedContentType = nil;

    return self;
}

- (void)dealloc;
{
    [headerDictionary release];
    [parameterizedContentTypeLock release];
    [parameterizedContentType release];
    [super dealloc];
}

- (NSArray *)stringArrayForKey:(NSString *)aKey;
{
    return [headerDictionary arrayForKey:aKey];
}

- (NSString *)firstStringForKey:(NSString *)aKey;
{
    return [headerDictionary firstObjectForKey:aKey];
}

- (NSString *)lastStringForKey:(NSString *)aKey;
{
    return [headerDictionary lastObjectForKey:aKey];
}

- (NSEnumerator *)keyEnumerator;
{
    return [headerDictionary keyEnumerator];
}

- (OFMultiValueDictionary *)dictionarySnapshot
{
    return [[headerDictionary mutableCopy] autorelease];
}

- (void)addString:(NSString *)aString forKey:(NSString *)aKey;
{
    if (parameterizedContentType && [aKey compare:ContentTypeHeaderKey options: NSCaseInsensitiveSearch] == NSOrderedSame) {
        [parameterizedContentTypeLock lock];
        [parameterizedContentType release];
        parameterizedContentType = nil;
        [parameterizedContentTypeLock unlock];
    }
    [headerDictionary addObject:aString forKey:aKey];
}

- (void)addStringsFromDictionary:(OFMultiValueDictionary *)source
{
    NSEnumerator *keyEnumerator = [source keyEnumerator];
    NSString *aKey;

    while( (aKey = [keyEnumerator nextObject]) != nil) {
        NSArray *values = [source arrayForKey:aKey];
        NSUInteger valueCount, valueIndex;
        
        if (!values || !(valueCount = [values count]))
            continue;
        
        if ([aKey compare:ContentTypeHeaderKey options: NSCaseInsensitiveSearch] == NSOrderedSame) {
            for(valueIndex = 0; valueIndex < valueCount; valueIndex ++)
                [self addString:[values objectAtIndex:valueIndex] forKey:aKey];
        } else {
            // optimized path
            [headerDictionary addObjects:values forKey:aKey];
        }
    }
}

- (void)parseRFC822Header:(NSString *)aHeader;
{
    NSRange colonRange;
    NSString *key, *value;

    // Use rangeOfString: rather than having a 8k character set to hold a single character
    colonRange = [aHeader rangeOfString: @":"];
    if (colonRange.length == 0)
	return;

    key = [aHeader substringToIndex:colonRange.location];
    value = [[aHeader substringFromIndex:NSMaxRange(colonRange)] stringByRemovingSurroundingWhitespace];
    [self addString:value forKey:key];
}

- (void)readRFC822HeadersFrom:(id)readLineSource;
{
    NSString *header = nil;

    do {
	NSString *newLine;

	newLine = [readLineSource readLine];
        if ([newLine isEqualToString:@"."])
            break;
	if (debugHeaderDictionary)
	    NSLog(@"%@", newLine);
	if ([newLine hasLeadingWhitespace])
	    header = [header stringByAppendingString:newLine];
	else {
	    if (header)
		[self parseRFC822Header:header];
	    header = newLine;
	}
    } while (header && [header length] > 0);	
}

- (void)readRFC822HeadersFromDataCursor:(OFDataCursor *)aCursor;
{
    [self readRFC822HeadersFrom:aCursor];
}

- (void)readRFC822HeadersFromCursor:(OWDataStreamCursor *)aCursor;
{
    OWDataStreamCharacterCursor *characterCursor;
    
    characterCursor = [[OWDataStreamCharacterCursor alloc] initForDataCursor:aCursor encoding:kCFStringEncodingISOLatin1];
    NS_DURING {
        [self readRFC822HeadersFrom:characterCursor];
        [characterCursor discardReadahead];
    } NS_HANDLER {
        [characterCursor release];
        [localException raise];
    } NS_ENDHANDLER;
    [characterCursor release];
}

- (void)readRFC822HeadersFromScanner:(OWDataStreamScanner *)aScanner;
{
    [self readRFC822HeadersFrom: aScanner];
}

- (void)readRFC822HeadersFromSocketStream:(ONSocketStream *)aSocketStream;
{
    [self readRFC822HeadersFrom:aSocketStream];
}

- (NSArray *)formatRFC822HeaderLines
{
    NSArray *keys = [headerDictionary allKeys];
    NSUInteger keyIndex, keyCount;
    NSMutableArray *lines;
    NSString *separatorString = @": ";
    
    keyCount = [keys count];
    lines = [[NSMutableArray alloc] initWithCapacity:keyCount];
    [lines autorelease];
    for(keyIndex = 0; keyIndex < keyCount; keyIndex ++) {
        NSString *thisKey = [keys objectAtIndex:keyIndex];
        NSArray *values = [headerDictionary arrayForKey:thisKey];
        NSUInteger valueIndex, valueCount;
        
        valueCount = [values count];
        for(valueIndex = 0; valueIndex < valueCount; valueIndex ++) {
            NSString *thisValue = [values objectAtIndex:valueIndex];
            NSMutableString *buffer;
            
            // TODO: Deal with continuation lines (for embedded newlines), and possibly check for illegal characters in the keys and values
            
            buffer = [[NSMutableString alloc] initWithCapacity:[thisKey length] + [thisValue length] + [separatorString length]];
            [buffer appendString:thisKey];
            [buffer appendString:separatorString];
            [buffer appendString:thisValue];
            
            [lines addObject:buffer];
            
            [buffer release];
        }
    }
    
    
    return lines;
}

- (OWParameterizedContentType *)parameterizedContentType;
{
    OWParameterizedContentType *returnValue;
    
    [parameterizedContentTypeLock lock];
    if (parameterizedContentType == nil)
        [self _locked_parseParameterizedContentType];
    returnValue = [parameterizedContentType retain];
    [parameterizedContentTypeLock unlock];
    return [returnValue autorelease];
}

#if 0
- (OWContentType *)contentType;
{
    return [[self parameterizedContentType] type];
}
#endif

- (OWContentType *)contentEncoding;
{
    NSString *headerString;
    OWContentType *contentEncoding;

    headerString = [self lastStringForKey:@"content-encoding"];
    if (!headerString || [headerString isEqualToString:@""])
	return nil;
    contentEncoding = [OWContentType contentTypeForString:[@"encoding/" stringByAppendingString:headerString]];
    return contentEncoding;
}

- (NSString *)contentDispositionFilename;
{
    OFMultiValueDictionary *contentDispositionParameters;
    
    contentDispositionParameters = [[[OFMultiValueDictionary alloc] init] autorelease];
    [isa parseParameterizedHeader:[self lastStringForKey:ContentDispositionHeaderKey] intoDictionary:contentDispositionParameters valueChars:TokenSet];
    
    return [contentDispositionParameters lastObjectForKey:@"filename"];
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];

    if (headerDictionary)
	[debugDictionary setObject:headerDictionary forKey:@"headerDictionary"];
        
    if (parameterizedContentType)
        [debugDictionary setObject:parameterizedContentType forKey:@"parameterizedContentType"];

    return debugDictionary;
}

+ (NSString *)parseParameterizedHeader:(NSString *)aString intoDictionary:(OFMultiValueDictionary *)parameters valueChars:(NSCharacterSet *)validValues;
{
    NSScanner *scanner;
    NSString *bareHeader;

    if (![aString containsString:@";"]) {
        return aString;
    }
    
    if (!validValues)
        validValues = TokenSet;

    scanner = [NSScanner scannerWithString:aString];
    if (![scanner scanCharactersFromSet:validValues intoString:&bareHeader]) {
        return aString;
    }

    while ([scanner scanString:@";" intoString:NULL]) {
        NSString *attribute, *value;

        if (![scanner scanCharactersFromSet:TokenSet intoString:&attribute])
            break;
        if (![scanner scanString:@"=" intoString:NULL])
            break;

        if ([scanner scanString:@"\"" intoString:NULL]) {
            if (![scanner scanStringWithEscape:@"\\" terminator:@"\"" intoString:&value])
                break;
        } else {
            if (![scanner scanCharactersFromSet:validValues intoString:&value])
                break;
        }
        [parameters addObject:value forKey:[attribute lowercaseString]];
    }

    return bareHeader;
}

+ (NSString *)formatHeaderParameter:(NSString *)name value:(NSString *)value;
{
    NSString *result;
        
    if ([value rangeOfCharacterFromSet:NonTokenSet].length > 0 || [value length] == 0) {
        NSUInteger searchIndex;
        NSRange foundRange;
        NSMutableString *escapedValue = [value mutableCopy];

        searchIndex = 0;
        for(;;) {
            foundRange = [escapedValue rangeOfCharacterFromSet:NonQuotedStringSet options:0 range:NSMakeRange(searchIndex, [escapedValue length] - searchIndex)];
            if (foundRange.length == 0)
                break;
            
            [escapedValue replaceCharactersInRange:NSMakeRange(foundRange.location, 0) withString:@"\\"];
            searchIndex = foundRange.location + foundRange.length + 1;
        }

        result = [NSString stringWithStrings:name, @"=\"", escapedValue, @"\"", nil];
        
        [escapedValue release];
    } else {

        result = [NSString stringWithStrings:name, @"=", value, nil];

    }
        
    return result;
}

+ (NSString *)formatHeaderParameters:(OFMultiValueDictionary *)parameters onlyLastValue:(BOOL)onlyLast;
{
    NSMutableArray *portions = [[NSMutableArray alloc] init];
    NSEnumerator *keyEnumerator;
    NSString *aKey;
    NSString *result;
    
    keyEnumerator = [parameters keyEnumerator];
    while((aKey = [keyEnumerator nextObject])) {
        if (onlyLast) {
            [portions addObject:[self formatHeaderParameter:aKey value:[parameters lastObjectForKey:aKey]]];
        } else {
            NSUInteger valueCount, valueIndex;
            NSArray *values = [parameters arrayForKey:aKey];
            valueCount = [values count];
            for(valueIndex = 0; valueIndex < valueCount; valueIndex ++) {
                [portions addObject:[self formatHeaderParameter:aKey value:[values objectAtIndex:valueIndex]]];
            }
        }
    }

    result = [portions componentsJoinedByString:@"; "];
    
    [portions release];
    
    return result;
}

+ (NSMutableArray *)splitHeaderValues:(NSArray *)headers
{
    NSMutableArray *values;
    NSUInteger headerIndex, headerCount;
    NSCharacterSet *whitespaceAndNewlineCharacterSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    values = [NSMutableArray array];

    headerCount = [headers count];
    for(headerIndex = 0; headerIndex < headerCount; headerIndex ++) {
        NSScanner *scan = [[NSScanner alloc] initWithString:[headers objectAtIndex:headerIndex]];

        [scan setCharactersToBeSkipped:whitespaceAndNewlineCharacterSet];

        for(;;) {
            NSRange valueRange;
            
            while ([scan scanString:@"," intoString:NULL])
                [values addObject:@""];
            
            if ([scan isAtEnd])
                break;

            valueRange.location = [scan scanLocation];

            for(;;) {
                NSUInteger location;
                
                [scan scanUpToCharactersFromSet:TSpecialsSet intoString:NULL];

                location = [scan scanLocation];
                
                if ([scan isAtEnd] || [scan scanString:@"," intoString:NULL]) {
                    valueRange.length = location - valueRange.location;
                    break;
                }
                
                if ([scan scanString:@"\"" intoString:NULL]) {
                    [scan scanStringWithEscape:@"\\" terminator:@"\"" intoString:NULL];
                } else {
                    [scan setScanLocation:location+1];
                }
            }

            [values addObject:[[scan string] substringWithRange:valueRange]];
        }

        [scan release];
    }

    return values;
}

@end

@implementation OWHeaderDictionary (Private)

- (void)_locked_parseParameterizedContentType;
{
    if (parameterizedContentType != nil)
        return;

    parameterizedContentType = [[OWParameterizedContentType contentTypeForString:[self lastStringForKey:ContentTypeHeaderKey]] retain];
    if (parameterizedContentType == nil)
        parameterizedContentType = [[OWParameterizedContentType alloc] initWithContentType:[OWContentType unknownContentType]];
}

@end
