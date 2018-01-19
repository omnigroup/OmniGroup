// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFHTTPHeaderDictionary.h>

#import <OmniFoundation/NSScanner-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/OFMultiValueDictionary.h>
#import <OmniFoundation/OFStringScanner.h>

RCS_ID("$Id$")

@interface OFCharacterScanner () <OFHTTPHeaderDictionaryReadLineSource>
@end

@implementation OFHTTPHeaderDictionary
{
    OFMultiValueDictionary *_headerDictionary;
}

static NSCharacterSet *TokenSet;
static NSCharacterSet *NonTokenSet;
static NSCharacterSet *TSpecialsSet;
static NSCharacterSet *QuotedStringSet;
static NSCharacterSet *NonQuotedStringSet;

NSString * const OFHTTPContentDispositionHeaderKey = @"content-disposition";
NSString * const OFHTTPContentTypeHeaderKey = @"content-type";

+ (void)initialize;
{
    OBINITIALIZE;
    
    NSMutableCharacterSet *tmpSet;
    
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

+ (NSString *)parseParameterizedHeader:(NSString *)aString intoDictionary:(OFMultiValueDictionary *)parameters valueChars:(NSCharacterSet *)validValues;
{
    if (![aString containsString:@";"])
        return aString;
    
    if (!validValues)
        validValues = TokenSet;
    
    NSString *bareHeader;
    NSScanner *scanner = [NSScanner scannerWithString:aString];
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

- init;
{
    if (!(self = [super init]))
	return nil;

    _headerDictionary = [[OFMultiValueDictionary alloc] initWithCaseInsensitiveKeys:YES];
    
    return self;
}

- (void)dealloc;
{
    [_headerDictionary release];
    [super dealloc];
}

- (NSArray <NSString *> *)stringArrayForKey:(NSString *)aKey;
{
    return [_headerDictionary arrayForKey:aKey];
}

- (NSString *)firstStringForKey:(NSString *)aKey;
{
    return [_headerDictionary firstObjectForKey:aKey];
}

- (NSString *)lastStringForKey:(NSString *)aKey;
{
    return [_headerDictionary lastObjectForKey:aKey];
}

- (NSEnumerator *)keyEnumerator;
{
    return [_headerDictionary keyEnumerator];
}

- (OFMultiValueDictionary *)dictionarySnapshot
{
    return [[_headerDictionary mutableCopy] autorelease];
}

- (void)addString:(NSString *)aString forKey:(NSString *)aKey;
{
    [_headerDictionary addObject:aString forKey:aKey];
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
        
        if ([aKey compare:OFHTTPContentTypeHeaderKey options: NSCaseInsensitiveSearch] == NSOrderedSame) {
            for(valueIndex = 0; valueIndex < valueCount; valueIndex ++)
                [self addString:[values objectAtIndex:valueIndex] forKey:aKey];
        } else {
            // optimized path
            [_headerDictionary addObjects:values forKey:aKey];
        }
    }
}

- (NSString *)contentDispositionFilename;
{
    OFMultiValueDictionary *contentDispositionParameters;
    
    contentDispositionParameters = [[[OFMultiValueDictionary alloc] init] autorelease];
    [[self class] parseParameterizedHeader:[self lastStringForKey:OFHTTPContentDispositionHeaderKey] intoDictionary:contentDispositionParameters valueChars:TokenSet];
    
    return [contentDispositionParameters lastObjectForKey:@"filename"];
}

- (NSArray *)formatRFC822HeaderLines
{
    NSString *separatorString = @": ";
    NSMutableArray *lines = [NSMutableArray array];
    
    for (NSString *thisKey in [_headerDictionary allKeys]) {
        for (NSString *thisValue in [_headerDictionary arrayForKey:thisKey]) {
            // TODO: Deal with continuation lines (for embedded newlines), and possibly check for illegal characters in the keys and values
            NSMutableString *buffer = [[NSMutableString alloc] initWithCapacity:[thisKey length] + [thisValue length] + [separatorString length]];
            [buffer appendString:thisKey];
            [buffer appendString:separatorString];
            [buffer appendString:thisValue];
            
            [lines addObject:buffer];
            
            [buffer release];
        }
    }
    
    
    return lines;
}

- (void)_parseRFC822Header:(NSString *)aHeader;
{
    // Use rangeOfString: rather than having a 8k character set to hold a single character
    NSRange colonRange = [aHeader rangeOfString:@":"];
    if (colonRange.length == 0)
	return;

    NSString *key = [aHeader substringToIndex:colonRange.location];
    NSString *value = [[aHeader substringFromIndex:NSMaxRange(colonRange)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self addString:value forKey:key];
}

- (void)readRFC822HeadersFromReadLineSource:(id <OFHTTPHeaderDictionaryReadLineSource>)readLineSource;
{
    NSString *header = nil;

    do {
	NSString *newLine = [readLineSource readLine];
	if ([newLine hasLeadingWhitespace]) {
	    header = [header stringByAppendingString:newLine];
            continue;
        }

        if (header != nil) {
            [self _parseRFC822Header:header];
        }

        header = newLine;
        if ([newLine isEqualToString:@"."]) {
            break;
        }
    } while (header && [header length] > 0);
}

- (void)readRFC822HeadersFromString:(NSString *)string;
{
    OFCharacterScanner *scanner = [[OFStringScanner alloc] initWithString:string];
    [self readRFC822HeadersFromReadLineSource:scanner];
    [scanner release];
}

+ (NSString *)formatHeaderParameter:(NSString *)name value:(NSString *)value;
{
    NSString *result;
    
    if ([value rangeOfCharacterFromSet:NonTokenSet].length > 0 || [value length] == 0) {
        NSMutableString *escapedValue = [value mutableCopy];
        
        NSUInteger searchIndex = 0;
        for(;;) {
            NSRange foundRange = [escapedValue rangeOfCharacterFromSet:NonQuotedStringSet options:0 range:NSMakeRange(searchIndex, [escapedValue length] - searchIndex)];
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

#pragma mark - Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    
    if (_headerDictionary)
	[dict setObject:_headerDictionary forKey:@"headerDictionary"];
    
    return dict;
}

@end
