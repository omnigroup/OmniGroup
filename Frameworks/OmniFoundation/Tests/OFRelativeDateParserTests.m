// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/OFRelativeDateParser.h>

#import <OmniFoundation/OFRegularExpression.h>
#import <OmniFoundation/OFRegularExpressionMatch.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import "OFRelativeDateParser-Internal.h"

#import <OmniBase/OmniBase.h>


RCS_ID("$Id$")

static NSArray *dateFormats;
static NSArray *timeFormats;
//static NSDateFormatter *formatter;

static OFRandomState RandomState;

@interface OFRelativeDateParserTests : OFTestCase
{
    NSCalendar *calendar;
}
//+ (NSDate *)_dateFromYear:(int)year month:(int)month day:(int)day hour:(int)hour minute:(int)minute second:(int)second;
@end

static NSDate *_dateFromYear(int year, int month, int day, int hour, int minute, int second, NSCalendar *cal)
{
    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setYear:year];
    [components setMonth:month];
    [components setDay:day];
    [components setHour:hour];
    [components setMinute:minute];
    [components setSecond:second];
    NSDate *result = [cal dateFromComponents:components];
    [components release];
    return result;
}

static unsigned int range(unsigned int min, unsigned int max)
{
    return min + OFRandomNextState(&RandomState)%(max - min);
}

static BOOL _testRandomDate(NSString *shortFormat, NSString *mediumFormat, NSString *longFormat, NSString *timeFormat)
{
    NSCalendar *calendar = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar] autorelease];
    NSString *testDateString = @""; //construct the natural language string
    
    NSDateComponents *testDateComponents = [[[NSDateComponents alloc] init] autorelease];
    
    OFRelativeDateParser *parser = [OFRelativeDateParser sharedParser];
    
    NSString *dateFormat = shortFormat;
    static OFRegularExpression *formatseparatorRegex = nil;
    if (!formatseparatorRegex)
	formatseparatorRegex = [[OFRegularExpression alloc] initWithString:@"^\\w+([\\./-])"];
//    OFRegularExpressionMatch *formattedDateMatch = [formatseparatorRegex matchInString:dateFormat];
//    NSString *formatStringseparator = nil;
//    if (formattedDateMatch) {
//	formatStringseparator = [formattedDateMatch subexpressionAtIndex:0];
//	if ([formatStringseparator isEqualToString:@"-"]) 
//	    isDashed = YES;
//    }
    
    DatePosition datePosition;
    
    //	datePosition.year = 1;
    //	datePosition.month = 2;
    //	datePosition.day = 3;
    //	datePosition.separator = formatStringseparator;
    //    } else
    datePosition = [parser _dateElementOrderFromFormat:dateFormat];
    NSString *separator = datePosition.separator;
    
    int month = range(1, 12);
    int day;
    if (month == 2)
	day = range(1,28);
    else if (month == 10 || month == 4 || month == 6 || month == 11)
	day = range(1,30);
    else
	day = range(1,31);
    int year = range(1990,2007);
    
    if ([NSString isEmptyString:separator]) {
	NSString *dayString;
	if (day < 10) 
	    dayString = [NSString stringWithFormat:@"0%d", day];
	else
	    dayString = [NSString stringWithFormat:@"%d", day];
	
	NSString *monthString;
	if (month < 10) 
	    monthString = [NSString stringWithFormat:@"0%d", month];
	else
	    monthString = [NSString stringWithFormat:@"%d", month];
	
	testDateString = [NSString stringWithFormat:@"%d%@%@%@%@", year, separator, monthString, separator, dayString];
    } else {
	if (datePosition.day == 1) {
	    if (datePosition.month == 2) {
		// d m y
		testDateString = [NSString stringWithFormat:@"%d%@%d%@%d", day, separator, month, separator, year];
	    } else {
		// d y m
		OBASSERT_NOT_REACHED("years don't come second");
	    }
	} else if (datePosition.day == 2 ) {
	    if (datePosition.month == 1) {
		// m d y
		testDateString = [NSString stringWithFormat:@"%d%@%d%@%d", month, separator, day, separator, year];
	    } else {
		// y d m
		testDateString = [NSString stringWithFormat:@"%d%@%d%@%d", year, separator, day, separator, month];
	    }
	} else {
	    if (datePosition.month == 1) {
		// m y d
		OBASSERT_NOT_REACHED("years don't come second");
	    } else {
		// y m d
		testDateString = [NSString stringWithFormat:@"%d%@%d%@%d", year, separator, month, separator, day];
	    }
	}
    }
    
    [testDateComponents setDay:day];
    [testDateComponents setMonth:month];
    [testDateComponents setYear:year];
    
    int minute = range(1,60);
    [testDateComponents setMinute:minute];
    
    BOOL hasSeconds = [timeFormat containsString:@"s"];
    int second = 0;
    if (hasSeconds) {
	second = range(1,60);
	[testDateComponents setSecond:second];
    }
    
    int hour;
    if ([timeFormat containsString:@"H"] || [timeFormat containsString:@"k"]) {
	hour = range(0,23);
	if (hasSeconds) 
	    testDateString = [testDateString stringByAppendingFormat:@" %d:%d:%d", hour, minute, second];
	else
	    testDateString = [testDateString stringByAppendingFormat:@" %d:%d", hour, minute];
    } else { 
	hour = range(1,12);
	int am = range(0,1);
	NSString *meridian = @"PM";
	if (am)
	    meridian = @"PM";
	if (hasSeconds)
	    testDateString = [testDateString stringByAppendingFormat:@" %d:%d:%d %@", hour, minute, second, meridian];
	else 
	    testDateString = [testDateString stringByAppendingFormat:@" %d:%d %@", hour, minute, meridian];
	if (!am && hour < 12)
	    hour += 12;
    }
    [testDateComponents setHour:hour];
    
    NSDate *testDate = [calendar dateFromComponents:testDateComponents];
    
    
    NSDate *baseDate = _dateFromYear(2007, 1, 1, 0, 0, 0, calendar);
    NSDate *testResult, *result = nil; 
    [[OFRelativeDateParser sharedParser] getDateValue:&testResult forString:testDateString fromStartingDate:baseDate withTimeZone:[NSTimeZone localTimeZone] withCalendarIdentifier:[calendar calendarIdentifier] withShortDateFormat:shortFormat withMediumDateFormat:mediumFormat withLongDateFormat:longFormat withTimeFormat:timeFormat error:nil]; 
    
    NSString *stringBack = [[OFRelativeDateParser sharedParser] stringForDate:testDate withDateFormat:dateFormat withTimeFormat:timeFormat withTimeZone:[NSTimeZone localTimeZone] withCalendarIdentifier:NSGregorianCalendar];
    [[OFRelativeDateParser sharedParser] getDateValue:&result forString:stringBack fromStartingDate:baseDate withTimeZone:[NSTimeZone localTimeZone] withCalendarIdentifier:[calendar calendarIdentifier] withShortDateFormat:shortFormat withMediumDateFormat:mediumFormat withLongDateFormat:longFormat withTimeFormat:timeFormat error:nil]; 
    
    if ([testResult isEqual:testDate] && [result isEqual:testDate]) 
	return YES;
    else {
	NSLog( @"RandomTestDate: %@, dateFormat: %@, timeFormat: %@", testDate, dateFormat, timeFormat);
	if (![result isEqual:testDate])
	    NSLog( @"string back failure: %@, Result:%@ expected:%@", stringBack, result, testDate );
	
	if (![testResult isEqual:testDate])
	    NSLog (@"--failure testDateString: %@, stringBack: %@,  testResult: %@, expected: %@", testDateString, stringBack, testResult, testDate);
    }
    
    return NO;
}


@implementation OFRelativeDateParserTests

- (void)setUp;
{
    const char *env = getenv("DataGeneratorSeed");
    unsigned int seed = env ? strtoul(env, NULL, 0) : OFRandomGenerateRandomSeed();
    OFRandomSeed(&RandomState, seed);
    
    calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    [NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4]; 
    dateFormats = [[[NSArray alloc] initWithObjects:@"MM/dd/yy", @"MM/dd/yyyy", @"dd/MM/yy", @"dd/MM/yyyy", @"yyyy-MM-dd", @"MM.dd.yy", @"dd.MM.yy", @"d-MMM-yy", nil] autorelease];
    timeFormats = [[[NSArray alloc] initWithObjects:@"hh:mm a", @"hh:mm:ss a", @"HH:mm:ss", @"HH:mm", @"HHmm", @"kk:mm", @"kkmm", nil] autorelease];
}

- (void)tearDown;
{
    [calendar release];
}

#define parseDate(string, expectedDate, baseDate, dateFormat, timeFormat) \
do { \
NSDate *result = nil; \
[[OFRelativeDateParser sharedParser] getDateValue:&result forString:string fromStartingDate:baseDate withTimeZone:[NSTimeZone localTimeZone] withCalendarIdentifier:[calendar calendarIdentifier] withShortDateFormat:dateFormat withMediumDateFormat:dateFormat withLongDateFormat:dateFormat withTimeFormat:timeFormat error:nil]; \
if (expectedDate && ![result isEqualTo:expectedDate]) \
NSLog( @"FAILURE-> String: %@, locale:%@, result:%@, expected: %@ dateFormat:%@, timeFormat:%@", string, [[[OFRelativeDateParser sharedParser] locale] localeIdentifier], result, expectedDate, dateFormat, timeFormat); \
shouldBeEqual(result, expectedDate); \
} while(0)
//NSLog( @"string: %@, expected: %@, result: %@", string, expectedDate, result );

- (void)testDayWeekCodes;
{
#if defined(MAC_OS_X_VERSION_10_6) && MAC_OS_X_VERSION_10_6 >= MAC_OS_X_VERSION_MIN_REQUIRED
    NSLog(@"Skipping test that fails due to bug in 10A222.");
#else
    NSString *timeFormat = @"h:mm a";
    NSString *dateFormat = @"d-MMM-yy";

    // now, should be this instant
    NSString *string = @" thu+1w";
    NSDate *baseDate     = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2001, 1, 11, 0, 0, 0, calendar);
    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
#endif
}

- (void)testRelativeDateNames;
{
    // test our relative date names
    unsigned int dateIndex = [dateFormats count];
    while (dateIndex--) {
	unsigned int timeIndex = [timeFormats count];
	while (timeIndex--) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	    
	    NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
	    NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
	    
	    // now, should be this instant
	    NSString *string = @"now";
	    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    NSDate *expectedDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    // should be 12pm of today
	    string = @"noon";
	    baseDate     = _dateFromYear(2001, 1, 1, 15, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 1, 1, 12, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @"tonight";
	    baseDate     = _dateFromYear(2001, 1, 1, 15, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 1, 1, 23, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    [pool release];
	}
    }
}

- (void)testFriNoon;
{
    //test setting the date with year-month-day even when the date format is d/m/y
    unsigned int dateIndex = [dateFormats count];
    while (dateIndex--) {
	unsigned int timeIndex = [timeFormats count];
	while (timeIndex--) {
	    NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
	    NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
	    
	    // skip we have crazy candian dates, this combo is just messed up
	    if (![dateFormat containsString:@"MMM"]) {
		NSString *string = @"fri noon";
		NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
		NSDate *expectedDate = _dateFromYear(2001, 1, 5, 12, 0, 0, calendar);
		parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    }
	}
    }
}

- (void)testCanada;
{
    // test using canada's date formats
    [calendar autorelease];
    calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    NSString *timeFormat = @"h:mm a";
    NSString *dateFormat = @"d-MMM-yy";
    should(_testRandomDate(dateFormat, dateFormat, dateFormat, timeFormat));
    
}

- (void)testSweden;
{
    //test setting the date with year-month-day even when the date format is d/m/y
    unsigned int dateIndex = [dateFormats count];
    while (dateIndex--) {
	unsigned int timeIndex = [timeFormats count];
	while (timeIndex--) {
	    NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
	    NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
	    
	    // skip we have crazy candian dates, this combo is just messed up
	    if (![dateFormat containsString:@"MMM"]) {
		NSString *string = @"1997-12-29";
		NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
		NSDate *expectedDate = _dateFromYear(1997, 12, 29, 0, 0, 0, calendar);
		parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    }
	}
    }
}

- (void)testRandomCases;
{
    NSString *timeFormat = @"HH:mm";
    NSString *dateFormat = @"d-MMM-yy";
    
    NSString *string = @"1-Jul-00 11:02";
    NSDate *baseDate = _dateFromYear(2000, 1, 1, 1, 1, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2000, 7, 1, 11, 2, 0, calendar);
    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
    
    timeFormat = @"hh:mm a";
    dateFormat = @"MM.dd.yy";
    string = @"04.13.00 03:05 PM";
    baseDate = _dateFromYear(2000, 1, 1, 1, 1, 0, calendar);
    expectedDate = _dateFromYear(2000, 4, 13, 15, 5, 0, calendar);
    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
}

-(void)testNil;
{
    [calendar autorelease];
    calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
    NSDate *baseDate = _dateFromYear(2007, 1, 1, 1, 1, 0, calendar);
    NSString *string = @"";
    unsigned int dateIndex = [dateFormats count];
    while (dateIndex--) {
	unsigned int timeIndex = [timeFormats count];
	while (timeIndex--) {
	    NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
	    NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
	    
	    parseDate( string, nil, baseDate, dateFormat, timeFormat );   
	}
    }
}

- (void)testDegenerates;
{
    // test with all different formats
    unsigned int dateIndex = [dateFormats count];
    while (dateIndex--) {
	unsigned int timeIndex = [timeFormats count];
	while (timeIndex--) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	    
	    NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
	    NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
	    
	    NSString *string = @" 2 weeks";
	    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    NSDate *expectedDate = _dateFromYear(2001, 1, 15, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @"1d 12 pm";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 1, 2, 12, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @"1d 12pm";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 1, 2, 12, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @"1d 2 pm";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 1, 2, 14, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @"1d 2pm";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 1, 2, 14, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @" 2 p";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 1, 1, 14, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @" 2p";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 1, 1, 14, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @" 2 PM";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 1, 1, 14, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @" 2PM";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 1, 1, 14, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @" 2 P";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 1, 1, 14, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @" 2P";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 1, 1, 14, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @"2";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 1, 2, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
            
            [pool release];
	}
    }
}

- (void)testBugs;
{
    // test with all different formats
    unsigned int dateIndex = [dateFormats count];
    while (dateIndex--) {
	unsigned int timeIndex = [timeFormats count];
	while (timeIndex--) {
	    NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
	    NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
	    
	    // <bug://bugs/37222> ("4 may" is interpreted at 4 months)
	    NSString *string = @"4 May";
	    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    NSDate *expectedDate = _dateFromYear(2001, 5, 4, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @"may 4";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2001, 5, 4, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  );	    
	    
	    // <bug://bugs/37216> (Entering a year into date fields doesn't work)
	    string = @"2008";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    if ([timeFormat isEqualToString:@"HHmm"] || [timeFormat isEqualToString:@"kkmm"]) {
		expectedDate = _dateFromYear(2001, 1, 1, 20, 8, 0, calendar);
		parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  );
	    } else {
		expectedDate = _dateFromYear(2008, 1, 1, 0, 0, 0, calendar);
		parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  );
	    }
	    
	    // <bug://bugs/37219> ("this year" and "next year" work in date formatter, but "last year" does not)
	    string = @"last year";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2000, 1, 1, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  );
	    
	    string = @"next year";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(2002, 1, 1, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  );
	    
	    // test tomorrow
	    string = @"tomorrow";
	    baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar); // y m d h m s
	    expectedDate = _dateFromYear(2001, 1, 2, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  );
	    
	    
	}
    }
}

- (void)testSeperatedDates;
{
    // test with all different formats
    unsigned int dateIndex = [dateFormats count];
    while (dateIndex--) {
	unsigned int timeIndex = [timeFormats count];
	while (timeIndex--) {
	    NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
	    NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
	    
	    // 23th of may, 1979
	    NSString *string = @"23 May 1979";
	    NSDate *baseDate = _dateFromYear(1979, 1, 1, 0, 0, 0, calendar);
	    NSDate *expectedDate = _dateFromYear(1979, 5, 23, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    
	    string = @"may-23-1979";
	    baseDate = _dateFromYear(1979, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(1979, 5, 23, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  );	    
	    
	    string = @"5-23-1979";
	    baseDate = _dateFromYear(1979, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(1979, 5, 23, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  );
	    
	    string = @"5 23 1979";
	    baseDate = _dateFromYear(1979, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(1979, 5, 23, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  );
	    
	    string = @"5/23/1979";
	    baseDate = _dateFromYear(1979, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(1979, 5, 23, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  );
	    
	    string = @"5.23.1979";
	    baseDate = _dateFromYear(1979, 1, 1, 0, 0, 0, calendar);
	    expectedDate = _dateFromYear(1979, 5, 23, 0, 0, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  );
	}
    }
}

- (void)testErrors;
{
    NSString *timeFormat = @"hh:mm";
    NSString *dateFormat = @"m/d/yy";
    
    NSString *string = @"jan 1 08";
    NSDate *baseDate = _dateFromYear(1979, 1, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2008, 1, 1, 0, 0, 0, calendar);
    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
}

- (void)testAt;
{
    // test with all different formats
    unsigned int dateIndex = [dateFormats count];
    while (dateIndex--) {
	unsigned int timeIndex = [timeFormats count];
	while (timeIndex--) {
	    NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
	    NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
	    
	    NSString *string = @"may 4 1997 at 3:07pm";
	    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    NSDate *expectedDate = _dateFromYear(1997, 5, 4, 15, 7, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	}
    }
}

- (void)testTwentyFourHourTime;
{
    // test with all different formats
    unsigned int dateIndex = [dateFormats count];
    while (dateIndex--) {
	unsigned int timeIndex = [timeFormats count];
	while (timeIndex--) {
	    NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
	    NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
	    
	    // <bug://bugs/37104> (Fix 24hour time support in OFRelativeDateParser)
	    NSString *string = @"19:59";
	    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    NSDate *expectedDate = _dateFromYear(2001, 1, 1, 19, 59, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	}
    }
}

- (void)testRandomDatesAndRoundTrips;
{
    // test with all different formats
    unsigned int dateIndex = [dateFormats count];
    while (dateIndex--) {
	unsigned int timeIndex = [timeFormats count];
	while (timeIndex--) {
	    NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
	    NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
	    should(_testRandomDate(dateFormat, dateFormat, dateFormat, timeFormat));
	}
    }
}

- (void)testLocaleWeekdays;
{
    NSLocale *currentLocale = [NSLocale currentLocale];
    NSArray *availableLocales = [NSArray arrayWithObjects:@"de", /*@"es",*/ @"fr", @"en_US", /*@"it",*/ @"ja", @"nl", @"zh_CN", nil];//[NSLocale availableLocaleIdentifiers];
    unsigned int localeIndex;
    for (localeIndex = 0; localeIndex < [availableLocales count]; localeIndex++) {
	NSLocale *locale = [[[NSLocale alloc] initWithLocaleIdentifier:[availableLocales objectAtIndex:localeIndex]] autorelease];
	[[OFRelativeDateParser sharedParser] setLocale:locale];
	
	NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease]; 
	[formatter setLocale:locale];
	
	NSArray *weekdays = [formatter weekdaySymbols];
	NSDate *baseDate = _dateFromYear(2001, 1, 10, 0, 0, 0, calendar);
	NSDateComponents *components = [calendar components:NSWeekdayCalendarUnit fromDate:baseDate];
	
	// test with all different formats
	unsigned int dateIndex = [dateFormats count];
	while (dateIndex--) {
	    unsigned int timeIndex = [timeFormats count];
	    while (timeIndex--) {
		NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
		NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
		
		unsigned int dayIndex = [weekdays count];
		unsigned int weekday = [components weekday] - 1; // 1 based
		while (dayIndex--) {
		    int addToWeek = (dayIndex - weekday);
		    if (addToWeek < 0)
			addToWeek = 7;
		    else 
			addToWeek = 0;
		    parseDate( [weekdays objectAtIndex:dayIndex], 
			      _dateFromYear(2001, 1, (10 + addToWeek + (dayIndex - weekday)), 0, 0, 0, calendar),
			      baseDate, dateFormat, timeFormat);
		}
		
		weekdays = [formatter shortWeekdaySymbols];
		dayIndex = [weekdays count];
		while (dayIndex--) {
		    int addToWeek = (dayIndex - weekday);
		    if (addToWeek < 0)
			addToWeek = 7;
		    else 
			addToWeek = 0;
		    parseDate( [weekdays objectAtIndex:dayIndex], 
			      _dateFromYear(2001, 1, (10 + addToWeek + (dayIndex - weekday)), 0, 0, 0, calendar),
			      baseDate, dateFormat, timeFormat);
		}
	    }
	}
    }
    [[OFRelativeDateParser sharedParser] setLocale:currentLocale];
}

- (void)testLocaleMonths;
{
    NSLocale *currentLocale = [NSLocale currentLocale];
    NSArray *availableLocales = [NSArray arrayWithObjects:@"de", @"es", @"fr", @"en_US", @"it", /*@"ja",*/ @"nl", @"zh_CN", nil];//[NSLocale availableLocaleIdentifiers]; // TODO: Figure out why -testLocaleMonths fails for Japanese
    unsigned int localeIndex;
    for (localeIndex = 0; localeIndex < [availableLocales count]; localeIndex++) {
	NSLocale *locale = [[[NSLocale alloc] initWithLocaleIdentifier:[availableLocales objectAtIndex:localeIndex]] autorelease];
	[[OFRelativeDateParser sharedParser] setLocale:locale];
	
	
        [calendar autorelease];
	calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
	NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
	[formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
	
	[formatter setLocale:locale];
	NSArray *months = [formatter monthSymbols];
	NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	
	NSDateComponents *components = [calendar components:NSMonthCalendarUnit fromDate:baseDate];
	
	unsigned int dateIndex = [dateFormats count];
	while (dateIndex--) {
	    unsigned int timeIndex = [timeFormats count];
	    while (timeIndex--) {
		NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
		NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
		
		unsigned int monthIndex = [months count];
		unsigned int month = [components month] - 1; // 1 based
		while (monthIndex--) {
		    int addToMonth = (monthIndex - month);
		    if (addToMonth < 0)
			addToMonth = 12;
		    else 
			addToMonth = 0;
		    parseDate( [months objectAtIndex:monthIndex], 
			      _dateFromYear(2001, (1 + addToMonth + (monthIndex - month)), 1, 0, 0, 0, calendar),
			      baseDate,  dateFormat, timeFormat );
		}
		
		months = [formatter shortMonthSymbols];
		
		monthIndex = [months count];
		while (monthIndex--) {
		    int addToMonth = (monthIndex - month);
		    if (addToMonth < 0)
			addToMonth = 12;
		    else 
			addToMonth = 0;
		    parseDate( [months objectAtIndex:monthIndex], 
			      _dateFromYear(2001, (1 + addToMonth + (monthIndex - month)), 1, 0, 0, 0, calendar),
			      baseDate,  dateFormat, timeFormat );
		}
	    }
	}
    }
    [[OFRelativeDateParser sharedParser] setLocale:currentLocale];
}


- (void)testTimes;
{
    unsigned int dateIndex = [dateFormats count];
    while (dateIndex--) {
	unsigned int timeIndex = [timeFormats count];
	while (timeIndex--) {
	    NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
	    NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
	    
	    parseDate( @"1d@5:45:1", 
		      _dateFromYear(2001, 1, 2, 5, 45, 1, calendar),
		      _dateFromYear(2001, 1, 1, 1, 1, 1, calendar),  dateFormat, timeFormat  );
	    parseDate( @"@17:45", 
		      _dateFromYear(2001, 1, 1, 17, 45, 0, calendar),
		      _dateFromYear(2001, 1, 1, 1, 1, 1, calendar),  dateFormat, timeFormat  );
	    parseDate( @"@5:45 pm", 
		      _dateFromYear(2001, 1, 1, 17, 45, 0, calendar),
		      _dateFromYear(2001, 1, 1, 1, 1, 1, calendar),  dateFormat, timeFormat  );
	    parseDate( @"@5:45 am", 
		      _dateFromYear(2001, 1, 1, 5, 45, 0, calendar),
		      _dateFromYear(2001, 1, 1, 1, 1, 1, calendar),  dateFormat, timeFormat  );
	}
    }
}

- (void)testCodes;
{
    unsigned int dateIndex = [dateFormats count];
    while (dateIndex--) {
	unsigned int timeIndex = [timeFormats count];
	while (timeIndex--) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            
	    NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
	    NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];    
	    parseDate( @"-1h2h3h4h+1h2h3h4h", 
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"0h", 
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"1h", 
		      _dateFromYear(2001, 1, 1, 2, 1, 1, calendar),
		      _dateFromYear(2001, 1, 1, 1, 1, 1, calendar),  dateFormat, timeFormat  );
	    parseDate( @"+1h1h", 
		      _dateFromYear(2001, 1, 1, 3, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 1, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"-1h", 
		      _dateFromYear(2001, 1, 1, 1, 1, 1, calendar),
		      _dateFromYear(2001, 1, 1, 2, 1, 1, calendar),  dateFormat, timeFormat  );
	    
	    parseDate( @"0d", 
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"1d", 
		      _dateFromYear(2001, 1, 2, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"+1d", 
		      _dateFromYear(2001, 1, 2, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"-1d", 
		      _dateFromYear(2000, 12, 31, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    
	    parseDate( @"0w", 
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"1w", 
		      _dateFromYear(2001, 1, 8, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"+1w", 
		      _dateFromYear(2001, 1, 8, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"-1w", 
		      _dateFromYear(2000, 12, 25, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    
	    parseDate( @"0m", 
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"1m", 
		      _dateFromYear(2001, 2, 1, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"+1m", 
		      _dateFromYear(2001, 2, 1, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"-1m", 
		      _dateFromYear(2000, 12, 1, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    
	    parseDate( @"0y", 
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"1y", 
		      _dateFromYear(2002, 1, 1, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"+1y", 
		      _dateFromYear(2002, 1, 1, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
	    parseDate( @"-1y", 
		      _dateFromYear(2000, 1, 1, 0, 0, 0, calendar),
		      _dateFromYear(2001, 1, 1, 0, 0, 0, calendar),  dateFormat, timeFormat  );
            
            [pool release];
	}
    }
}


@end
