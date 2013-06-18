// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDateFormatConversion.h>

RCS_ID("$Id$");

#import <OmniFoundation/OFStringScanner.h>

void OFProcessICUDateFormatStringWithComponentHandler(NSString *formatString, void (^componentHandler)(NSString *component, BOOL isLiteral))
{
    OFStringScanner *scanner = [[OFStringScanner alloc] initWithString:formatString];
    
    while (scannerHasData(scanner)) {
        unichar character = scannerReadCharacter(scanner);
        
        // Check for a quoted literal
        if (character == '\'') {
            // Literal string
            NSMutableString *literal = [[NSMutableString alloc] init];
            while (scannerHasData(scanner)) {
                unichar quotedCharacter = scannerReadCharacter(scanner);
                if (quotedCharacter == '\'') {
                    // Two single quotes inside or outside of a quoted block represent a quote.
                    if (scannerHasData(scanner) && (scannerPeekCharacter(scanner) == '\'')) {
                        // This is a quote inside a quoted block
                        scannerReadCharacter(scanner);
                        [literal appendString:@"'"];
                    } else {
                        // This is the end of a quoted block
                        break;
                    }
                } else {
                    CFStringAppendCharacters((CFMutableStringRef)literal, &quotedCharacter, 1);
                }
                OBASSERT(scannerHasData(scanner)); // warn if we get an input format with unmatched quotes
            }
            
            if ([literal length] == 0)
                // This is a quote outside a quoted block
                componentHandler(@"'", YES);
            else
                componentHandler(literal, YES);
            [literal release];
            continue;
        }
        
        // Not a literal, read a batch of identical sequential charactders representing a format specifier
        NSMutableString *component = [NSMutableString string];
        CFStringAppendCharacters((CFMutableStringRef)component, &character, 1);
        while (scannerHasData(scanner) && scannerPeekCharacter(scanner) == character) {
            scannerReadCharacter(scanner);
            CFStringAppendCharacters((CFMutableStringRef)component, &character, 1);
        }
        componentHandler(component, NO);
    }
    
    [scanner release];
}

NSArray *OFComponentsFromICUDateFormatString(NSString *formatString)
{
    NSMutableArray *components = [NSMutableArray array];
    OFProcessICUDateFormatStringWithComponentHandler(formatString, ^(NSString *component, BOOL isLiteral) {
        [components addObject:component];
    });
    return components;
}

NSString *OFDateFormatStringForOldFormatString(NSString *oldFormat)
{
    // This function converts old crufty pre-10.4 date formats into shiny new 10.4+ Unicode-standard date formats.
    // Caveats: Weekday numbers are different (old format used 0=Sunday, new standard has a localized 0) and time zone names are different (America/Los_Angeles -> Pacific Daylight Time).  Also, the old format apparently truncated milliseconds while the new one seems rounds them to the nearest millisecond.
    // Relevant documentation for the formats can currently be found at the following links:
    //   http://unicode.org/reports/tr35/tr35-6.html#Date_Format_Patterns
    //   file:///Developer/Documentation/DocSets/com.apple.adc.documentation.AppleSnowLeopard.CoreReference.docset/Contents/Resources/Documents/documentation/Cocoa/Conceptual/DataFormatting/Articles/df100103.html
    
    NSMutableString *result = [NSMutableString string];
    OFStringScanner *scanner = [[OFStringScanner alloc] initWithString:oldFormat];
    BOOL inLiteralMode = NO;
    while (scannerHasData(scanner)) {
        unichar nextCharacter = scannerReadCharacter(scanner);
        if (nextCharacter != '%') {
            // "Two single quotes represents a literal single quote, either inside or outside single quotes."
            if (nextCharacter == '\'') {
                [result appendString:@"''"];
                continue;
            }

            unichar insertCharacters[3];
            int insertCount = 0;
            if (!inLiteralMode) {
                insertCharacters[insertCount++] = '\'';
                inLiteralMode = YES;
            }
            insertCharacters[insertCount++] = nextCharacter;
            CFStringAppendCharacters((CFMutableStringRef)result, insertCharacters, insertCount);
        } else {
           
    // Only end literal mode if we got a valid format, else we might be in a sequence of "?" characters
#define APPEND_FORMAT(f) do { \
    if (inLiteralMode) { \
        [result appendString:@"\'"]; \
        inLiteralMode = NO; \
    } \
    [result appendString:(f)]; \
} while (0)

            unsigned int formatLength = [scanner scanUnsignedIntegerMaximumDigits:5];
            unichar formatCharacter = scannerReadCharacter(scanner);
            
            switch (formatCharacter) {
                default:
                    // Start or continue a literal of ? characters, matching what we'd get from the strftime-like formatter
                    if (!inLiteralMode) {
                        [result appendString:@"'"];
                        inLiteralMode = YES;
                    }
                    [result appendString:@"?"];
                    break;
                    
                case '%': // A '%' character
                    APPEND_FORMAT(@"%");
                    break;
                    
                case 'a': // Abbreviated weekday name
                    APPEND_FORMAT(@"EEE");
                    break;
                    
                case 'A': // Full weekday name
                    APPEND_FORMAT(@"EEEE");
                    break;
                    
                case 'b': // Abbreviated month name
                    APPEND_FORMAT(@"MMM");
                    break;
                    
                case 'B': // Full month name
                    APPEND_FORMAT(@"MMMM");
                    break;
                    
                case 'c': // Shorthand for "%X %x", the locale format for date and time
                    APPEND_FORMAT(@"EEE MMM dd HH:mm:ss zzz yyyy");
                    break;
                    
                case 'd': // Day of the month as a decimal number (01-31)
                    if (formatLength == 1)
                        APPEND_FORMAT(@"d");
                    else
                        APPEND_FORMAT(@"dd");
                    break;
                    
                case 'e': // Same as %d but does not print the leading 0 for days 1 through 9 (unlike strftime(), does not print a leading space)
                    APPEND_FORMAT(@"d");
                    break;
                    
                case 'F': // Milliseconds as a decimal number (000-999)
                    APPEND_FORMAT(@"SSS");
                    break;
                    
                case 'H': // Hour based on a 24-hour clock as a decimal number (00-23)
                    if (formatLength == 1)
                        APPEND_FORMAT(@"H");
                    else
                        APPEND_FORMAT(@"HH");
                    break;
                    
                case 'I': // Hour based on a 12-hour clock as a decimal number (01-12)
                    if (formatLength == 1)
                        APPEND_FORMAT(@"h");
                    else
                        APPEND_FORMAT(@"hh");
                    break;
                    
                case 'j': // Day of the year as a decimal number (001-366)
                    APPEND_FORMAT(@"DDD");
                    break;
                    
                case 'm': // Month as a decimal number (01-12)
                    if (formatLength == 1)
                        APPEND_FORMAT(@"M");
                    else
                        APPEND_FORMAT(@"MM");
                    break;
                    
                case 'M': // Minute as a decimal number (00-59)
                    APPEND_FORMAT(@"mm");
                    break;
                    
                case 'p': // AM/PM designation for the locale
                    APPEND_FORMAT(@"a");
                    break;
                    
                case 'S': // Second as a decimal number (00-59)
                    APPEND_FORMAT(@"ss");
                    break;
                    
                case 'w': // Weekday as a decimal number (0-6), where Sunday is 0
                    APPEND_FORMAT(@"e"); // NOTE: This is not exactly equal:  the 'e' specifier treats Monday as 0
                    break;
                    
                case 'x': // Date using the date representation for the locale, including the time zone (produces different results from strftime())
                    APPEND_FORMAT(@"EEE MMM dd yyyy");
                    break;
                    
                case 'X': // Time using the time representation for the locale (produces different results from strftime())
                    APPEND_FORMAT(@"HH:mm:ss zzz");
                    break;
                    
                case 'y': // Year without century (00-99)
                    APPEND_FORMAT(@"yy");
                    break;
                    
                case 'Y': // Year with century (such as 1990)
                    APPEND_FORMAT(@"yyyy");
                    break;
                    
                case 'Z': // Time zone name (such as Pacific Daylight Time; produces different results from strftime())
                    APPEND_FORMAT(@"zzzz");
                    break;
                    
                case 'z': // Time zone offset in hours and minutes from GMT (HHMM)
                    APPEND_FORMAT(@"ZZZ");
                    break;
            }
        }
    }
    if (inLiteralMode) {
        unichar insertCharacter = '\'';
        CFStringAppendCharacters((CFMutableStringRef)result, &insertCharacter, 1);
    }
    
#undef APPEND_FORMAT
    
    [scanner release];
    return result;
}

NSString *OFOldDateFormatStringForFormatString(NSString *newFormat)
{
    NSMutableString *result = [NSMutableString string];
    OFProcessICUDateFormatStringWithComponentHandler(newFormat, ^(NSString *component, BOOL isLiteral) {
        if (isLiteral) {
            [result appendString:component];
        } else {
            NSUInteger characterCount = [component length];
            unichar character = [component characterAtIndex:0];
            switch (character) {
                case '%': // quoted percent
                    [result appendString:@"%%"];
                    break;
                    
                case 'y': // year
                    OBASSERT(characterCount == 1 || characterCount == 2 || characterCount == 4); // ICU supports any length, but we expect to get "reasonable" strings for now. Handle other lengths, but alert if we get them.
                    if (characterCount == 2)
                        [result appendString:@"%y"];
                    else
                        [result appendString:@"%Y"]; // 'y' and 'yyyy' are explicitly stated to be 4-digit year in ICU
                    break;
                case 'M': // month
                    if (characterCount == 1)
                        [result appendString:@"%1m"]; // no leading zero
                    else if (characterCount == 2)
                        [result appendString:@"%m"]; // with leading zero, if needed
                    else if (characterCount == 3)
                        [result appendString:@"%b"]; // short month name
                    else {
                        OBASSERT(characterCount == 4); // ICU supports 5 too for a "narrow name"
                        [result appendString:@"%B"]; // full month name
                    }
                    break;
                case 'd': // day of month
                    OBASSERT(characterCount <= 2);
                    if (characterCount == 1)
                        [result appendString:@"%e"]; // no leading zero ("%1d" also works, but we are writing %e in OO3)
                    else
                        [result appendString:@"%d"]; // with leading zero, if needed
                    break;
                case 'D': // day of year
                    OBASSERT(characterCount == 3);
                    if (characterCount >= 3)
                        [result appendString:@"%j"];
                    else
                        [result appendFormat:@"%%%luj", characterCount];
                    break;
                case 'E': // day name of week
                    if (characterCount <= 3)
                        [result appendString:@"%a"]; // short weekday name
                    else {
                        OBASSERT(characterCount == 4); // ICU supports 5 too for a "narrow name"
                        [result appendString:@"%A"];
                    }
                    break;
                case 'e': // local day name of week
                    if (characterCount == 1)
                        [result appendString:@"%u"]; // short weekday name
                    else if (characterCount <= 3)
                        [result appendString:@"%a"]; // short weekday name
                    else {
                        OBASSERT(characterCount == 4); // ICU supports 5 too for a "narrow name"
                        [result appendString:@"%A"];
                    }
                    break;
                case 'a': // period
                    OBASSERT(characterCount == 1);
                    [result appendString:@"%p"]; // AM/PM
                    break;
                case 'h': // hour, 1-12
                    OBASSERT(characterCount <= 2);
                    if (characterCount == 1)
                        [result appendString:@"%1I"];
                    else
                        [result appendString:@"%I"];
                    break;
                case 'H': // hour, 0-23
                    OBASSERT(characterCount <= 2);
                    if (characterCount == 1)
                        [result appendString:@"%1H"];
                    else
                        [result appendString:@"%H"];
                    break;
                case 'm': // minute
                    OBASSERT(characterCount <= 2);
                    if (characterCount == 1)
                        [result appendString:@"%1M"];
                    else
                        [result appendString:@"%M"];
                    break;
                case 's': // second
                    OBASSERT(characterCount <= 2);
                    if (characterCount == 1)
                        [result appendString:@"%1S"];
                    else
                        [result appendString:@"%S"];
                    break;
                case 'S': // fractional seconds
                    OBASSERT(characterCount == 3);
                    [result appendString:@"%F"];
                    break;
                case 'z':
                    if (characterCount <= 3) {
                        // ICU for this should be "PDT", but strftime/10.2 NSDateFormatter doesn't seem to have a format for that.
                        [result appendString:@"%Z"];
                    } else {
                        OBASSERT(characterCount == 4);
                        // ICU for this should be "Pacific Daylight Time". %Z in strftime gives "America/Los_Angeles"
                        [result appendString:@"%Z"];
                    }
                    break;
                case 'Z':
                    OBASSERT(characterCount == 3); // 1-3 give "-0800", 4 characters gives a different format in ICU, "GMT-08:00"
                    [result appendString:@"%z"]; // Time zone offset in hours and minutes from GMT (HHMM)
                    break;
                    
                case 'G': // era
                case 'Y': // week of year
                case 'u': // extended year
                case 'Q': // quarter
                case 'q': // stand-alone quarter
                case 'L': // stand-along month
                case 'w': // week of year
                case 'W': // week of month
                case 'F': // day of week in month
                case 'g': // modified julian day
                case 'c': // stand-alone local day of week
                case 'K': // hour, 0-11
                case 'k': // hour, 1-24
                case 'A': // milliseconds in day
                    // Some of these full strftime supports, some it may not (just doing the ones documented for 10.0-10.3 NSDateFormatters for now).
                    OBASSERT_NOT_REACHED("No support for specified format.");
                    break;
                default:
                    // NSDateFormatter on iOS will specify random unquoted strings in the middle of formats (like "M/d/yy h:mm a")
                    for (NSUInteger characterIndex = 0; characterIndex < characterCount; characterIndex++)
                        [result appendFormat:@"%C", character];
                    break;
            }
        }
    });
    return result;
}

