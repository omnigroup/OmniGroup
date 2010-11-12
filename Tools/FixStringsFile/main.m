// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// RCS_ID("$Id$")

#include <Foundation/Foundation.h>


static void fixStringsFile(NSString *path);

static NSString *_quotedString(NSString *str)
{
    static NSCharacterSet *CharactersNeedingQuoting = nil;
    if (!CharactersNeedingQuoting)
        CharactersNeedingQuoting = [[NSCharacterSet characterSetWithCharactersInString:@"\\\"\n"] retain];
    
    if ([str rangeOfCharacterFromSet:CharactersNeedingQuoting].length == 0)
        return str;
    
    NSMutableString *result = [str mutableCopy];
    [result replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:(NSRange){0, [result length]}]; // must be first to avoid quoting the backslashes entered here
    [result replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:(NSRange){0, [result length]}];
    [result replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:(NSRange){0, [result length]}];
    return result;
}

static NSString *_smartQuotedString(NSString *source, NSString *asciiQuote, unichar leftQuoteCharacter, unichar rightQuoteCharacter)
{
    if ([source rangeOfString:asciiQuote].length == 0)
        return source;
    
    NSMutableString *result = [[source mutableCopy] autorelease];
    NSString *leftQuoteString = [NSString stringWithFormat:@"%C", leftQuoteCharacter];
    NSString *rightQuoteString = [NSString stringWithFormat:@"%C", rightQuoteCharacter];
    
    NSUInteger length = [source length];
    while (YES) {
        // Look for pairs of matching quotes.  This could misfire if you have a string with two sets of inches, though they'd have to be in the format string itself.
        NSRange firstRange = [result rangeOfString:asciiQuote options:NSLiteralSearch];
        if (firstRange.length == 0 || NSMaxRange(firstRange) >= length) // Don't search for a 2nd quote past the end of the string
            break;
        
        NSUInteger nextIndex = NSMaxRange(firstRange);
        NSRange secondRange = [result rangeOfString:asciiQuote options:NSLiteralSearch range:NSMakeRange(nextIndex, length - nextIndex)];
        if (secondRange.length == 0) {
            NSLog(@"Found mismatched use of '%@' in '%@'.  Please check that the result is correct.", asciiQuote, source);
            break;
        }
        
        [result replaceCharactersInRange:firstRange withString:leftQuoteString];
        [result replaceCharactersInRange:secondRange withString:rightQuoteString];
    }
    
    return result;
}

@interface Entry : NSObject
{
@private
    NSArray *_comments;
    NSDictionary *_pairs;
}

- initWithComments:(NSArray *)comments pairs:(NSDictionary *)pairs;
@property(nonatomic,readonly) NSString *minimalSource;
- (NSComparisonResult)compareBySource:(Entry *)entry;
@end

@implementation Entry

NSString *_transformedTranslation(NSString *translation)
{
    // Replace ... with real ellipsis characters
    if ([translation rangeOfString:@"..."].length != 0) {
        static NSString *ellipsisString = nil;
        if (!ellipsisString) {
            unichar c = 0x2026;
            ellipsisString = [[NSString alloc] initWithCharacters:&c length:1];
        }
        
        NSMutableString *ellipsizedString = [[translation mutableCopy] autorelease];
        [ellipsizedString replaceOccurrencesOfString:@"..." withString:ellipsisString options:0 range:NSMakeRange(0, [ellipsizedString length])];
        translation = ellipsizedString;
    }
    
    // Replace "..." with curly quotes
    translation = _smartQuotedString(translation, @"\"", 8220, 8221);
    
    // This gets quite a few bad matches due to contractions and possessives.  We could be smarter by requiring the starting quote to be at the beginning of the string or have a preceeding non-alpha character (likewise for the ending quote).  This would be significantly more complicated and really we should just use "..." in most places.  We won't need embedded quotes in UI strings.
    //translation = _smartQuotedString(translation, @"'", 8216, 8217);
    
    return translation;
}

- initWithComments:(NSArray *)comments pairs:(NSDictionary *)pairs;
{
    _comments = [comments copy];
    
    NSMutableDictionary *transformedPairs = [NSMutableDictionary dictionary];
    for (NSString *source in pairs) {
        NSString *translation = [pairs objectForKey:source];
        [transformedPairs setObject:_transformedTranslation(translation) forKey:source];
    }
    _pairs = [transformedPairs copy];
    
    return self;
}

- (void)dealloc;
{
    [_comments release];
    [_pairs release];
}

- (NSComparisonResult)compareBySource:(Entry *)entry;
{
    // We keep any multi-pair cross product locations together. Sort between entries by comparing the minimal source.
    return [self.minimalSource localizedStandardCompare:entry.minimalSource];
}

- (NSString *)minimalSource;
{
    NSString *minimal = nil;
    for (NSString *source in _pairs) {
        if (!minimal || [minimal localizedStandardCompare:source] == NSOrderedDescending)
            minimal = source;
    }
    return minimal;
}

- (void)appendToString:(NSMutableString *)string;
{
    [string appendString:@"/* "];
    NSUInteger commentIndex, commentCount = [_comments count];
    for (commentIndex = 0; commentIndex < commentCount; commentIndex++) {
        if (commentIndex)
            [string appendString:@"\n   "];
        [string appendString:[_comments objectAtIndex:commentIndex]];
    }
    [string appendString:@" */\n"];
    
    for (NSString *source in [[_pairs allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        NSString *translation = [_pairs objectForKey:source];
        [string appendFormat:@"\"%@\" = \"%@\";\n", _quotedString(source), _quotedString(translation)];
    }
}
@end


int main (int argc, const char * argv[])
{
    
    if (argc < 2) {
	fprintf(stderr, "usage: %s file1 ... fileN\n", argv[0]);
	return 1;
    }
    
    int argi;
    for (argi = 1; argi < argc; argi++) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:argv[argi] length:strlen(argv[argi])];
	fixStringsFile(path);
	[pool release];
    }
    
    return 0;
}

static void fixStringsFile(NSString *path)
{
    NSData *fileData = [[[NSData alloc] initWithContentsOfFile:path] autorelease];
    if (!fileData) {
	NSLog(@"Unable to read file '%@'", path);
	exit(1);
    }
    
    // Allow loading both UTF-16 and UTF-8 files.  -[NSString initWithData:encoding:] with NSUnicodeStringEncoding doesn't require the BOM, so if the file is UTF-8, it would just produce gibberish.
    if ([fileData length] < 2) {
	// Nothing interesting anyway -- probably just empty.
	return;
    }
    uint8_t byte0 = ((const uint8_t *)[fileData bytes])[0];
    uint8_t byte1 = ((const uint8_t *)[fileData bytes])[1];
    
    NSString *fileString = nil;
    
    if ((byte0 == 0xff && byte1 == 0xfe) || (byte0 == 0xfe && byte1 == 0xff))
	fileString = [[NSString alloc] initWithData:fileData encoding:NSUnicodeStringEncoding];
    
#if 0 && defined(DEBUG_bungi)
    if (fileString)
	NSLog(@"Loaded %@ as UTF-16, length = %d", path, [fileString length]);
#endif
    
    if (!fileString) {
	fileString = [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
#if 0 && defined(DEBUG_bungi)
	if (fileString)
	    NSLog(@"Loaded %@ as UTF-8, length = %d", path, [fileString length]);
#endif
    }
    
    if (!fileString) {
	NSLog(@"Unable to interpret file '%@' as UTF-8 or UTF-16.", path);
	exit(1);
    }
    
    NSMutableArray *entries = [NSMutableArray array];
    
    NSScanner *scanner = [[NSScanner alloc] initWithString:fileString];
    [fileString release];
    while (![scanner isAtEnd]) {
	if (![scanner scanString:@"/*" intoString:NULL]) {
	    NSLog(@"no starting comment found, but not at end (at position %ld)", [scanner scanLocation]);
	    exit(1);
	}
        
	NSString *commentString = nil;
	if (![scanner scanUpToString:@"*/" intoString:&commentString]) {
	    NSLog(@"Unterminated comment in '%@'", path);
	    exit(1);
	}
	if (![scanner scanString:@"*/" intoString:NULL]) {
	    NSLog(@"Unable to read expected comment termination in '%@'", path);
	    exit(1);
	}
        
	commentString = [commentString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; // up-to leaves the trailing space
        
	NSMutableArray *comments = [NSMutableArray arrayWithArray:[commentString componentsSeparatedByString:@"\n"]];
	NSUInteger commentIndex = [comments count];
	while (commentIndex--) {
	    NSString *comment = [[comments objectAtIndex:commentIndex] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	    [comments replaceObjectAtIndex:commentIndex withObject:comment];
	}
	[comments sortUsingSelector:@selector(localizedStandardCompare:)];
	
	NSString *keyValue;
	if (![scanner scanUpToString:@"/*" intoString:&keyValue]) {
	    NSLog(@"Missing key-value pair in '%@'", path);
	    exit(1);
	}
	
        //NSLog(@"key/value = '%@'", keyValue);
        NSDictionary *dict = [keyValue propertyList]; // So we don't have to parse the string quoting and such.
        
        // genstrings can emit more than one key/value pair per comment for the cross-product style replacements (see input.m's test).
        Entry *entry = [[Entry alloc] initWithComments:comments pairs:dict];
        [entries addObject:entry];
        [entry release];
    }
    [scanner release];
    
    NSMutableString *output = [NSMutableString string];
    {
	[entries sortUsingSelector:@selector(compareBySource:)];
        
	NSUInteger entryIndex, entryCount = [entries count];
	for (entryIndex = 0; entryIndex < entryCount; entryIndex++) {
	    [[entries objectAtIndex:entryIndex] appendToString:output];
	    [output appendString:@"\n"];
	}
    }
    
    NSData *resultData = [output dataUsingEncoding:NSUTF8StringEncoding];
    if (![resultData writeToFile:path atomically:YES]) {
        NSLog(@"Unable to write '%@'", path);
        exit(1);
    }
}
