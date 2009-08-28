// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSString-OFReplacement.h>

#import <OmniFoundation/NSString-OFSimpleMatching.h>

RCS_ID("$Id$");

@implementation NSString (OFReplacement)

- (NSString *)stringByRemovingPrefix:(NSString *)prefix;
{
    NSRange aRange;
    
    aRange = [self rangeOfString:prefix options:NSAnchoredSearch];
    if ((aRange.length == 0) || (aRange.location != 0))
        return [[self retain] autorelease];
    return [self substringFromIndex:aRange.location + aRange.length];
}

- (NSString *)stringByRemovingSuffix:(NSString *)suffix;
{
    if (![self hasSuffix:suffix])
        return [[self retain] autorelease];
    return [self substringToIndex:[self length] - [suffix length]];
}

- (NSString *)stringByRemovingSurroundingWhitespace;
{
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)stringByRemovingString:(NSString *)removeString
{
    NSArray *lines;
    NSMutableString *newString;
    NSString *returnValue;
    unsigned int lineIndex, lineCount;
    
    if (![self containsString:removeString])
	return [[self copy] autorelease];
    newString = [[NSMutableString alloc] initWithCapacity:[self length]];
    lines = [self componentsSeparatedByString:removeString];
    lineCount = [lines count];
    for (lineIndex = 0; lineIndex < lineCount; lineIndex++)
	[newString appendString:[lines objectAtIndex:lineIndex]];
    returnValue = [newString copy];
    [newString release];
    return [returnValue autorelease];
}

- (NSString *)stringByReplacingAllOccurrencesOfString:(NSString *)stringToReplace withString:(NSString *)replacement;
{
    NSRange searchRange = NSMakeRange(0, [self length]);
    NSRange foundRange = [self rangeOfString:stringToReplace options:0 range:searchRange];
    
    // If stringToReplace is not found, then there's nothing to replace -- just return self
    if (foundRange.length == 0)
        return [[self copy] autorelease];
    
    NSMutableString *copy = [self mutableCopy];
    unsigned int replacementLength = [replacement length];
    
    while (foundRange.length > 0) {
        [copy replaceCharactersInRange:foundRange withString:replacement];
        
        searchRange.location = foundRange.location + replacementLength;
        searchRange.length = [copy length] - searchRange.location;
        
        foundRange = [copy rangeOfString:stringToReplace options:0 range:searchRange];
    }
    
    // Avoid an autorelease
    NSString *result = [copy copy];
    [copy release];
    
    return [result autorelease];
}

- (NSString *)stringByReplacingCharactersInSet:(NSCharacterSet *)set withString:(NSString *)replaceString;
{
    if (![self containsCharacterInSet:set])
	return [[self retain] autorelease];
    
    NSMutableString *newString = [[self mutableCopy] autorelease];
    [newString replaceAllOccurrencesOfCharactersInSet:set withString:replaceString];
    return newString;
}

struct DictionaryVariableSubstitution {
    BOOL removeUndefinedKeys;
    NSDictionary *dictionary;
};

static NSString *_variableSubstitutionInDictionary(NSString *key, void *context)
{
    struct DictionaryVariableSubstitution *info = (struct DictionaryVariableSubstitution *)context;
    NSString *value = [info->dictionary objectForKey:key];
    if (value == nil && info->removeUndefinedKeys)
	value = @"";
    return value;
}

- (NSString *)stringByReplacingKeysInDictionary:(NSDictionary *)keywordDictionary startingDelimiter:(NSString *)startingDelimiterString endingDelimiter:(NSString *)endingDelimiterString removeUndefinedKeys: (BOOL)removeUndefinedKeys;
{
    struct DictionaryVariableSubstitution info;
    
    info.removeUndefinedKeys = removeUndefinedKeys;
    info.dictionary = keywordDictionary;
    return [self stringByReplacingKeys:_variableSubstitutionInDictionary startingDelimiter:startingDelimiterString endingDelimiter:endingDelimiterString context:&info];
}

- (NSString *)stringByReplacingKeysInDictionary:(NSDictionary *)keywordDictionary startingDelimiter:(NSString *)startingDelimiterString endingDelimiter:(NSString *)endingDelimiterString;
{
    return [self stringByReplacingKeysInDictionary:keywordDictionary startingDelimiter:startingDelimiterString endingDelimiter:endingDelimiterString removeUndefinedKeys:NO];
}

- (NSString *)stringByReplacingKeys:(OFVariableReplacementFunction)replacer startingDelimiter:(NSString *)startingDelimiterString endingDelimiter:(NSString *)endingDelimiterString context:(void *)context;
{
    NSScanner *scanner = [NSScanner scannerWithString:self];
    
    // <bug://bugs/11340> (Whitespace deletion bug in -stringByReplacingKeysInDictionary:startingDelimiter:endingDelimiter:removeUndefinedKeys:)
    // Really there is no reason to use NSScanner here; could just use -rangeOfString:options:range:...
    [scanner setCharactersToBeSkipped:[NSCharacterSet characterSetWithRange:NSMakeRange(0, 0)]];
    
    NSMutableString *interpolatedString = [NSMutableString string];
    NSString *scannerOutput;
    BOOL didInterpolate = NO;
    
    while (![scanner isAtEnd]) {
        NSString *key = nil;
        NSString *value;
        BOOL gotInitialString, gotStartDelimiter, gotEndDelimiter;
        BOOL gotKey;
        
        gotInitialString = [scanner scanUpToString:startingDelimiterString intoString:&scannerOutput];
        if (gotInitialString) {
            [interpolatedString appendString:scannerOutput];
        }
        
        gotStartDelimiter = [scanner scanString:startingDelimiterString intoString:NULL];
        gotKey = [scanner scanUpToString:endingDelimiterString intoString:&key];
        gotEndDelimiter = [scanner scanString:endingDelimiterString intoString:NULL];
        
        if (gotKey) {
	    value = replacer(key, context);
	    if (value == nil || ![value isKindOfClass:[NSString class]]) {
		if (gotStartDelimiter)
		    [interpolatedString appendString:startingDelimiterString];
		[interpolatedString appendString:key];
		if (gotEndDelimiter)
		    [interpolatedString appendString:endingDelimiterString];
	    } else {
                [interpolatedString appendString:value];
                didInterpolate = YES;
	    }
        } else {
            if (gotStartDelimiter)
                [interpolatedString appendString:startingDelimiterString];
            if (gotEndDelimiter)
                [interpolatedString appendString:endingDelimiterString];
        }
    }
    return didInterpolate ? [[interpolatedString copy] autorelease] : self;
}

- (NSString *)stringByPerformingReplacement:(OFSubstringReplacementFunction)replacer
                               onCharacters:(NSCharacterSet *)replaceMe
                                    context:(void *)context
                                    options:(NSStringCompareOptions)options
                                      range:(NSRange)touchMe
{
    // Early out, if possible.
    NSRange foundChar = [self rangeOfCharacterFromSet:replaceMe options:options range:touchMe];
    if (foundChar.length == 0)
        return self;

    NSMutableString *buffer = [self mutableCopy];
    
    NSUInteger searchPosition = touchMe.location;
    NSUInteger searchEndPosition = touchMe.location + touchMe.length;
    
    while (searchPosition < searchEndPosition) {
        NSRange searchRange = NSMakeRange(searchPosition, searchEndPosition - searchPosition);
        foundChar = [buffer rangeOfCharacterFromSet:replaceMe options:options range:searchRange];
        if (foundChar.location == NSNotFound)
            break;
        
        NSString *replacement = (*replacer)(buffer, &foundChar, context);
        
        if (replacement != nil) {
            NSUInteger replacementStringLength = [replacement length];
            [buffer replaceCharactersInRange:foundChar withString:replacement];
            searchPosition = foundChar.location + replacementStringLength;
            searchEndPosition = searchEndPosition + replacementStringLength - foundChar.length;
        } else {
            searchPosition = NSMaxRange(foundChar);
        }
    }
    
    // Make the result immutable
    NSString *result = [[buffer copy] autorelease];
    [buffer release];
    return result;
}

- (NSString *)stringByPerformingReplacement:(OFSubstringReplacementFunction)replacer
                               onCharacters:(NSCharacterSet *)replaceMe;
{
    return [self stringByPerformingReplacement: replacer
                                  onCharacters: replaceMe
                                       context: NULL
                                       options: 0
                                         range: (NSRange){0, [self length]}];
}


@end

@implementation NSMutableString (OFReplacement)

- (void)replaceAllOccurrencesOfCharactersInSet:(NSCharacterSet *)set withString:(NSString *)replaceString;
{
    NSRange characterRange, searchRange;
    unsigned int replaceStringLength;
    
    searchRange = NSMakeRange(0, [self length]);
    replaceStringLength = [replaceString length];
    while ((characterRange = [self rangeOfCharacterFromSet:set options:NSLiteralSearch range:searchRange]).length) {
	[self replaceCharactersInRange:characterRange withString:replaceString];
	searchRange.location = characterRange.location + replaceStringLength;
	searchRange.length = [self length] - searchRange.location;
	if (searchRange.length == 0)
	    break; // Might as well save that extra method call.
    }
}

@end

