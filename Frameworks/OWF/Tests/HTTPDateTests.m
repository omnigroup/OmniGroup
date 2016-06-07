// Copyright 2004-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>
#import <XCTest/XCTest.h>

#import <OWF/NSDate-OWExtensions.h>

RCS_ID("$Id$");

@interface HTTPDateTests : XCTestCase
@end

@implementation HTTPDateTests

- (void)testHTTPDate;
{
    NSTimeZone *gmt = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];

    // Various standard formats
    NSString *rfc1123Format = @"%a, %d %b %Y %H:%M:%S %Z"; // RFC1123
    NSString *rfc850Format = @"%A, %d-%b-%y %H:%M:%S %Z"; // RFC850
    NSString *asctimeFormat = @"%a %b %d %H:%M:%S %Y"; // asctime() format

    // Various observed variants which we've encountered on the web: long years, long weekdays, extra dashes and missing dashes, missing spaces, numeric months, etc.
    NSString *nonstandardFormat1 = @"%a, %d-%b-%Y %H:%M:%S %Z";
    NSString *nonstandardFormat2 = @"%A, %d-%b-%Y %H:%M:%S %Z";
    NSString *nonstandardFormat3 = @"%A, %d %b %Y %H:%M:%S %Z";
    NSString *nonstandardFormat4 = @"%a, %d %b %Y %H:%M:%S%Z";
    NSString *nonstandardFormat5 = @"%a, %d-%m-%Y %H:%M:%S %Z";

#define testFormat(testDate, format) XCTAssertEqualObjects([NSDate dateWithHTTPDateString:[testDate descriptionWithCalendarFormat:format]], testDate);

    // Let's try parsing the current time using lots of formats
    NSCalendarDate *currentDate = [NSDate dateWithString:[[NSCalendarDate calendarDate] descriptionWithCalendarFormat:rfc1123Format]];
    testFormat(currentDate, rfc1123Format);
    testFormat(currentDate, rfc850Format);
    testFormat(currentDate, asctimeFormat);
    testFormat(currentDate, nonstandardFormat1);
    testFormat(currentDate, nonstandardFormat2);
    testFormat(currentDate, nonstandardFormat3);
    testFormat(currentDate, nonstandardFormat4);
    testFormat(currentDate, nonstandardFormat5);

    // And, of course, lots people seem to use "0", "-1", or "now" in their expires headers rather than using a date, so...
#define testTimeIntervalString(intervalString, interval) XCTAssertTrue(fabs([[NSDate dateWithHTTPDateString:intervalString] timeIntervalSinceNow] - interval) < 0.01)
    testTimeIntervalString(@"0", 0.0);
    testTimeIntervalString(@"-1", -1.0);
    testTimeIntervalString(@"now", 0.0);
    testTimeIntervalString(@"Now", 0.0);
    testTimeIntervalString(@"NOW", 0.0);
    
    // OK, let's try the exact numeric month string which we were handed by www.volkskrant.nl (bug #13990).  You can't get this exact string from descriptionWithCalendarFormat, because Jan 1, 1970 was actually a Thursday.
    XCTAssertEqualObjects([NSDate dateWithHTTPDateString:@"Mon, 01-01-1970 00:00:01 GMT"], [NSCalendarDate dateWithYear:1970 month:00 day:01 hour:00 minute:00 second:01 timeZone:gmt]);
}

@end
