// Copyright 2006-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFRelativeDateParser.h>

#import <OmniFoundation/OFRandom.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSRegularExpression-OFExtensions.h>
#import "OFRelativeDateParser-Internal.h"

#import <OmniBase/OmniBase.h>


RCS_ID("$Id$")


@interface OFRelativeDateParserTests : OFTestCase
{
    NSCalendar *calendar;
    OFRandomState *randomState;
    NSArray *dateFormats;
    NSArray *timeFormats;
    //NSDateFormatter *formatter;
    
}
//+ (NSDate *)_dateFromYear:(int)year month:(int)month day:(int)day hour:(int)hour minute:(int)minute second:(int)second;
@end

@implementation OFRelativeDateParserTests

static NSDate *_dateFromYear(NSInteger year, NSInteger month, NSInteger day, NSInteger hour, NSInteger minute, NSInteger second, NSCalendar *cal)
{
    NSDateComponents *components = [[NSDateComponents alloc] init];
    [components setYear:year];
    [components setMonth:month];
    [components setDay:day];
    [components setHour:hour];
    [components setMinute:minute];
    [components setSecond:second];
    NSDate *result = [cal dateFromComponents:components];
    return result;
}

static unsigned int range(OFRandomState *state, unsigned int min, unsigned int max)
{
    return min + OFRandomNextState32(state)%(max - min);
}

static BOOL _testRandomDate(OFRandomState *state, NSString *shortFormat, NSString *mediumFormat, NSString *longFormat, NSString *timeFormat)
{
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    
    // specifically set en_US, to make this pass if the user's current locale is ja_JP.
    [calendar setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]];

    NSString *testDateString = @""; //construct the natural language string
    
    NSDateComponents *testDateComponents = [[NSDateComponents alloc] init];
    
    OFRelativeDateParser *parser = [OFRelativeDateParser sharedParser];
    
    NSString *dateFormat = shortFormat;

    OFCreateRegularExpression(formatseparatorRegex, @"^\\w+([\\./-])"); // Backslash, period, forward slash, hyphen
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
    
    int month = range(state, 1, 12);
    int day;
    if (month == 2)
	day = range(state, 1,28);
    else if (month == 10 || month == 4 || month == 6 || month == 11)
	day = range(state, 1,30);
    else
	day = range(state, 1,31);
    int year = range(state, 1990, 2007);
    
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
    
    int minute = range(state, 1,60);
    [testDateComponents setMinute:minute];
    
    BOOL hasSeconds = [timeFormat containsString:@"s"];
    int second = 0;
    if (hasSeconds) {
	second = range(state, 1,60);
	[testDateComponents setSecond:second];
    }
    
    int hour;
    if ([timeFormat containsString:@"H"] || [timeFormat containsString:@"k"]) {
	hour = range(state, 0,23);
	if (hasSeconds) 
	    testDateString = [testDateString stringByAppendingFormat:@" %d:%d:%d", hour, minute, second];
	else
	    testDateString = [testDateString stringByAppendingFormat:@" %d:%d", hour, minute];
    } else { 
	hour = range(state, 1,12);
	int am = range(state, 0,1);
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
    [[OFRelativeDateParser sharedParser] getDateValue:&testResult forString:testDateString fromStartingDate:baseDate calendar:calendar withShortDateFormat:shortFormat withMediumDateFormat:mediumFormat withLongDateFormat:longFormat withTimeFormat:timeFormat error:nil]; 
    
    NSString *stringBack = [[OFRelativeDateParser sharedParser] stringForDate:testDate withDateFormat:dateFormat withTimeFormat:timeFormat calendar:calendar];
    [[OFRelativeDateParser sharedParser] getDateValue:&result forString:stringBack fromStartingDate:baseDate calendar:calendar withShortDateFormat:shortFormat withMediumDateFormat:mediumFormat withLongDateFormat:longFormat withTimeFormat:timeFormat error:nil]; 
    
    if ([testResult isEqual:testDate] && [result isEqual:testDate]) 
	return YES;
    else {
	NSLog( @"RandomTestDate: %@, string \"%@\", shortFormat:%@ mediumFormat:%@ longFormat:%@ timeFormat:%@", testDate, testDateString, shortFormat, mediumFormat, longFormat, timeFormat);
	if (![result isEqual:testDate])
	    NSLog( @"string back failure: %@, Result:%@ expected:%@", stringBack, result, testDate );
	
	if (![testResult isEqual:testDate])
	    NSLog (@"--failure testDateString: %@, stringBack: %@,  testResult: %@, expected: %@", testDateString, stringBack, testResult, testDate);
    }
    
    return NO;
}


- (void)setUp;
{
    [super setUp];
    
    const char *env = getenv("DataGeneratorSeed");
    if (env) {
        uint32_t seed = (uint32_t)strtoul(env, NULL, 0);
        randomState = OFRandomStateCreateWithSeed32(&seed, 1);
    } else
        randomState = OFRandomStateCreate();
    
    // Default to en_US instead of the user's locale for now (in the tests only). Some tests will override this.
    [[OFRelativeDateParser sharedParser] setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]];
     
    calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    
    // specifically set en_US, to make this pass if the user's current locale is ja_JP.
    [calendar setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]];

    dateFormats = [[NSArray alloc] initWithObjects:@"MM/dd/yy", @"MM/dd/yyyy", @"dd/MM/yy", @"dd/MM/yyyy", @"yyyy-MM-dd", @"MM.dd.yy", @"dd.MM.yy", @"d-MMM-yy", nil];
    timeFormats = [[NSArray alloc] initWithObjects:@"hh:mm a", @"hh:mm:ss a", @"HH:mm:ss", @"HH:mm", @"HHmm", @"kk:mm", @"kkmm", nil];
}

- (void)tearDown;
{
    OFRandomStateDestroy(randomState);
    randomState = NULL;
    
    calendar = nil;
    
    dateFormats = nil;
    
    timeFormats = nil;
    
    [super tearDown];
}

static NSString *_stringForDate(NSDate *date)
{
    static NSDateFormatter *dateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm zzz";
    });
    return [dateFormatter stringFromDate:date];
}

static void _parseDate(OFRelativeDateParserTests *self, NSString *string, NSDate *expectedDate, NSDate *baseDate, NSString *dateFormat, NSString *timeFormat)
{
    NSDate *result = nil;
    if (dateFormat == nil && timeFormat == nil) {
        [[OFRelativeDateParser sharedParser] getDateValue:&result forString:string fromStartingDate:baseDate useEndOfDuration:NO defaultTimeDateComponents:nil calendar:self->calendar error:NULL];
    } else {
        [[OFRelativeDateParser sharedParser] getDateValue:&result forString:string fromStartingDate:baseDate calendar:self->calendar withShortDateFormat:dateFormat withMediumDateFormat:dateFormat withLongDateFormat:dateFormat withTimeFormat:timeFormat error:nil];
    }
    if (expectedDate && ![result isEqual:expectedDate]) {
        NSLog( @"FAILURE-> String: %@, locale:%@, result:%@, expected: %@ dateFormat:%@, timeFormat:%@", string, [[[OFRelativeDateParser sharedParser] locale] localeIdentifier], _stringForDate(result), _stringForDate(expectedDate), dateFormat, timeFormat);
    }
    XCTAssertEqualObjects(result, expectedDate);
}
#define parseDate(string, expectedDate, baseDate, dateFormat, timeFormat) _parseDate(self, (string), (expectedDate), (baseDate), (dateFormat), (timeFormat))

//NSLog( @"string: %@, expected: %@, result: %@", string, expectedDate, result );

- (void)testDayWeekCodes;
{
    NSString *timeFormat = @"h:mm a";
    NSString *dateFormat = @"d-MMM-yy";

    // now, should be this instant
    NSString *string = @" thu+1w";
    NSDate *baseDate     = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2001, 1, 11, 0, 0, 0, calendar);
    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
}

- (void)testRelativeDateNames;
{
    // test our relative date names
    NSUInteger dateIndex = [dateFormats count];
    while (dateIndex--) {
	NSUInteger timeIndex = [timeFormats count];
	while (timeIndex--) {
            @autoreleasepool {

                NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
                NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];

                // "now" should be this instant - it should be [NSDate date], regardless of baseDate
                NSString *string = @"now";
                NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
                NSDate *expectedDate = [NSDate date];
                NSDate *nowResult = nil;
                [[OFRelativeDateParser sharedParser] getDateValue:&nowResult forString:string fromStartingDate:baseDate calendar:calendar withShortDateFormat:dateFormat withMediumDateFormat:dateFormat withLongDateFormat:dateFormat withTimeFormat:timeFormat error:nil];
                XCTAssertEqualWithAccuracy(nowResult.timeIntervalSince1970, expectedDate.timeIntervalSince1970, 1.0);

                // should be 12pm of today
                string = @"noon";
                baseDate     = _dateFromYear(2001, 1, 1, 15, 0, 0, calendar);
                expectedDate = _dateFromYear(2001, 1, 1, 12, 0, 0, calendar);
                parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  );

                string = @"tonight";
                baseDate     = _dateFromYear(2001, 1, 1, 15, 0, 0, calendar);
                expectedDate = _dateFromYear(2001, 1, 1, 23, 0, 0, calendar);
                parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  );
                
            }
        }
    }
}

- (void)testFriNoon;
{
    //test setting the date with year-month-day even when the date format is d/m/y
    for (NSString *dateFormat in dateFormats) {
	for (NSString *timeFormat in timeFormats) {
	    // skip we have crazy canadian dates, this combo is just messed up
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
    calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    
    // specifically set en_US, to make this pass if the user's current locale is ja_JP.
    [calendar setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]];
     
    NSString *timeFormat = @"h:mm a";
    NSString *dateFormat = @"d-MMM-yy";
    XCTAssertTrue(_testRandomDate(randomState, dateFormat, dateFormat, dateFormat, timeFormat));
    
}

- (void)testSweden;
{
    //test setting the date with year-month-day even when the date format is d/m/y
    for (NSString *dateFormat in dateFormats) {
	for (NSString *timeFormat in timeFormats) {
	    // skip we have crazy canadian dates, this combo is just messed up
	    if (![dateFormat containsString:@"MMM"]) {
		NSString *string = @"1997-12-29";
		NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
		NSDate *expectedDate = _dateFromYear(1997, 12, 29, 0, 0, 0, calendar);
		parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	    }
	}
    }
}

- (void)testFrench;
{
    NSLocale *savedLocale = [[OFRelativeDateParser sharedParser] locale];

    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"fr"];
    [[OFRelativeDateParser sharedParser] setLocale:locale];

    NSDate *baseDate = nil;
    NSDate *expectedDate = nil;
        
    // We have to test French "tomorrow" as "tomorrow", not "demain", because we don't have localized resources
    baseDate = _dateFromYear(2011, 7, 15, 0, 0, 0, calendar);
    expectedDate = _dateFromYear(2011, 7, 16, 0, 0, 0, calendar);
    parseDate( @"tomorrow", expectedDate, baseDate, nil, nil ); 
    
    baseDate = _dateFromYear(2011, 7, 15, 0, 0, 0, calendar);
    expectedDate = _dateFromYear(2012, 12, 29, 0, 0, 0, calendar);
    parseDate( @"29 dec. 2012", expectedDate, baseDate, nil, nil ); 
    parseDate( @"29 déc. 2012", expectedDate, baseDate, nil, nil );

    [[OFRelativeDateParser sharedParser] setLocale:savedLocale];
}

- (void)testSpanish;
{
    NSLocale *savedLocale = [[OFRelativeDateParser sharedParser] locale];

    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"es"];
    [[OFRelativeDateParser sharedParser] setLocale:locale];

    // We expected to get tuesday, not "mar"=>March/Marzo then nil because of the extra input
    // See <bug:///73211> (OFRelativeDateParser doesn't use localized string/abbreviation when parsing out hours)
    
    NSDate *baseDate = nil;
    NSDate *expectedDate = nil;
    
    baseDate = _dateFromYear(2011, 6, 29, 0, 0, 0, calendar);
    expectedDate = _dateFromYear(2011, 7, 5, 0, 0, 0, calendar);
    parseDate( @"martes", expectedDate, baseDate, nil, nil ); 
    
    // We expect to be able to use either miercoles for miércoles for wednesday and have it work
    
    baseDate = _dateFromYear(2011, 7, 5, 0, 0, 0, calendar);
    expectedDate = _dateFromYear(2011, 7, 6, 0, 0, 0, calendar);
    parseDate( @"miercoles", expectedDate, baseDate, nil, nil ); 
    parseDate( @"miércoles", expectedDate, baseDate, nil, nil );
    

    [[OFRelativeDateParser sharedParser] setLocale:savedLocale];
}

- (void)testItalian;
{
    NSLocale *savedLocale = [[OFRelativeDateParser sharedParser] locale];

    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"it"];
    [[OFRelativeDateParser sharedParser] setLocale:locale];

    // We expected to get tuesday, not "mar"=>March/Marzo then nil because of the extra input
    // See <bug:///68115> (Italian localization for Sunday doesn't parse in cells [natural language, Domenica])
    
    NSDate *baseDate = nil;
    NSDate *expectedDate = nil;

    baseDate = _dateFromYear(2011, 6, 29, 0, 0, 0, calendar);
    expectedDate = _dateFromYear(2011, 7, 5, 0, 0, 0, calendar);
    parseDate( @"martedì", expectedDate, baseDate, nil, nil );

    baseDate = _dateFromYear(2011, 7, 5, 0, 0, 0, calendar);
    expectedDate = _dateFromYear(2011, 7, 10, 0, 0, 0, calendar);
    parseDate( @"domenica", expectedDate, baseDate, nil, nil );

    [[OFRelativeDateParser sharedParser] setLocale:savedLocale];
}

- (void)testGerman;
{
    NSLocale *savedLocale = [[OFRelativeDateParser sharedParser] locale];

    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"de"];
    [[OFRelativeDateParser sharedParser] setLocale:locale];

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setLocale:locale];

    // We expect to be able to get dates back for German days of the week whether or not we include punctuation at the end of the abbreviated day name

    NSDate *baseDate = _dateFromYear(2011, 7, 3, 0, 0, 0, calendar);;
    NSDate *expectedDate = nil;

    NSUInteger i, count = [[dateFormatter shortWeekdaySymbols] count];
    for (i = 0; i < count; i++) {
        NSString *dayName = [[dateFormatter shortWeekdaySymbols] objectAtIndex: i];
        
        expectedDate = _dateFromYear(2011, 7, 3 + i, 0, 0, 0, calendar);
        parseDate( dayName, expectedDate, baseDate, nil, nil ); 

        dayName = [dayName stringByReplacingCharactersInSet:[NSCharacterSet punctuationCharacterSet] withString:@""];
        parseDate( dayName, expectedDate, baseDate, nil, nil ); 
    }

    [[OFRelativeDateParser sharedParser] setLocale:savedLocale];
}

- (void)testChineseTaiwan;
{
    // <bug:///102906> (Bug: Can't change Due time when using Chinese (Simplified or Traditional) language and China or Taiwan region settings [default, due])
    NSLocale *savedLocale = [[OFRelativeDateParser sharedParser] locale];
    NSLocale *savedCalendarLocale = calendar.locale;

    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"zh-Hans_TW"];
    [[OFRelativeDateParser sharedParser] setLocale:locale];
    calendar.locale = locale;

    NSDate *baseDate = _dateFromYear(2011, 7, 5, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2014, 9, 21, 16, 52, 0, calendar);
    NSString *dateString = @"14/9/21 下午4:52";
    parseDate( dateString, expectedDate, baseDate, nil, nil ); 

    [[OFRelativeDateParser sharedParser] setLocale:savedLocale];
    calendar.locale = savedCalendarLocale;
}

- (void)_testRoundtripDate:(NSDate *)originalDate inLocaleIdentifier:(NSString *)localeIdentifier;
{
    NSLocale *savedLocale = [[OFRelativeDateParser sharedParser] locale];
    NSLocale *savedCalendarLocale = calendar.locale;

    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:localeIdentifier];
    [[OFRelativeDateParser sharedParser] setLocale:locale];
    calendar.locale = locale;

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];

    [formatter setCalendar:calendar];
    [formatter setLocale:locale];
    
    [formatter setDateStyle:NSDateFormatterNoStyle];
    [formatter setTimeStyle:NSDateFormatterShortStyle]; 
    NSString *timeFormat = [[formatter dateFormat] copy];
    NSString *timeString = [formatter stringFromDate:originalDate];

    // We're not going to combine the input date and time in a single format, we'll ensure that there is always a space between the date and time and they're in the expected order
    [formatter setDateStyle:NSDateFormatterShortStyle];
    [formatter setTimeStyle:NSDateFormatterNoStyle]; 
    NSString *shortFormat = [[formatter dateFormat] copy];
    NSString *shortDateString = [NSString stringWithFormat:@"%@ %@", [formatter stringFromDate:originalDate], timeString];

    [formatter setDateStyle:NSDateFormatterMediumStyle];
    NSString *mediumFormat = [[formatter dateFormat] copy];
    NSString *mediumDateString = [NSString stringWithFormat:@"%@ %@", [formatter stringFromDate:originalDate], timeString];

    // [formatter setDateStyle:NSDateFormatterLongStyle];
    // NSString *longFormat = [[formatter dateFormat] copy];
    // NSString *longDateString = [NSString stringWithFormat:@"%@ %@", [formatter stringFromDate:originalDate], timeString];

    NSLog(@"Testing round trip dates in [%@], time [%@] [%@], short [%@] [%@], medium [%@] [%@]", localeIdentifier, timeFormat, timeString, shortFormat, shortDateString, mediumFormat, mediumDateString);
    parseDate(shortDateString, originalDate, originalDate, shortFormat, timeFormat);
    parseDate(mediumDateString, originalDate, originalDate, mediumFormat, timeFormat);
    // parseDate(longDateString, originalDate, originalDate, longFormat, timeFormat);
    parseDate(timeString, originalDate, originalDate, nil, timeFormat);

    [[OFRelativeDateParser sharedParser] setLocale:savedLocale];
    calendar.locale = savedCalendarLocale;
}

- (void)testRoundtripDatesInAllLocales;
{
    NSDate *originalDate = _dateFromYear(2014, 9, 21, 16, 52, 0, calendar);
    for (NSString *localeIdentifier in [NSLocale availableLocaleIdentifiers]) {
        if ([localeIdentifier hasPrefix:@"mi"]) {
            // <bug:///182592> (Frameworks-Mac Bug: -[OFRelativeDateParserTests testRoundtripDatesInAllLocales] fails for `mi` locales on Catalina 10.15.4 betas)
            NSLog(@"Skipping locale %@, since NSDateFormatter incorrectly formats past-noon hours on 10.15.4 betas (FB7601856)", localeIdentifier);
            continue;
        }
        [self _testRoundtripDate:originalDate inLocaleIdentifier:localeIdentifier];
    }
}

- (void)testBasicRoundtripDate;
{
    NSDate *originalDate = _dateFromYear(2014, 9, 21, 16, 52, 0, calendar);
    [self _testRoundtripDate:originalDate inLocaleIdentifier:@"en_US"]; // English (U.S.)
}

- (void)testTrickyRoundtripDates;
{
    NSDate *originalDate = _dateFromYear(2014, 9, 21, 16, 52, 0, calendar);
    [self _testRoundtripDate:originalDate inLocaleIdentifier:@"ar_OM"]; // Arabic (Oman)
    [self _testRoundtripDate:originalDate inLocaleIdentifier:@"ee_TG"]; // Ewe (Togo)
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
    calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDate *baseDate = _dateFromYear(2007, 1, 1, 1, 1, 0, calendar);
    NSString *string = @"";
    for (NSString *dateFormat in dateFormats) {
	for (NSString *timeFormat in timeFormats) {
	    parseDate( string, nil, baseDate, dateFormat, timeFormat );   
	}
    }
}

- (void)testDegenerates;
{
    // test with all different formats
    NSUInteger dateIndex = [dateFormats count];
    while (dateIndex--) {
	NSUInteger timeIndex = [timeFormats count];
	while (timeIndex--) {
            @autoreleasepool {
	    
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
            
            }
	}
    }
}

- (void)testBugs;
{
    // test with all different formats
    for (NSString *dateFormat in dateFormats) {
	for (NSString *timeFormat in timeFormats) {
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

- (void)testSeparatedDates;
{
    // test with all different formats
    for (NSString *dateFormat in dateFormats) {
	for (NSString *timeFormat in timeFormats) {
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
    for (NSString *dateFormat in dateFormats) {
	for (NSString *timeFormat in timeFormats) {
	    NSString *string = @"may 4 1997 at 3:07pm";
	    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	    NSDate *expectedDate = _dateFromYear(1997, 5, 4, 15, 7, 0, calendar);
	    parseDate( string, expectedDate, baseDate,  dateFormat, timeFormat  ); 
	}
    }
}

- (void)testSpecificAt;
{
    NSString *string = @"may 4 1997 at 3:07pm";
    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(1997, 5, 4, 15, 7, 0, calendar);
    parseDate( string, expectedDate, baseDate, @"MM/dd/yy", @"HH:mm" );
}

- (void)testTodayAtNoon;
{
    NSString *string = @"today at noon";
    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2001, 1, 1, 12, 0, 0, calendar);
    parseDate( string, expectedDate, baseDate, @"MM/dd/yy", @"HH:mm" );
}

- (void)testNMonths
{
    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2001, 2, 1, 0, 0, 0, calendar);

    parseDate(@"1 month", expectedDate, baseDate, nil, nil);
    parseDate(@"1 m", expectedDate, baseDate, nil, nil);

    expectedDate = _dateFromYear(2001, 3, 1, 0, 0, 0, calendar);
    parseDate(@"2 months", expectedDate, baseDate, nil, nil);
    parseDate(@"2 month", expectedDate, baseDate, nil, nil);
    parseDate(@"2months", expectedDate, baseDate, nil, nil);
    parseDate(@"2m", expectedDate, baseDate, nil, nil);
    parseDate(@"2 m", expectedDate, baseDate, nil, nil);

    expectedDate = _dateFromYear(2002, 1, 1, 0, 0, 0, calendar);
    parseDate(@"12 months", expectedDate, baseDate, nil, nil);
    parseDate(@"12months", expectedDate, baseDate, nil, nil);
    parseDate(@"12month", expectedDate, baseDate, nil, nil);
    parseDate(@"12 month", expectedDate, baseDate, nil, nil);
    parseDate(@"12 m", expectedDate, baseDate, nil, nil);
    parseDate(@"12m", expectedDate, baseDate, nil, nil);
}

- (void)testRoundtripCommaFormat;
{
    NSString *commaFormat = @"M/d/yy, h:mm a";
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[OFRelativeDateParser sharedParser] locale];
    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
    NSDate *originalDate = _dateFromYear(2014, 9, 25, 15, 30, 0, calendar);
    formatter.dateFormat = commaFormat;
    NSString *originalDateString = [formatter stringFromDate:originalDate];
    NSLog(@"Parsing [%@]", originalDateString);

    NSDate *parsedDate;
    [[OFRelativeDateParser sharedParser] getDateValue:&parsedDate forString:originalDateString fromStartingDate:baseDate useEndOfDuration:NO defaultTimeDateComponents:nil calendar:calendar error:NULL];
    XCTAssertEqualObjects(originalDate, parsedDate);
    NSString *parsedDateString = [formatter stringFromDate:parsedDate];
    XCTAssertEqualObjects(originalDateString, parsedDateString);

    NSDate *reparsedDate;
    [[OFRelativeDateParser sharedParser] getDateValue:&reparsedDate forString:parsedDateString fromStartingDate:baseDate useEndOfDuration:NO defaultTimeDateComponents:nil calendar:calendar error:NULL];
    XCTAssertEqualObjects(parsedDate, reparsedDate);
    NSString *reparsedDateString = [formatter stringFromDate:reparsedDate];
    XCTAssertEqualObjects(parsedDateString, reparsedDateString);
}

- (void)testTwentyFourHourTime;
{
    // test with all different formats
    for (NSString *dateFormat in dateFormats) {
	for (NSString *timeFormat in timeFormats) {
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
    for (NSString *dateFormat in dateFormats) {
	for (NSString *timeFormat in timeFormats) {
	    XCTAssertTrue(_testRandomDate(randomState, dateFormat, dateFormat, dateFormat, timeFormat));
	}
    }
}

// Values produced by -testRandomDatesAndRoundTrips
- (void)testRandomDatesAndRoundTrips0;
{
    NSString *testDateString = @"26-Sep-94 0928";
    NSString *dateFormat = @"d-MMM-yy";
    NSString *timeFormat = @"kkmm";
    
    [calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    
    NSDate *baseDate = _dateFromYear(2007, 1, 1, 0, 0, 0, calendar);
    NSDate *date = nil;
    [[OFRelativeDateParser sharedParser] getDateValue:&date forString:testDateString fromStartingDate:baseDate calendar:calendar withShortDateFormat:dateFormat withMediumDateFormat:dateFormat withLongDateFormat:dateFormat withTimeFormat:timeFormat error:nil];
    
    XCTAssertEqualObjects(date, _dateFromYear(1994, 9, 26, 9, 28, 0, calendar));
}

- (void)testLocaleWeekdays;
{
    NSLocale *currentLocale = [NSLocale currentLocale];
    NSArray *availableLocales = [NSArray arrayWithObjects:@"de", @"es", @"fr", @"en_US", @"it", @"ja", @"nl", @"zh_CN", nil];//[NSLocale availableLocaleIdentifiers];
    unsigned int localeIndex;
    for (localeIndex = 0; localeIndex < [availableLocales count]; localeIndex++) {
	NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:[availableLocales objectAtIndex:localeIndex]];
	[[OFRelativeDateParser sharedParser] setLocale:locale];
	
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init]; 
	[formatter setLocale:locale];
	
	NSArray *weekdays = [formatter weekdaySymbols];
	NSDate *baseDate = _dateFromYear(2001, 1, 10, 0, 0, 0, calendar);
	NSDateComponents *components = [calendar components:NSCalendarUnitWeekday fromDate:baseDate];

	// test with all different formats
	NSUInteger dateIndex = [dateFormats count];
	while (dateIndex--) {
	    NSUInteger timeIndex = [timeFormats count];
	    while (timeIndex--) {
		NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
		NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
		
		NSUInteger dayIndex = [weekdays count];
		NSInteger weekday = [components weekday] - 1; // 1 based
		while (dayIndex--) {
		    NSInteger addToWeek = (dayIndex - weekday);
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
		    NSInteger addToWeek = (dayIndex - weekday);
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
	NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:[availableLocales objectAtIndex:localeIndex]];
	[[OFRelativeDateParser sharedParser] setLocale:locale];
	
	
	calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	
	[formatter setLocale:locale];
	NSArray *months = [formatter monthSymbols];
	NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
	
        NSSet *shortdays = [NSSet setWithArray:[formatter shortWeekdaySymbols]];

	NSDateComponents *components = [calendar components:NSCalendarUnitMonth fromDate:baseDate];
	
	NSUInteger dateIndex = [dateFormats count];
	while (dateIndex--) {
	    NSUInteger timeIndex = [timeFormats count];
	    while (timeIndex--) {
		NSString *timeFormat = [timeFormats objectAtIndex:timeIndex];
		NSString *dateFormat = [dateFormats objectAtIndex:dateIndex];
		
		NSUInteger monthIndex = [months count];
		NSUInteger month = [components month] - 1; // 1 based
		while (monthIndex--) {
		    NSInteger addToMonth = (monthIndex - month);
		    if (addToMonth < 0)
			addToMonth = 12;
		    else 
			addToMonth = 0;
                        
                    // If the short month symbol is also a short day symbol, skip it. We prioritize days
                    if ([shortdays containsObject:[months objectAtIndex:monthIndex]])
                        continue;

		    parseDate( [months objectAtIndex:monthIndex], 
			      _dateFromYear(2001, (1 + addToMonth + (monthIndex - month)), 1, 0, 0, 0, calendar),
			      baseDate,  dateFormat, timeFormat );
		}
		
		months = [formatter shortMonthSymbols];
		
		monthIndex = [months count];
		while (monthIndex--) {
		    NSInteger addToMonth = (monthIndex - month);
		    if (addToMonth < 0)
			addToMonth = 12;
		    else 
			addToMonth = 0;

                    // If the short month symbol is also a short day symbol, skip it. We prioritize days
                    if ([shortdays containsObject:[months objectAtIndex:monthIndex]])
                        continue;

		    parseDate( [months objectAtIndex:monthIndex], 
			      _dateFromYear(2001, (1 + addToMonth + (monthIndex - month)), 1, 0, 0, 0, calendar),
			      baseDate,  dateFormat, timeFormat );
		}
	    }
	}
    }
    [[OFRelativeDateParser sharedParser] setLocale:currentLocale];
}

- (void)testTimestamps;
{
    NSString *testDateString = @"2014-09-21 20:35:54 -0700";
    NSString *customFormat = @"yyyy'-'MM'-'dd' 'HH':'mm':'ss' 'ZZZ";
    NSString *timeFormat = @"";

    [calendar setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"PDT"]];

    NSDate *baseDate = _dateFromYear(2007, 1, 1, 0, 0, 0, calendar);
    NSDate *date = nil;
    [[OFRelativeDateParser sharedParser] getDateValue:&date forString:testDateString fromStartingDate:baseDate calendar:calendar withCustomFormat:customFormat withShortDateFormat:customFormat withMediumDateFormat:customFormat withLongDateFormat:customFormat withTimeFormat:timeFormat error:nil];

    XCTAssertEqualObjects(date, _dateFromYear(2014, 9, 21, 20, 35, 54, calendar));
}

- (void)testTimes;
{
    for (NSString *dateFormat in dateFormats) {
	for (NSString *timeFormat in timeFormats) {
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
    for (NSString *dateFormat in dateFormats) {
	for (NSString *timeFormat in timeFormats) {
            @autoreleasepool {
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
            
            }
	}
    }
}

- (void)testKoreanDateTime;
{
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"ko_KR"];
    
    calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    [calendar setLocale:locale];

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterMediumStyle];
    [dateFormatter setLocale:locale];
    [dateFormatter setCalendar:calendar];

    /*
     In ko_KR, the AM/PM designation comes before the time:
     
     NSLog(@"%@", [dateFormatter stringFromDate:_dateFromYear(2014, 1, 2, 3, 4, 5, calendar)]);
     NSLog(@"%@", [dateFormatter stringFromDate:_dateFromYear(2014, 1, 2, 15, 4, 5, calendar)]);

     2014-04-21 09:37:55.359 otest[90668:303] 2014. 1. 2. 오전 3:04:05
     2014-04-21 09:37:55.360 otest[90668:303] 2014. 1. 2. 오후 3:04:05

     */
    NSString *amDateString = @"2014. 4. 10. 오전 5:28";
    NSString *pmDateString = @"2014. 4. 10. 오후 5:28";
    
    for (NSString *dateString in @[pmDateString, amDateString]) {
        NSInteger expectedHour = (dateString == amDateString) ? 5 : 17;
        
        OFRelativeDateParser *parser = [[OFRelativeDateParser alloc] initWithLocale:locale];
        __autoreleasing NSDate *date = nil;
        __autoreleasing NSError *error = nil;
        if (![parser getDateValue:&date forString:dateString fromStartingDate:nil useEndOfDuration:NO defaultTimeDateComponents:nil calendar:calendar error:&error]) {
            XCTFail(@"Failed to parse date");
            return;
        }
        
        XCTAssertNotNil(date, @"Success should fill out a date");
        
        NSDateComponents *components = [calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute fromDate:date];
        XCTAssertEqual(components.year, 2014L);
        XCTAssertEqual(components.month, 4L);
        XCTAssertEqual(components.day, 10L);
        XCTAssertEqual(components.hour, expectedHour);
        XCTAssertEqual(components.minute, 28L);
    }
}

- (void)_testDateRelativeToAbsoluteDateWithDateFormat:(NSString *)dateFormat timeFormat:(NSString *)timeFormat;
{
    @autoreleasepool {
        NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);

        // Try parsing with a date and time format
        NSDate *expectedDate = _dateFromYear(2001, 4, 1, 0, 0, 0, calendar);

        parseDate(@"2001-07-01 -3m", expectedDate, baseDate, dateFormat, timeFormat);
        parseDate(@"July 1, 2001 -3m", expectedDate, baseDate, dateFormat, timeFormat);
        parseDate(@"July 1, 2001 3pm -3m", expectedDate, baseDate, dateFormat, timeFormat);

        expectedDate = _dateFromYear(2001, 6, 30, 0, 0, 0, calendar);
        parseDate(@"2001-07-01 -1d", expectedDate, baseDate, dateFormat, timeFormat);
        parseDate(@"July 1, 2001 -1d", expectedDate, baseDate, dateFormat, timeFormat);
        parseDate(@"July 1, 2001 15:31 -1d", expectedDate, baseDate, dateFormat, timeFormat);
        parseDate(@"July 1, 2001 3pm -1d", expectedDate, baseDate, dateFormat, timeFormat);

        expectedDate = _dateFromYear(2001, 6, 30, 15, 31, 0, calendar);
        parseDate(@"2001-07-01 15:31 -24h", expectedDate, baseDate, dateFormat, timeFormat);

        expectedDate = _dateFromYear(2001, 7, 1, 14, 31, 0, calendar);
        parseDate(@"2001-07-01 15:31 -1h", expectedDate, baseDate, dateFormat, timeFormat);

        expectedDate = _dateFromYear(2001, 6, 30, 15, 0, 0, calendar);
        parseDate(@"2001-07-01 3pm -24h", expectedDate, baseDate, dateFormat, timeFormat);

        expectedDate = _dateFromYear(2001, 7, 1, 14, 0, 0, calendar);
        parseDate(@"2001-07-01 3pm -1h", expectedDate, baseDate, dateFormat, timeFormat);

        expectedDate = _dateFromYear(2016, 4, 1, 0, 0, 0, calendar);
        parseDate(@"2016-07-01 -3m", expectedDate, baseDate, dateFormat, timeFormat);
        parseDate(@"20160701 -3m", expectedDate, baseDate, dateFormat, timeFormat);
        parseDate(@"2016  07    01 -3m", expectedDate, baseDate, dateFormat, timeFormat);
    }
}

- (void)testDateRelativeToAbsoluteDate;
{
    [self _testDateRelativeToAbsoluteDateWithDateFormat:nil timeFormat:nil];
    [self _testDateRelativeToAbsoluteDateWithDateFormat:@"yyyy-MM-dd" timeFormat:@"HH:mm"];
    [self _testDateRelativeToAbsoluteDateWithDateFormat:@"M/d/yy" timeFormat:@"HH:mm"];
    [self _testDateRelativeToAbsoluteDateWithDateFormat:@"MMMM d, y" timeFormat:@"h:mm a"];
    [self _testDateRelativeToAbsoluteDateWithDateFormat:@"MMMM d, yy" timeFormat:@"h:mm a"];
}

- (void)testMeridians;
{
    NSString *timeFormat = @"HH:mm";
    NSString *dateFormat = @"yyyy-MM-dd";
    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
    parseDate(@"12am", expectedDate, baseDate, dateFormat, timeFormat);
    parseDate(@"3am -3h", expectedDate, baseDate, dateFormat, timeFormat);
    parseDate(@"3pm -15h", expectedDate, baseDate, dateFormat, timeFormat);
    expectedDate = _dateFromYear(2001, 1, 1, 12, 0, 0, calendar);
    parseDate(@"12pm", expectedDate, baseDate, dateFormat, timeFormat);
    parseDate(@"3pm -3h", expectedDate, baseDate, dateFormat, timeFormat);
    parseDate(@"3am +9h", expectedDate, baseDate, dateFormat, timeFormat);
}

- (void)testNonIsoDashDate;
{
    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2014, 5, 6, 0, 0, 0, calendar);
    parseDate(@"05-06-14", expectedDate, baseDate, @"MM-dd-yy", @"HH:mm");
    parseDate(@"2014-05-06", expectedDate, baseDate, @"MM-dd-yy", @"HH:mm");

    expectedDate = _dateFromYear(2040, 10, 20, 0, 0, 0, calendar);
    for (NSString *dateFormat in dateFormats) {
	for (NSString *timeFormat in timeFormats) {
            parseDate(@"40-20-10", expectedDate, baseDate, dateFormat, timeFormat);
            parseDate(@"40-10-20", expectedDate, baseDate, dateFormat, timeFormat);
            parseDate(@"20-40-10", expectedDate, baseDate, dateFormat, timeFormat);
            parseDate(@"20-10-40", expectedDate, baseDate, dateFormat, timeFormat);
            parseDate(@"10-20-40", expectedDate, baseDate, dateFormat, timeFormat);
            parseDate(@"10-40-20", expectedDate, baseDate, dateFormat, timeFormat);
        }
    }
}

- (void)testShortNonIsoHyphenDates;
{
    NSDate *baseDate = _dateFromYear(2014, 1, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2014, 1, 5, 0, 0, 0, calendar);
    parseDate(@"5-1", expectedDate, baseDate, @"dd-MM-yy", @"HH:mm");
    parseDate(@"1-5", expectedDate, baseDate, @"MM-dd-yy", @"HH:mm");
}

- (void)testShortNonIsoEnDashDates;
{
    NSDate *baseDate = _dateFromYear(2014, 1, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2014, 1, 5, 0, 0, 0, calendar);
    parseDate(@"5–1", expectedDate, baseDate, @"dd-MM-yy", @"HH:mm"); // en-dash
}

- (void)testCentury;
{
    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
    NSDate *thisCentury = _dateFromYear(2040, 10, 20, 0, 0, 0, calendar);
    NSDate *firstCentury = _dateFromYear(40, 10, 20, 0, 0, 0, calendar);
    for (NSString *dateFormat in dateFormats) {
	for (NSString *timeFormat in timeFormats) {
            parseDate(@"10-20-2040", thisCentury, baseDate, dateFormat, timeFormat);
            parseDate(@"10-20-40", thisCentury, baseDate, dateFormat, timeFormat);
            if ([dateFormat containsString:@"yyyy"]) {
                parseDate(@"10-20-0040", firstCentury, baseDate, dateFormat, timeFormat);
            }
        }
    }

    NSDate *lastCentury = _dateFromYear(1999, 10, 20, 0, 0, 0, calendar);
    thisCentury = _dateFromYear(2099, 10, 20, 0, 0, 0, calendar);
    firstCentury = _dateFromYear(99, 10, 20, 0, 0, 0, calendar);
    for (NSString *dateFormat in dateFormats) {
	for (NSString *timeFormat in timeFormats) {
            parseDate(@"10-20-99", lastCentury, baseDate, dateFormat, timeFormat);
            parseDate(@"10-20-1999", lastCentury, baseDate, dateFormat, timeFormat);
            parseDate(@"10-20-2099", thisCentury, baseDate, dateFormat, timeFormat);
            if ([dateFormat containsString:@"yyyy"]) {
                parseDate(@"10-20-0099", firstCentury, baseDate, dateFormat, timeFormat);
            }
        }
    }
}

- (void)testDefaultTime;
{
    NSDateComponents *defaultTimeComponents = [[NSDateComponents alloc] init];
    defaultTimeComponents.hour = 17;
    defaultTimeComponents.minute = 0;
    defaultTimeComponents.second = 0;
    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2016, 4, 20, 17, 0, 0, calendar);
    NSDate *result = nil;
    NSString *string = @"4.20.16";
    [[OFRelativeDateParser sharedParser] getDateValue:&result forString:string fromStartingDate:baseDate useEndOfDuration:NO defaultTimeDateComponents:defaultTimeComponents calendar:calendar withCustomFormat:@"MM/dd/yy" error:NULL];
    if (expectedDate && ![result isEqual:expectedDate])
        NSLog( @"FAILURE-> String: %@, locale:%@, result:%@, expected: %@", string, [[[OFRelativeDateParser sharedParser] locale] localeIdentifier], _stringForDate(result), _stringForDate(expectedDate));
    XCTAssertEqualObjects(result, expectedDate);
}

- (void)testCombinedDateWithoutYear;
{
    NSDate *baseDate = _dateFromYear(2016, 4, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2016, 5, 12, 0, 0, 0, calendar);
    parseDate(@"May 15 -3d", expectedDate, baseDate, nil, nil);
    parseDate(@"5/15 -3d", expectedDate, baseDate, nil, nil);
    expectedDate = _dateFromYear(2017, 1, 12, 0, 0, 0, calendar);
    parseDate(@"Jan 15 -3d", expectedDate, baseDate, nil, nil);
    parseDate(@"1/15 -3d", expectedDate, baseDate, nil, nil);
    expectedDate = _dateFromYear(2016, 4, 12, 0, 0, 0, calendar);
    parseDate(@"April 15 -3d", expectedDate, baseDate, nil, nil);
    parseDate(@"4/15 -3d", expectedDate, baseDate, nil, nil);
}

- (void)testDateWithoutYearWithTime;
{
    NSDate *baseDate = _dateFromYear(2016, 4, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2016, 5, 15, 20, 01, 0, calendar);
    parseDate(@"May 15 20:01", expectedDate, baseDate, nil, nil);

    expectedDate = _dateFromYear(2016, 11, 2, 15, 0, 0, calendar);
    parseDate(@"11.2 15:", expectedDate, baseDate, nil, nil);
    parseDate(@"11.2 15:00", expectedDate, baseDate, nil, nil);
    parseDate(@"11.2. 3pm", expectedDate, baseDate, nil, nil);
    parseDate(@"11.2 3:00 pm", expectedDate, baseDate, nil, nil);
    parseDate(@"11.2 3pm", expectedDate, baseDate, nil, nil);

    expectedDate = _dateFromYear(2017, 2, 11, 15, 0, 0, calendar);
    parseDate(@"11.2 15:", expectedDate, baseDate, @"dd-MM-yy", @"HH:mm");
    parseDate(@"11.2 15:00", expectedDate, baseDate, @"dd-MM-yy", @"HH:mm");
    parseDate(@"11.2. 3pm", expectedDate, baseDate, @"dd-MM-yy", @"HH:mm");
    parseDate(@"11.2 3:00 pm", expectedDate, baseDate, @"dd-MM-yy", @"HH:mm");
    parseDate(@"11.2 3pm", expectedDate, baseDate, @"dd-MM-yy", @"HH:mm");
}

- (void)testCombinedDateWithoutYearWithTime;
{
    NSDate *baseDate = _dateFromYear(2016, 4, 1, 0, 0, 0, calendar);

    NSDate *expectedDate = _dateFromYear(2016, 5, 12, 21, 01, 0, calendar);
    parseDate(@"May 15 20:01 -71h", expectedDate, baseDate, nil, nil);
    parseDate(@"5/15 20:01 -71h", expectedDate, baseDate, nil, nil);

    expectedDate = _dateFromYear(2016, 4, 12, 17, 01, 02, calendar);
    parseDate(@"April 15 17:01:02 -72h", expectedDate, baseDate, nil, nil);
    parseDate(@"4/15 17:01:02 -72h", expectedDate, baseDate, nil, nil);

    expectedDate = _dateFromYear(2016, 4, 12, 17, 0, 0, calendar);
    parseDate(@"April 15 5pm -72h", expectedDate, baseDate, nil, nil);
    parseDate(@"4/15 5pm -72h", expectedDate, baseDate, nil, nil);

    expectedDate = _dateFromYear(2016, 4, 12, 0, 0, 0, calendar);
    parseDate(@"April 15 5pm -3d", expectedDate, baseDate, nil, nil);
    parseDate(@"4/15 5pm -3d", expectedDate, baseDate, nil, nil);
}

- (void)testGermanLongFormatDate;
{
    NSLocale *savedLocale = [[OFRelativeDateParser sharedParser] locale];

    NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:@"de"];
    [[OFRelativeDateParser sharedParser] setLocale:locale];

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setLocale:locale];

    NSDate *baseDate = _dateFromYear(2001, 1, 1, 0, 0, 0, calendar);
    NSDate *expectedDate = _dateFromYear(2014, 8, 4, 0, 0, 0, calendar);
    parseDate(@"4. August 2014", expectedDate, baseDate, nil, nil);

    [[OFRelativeDateParser sharedParser] setLocale:savedLocale];
}

- (void)testSevenDigitHeuristicDate;
{
    OFRelativeDateParser *parser = [OFRelativeDateParser sharedParser];
    
    // <bug:///136930> (Mac-OmniFocus Crasher: Crash entering date? (-[__NSCFCalendar components:fromDate:]: date cannot be nil))
    // Ensure that this fails (without raising an exception)

    @try {
        NSDate *date = nil;
        NSError *error = nil;
        BOOL result = [parser getDateValue:&date forString:@"2017011 +1d" error:&error];
        
        XCTAssertFalse(result);
        XCTAssertNil(date);
        XCTAssertNotNil(error);
    } @catch (id exception) {
        XCTFail("Parsing date threw an exception.");
    }
}

@end
