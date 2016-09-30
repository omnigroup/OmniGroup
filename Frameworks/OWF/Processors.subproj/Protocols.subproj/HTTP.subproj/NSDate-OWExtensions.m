// Copyright 1999-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/NSDate-OWExtensions.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWHTTPSession.h>

RCS_ID("$Id$")

@interface OWHoursMinutesSeconds : OFObject
{
@public
    unsigned int hours;
    unsigned int minutes;
    unsigned int seconds;
}

+ (OWHoursMinutesSeconds *)objectHoldingHours:(unsigned int)newHours minutes:(unsigned int)newMinutes seconds:(unsigned int)newSeconds;
- initWithHours:(unsigned int)newHours minutes:(unsigned int)newMinutes seconds:(unsigned int)newSeconds;

@end

@interface NSDate (OWExtensionsPrivate)
+ (NSCalendarDate *)readRFCFormatDateFromScanner:(OFStringScanner *)scanner;
+ (NSCalendarDate *)readAsctimeDateFromScanner:(OFStringScanner *)scanner;
+ (OWHoursMinutesSeconds *)readTimeFromScanner:(OFStringScanner *)scanner;
@end

@implementation NSDate (OWExtensions)

static BOOL OWDebugHTTPDateString = NO;

static OFCharacterSet *nonalphaOFCharacterSet;
static OFCharacterSet *nonalphanumericOFCharacterSet;
static NSArray *shortMonthNames;
static NSArray *longMonthNames;
static NSArray *shortWeekdayNames;
static NSArray *longWeekdayNames;
static NSTimeZone *gmtTimeZone;

+ (void)didLoad;
{
    nonalphaOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:[[NSCharacterSet letterCharacterSet] invertedSet]];
    nonalphanumericOFCharacterSet = [[OFCharacterSet alloc] initWithCharacterSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
    shortMonthNames = [[NSArray alloc] initWithObjects:@"jan", @"feb", @"mar", @"apr", @"may", @"jun", @"jul", @"aug", @"sep", @"oct", @"nov", @"dec", nil];
    longMonthNames = [[NSArray alloc] initWithObjects:@"january", @"february", @"march", @"april", @"may", @"june", @"july", @"august", @"september", @"october", @"november", @"december", nil];
    shortWeekdayNames = [[NSArray alloc] initWithObjects:@"sun", @"mon", @"tue", @"wed", @"thu", @"fri", @"sat", nil];
    longWeekdayNames = [[NSArray alloc] initWithObjects:@"sunday", @"monday", @"tuesday", @"wednesday", @"thursday", @"friday", @"saturday", nil];
    gmtTimeZone = [NSTimeZone timeZoneWithName:@"GMT"];
}

+ (void)setDebugHTTPDateParsing:(BOOL)shouldDebug;
{
    OWDebugHTTPDateString = shouldDebug;
}

#if 0
    // Formats are:
    "%a, %d %b %Y %H:%M:%S %Z", /* RFC1123 */
    "%A, %d-%b-%y %H:%M:%S %Z", /* RFC850 */
    "%a %b %d %H:%M:%S %Y", /* asctime() format */

    /* various observed variants: long years, long weekdays, extra dashes and missing dashes, missing spaces, etc. */
    "%a, %d-%b-%Y %H:%M:%S %Z",
    "%A, %d-%b-%Y %H:%M:%S %Z",
    "%A, %d %b %Y %H:%M:%S %Z",
    "%a, %d %b %Y %H:%M:%S%Z"
#endif

+ (NSDate *)dateWithHTTPDateString:(NSString *)aString;
{
    NSCalendarDate *date = nil;
    OFStringScanner *scanner;
    NSString *preferredDateFormat;

    if (!aString)
        return nil;

    preferredDateFormat = [OWHTTPSession preferredDateFormat];

    scanner = [[OFStringScanner alloc] initWithString:aString];

    if (((scannerPeekCharacter(scanner) == 'n' || scannerPeekCharacter(scanner) == 'N') && [aString caseInsensitiveCompare:@"now"] == NSOrderedSame) ||
        (scannerPeekCharacter(scanner) == '0' && [aString isEqualToString:@"0"])) {
        // "NOW" is non-standard, but means the present time.
        // "0" is also a non-standard format for a date, but since many people use it on expirations to mean "0 seconds from now" that's how we'll interpret it.
        date = [NSCalendarDate calendarDate];
    } else if (scannerPeekCharacter(scanner) == '-' && [aString isEqualToString:@"-1"]) {
        // "-1" is a non-standard format for a date, but statse.webtrendslive.com (referenced by www.apple.com) seems to use it in the Expires header to mean "-1 seconds from now" (maybe?) so that's how we'll interpret it (rather than logging an error about it being a non-standard date).
        date = [[NSCalendarDate calendarDate] dateByAddingTimeInterval:-1.0];
    } else {
        // Standard date formats usually begin with a weekday
        // If the first character is a letter, scan the weekday
        if (!OFCharacterSetHasMember(nonalphaOFCharacterSet, scannerPeekCharacter(scanner))) {
            // Skip weekday name (short or long name)
            if (!scannerScanUpToCharacterInOFCharacterSet(scanner, nonalphaOFCharacterSet))
                goto nonstandardDate;

            // Skip comma, if present
            if (scannerPeekCharacter(scanner) == ',') {
                scannerSkipPeekedCharacter(scanner);
            }
        }

        // Save the current position in the scanner
        [scanner setRewindMark];

        // Try reading an RFC1123 or RFC850 date
        date = [self readRFCFormatDateFromScanner:scanner];

        // If that was unsuccessful
        if (!date) {
            [scanner rewindToMark];

            // Try reading an asctime() format date
            date = [self readAsctimeDateFromScanner:scanner];
        } else {
            // don't bother discarding the rewind on the scanner.  we're going to release it anyway
        }
    }

nonstandardDate:

#if 0
    // Foundation's date parser is REALLY slow (like, 40 seconds) for bogus strings like this one that we get from google ad syndication: "Built on Oct  8 2003 12:43:55 (1065642215)"
    if (!date) {
        // If we still haven't figured out the date, let's try Foundation's (leaky and slow) natural language parser.
        date = [self dateWithNaturalLanguageString:aString];
    }
#endif
    if (date) {
        // Set the date's format.
        [date setCalendarFormat:preferredDateFormat];
        if (OWDebugHTTPDateString) {
            NSLog(@"+[NSDate(OWExtensions) dateWithHTTPDateString:]: parsed date:\ninput:\t'%@'\noutput:\t'%@'", aString, date);
        }
    } else {
        // Neither we nor the natural language parser could figure out the date.
        NSLog(@"+[NSDate(OWExtensions) dateWithHTTPDateString:]: specified date in nonstandard format: %@", aString);
    }
    OBPOSTCONDITION(date == nil || [date isKindOfClass:self]);
    return date;
}

+ (NSCalendarDate *)readRFCFormatDateFromScanner:(OFStringScanner *)scanner;
{
    unsigned int dayOfMonth;
    NSString *month;
    NSUInteger monthIndex;
    unsigned int year;
    OWHoursMinutesSeconds *scannedTime;
    int timeZoneOffset;
    NSString *timeZoneName;
    NSTimeZone *timeZone;

    // Parse RFC1123 or RFC850 format date

    // Skip whitespace (if any)
    while (scannerPeekCharacter(scanner) == ' ') {
        scannerSkipPeekedCharacter(scanner);
    }

    // Make sure the next character is a digit
    if (scannerPeekCharacter(scanner) < '0' || scannerPeekCharacter(scanner) > '9')
        return nil;

    // Read day of month (one or two digits)
    dayOfMonth = [scanner scanUnsignedIntegerMaximumDigits:2];

    // Skip space or dash
    switch (scannerPeekCharacter(scanner)) {
        case ' ':
        case '-':
            scannerSkipPeekedCharacter(scanner);
            break;
        default:
            return nil;
    }

    // Make sure the next character is a letter
    if (OFCharacterSetHasMember(nonalphaOFCharacterSet, scannerPeekCharacter(scanner))) {
        // Perhaps we found a numeric month instead, e.g. "01-01-1970"?  Let's go ahead and relax our parsing enough to allow this.
        if (scannerPeekCharacter(scanner) >= '0' || scannerPeekCharacter(scanner) <= '9') {
            // Read day of month (one or two digits)
            monthIndex = [scanner scanUnsignedIntegerMaximumDigits:2];
            if (monthIndex < 1 || monthIndex > 12)
                return nil; // Nonsensical month
            monthIndex--; // The month index variable is 0-based
        } else {
            // We don't understand this format
            return nil;
        }
    } else {
        // Read month name (short or long)
        month = [scanner readFullTokenWithDelimiterOFCharacterSet:nonalphaOFCharacterSet forceLowercase:YES];
        monthIndex = [shortMonthNames indexOfObject:month];
        if (monthIndex == NSNotFound) {
            monthIndex = [longMonthNames indexOfObject:month];
            if (monthIndex == NSNotFound) {
                return nil;
            }
        }
    }

    // Skip space or dash
    switch (scannerPeekCharacter(scanner)) {
        case ' ':
        case '-':
            scannerSkipPeekedCharacter(scanner);
            break;
        default:
            return nil;
    }

    // Make sure the next character is a digit
    if (scannerPeekCharacter(scanner) < '0' || scannerPeekCharacter(scanner) > '9')
        return nil;

    // Read year (two or four digits)
    year = [scanner scanUnsignedIntegerMaximumDigits:4];
    if (year <= 99) {
        // We interpret two-digit years as starting with 1970 (beginning of the UNIX era) and ending in 2069.  If people are still providing two-digit years in 2070, we should probably switch to an adaptive algorithm (look at the current year and choose the nearest match, perhaps preferring the future to the past or something).
        if (year >= 70)
            year += 1900;
        else
            year += 2000;
    }

    // Make sure the next character is whitespace
    if (scannerPeekCharacter(scanner) != ' ')
        return nil;

    // Skip whitespace
    while (scannerPeekCharacter(scanner) == ' ') {
        scannerSkipPeekedCharacter(scanner);
    }

    // Read the time
    scannedTime = [self readTimeFromScanner:scanner];
    if (!scannedTime)
        return nil;

    // Skip whitespace (if any)
    while (scannerPeekCharacter(scanner) == ' ') {
        scannerSkipPeekedCharacter(scanner);
    }

    // Read time zone
    switch (scannerPeekCharacter(scanner)) {
        case '-':
        case '+':
        case '0':
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
        case '6':
        case '7':
        case '8':
        case '9':
            timeZoneOffset = [scanner scanIntegerMaximumDigits:4];
            timeZone = [NSTimeZone timeZoneForSecondsFromGMT:(timeZoneOffset / 100 * 60 + timeZoneOffset % 100) * 60];
            break;
        default:
            timeZoneName = [scanner readFullTokenWithDelimiterOFCharacterSet:nonalphanumericOFCharacterSet forceLowercase:NO];
            if (timeZoneName) {
                timeZone = [NSTimeZone timeZoneWithName:timeZoneName];
            } else {
                timeZone = gmtTimeZone;
            }
            break;
    }

    return [NSCalendarDate dateWithYear:year month:monthIndex + 1 day:dayOfMonth hour:scannedTime->hours minute:scannedTime->minutes second:scannedTime->seconds timeZone:timeZone];
}

+ (NSCalendarDate *)readAsctimeDateFromScanner:(OFStringScanner *)scanner;
{
    unsigned int dayOfMonth;
    NSString *month;
    NSUInteger monthIndex;
    unsigned int year;
    OWHoursMinutesSeconds *scannedTime;

    // Parse asctime() format date

    // Skip whitespace
    while (scannerPeekCharacter(scanner) == ' ') {
        scannerSkipPeekedCharacter(scanner);
    }

    // Make sure the next character is a letter
    if (OFCharacterSetHasMember(nonalphaOFCharacterSet, scannerPeekCharacter(scanner)))
        return nil;

    // Read month name (short or long)
    month = [scanner readFullTokenWithDelimiterOFCharacterSet:nonalphaOFCharacterSet forceLowercase:YES];
    monthIndex = [shortMonthNames indexOfObject:month];
    if (monthIndex == NSNotFound) {
        monthIndex = [longMonthNames indexOfObject:month];
        if (monthIndex == NSNotFound) {
            return nil;
        }
    }

    // Skip whitespace
    while (scannerPeekCharacter(scanner) == ' ') {
        scannerSkipPeekedCharacter(scanner);
    }

    // Make sure the next character is a digit
    if (scannerPeekCharacter(scanner) < '0' || scannerPeekCharacter(scanner) > '9')
        return nil;

    // Read day of month (one or two digits)
    dayOfMonth = [scanner scanUnsignedIntegerMaximumDigits:2];

    // Make sure the next character is whitespace
    if (scannerPeekCharacter(scanner) != ' ')
        return nil;

    // Skip whitespace
    while (scannerPeekCharacter(scanner) == ' ') {
        scannerSkipPeekedCharacter(scanner);
    }

    // Read the time
    scannedTime = [self readTimeFromScanner:scanner];
    if (!scannedTime)
        return nil;

    // Make sure the next character is whitespace
    if (scannerPeekCharacter(scanner) != ' ')
        return nil;

    // Skip whitespace
    while (scannerPeekCharacter(scanner) == ' ') {
        scannerSkipPeekedCharacter(scanner);
    }

    // Read year (four digits)
    year = [scanner scanUnsignedIntegerMaximumDigits:4];
    if (year <= 99) {
        // Unlikely for an asctime() format date, but just in case...
        year += 1900;
    }

    return [NSCalendarDate dateWithYear:year month:monthIndex + 1 day:dayOfMonth hour:scannedTime->hours minute:scannedTime->minutes second:scannedTime->seconds timeZone:gmtTimeZone];
}

+ (OWHoursMinutesSeconds *)readTimeFromScanner:(OFStringScanner *)scanner;
{
    unsigned int hours;
    unsigned int minutes;
    unsigned int seconds;

    // Read the time
    if (scannerPeekCharacter(scanner) == '?') {
        // Some servers return a time of '?', treat it as 00:00:00
        scannerSkipPeekedCharacter(scanner);
        return [OWHoursMinutesSeconds objectHoldingHours:0 minutes:0 seconds:0];
    } else {
        // Make sure the first character is a digit
        if (scannerPeekCharacter(scanner) < '0' || scannerPeekCharacter(scanner) > '9') {
            // Well, if they left out a time, let's assume 00:00:00
            return [OWHoursMinutesSeconds objectHoldingHours:0 minutes:0 seconds:0];
        }

        // Read hours (two digits)
        hours = [scanner scanUnsignedIntegerMaximumDigits:2];

        // Skip colon
        if (scannerPeekCharacter(scanner) == ':') {
            scannerSkipPeekedCharacter(scanner);
        } else {
            return nil;
        }

        // Read minutes (two digits)
        minutes = [scanner scanUnsignedIntegerMaximumDigits:2];

        // Skip colon
        if (scannerPeekCharacter(scanner) == ':') {
            scannerSkipPeekedCharacter(scanner);

            // Read seconds (two digits)
            seconds = [scanner scanUnsignedIntegerMaximumDigits:2];
        } else {
            seconds = 0;
        }
    }

    return [OWHoursMinutesSeconds objectHoldingHours:hours minutes:minutes seconds:seconds];
}

@end

@implementation OWHoursMinutesSeconds

+ (OWHoursMinutesSeconds *)objectHoldingHours:(unsigned int)newHours minutes:(unsigned int)newMinutes seconds:(unsigned int)newSeconds;
{
    return [[self alloc] initWithHours:newHours minutes:newMinutes seconds:newSeconds];
}

- initWithHours:(unsigned int)newHours minutes:(unsigned int)newMinutes seconds:(unsigned int)newSeconds;
{
    if (!(self = [super init]))
        return nil;

    hours = newHours;
    minutes = newMinutes;
    seconds = newSeconds;

    return self;
}

@end
