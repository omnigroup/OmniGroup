// Copyright 2002-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniFoundation/OFVersionNumber.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@interface OFDateXMLTestCase : OFTestCase
@end


@implementation OFDateXMLTestCase

- (void)testUTCTimeZone;
{
    NSTimeZone *tz = [NSDate UTCTimeZone];
    XCTAssertTrue(tz != nil);
    XCTAssertTrue([tz secondsFromGMT] == 0);
    
    // This seems buggy, but this is what we currently get. Radar 11739087: NSTimeZone returning GMT instead of UTC. We could presumably make our own shared instance with -initWithName:data:, but that would only fix confusion with the name. If the data ever divereged w.r.t. leap seconds or ...
    XCTAssertEqualObjects([tz name], @"GMT");
}

- (void)testGregorianUTCCalendar;
{
    NSCalendar *cal = [NSDate gregorianUTCCalendar];
    XCTAssertTrue(cal != nil);
    XCTAssertEqualObjects([cal calendarIdentifier], NSCalendarIdentifierGregorian);
    XCTAssertEqualObjects([cal timeZone], [NSDate UTCTimeZone]);
}

- (void)testXMLDateParsing;
{
    NSDate *date = [[NSDate alloc] initWithXMLString:@"2004-06-07T14:15:34.987Z"];
    
    NSDateComponents *components = [[NSDate gregorianUTCCalendar] components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:date];
    
    XCTAssertEqual([components year], 2004);
    XCTAssertEqual([components month], 6);
    XCTAssertEqual([components day], 7);
    XCTAssertEqual([components hour], 14);
    XCTAssertEqual([components minute], 15);
    XCTAssertEqual([components second], 34); // Not float (Radar 4867971).  Choice of floating portion ensures we are checking that they truncate.
    
    NSTimeInterval interval = [date timeIntervalSinceReferenceDate];
    NSTimeInterval milliseconds = interval - floor(interval);
    XCTAssertTrue(fabs(milliseconds - 0.987) < 0.0001);
}

#define ROUND_TRIP(inputString) do { \
    NSDate *date = [[NSDate alloc] initWithXMLString:inputString]; \
    NSString *outputString = [date xmlString]; \
    XCTAssertEqualObjects(inputString, outputString); \
} while(0)

- (void)testXMLDateParsingRoundTrip;
{
    // This case had a rounding problem such that converting the date back to an XML string would end up with .139Z instead of .140Z.
    ROUND_TRIP(@"2006-12-15T21:38:04.140Z");

    // This was going to a NSDate of "2007-12-30 21:00:00 -0800" and then to an XML string of "2008-12-31T05:00:00.000Z"
    ROUND_TRIP(@"2007-12-31T05:00:00.000Z");
}

#define ROUND_TRIP_FLOATING(inputString) do { \
    BOOL isFloating = NO; \
    NSDate *date = [[NSDate alloc] initWithXMLString:inputString allowFloating:YES outIsFloating:&isFloating]; \
    XCTAssertNotNil(date); \
    XCTAssertTrue(isFloating); \
    NSString *outputString = [date floatingTimeZoneXMLString]; \
    XCTAssertEqualObjects(inputString, outputString); \
} while(0)

- (void)testFloatingXMLDateParsingRoundTrip;
{
    ROUND_TRIP_FLOATING(@"2007-12-31T05:00:00.000");
}

- (void)testDescriptionWithHTTPFormat;
{
    XCTAssertEqualObjects([[NSDate dateWithTimeIntervalSinceReferenceDate:0.0] descriptionWithHTTPFormat],
                  @"Mon, 01 Jan 2001 00:00:00 GMT");
    XCTAssertEqualObjects([[NSDate dateWithTimeIntervalSinceReferenceDate:242635426.0] descriptionWithHTTPFormat],
                  @"Tue, 09 Sep 2008 06:43:46 GMT");
}

- (void)test1000MillisecondRounding;
{
    // <bug://bugs/48662> ("can't save" error if action modified date has 1000 thousandths of a second)
    // Make sure this does something reasonable instead of rounding the milliseconds portion to "1000Z"    
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:239687680.999502]; // 2008-08-05 20:54:41 -0700
    NSString *xmlString = [date xmlString];
    XCTAssertEqualObjects(xmlString, @"2008-08-06T03:54:41.000Z");

#if 0
    while (YES) {
        @autoreleasepool {
            NSDate *date = [NSDate date];
            NSString *xmlString = [date xmlString];
            
            if ([xmlString hasSuffix:@"1000Z"]) {
                NSLog(@"offset = %f, date = %@, xmlString = %@", [date timeIntervalSinceReferenceDate], date, xmlString);
                break;
            }
        }
    }
#endif
}

// -autorelease to make clang happy.
#define REJECT(str) XCTAssertTrue([[NSDate alloc] initWithXMLString:str] == nil)

static void _checkFraction(OFDateXMLTestCase *self, SEL _cmd, NSString *str, NSTimeInterval expectedFraction)
{
    NSDate *date = [[NSDate alloc] initWithXMLString:str];
    XCTAssertTrue(date != nil);
    if (date == nil)
        return;
    
    NSTimeInterval interval = [date timeIntervalSinceReferenceDate];
    
    NSTimeInterval actualFraction = interval - floor(interval);

    NSTimeInterval error = fabs(expectedFraction - actualFraction);
    XCTAssertTrue(error < 0.00000001);
}

- (void)testFractionalSecond;
{
    // Decimal point w/o at least one digit should be rejected.
    REJECT(@"2004-06-07T14:15:34.Z");

    // Should allow variable length fractional second, with 1 to 9 digits.
#define CHECK_FRACTION(str, frac) _checkFraction(self, _cmd, str, frac)
    CHECK_FRACTION(@"2004-06-07T14:15:34.1Z", 0.1);
    CHECK_FRACTION(@"2004-06-07T14:15:34.12Z", 0.12);
    CHECK_FRACTION(@"2004-06-07T14:15:34.123Z", 0.123);
    CHECK_FRACTION(@"2004-06-07T14:15:34.1234Z", 0.1234);
    CHECK_FRACTION(@"2004-06-07T14:15:34.12345Z", 0.12345);
    CHECK_FRACTION(@"2004-06-07T14:15:34.123456Z", 0.123456);
    CHECK_FRACTION(@"2004-06-07T14:15:34.1234567Z", 0.1234567);
    CHECK_FRACTION(@"2004-06-07T14:15:34.12345678Z", 0.12345678);
    CHECK_FRACTION(@"2004-06-07T14:15:34.123456789Z", 0.123456789);
#undef CHECK_FRACTION
    
    // Too long of a fraction string should be rejected.
    REJECT(@"2004-06-07T14:15:34.1234567891Z");
}

- (void)testNil;
{
    NSString *input = nil;
    REJECT(input);
}

- (void)testTruncatedDate
{
    // Every prefix of this date should be rejected.
    NSString *dateString = @"2004-06-07T14:15:34.987Z";
    NSUInteger dateStringIndex = [dateString length];
    while (dateStringIndex--) {
        NSString *prefix = [dateString substringToIndex:dateStringIndex];
        REJECT(prefix);
    }
}

#undef REJECT

#define EQUAL_DATES(str1, str2) do { \
    NSDate *date1 = [[NSDate alloc] initWithXMLString:str1]; \
    NSDate *date2 = [[NSDate alloc] initWithXMLString:str2]; \
    XCTAssertEqualObjects(date1, date2); \
} while(0)

- (void)testNonUTCTimeZone;
{
    EQUAL_DATES(@"2004-06-07T16:15:34.987Z", @"2004-06-07T15:15:34.987-01:00");
    EQUAL_DATES(@"2004-06-07T22:50:00Z", @"2004-06-07T18:50:00-04:00");

    EQUAL_DATES(@"2004-06-07T14:15:34.987Z", @"2004-06-07T15:15:34.987+01:00");
    EQUAL_DATES(@"2004-06-07T14:50:00Z", @"2004-06-07T18:50:00+04:00");
}

#undef EQUAL_DATES

- (void)testThreadSafety;
{
    if (![[self class] shouldRunSlowUnitTests]) {
        NSLog(@"*** SKIPPING slow test [%@ %@]", [self class], NSStringFromSelector(_cmd));
        return;
    }

    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.name = self.name;
    
    for (NSUInteger blockIndex = 0; blockIndex < 64; blockIndex++) {
        [queue addOperationWithBlock:^{
            for (NSUInteger dateIndex = 0; dateIndex < 1e4; dateIndex++) {
                NSDate *originalDate = [NSDate date];
                NSString *xmlString = [originalDate xmlString];
                NSDate *decodedDate = [[NSDate alloc] initWithXMLString:xmlString];
                XCTAssertNotNil(decodedDate);
                
                if (fabs([originalDate timeIntervalSinceReferenceDate] - [decodedDate timeIntervalSinceReferenceDate]) > 0.001) {
                    NSLog(@"originalDate %@ / %f, xmlString %@, decodedDate %@  / %f", originalDate, [originalDate timeIntervalSinceReferenceDate], xmlString, decodedDate, [decodedDate timeIntervalSinceReferenceDate]);
                    XCTFail(@"Did not round-trip date");
                }
                //XCTAssertEqualWithAccuracy([originalDate timeIntervalSinceReferenceDate], [decodedDate timeIntervalSinceReferenceDate], 0.001, nil);
            }
        }];
    }
    
    [queue waitUntilAllOperationsAreFinished];
}

// Check our new implementation vs. how the system does it.
static NSDateFormatter *HttpDateFormatter(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // reference: https://developer.apple.com/library/archive/qa/qa1480/_index.html
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss 'GMT'"];
        [dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
        [dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

        formatter = dateFormatter;
    });
    return formatter;
}


- (void)testRandomHTTPDateParsing;
{
    for (NSUInteger trial = 0; trial < 100000; trial++) {
        NSTimeInterval timeInterval = round(OFRandomNextDouble() * 1e6); // One million seconds since the Jan 1, 2001 epoch.
        NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:timeInterval];

        NSString *httpString = [HttpDateFormatter() stringFromDate:date];
        NSDate *parsedDate = [[NSDate alloc] initWithHTTPString:httpString];

        XCTAssertEqualObjects(date, parsedDate);

        NSString *formattedString = [date descriptionWithHTTPFormat];
        XCTAssertEqualObjects(httpString, formattedString);
    }
}

- (void)testHTTPDateParsing;
{
    NSString *httpString = @"Sat, 06 Jan 2001 10:14:09 GMT";
    NSDate *date = [HttpDateFormatter() dateFromString:httpString];
    NSDate *parsedDate = [[NSDate alloc] initWithHTTPString:httpString];
    XCTAssertEqualObjects(date, parsedDate);
}

- (void)testHTTPDateParsingSpeed;
{
    NSArray <NSString *> *dateStrings;
    @autoreleasepool {
        NSMutableArray *results = [NSMutableArray array];
        for (NSUInteger trial = 0; trial < 100000; trial++) {
            NSTimeInterval timeInterval = round(OFRandomNextDouble() * 1e6); // One million seconds since the Jan 1, 2001 epoch.
            NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:timeInterval];
            NSString *httpString = [HttpDateFormatter() stringFromDate:date];
            [results addObject:httpString];
        }
        dateStrings = [results copy];
    }

    NSMutableArray *dates = [NSMutableArray array];
    NSMutableArray *parsedDates = [NSMutableArray array];
    NSTimeInterval start, end, old, new;

    start = [NSDate timeIntervalSinceReferenceDate];
    for (NSString *string in dateStrings) {
        NSDate *date = [HttpDateFormatter() dateFromString:string];
        [dates addObject:date];
    }
    end = [NSDate timeIntervalSinceReferenceDate];
    old = (end - start);

    start = [NSDate timeIntervalSinceReferenceDate];
    for (NSString *string in dateStrings) {
        NSDate *date = [[NSDate alloc] initWithHTTPString:string];
        [parsedDates addObject:date];
    }
    end = [NSDate timeIntervalSinceReferenceDate];
    new = (end - start);

    XCTAssertEqualObjects(dates, parsedDates);
    NSLog(@"old %f, new %f", old, new);
}

// YYYYMMddTHHmmssZ
- (void)testICSString;
{
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:390177789];
    NSLog(@"date = %@", date);
    NSString *dateString = [date icsDateString];
    XCTAssertEqualObjects(dateString, @"20130513T224309Z");
    
    NSDate *decodedDate = [[NSDate alloc] initWithICSDateString:dateString];
    
    NSDateComponents *components = [[NSDate gregorianUTCCalendar] components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:decodedDate];
    XCTAssertEqual(components.year, 2013L);
    XCTAssertEqual(components.month, 5L);
    XCTAssertEqual(components.day, 13L);
    XCTAssertEqual(components.hour, 22L);
    XCTAssertEqual(components.minute, 43L);
    XCTAssertEqual(components.second, 9L);
}

// ISO 8601 Calendar date strings (YYYY-MM-DD)
- (void)testCalendarDateString;
{
    NSString *dateString = [[NSDate dateWithTimeIntervalSinceReferenceDate:390177780] xmlDateString];
    XCTAssertEqualObjects(dateString, @"2013-05-13");
    
    NSDate *decodedDate = [[NSDate alloc] initWithXMLDateString:dateString];
    NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:decodedDate];
    XCTAssertEqual(components.year, 2013L);
    XCTAssertEqual(components.month, 5L);
    XCTAssertEqual(components.day, 13L);
    XCTAssertEqual(components.hour, 0L);
    XCTAssertEqual(components.minute, 0L);
    XCTAssertEqual(components.second, 0L);
}

// ICS drops the dashes, YYYYMMDD
- (void)testICSDateString;
{
    NSString *dateString = [[NSDate dateWithTimeIntervalSinceReferenceDate:390177780] icsDateOnlyString];
    XCTAssertEqualObjects(dateString, @"20130513");
    
    NSDate *decodedDate = [[NSDate alloc] initWithICSDateOnlyString:dateString];
    NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:decodedDate];
    XCTAssertEqual(components.year, 2013L);
    XCTAssertEqual(components.month, 5L);
    XCTAssertEqual(components.day, 13L);
    XCTAssertEqual(components.hour, 0L);
    XCTAssertEqual(components.minute, 0L);
    XCTAssertEqual(components.second, 0L);
}

- (void)testDateComponentsTimeZone;
{
    NSCalendar *calendar = [NSDate gregorianUTCCalendar];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.year = 2014;
    components.month = 8;
    components.day = 15;
    components.hour = 0;
    components.minute = 0;
    components.second = 0;
    components.nanosecond = 0;

    components.calendar = calendar;
    components.timeZone = calendar.timeZone;
    
    NSTimeInterval UTCInterval = [[calendar dateFromComponents:components] timeIntervalSinceReferenceDate];
    
    components.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:3600];
    NSTimeInterval OffsetInterval = [[calendar dateFromComponents:components] timeIntervalSinceReferenceDate];
    
    XCTAssertEqualWithAccuracy(UTCInterval - OffsetInterval, 3600, 0.01);
}

- (void)testOutOfRangeComponent;
{
    // Our current implementation uses a path that wraps out-of-range components. This isn't ideal, but we should get a reasonable result.
    NSDate *date = [[NSDate alloc] initWithXMLString:@"2001-01-01T25:00:00Z"];

    NSString *dateString = [date xmlString];

    XCTAssertEqualObjects(dateString, @"2001-01-02T01:00:00.000Z");
}

// A NSCalendar-based version for -xmlString
static NSString *_xmlStyleDateStringWithFormat(NSDate *self)
{
    NSString *formatString = @"%04d-%02d-%02dT%02d:%02d:%02d.%03dZ";
    NSCalendar *calendar = [NSDate gregorianUTCCalendar];
    NSDateComponents *components = [calendar componentsInTimeZone:calendar.timeZone fromDate:self];

    // Figure out the milliseconds portion
    NSTimeInterval fractionalSeconds = components.nanosecond * 1e-9;
    OBASSERT(fractionalSeconds >= 0.0);

    // Convert the milliseconds to an integer.  If this rolls over to the next second due to rounding, deal with it.
    unsigned milliseconds = (unsigned)round(fractionalSeconds * 1000.0);
    if (milliseconds >= 1000) {
        milliseconds = 0;

        NSDateComponents *secondComponents = [[NSDateComponents alloc] init];
        secondComponents.second = 1;

        NSDate *date = [calendar dateByAddingComponents:secondComponents toDate:self options:0];

        components = [calendar componentsInTimeZone:calendar.timeZone fromDate:date];
    }

    return [NSString stringWithFormat:formatString, components.year, components.month, components.day, components.hour, components.minute, components.second, milliseconds];
}

- (void)testRoundingBeforeReferenceDate;
{
    NSTimeInterval ti = -61213924.841500; // ... which is actually -61213924.841499999, but NSCalendar rounds as if it is the typed value.
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:ti];

    NSString *oldString = _xmlStyleDateStringWithFormat(date); // 1999-01-23T12:07:55.158Z
    NSString *newString = [date xmlString];
    XCTAssertEqualObjects(oldString, newString);
}
- (void)testRoundingBeforeReferenceDate2;
{
    NSTimeInterval ti = -91566632.182315856;
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:ti];

    NSString *oldString = _xmlStyleDateStringWithFormat(date); // 1998-02-06T04:49:27.818Z
    NSString *newString = [date xmlString];
    XCTAssertEqualObjects(oldString, newString);
}
- (void)testRoundingBeforeReferenceDate3;
{
    NSTimeInterval ti = -150304740.64349997;
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:ti];

    NSString *oldString = _xmlStyleDateStringWithFormat(date); // 1996-03-28T08:40:59.357Z
    NSString *newString = [date xmlString];
    XCTAssertEqualObjects(oldString, newString);
}
- (void)testRoundingBeforeReferenceDate4;
{
    NSTimeInterval ti = -7396826.312500;
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:ti];
    
    NSString *oldString = _xmlStyleDateStringWithFormat(date); // 2000-10-07T09:19:33.688Z
    NSString *newString = [date xmlString];
    XCTAssertEqualObjects(oldString, newString);
}

// Playing off -testRoundingBeforeReferenceDate4, test what happens with a -0.NNN5 fractional seconds value in the first second of a day.

- (void)testRoundingBeforeReferenceDate5;
{
    NSDate *day = [[NSDate alloc] initWithXMLString:@"1999-01-01T00:00:00Z"];
    NSTimeInterval ti = day.timeIntervalSinceReferenceDate + 0.6875; // This gives a negative time interval where the fractional part ends in 0.NNN5 instead of 0.NNN49999 or the like.

    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:ti];

    NSString *oldString = _xmlStyleDateStringWithFormat(date);
    NSString *newString = [date xmlString];
    XCTAssertEqualObjects(oldString, newString);
    XCTAssertEqualObjects(oldString, @"1999-01-01T00:00:00.688Z");
}

- (void)testXMLStringVsPreviousImplementation;
{
    // Test +/- about 5 years around the NSDate epoch
    NSTimeInterval magnitude = 60*60*24*365*5;

    for (NSUInteger test = 0; test < 100000; test++) {
        NSTimeInterval ti = -magnitude + (2*magnitude)*OFRandomNextDouble();

        @autoreleasepool {
            NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:ti];
            NSString *oldString = _xmlStyleDateStringWithFormat(date);
            NSString *newString = [date xmlString];
            XCTAssertEqualObjects(oldString, newString, @"Failed for time interval %lf", ti);
        }
    }
}

- (void)test1970;
{
    NSString *oldString = _xmlStyleDateStringWithFormat([NSDate dateWithTimeIntervalSince1970:0]);
    NSString *newString = [[NSDate dateWithTimeIntervalSince1970:0] xmlString];

    XCTAssertEqualObjects(newString, oldString);
    XCTAssertEqualObjects(newString, @"1970-01-01T00:00:00.000Z");

    NSString *slightlyBefore1970 = [[NSDate dateWithTimeIntervalSince1970: -0.001] xmlString];
    XCTAssertEqualObjects(slightlyBefore1970, @"1969-12-31T23:59:59.999Z");

    NSString *slightlyAfter1970 = [[NSDate dateWithTimeIntervalSince1970: +0.001] xmlString];
    XCTAssertEqualObjects(slightlyAfter1970, @"1970-01-01T00:00:00.001Z");
}

- (void)testOmnifocusSyncTransactionDateString;
{
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:239687680.999502]; // 2008-08-05 20:54:41 -0700
    NSString *string = [date omnifocusSyncTransactionDateString];
    XCTAssertEqualObjects(string, @"20080806035441");
}

@end

@interface OFDateXMLMultithreadingTestCase : OFTestCase
@end

@implementation OFDateXMLMultithreadingTestCase

+ (NSUInteger)defaultLimit;
{
    return 1000000;
}

- (NSOperation *)dateFormattingOperationWithSelector:(SEL)formatSelector;
{
    return [self dateFormattingOperationWithSelector:formatSelector limit:[[self class] defaultLimit]];
}

- (NSOperation *)dateFormattingOperationWithSelector:(SEL)formatSelector limit:(NSUInteger)limit;
{
    return [NSBlockOperation blockOperationWithBlock:^{
        for (NSUInteger i = 0; i < limit; i++) {
            NSString *string = OBSendObjectReturnMessage([NSDate date], formatSelector);
            OB_UNUSED_VALUE(string);
        }
    }];
}

/// -omnifocusSyncTransactionDateString uses date + time to the second in UTC without separators
- (void)testOmniFocusSyncTransactionDateStringMultithreaded;
{
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
    
    queue.suspended = YES;
    [queue addOperation:[self dateFormattingOperationWithSelector:@selector(omnifocusSyncTransactionDateString)]];
    [queue addOperation:[self dateFormattingOperationWithSelector:@selector(omnifocusSyncTransactionDateString)]];
    queue.suspended = NO;
    
    [queue waitUntilAllOperationsAreFinished];
}

/// -xmlString uses date + time to the millisecond in UTC with separators
- (void)testXMLStringMultithreaded;
{
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
    
    queue.suspended = YES;
    [queue addOperation:[self dateFormattingOperationWithSelector:@selector(xmlString)]];
    [queue addOperation:[self dateFormattingOperationWithSelector:@selector(xmlString)]];
    queue.suspended = NO;
    
    [queue waitUntilAllOperationsAreFinished];
}

/// -xmlDateString uses date only in the local time zone
- (void)testXMLDateStringMultithreaded;
{
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
    
    queue.suspended = YES;
    [queue addOperation:[self dateFormattingOperationWithSelector:@selector(xmlDateString)]];
    [queue addOperation:[self dateFormattingOperationWithSelector:@selector(xmlDateString)]];
    queue.suspended = NO;
    
    [queue waitUntilAllOperationsAreFinished];
}

- (void)testMultipleXMLStringMethodsMultithreaded;
{
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
    
    queue.suspended = YES;
    [queue addOperation:[self dateFormattingOperationWithSelector:@selector(xmlString)]];
    [queue addOperation:[self dateFormattingOperationWithSelector:@selector(xmlDateString)]];
    [queue addOperation:[self dateFormattingOperationWithSelector:@selector(omnifocusSyncTransactionDateString)]];
    queue.suspended = NO;
    
    [queue waitUntilAllOperationsAreFinished];
}

@end
