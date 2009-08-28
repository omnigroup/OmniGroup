// Copyright 2002-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@interface OFDateXMLTestCase : OFTestCase
@end


@implementation OFDateXMLTestCase

- (void)testUTCTimeZone;
{
    NSTimeZone *tz = [NSDate UTCTimeZone];
    should(tz != nil);
    should([tz secondsFromGMT] == 0);
    shouldBeEqual([tz name], @"UTC");
}

- (void)testGregorianUTCCalendar;
{
    NSCalendar *cal = [NSDate gregorianUTCCalendar];
    should(cal != nil);
    shouldBeEqual([cal calendarIdentifier], NSGregorianCalendar);
    shouldBeEqual([cal timeZone], [NSDate UTCTimeZone]);
}

- (void)testXMLDateParsing;
{
    NSDate *date = [[[NSDate alloc] initWithXMLString:@"2004-06-07T14:15:34.987Z"] autorelease];
    
    NSDateComponents *components = [[NSDate gregorianUTCCalendar] components:NSYearCalendarUnit|NSMonthCalendarUnit|NSDayCalendarUnit|NSHourCalendarUnit|NSMinuteCalendarUnit|NSSecondCalendarUnit fromDate:date];
    
    should([components year] == 2004);
    should([components month] == 6);
    should([components day] == 7);
    should([components hour] == 14);
    should([components minute] == 15);
    should([components second] == 34); // Not float (Radar 4867971).  Choice of floating portion ensures we are checking that they truncate.
    
    NSTimeInterval interval = [date timeIntervalSinceReferenceDate];
    NSTimeInterval milliseconds = interval - floor(interval);
    should(fabs(milliseconds - 0.987) < 0.0001);
}

#define ROUND_TRIP(inputString) do { \
    NSDate *date = [[[NSDate alloc] initWithXMLString:inputString] autorelease]; \
    NSString *outputString = [date xmlString]; \
    shouldBeEqual(inputString, outputString); \
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
    shouldBeEqual([[NSDate dateWithTimeIntervalSinceReferenceDate:0.0] descriptionWithHTTPFormat],
                  @"Mon, 01 Jan 2001 00:00:00 GMT");
    shouldBeEqual([[NSDate dateWithTimeIntervalSinceReferenceDate:242635426.0] descriptionWithHTTPFormat],
                  @"Tue, 09 Sep 2008 06:43:46 GMT");
}

- (void)test1000MillisecondRounding;
{
    // <bug://bugs/48662> ("can't save" error if action modified date has 1000 thousandths of a second)
    // Make sure this does something reasonable instead of rounding the milliseconds portion to "1000Z"    
    NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:239687680.999502]; // 2008-08-05 20:54:41 -0700
    NSString *xmlString = [date xmlString];
    shouldBeEqual(xmlString, @"2008-08-06T03:54:41.000Z");

#if 0
    while (YES) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
        NSDate *date = [NSDate date];
        NSString *xmlString = [date xmlString];
        
        if ([xmlString hasSuffix:@"1000Z"]) {
            NSLog(@"offset = %f, date = %@, xmlString = %@", [date timeIntervalSinceReferenceDate], date, xmlString);
            break;
        }
        
        [pool release];
    }
#endif
}

// -autorelease to make clang happy.
#define REJECT(str) should([[[NSDate alloc] initWithXMLString:str] autorelease] == nil)

static void _checkFraction(OFDateXMLTestCase *self, SEL _cmd, NSString *str, NSTimeInterval expectedFraction)
{
    NSDate *date = [[NSDate alloc] initWithXMLString:str];
    should(date != nil);
    if (date == nil)
        return;
    
    NSTimeInterval interval = [date timeIntervalSinceReferenceDate];
    [date release];
    
    NSTimeInterval actualFraction = interval - floor(interval);

    NSTimeInterval error = fabs(expectedFraction - actualFraction);
    should(error < 0.00000001);
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
    shouldBeEqual(date1, date2); \
    [date1 release]; \
    [date2 release]; \
} while(0)

- (void)testNonUTCTimeZone;
{
    EQUAL_DATES(@"2004-06-07T14:15:34.987Z", @"2004-06-07T15:15:34.987-01:00");
    EQUAL_DATES(@"2004-06-07T22:50:00Z", @"2004-06-07T18:50:00-04:00");

    EQUAL_DATES(@"2004-06-07T13:15:34.987Z", @"2004-06-07T15:15:34.987+01:00");
    EQUAL_DATES(@"2004-06-07T14:50:00Z", @"2004-06-07T18:50:00+04:00");
}

#undef EQUAL_DATES

@end
