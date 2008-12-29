// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSScanner-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSMutableString-OFExtensions.h>

RCS_ID("$Id$")

@implementation NSScanner (OFExtensions)

- (BOOL)scanStringOfLength:(unsigned int)length intoString:(NSString **)result;
{
    NSString                   *string;
    unsigned int                scanLocation;

    string = [self string];
    scanLocation = [self scanLocation];
    if (scanLocation + length > [string length])
	return NO;
    if (result)
	*result = [string substringWithRange: NSMakeRange(scanLocation, length)];
    [self setScanLocation:scanLocation + length];
    return YES;
}

- (BOOL)scanStringWithEscape:(NSString *)escape terminator:(NSString *)quoteMark intoString:(NSString **)output
{
    NSCharacterSet *stopSet;
    NSMutableString *prefixes;
    NSString *value;
    NSMutableString *buffer;
    NSCharacterSet *oldCharactersToBeSkipped;
#if defined(OMNI_ASSERTIONS_ON)
    unsigned beganLocation = [self scanLocation];
#endif

    OBPRECONDITION(![NSString isEmptyString:escape]);
    OBPRECONDITION(![NSString isEmptyString:quoteMark]);

    if ([self isAtEnd])
        return NO;

    prefixes = [[NSMutableString alloc] initWithCapacity:2];
    [prefixes appendLongCharacter:[escape characterAtIndex:0]];
    [prefixes appendLongCharacter:[quoteMark characterAtIndex:0]];
    stopSet = [NSCharacterSet characterSetWithCharactersInString:prefixes];
    [prefixes release];

    buffer = nil;
    value = nil;

    oldCharactersToBeSkipped = [self charactersToBeSkipped];
    [self setCharactersToBeSkipped:nil];

    do {
        NSString *fragment;

        if ([self scanUpToCharactersFromSet:stopSet intoString:&fragment]) {
            if (value && !buffer) {
                buffer = [value mutableCopy];
                value = nil;
            }
            if (buffer) {
                OBASSERT(value == nil);
                [buffer appendString:fragment];
            } else {
                value = fragment;
            }
        }

        if ([self scanString:quoteMark intoString:NULL])
            break;

        /* Two cases: either we scan the escape sequence successfully, and then we pull one (uninterpreted) character out of the string into the buffer; or we don't scan the escape sequence successfully (i.e. false alarm from the stopSet), in which we pull one uninterpreted character out of the string into the buffer. */

        if (!buffer) {
            if (value) {
                buffer = [value mutableCopy];
                value = nil;
            } else
                buffer = [[NSMutableString alloc] init];
        }

        [self scanString:escape intoString:NULL];
        if ([self scanStringOfLength:1 intoString:&fragment])
            [buffer appendString:fragment];
    } while (![self isAtEnd]);

    [self setCharactersToBeSkipped:oldCharactersToBeSkipped];

    if (buffer) {
        if (output)
            *output = [[buffer copy] autorelease];
        [buffer release];
        return YES;
    }
    if (value) {
        if (output)
            *output = value;
        return YES;
    }

    // Edge case --- we scanned an escape sequence and then hit EOF immediately afterwards. Still, we *did* advance our scan location, so we should return YES.
    OBASSERT([self scanLocation] != beganLocation);
    OBASSERT([self isAtEnd]);
    if (output)
        *output = @"";
    return YES;
}

- (BOOL)scanUpToStringFromArray:(NSArray *)stringArray intoString:(NSString **)returnString;
{
    NSRange scanRange = NSMakeRange([self scanLocation], [[self string] length] - [self scanLocation]);
    
    unsigned stringIndex, stringCount = [stringArray count];
    for (stringIndex = 0; stringIndex < stringCount; stringIndex++) {
        NSString *stopString = [stringArray objectAtIndex:stringIndex];
        NSRange foundRange = [[self string] rangeOfString:stopString options:0 range:scanRange];
        if (foundRange.location != NSNotFound) {
            scanRange.length = foundRange.location - scanRange.location;
        }
    }
    if (scanRange.length) {
        if (returnString)
            *returnString = [[self string] substringWithRange:scanRange];
        [self setScanLocation:NSMaxRange(scanRange)];
        return YES;
    }
    return NO;
}

- (BOOL)scanLineComponentsSeparatedByString:(NSString *)separator intoArray:(NSArray **)returnComponents;
{
    NSArray *separatorStrings = [NSArray arrayWithObjects:@"\n", separator, nil];
    if (returnComponents)
        *returnComponents = nil;
    
    if ([self isAtEnd])
        return NO;
    
    NSMutableArray *components = [NSMutableArray array];
    NSMutableCharacterSet *whiteSpaceSet = [[NSCharacterSet whitespaceCharacterSet] mutableCopy];
    [whiteSpaceSet removeCharactersInString:separator];
    BOOL foundNewline = NO;
    
    do {
        [self scanCharactersFromSet:whiteSpaceSet intoString:NULL];

        if ([self scanString:@"\"" intoString:NULL]) {
            // Scan Quoted String
            
            NSMutableString *myValue = [NSMutableString string];
            
            do {
                NSString *tempString = nil;
                
                if ([self scanUpToString:@"\"" intoString:&tempString])
                    [myValue appendString:tempString];
                
                if (![self scanString:@"\"" intoString:NULL]) {
                    [whiteSpaceSet release];
                    return NO;
                }
                
                if (![self scanString:@"\"" intoString:NULL])
                    break;
                
                [myValue appendString:@"\""];
            } while (1);
            [components addObject:myValue];
        } else {
            // Scan regular value
            NSString *tempString = nil;
            if ([self scanUpToStringFromArray:separatorStrings intoString:&tempString]) {
                [components addObject:[tempString stringByTrimmingCharactersInSet:whiteSpaceSet]];
            } else {
                [components addObject:@""];
            }
        }
	[self scanCharactersFromSet:whiteSpaceSet intoString:NULL];

	if ([self scanString:@"\n" intoString:NULL]) {
            foundNewline = YES;
            break;
        }
    } while ([self scanString:separator intoString:NULL]);
    
    [whiteSpaceSet release];

    if (!foundNewline && ![self isAtEnd]) {
        // We must have stopped scanning when a quoted string was followed by optional whitespace and the next thing wasn't a separator.  Don't know how to handle that.  Die.
        return NO;
    }

    if (returnComponents)
        *returnComponents = components;
    return YES;
}

@end
