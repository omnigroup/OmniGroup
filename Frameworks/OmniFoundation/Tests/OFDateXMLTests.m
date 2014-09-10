// Copyright 2002-2008, 2010, 2012-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/NSDate-OFExtensions.h>
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
    
    XCTAssertTrue([components year] == 2004);
    XCTAssertTrue([components month] == 6);
    XCTAssertTrue([components day] == 7);
    XCTAssertTrue([components hour] == 14);
    XCTAssertTrue([components minute] == 15);
    XCTAssertTrue([components second] == 34); // Not float (Radar 4867971).  Choice of floating portion ensures we are checking that they truncate.
    
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
    REJECT(nil);
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
    NSDate *date2 = [[NSDate alloc] initWithXMLString:str1]; \
    XCTAssertEqualObjects(date1, date2); \
} while(0)

- (void)testNonUTCTimeZone;
{
    EQUAL_DATES(@"2004-06-07T14:15:34.987Z", @"2004-06-07T15:15:34.987-01:00");
    EQUAL_DATES(@"2004-06-07T22:50:00Z", @"2004-06-07T18:50:00-04:00");

    EQUAL_DATES(@"2004-06-07T13:15:34.987Z", @"2004-06-07T15:15:34.987+01:00");
    EQUAL_DATES(@"2004-06-07T14:50:00Z", @"2004-06-07T18:50:00+04:00");
}

#undef EQUAL_DATES

- (void)testThreadSafety;
{
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

@end
