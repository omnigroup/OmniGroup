// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// RCS_ID("$Id$")

#import <Foundation/Foundation.h>
#import <getopt.h>

static void fixStringsFile(NSString *path, NSString *outputEncodingName, NSString *outputDirectory);

static NSString *_quotedString(NSString *str)
{
    static NSCharacterSet *CharactersNeedingQuoting = nil;
    if (!CharactersNeedingQuoting)
        CharactersNeedingQuoting = [NSCharacterSet characterSetWithCharactersInString:@"\\\"\n"];
    
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
    
    NSMutableString *result = [source mutableCopy];
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
@property(weak, nonatomic,readonly) NSString *minimalSource;
- (NSComparisonResult)compareBySource:(Entry *)entry;
@end

@implementation Entry

static NSString *_transformedTranslation(NSString *translation)
{
    // Replace ... with real ellipsis characters
    if ([translation rangeOfString:@"..."].length != 0) {
        static NSString *ellipsisString = nil;
        if (!ellipsisString) {
            unichar c = 0x2026;
            ellipsisString = [[NSString alloc] initWithCharacters:&c length:1];
        }
        
        NSMutableString *ellipsizedString = [translation mutableCopy];
        [ellipsizedString replaceOccurrencesOfString:@"..." withString:ellipsisString options:0 range:NSMakeRange(0, [ellipsizedString length])];
        translation = ellipsizedString;
    }
    
    // Replace "..." with curly quotes
    translation = _smartQuotedString(translation, @"\"", 8220, 8221);
    
    // This gets quite a few bad matches due to contractions and possessives.  We could be smarter by requiring the starting quote to be at the beginning of the string or have a preceding non-alpha character (likewise for the ending quote).  This would be significantly more complicated and really we should just use "..." in most places.  We won't need embedded quotes in UI strings.
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

- (NSComparisonResult)compareBySource:(Entry *)entry;
{
    // We keep any multi-pair cross product locations together. Sort between entries by comparing the minimal source.
    NSString *minimalSource = self.minimalSource;
    NSString *otherMinimalSource = entry.minimalSource;
    
    if (minimalSource == otherMinimalSource)
        return NSOrderedSame;
    if (minimalSource == nil)
        return NSOrderedAscending;
    if (otherMinimalSource == nil)
        return NSOrderedDescending;
        
    return [minimalSource localizedStandardCompare:otherMinimalSource];
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


int main (int argc, char * const * argv)
{
    NSString *outputEncodingName = nil;
    NSString *outputDirectory = nil;
    
    @autoreleasepool {
        static struct option longopts[] = {
            { "outputencoding",   required_argument, NULL, 'e' },
            { "outdir", required_argument, NULL, 'o' },
            { NULL, 0, NULL, 0 }
        };
        
        int ch;
        while ((ch = getopt_long(argc, argv, "e:o:", longopts, NULL)) != -1) {
            switch (ch) {
                case 'e': {
                    outputEncodingName = [[NSString alloc] initWithUTF8String:optarg];
                    break;
                }
                case 'o': {
                    outputDirectory = [[[NSFileManager defaultManager] stringWithFileSystemRepresentation:optarg length:strlen(optarg)] copy];
                    break;
                }
                default:
                    fprintf(stderr, "usage: %s [--outputencoding encoding-name] [--outdir dir] file1 ... fileN\n", argv[0]);
                    exit(1);
            }
        }
    }
        
    int argi;
    for (argi = optind; argi < argc; argi++) {
	@autoreleasepool {
            NSString *path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:argv[argi] length:strlen(argv[argi])];
            fixStringsFile(path, outputEncodingName, outputDirectory);
	}
    }
    
    
    return 0;
}

static NSData *fixedStringRepresentationForStringsFile(NSData *fileData, NSString *outputEncodingName)
{
    uint8_t byte0 = ((const uint8_t *)[fileData bytes])[0];
    uint8_t byte1 = ((const uint8_t *)[fileData bytes])[1];
    
    __autoreleasing NSError *error = nil;
    if (byte0 == 'b' && byte1 == 'p') {
        id plist = [NSPropertyListSerialization propertyListWithData:fileData options:0 format:NULL error:&error];
        if (!plist) {
            NSLog(@"Data is not a property list: %@", error);
            return nil;
        }
        
        // The only valid output format in this case is 'binary'
        if (!outputEncodingName && [outputEncodingName compare:@"binary" options:NSCaseInsensitiveSearch] != NSOrderedSame) {
            NSLog(@"Can only copy binary input to binary output.");
            return nil;
        }
        
        return fileData;
    }
    
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
	NSLog(@"Unable to interpret data as UTF-8 or UTF-16.");
        return nil;
    }
    
    NSMutableArray *entries = [NSMutableArray array];
    
    NSScanner *scanner = [[NSScanner alloc] initWithString:fileString];
    while (![scanner isAtEnd]) {
	if (![scanner scanString:@"/*" intoString:NULL]) {
	    NSLog(@"no starting comment found, but not at end (at position %ld)", [scanner scanLocation]);
	    exit(1);
	}
        
	__autoreleasing NSString *commentString = nil;
	if (![scanner scanUpToString:@"*/" intoString:&commentString]) {
	    NSLog(@"Unterminated comment!");
            return nil;
	}
	if (![scanner scanString:@"*/" intoString:NULL]) {
	    NSLog(@"Unable to read expected comment termination!");
            return nil;
	}
        
	commentString = [commentString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; // up-to leaves the trailing space
        
	NSMutableArray *comments = [NSMutableArray arrayWithArray:[commentString componentsSeparatedByString:@"\n"]];
	NSUInteger commentIndex = [comments count];
	while (commentIndex--) {
	    NSString *comment = [[comments objectAtIndex:commentIndex] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	    [comments replaceObjectAtIndex:commentIndex withObject:comment];
	}
	[comments sortUsingSelector:@selector(localizedStandardCompare:)];
	
	__autoreleasing NSString *keyValue;
	if (![scanner scanUpToString:@"/*" intoString:&keyValue]) {
	    NSLog(@"Missing key-value pair!");
            return nil;
	}
	
        //NSLog(@"key/value = '%@'", keyValue);
        NSDictionary *dict = [keyValue propertyList]; // So we don't have to parse the string quoting and such.
        
        // genstrings can emit more than one key/value pair per comment for the cross-product style replacements (see input.m's test).
        Entry *entry = [[Entry alloc] initWithComments:comments pairs:dict];
        [entries addObject:entry];
    }
    
    NSMutableString *output = [NSMutableString string];
    {
	[entries sortUsingSelector:@selector(compareBySource:)];
        
	NSUInteger entryIndex, entryCount = [entries count];
	for (entryIndex = 0; entryIndex < entryCount; entryIndex++) {
	    [[entries objectAtIndex:entryIndex] appendToString:output];
	    [output appendString:@"\n"];
	}
    }

    if (outputEncodingName && [outputEncodingName compare:@"binary" options:NSCaseInsensitiveSearch] == NSOrderedSame) {
        NSDictionary *plist = [output propertyList];
        NSData *resultData = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
        if (!resultData) {
            NSLog(@"Unable to serialize as a binary plist: %@", error);
            return nil;
        }
        return resultData;
    } else {
        CFStringEncoding outputEncoding = kCFStringEncodingUTF8;
        
        if (outputEncodingName)
            outputEncoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)outputEncodingName);
        if (outputEncoding == kCFStringEncodingInvalidId) {
            NSLog(@"No such encoding '%@'!", outputEncodingName);
            return nil;
        }
        return CFBridgingRelease(CFStringCreateExternalRepresentation(kCFAllocatorDefault, (CFStringRef)output, outputEncoding, 0));
    }
    
}

static void fixStringsFile(NSString *path, NSString *outputEncodingName, NSString *outputDirectory)
{
    NSData *fileData = [[NSData alloc] initWithContentsOfFile:path];
    if (!fileData) {
	NSLog(@"Unable to read file '%@'", path);
	exit(1);
    }
    
    // Allow loading both UTF-16 and UTF-8 files.  -[NSString initWithData:encoding:] with NSUnicodeStringEncoding doesn't require the BOM, so if the file is UTF-8, it would just produce gibberish.
    // Also, allow pre-converted binary plist files for the case of iOS targets where libraries export strings files and apps copy them in.
    if ([fileData length] < 2) {
	// Nothing interesting anyway -- probably just empty.
	return;
    }

    NSData *resultData = fixedStringRepresentationForStringsFile(fileData, outputEncodingName);
    if (!resultData) {
        NSLog(@"Unable to fix strings file data for \"%@\".", path);
        exit(1);
    }
        
    NSString *outputPath;
    if (outputDirectory)
        outputPath = [outputDirectory stringByAppendingPathComponent:[path lastPathComponent]];
    else
        outputPath = path;
    
    __autoreleasing NSError *error = nil;
    if (![resultData writeToFile:outputPath options:NSDataWritingAtomic error:&error]) {
        NSLog(@"Unable to write '%@': %@", outputPath, error);
        exit(1);
    }
}
