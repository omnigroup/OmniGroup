// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDateFormatConversion.h>

RCS_ID("$Id$");

#import <OmniFoundation/OFStringScanner.h>

NSString *OFDateFormatStringForOldFormatString(NSString *oldFormat)
{
    // This function converts old crufty pre-10.4 date formats into shiny new 10.4+ Unicode-standard date formats.
    // Caveats: Weekday numbers are different (old format used 0=Sunday, new standard has a localized 0) and time zone names are different (America/Los_Angeles -> Pacific Daylight Time).  Also, the old format apparently truncated milliseconds while the new one seems rounds them to the nearest millisecond.
    // Relevant documentation for the formats can currently be found at the following links:
    //   http://unicode.org/reports/tr35/tr35-6.html#Date_Format_Patterns
    //   file:///Developer/Platforms/iPhoneOS.platform/Developer/Documentation/DocSets/com.apple.adc.documentation.AppleiPhone3_2.iPhoneLibrary.docset/Contents/Resources/Documents/documentation/Cocoa/Conceptual/DataFormatting/Articles/df100103.html
    
    NSMutableString *result = [NSMutableString string];
    OFStringScanner *scanner = [[OFStringScanner alloc] initWithString:oldFormat];
    BOOL inLiteralMode = NO;
    while (scannerHasData(scanner)) {
        unichar nextCharacter = scannerReadCharacter(scanner);
        if (nextCharacter != '%') {
            // "Two single quotes represents a literal single quote, either inside or outside single quotes."
            if (nextCharacter == '\'') {
                CFStringAppend((CFMutableStringRef)result, CFSTR("''"));
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
            if (inLiteralMode) {
                unichar insertCharacter = '\'';
                CFStringAppendCharacters((CFMutableStringRef)result, &insertCharacter, 1);
                inLiteralMode = NO;
            }
            
            nextCharacter = scannerReadCharacter(scanner);
            
            // %1d and %1m, which avoid the leading zero <http://developer.apple.com/mac/library/documentation/cocoa/conceptual/dataformatting/Articles/df100103.html#//apple_ref/doc/uid/TP40007972-SW1>
            if (nextCharacter == '1') {
                unichar peek = scannerPeekCharacter(scanner);
                if (peek == 'd') {
                    scannerReadCharacter(scanner); // eat peeked character
                    [result appendString:@"d"];
                    continue;
                }
                if (peek == 'm') {
                    scannerReadCharacter(scanner); // eat peeked character
                    [result appendString:@"M"];
                    continue;
                }
                
                OBASSERT_NOT_REACHED("Not expecting any other %1 formats");
                // fall through...
            }
            
            switch (nextCharacter) {
                default:
                    [result appendString:@"?"];
                    break;
                    
                case '%': // A '%' character
                    [result appendString:@"%"];
                    break;
                    
                case 'a': // Abbreviated weekday name
                    [result appendString:@"EEE"];
                    break;
                    
                case 'A': // Full weekday name
                    [result appendString:@"EEEE"];
                    break;
                    
                case 'b': // Abbreviated month name
                    [result appendString:@"MMM"];
                    break;
                    
                case 'B': // Full month name
                    [result appendString:@"MMMM"];
                    break;
                    
                case 'c': // Shorthand for "%X %x", the locale format for date and time
                    [result appendString:@"EEE MMM dd HH:mm:ss zzz yyyy"];
                    break;
                    
                case 'd': // Day of the month as a decimal number (01-31)
                    [result appendString:@"dd"];
                    break;
                    
                case 'e': // Same as %d but does not print the leading 0 for days 1 through 9 (unlike strftime(), does not print a leading space)
                    [result appendString:@"d"];
                    break;
                    
                case 'F': // Milliseconds as a decimal number (000-999)
                    [result appendString:@"SSS"];
                    break;
                    
                case 'H': // Hour based on a 24-hour clock as a decimal number (00-23)
                    [result appendString:@"HH"];
                    break;
                    
                case 'I': // Hour based on a 12-hour clock as a decimal number (01-12)
                    [result appendString:@"hh"];
                    break;
                    
                case 'j': // Day of the year as a decimal number (001-366)
                    [result appendString:@"DDD"];
                    break;
                    
                case 'm': // Month as a decimal number (01-12)
                    [result appendString:@"MM"];
                    break;
                    
                case 'M': // Minute as a decimal number (00-59)
                    [result appendString:@"mm"];
                    break;
                    
                case 'p': // AM/PM designation for the locale
                    [result appendString:@"a"];
                    break;
                    
                case 'S': // Second as a decimal number (00-59)
                    [result appendString:@"ss"];
                    break;
                    
                case 'w': // Weekday as a decimal number (0-6), where Sunday is 0
                    [result appendString:@"e"]; // NOTE: This is not exactly equal:  the 'e' specifier treats Monday as 0
                    break;
                    
                case 'x': // Date using the date representation for the locale, including the time zone (produces different results from strftime())
                    [result appendString:@"EEE MMM dd yyyy"];
                    break;
                    
                case 'X': // Time using the time representation for the locale (produces different results from strftime())
                    [result appendString:@"HH:mm:SS zzz"];
                    break;
                    
                case 'y': // Year without century (00-99)
                    [result appendString:@"yy"];
                    break;
                    
                case 'Y': // Year with century (such as 1990)
                    [result appendString:@"yyyy"];
                    break;
                    
                case 'Z': // Time zone name (such as Pacific Daylight Time; produces different results from strftime())
                    [result appendString:@"zzzz"];
                    break;
                    
                case 'z': // Time zone offset in hours and minutes from GMT (HHMM)
                    [result appendString:@"ZZZ"];
                    break;
            }
        }
    }
    if (inLiteralMode) {
        unichar insertCharacter = '\'';
        CFStringAppendCharacters((CFMutableStringRef)result, &insertCharacter, 1);
    }
    [scanner release];
    return result;
}
