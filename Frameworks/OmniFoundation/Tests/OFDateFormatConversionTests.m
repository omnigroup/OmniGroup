// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFDateFormatConversion.h>
#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniFoundation/OFNull.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@interface OFDateFormatConversionTests : OFTestCase
{
    NSCalendarDate *_date;
    NSDateFormatter *_dateFormatter;
}
@end

@implementation OFDateFormatConversionTests

- (void)setUp;
{
    [super setUp];
    
    // Use a date with a different numeric value in each component (including treating the year as 2-digit and weekday as a number), otherwise we might not notice transposition failures.
    // Do all the tests in UTC to make sure the hours don't get shifted into our local timezone, making this potentially pointless.
    // Make the day and month single digits so that we can get both "0N" and "N" out of their formats. This leaves 0-7 for possible day-of-week values. Phew.
    
    NSDate *date = [[NSDate alloc] initWithXMLString:@"2010-09-08T13:14:15.16Z"];
    OBASSERT(date);
    
    _date = [[NSCalendarDate alloc] initWithTimeIntervalSinceReferenceDate:[date timeIntervalSinceReferenceDate]];
    [_date setTimeZone:[NSDate UTCTimeZone]];
    
    [date release];

    _dateFormatter = [[NSDateFormatter alloc] init];
    [_dateFormatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease]];
    STAssertTrue([_dateFormatter formatterBehavior] == NSDateFormatterBehavior10_4, @"Should default to the 10.4+ behavior when linked on 10.6");
    
    [_dateFormatter setTimeZone:[NSDate UTCTimeZone]];
}

- (void)tearDown;
{
    [_date release];
    _date = nil;
    
    [_dateFormatter release];
    _dateFormatter = nil;
    
    [super tearDown];
}

void _testFormat(OFDateFormatConversionTests *self, NSString *oldDateFormat, BOOL shouldBeEqual, NSString *expectedNewResult)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSString *oldResult = [self->_date descriptionWithCalendarFormat:oldDateFormat];
    
    NSString *newDateFormat = OFDateFormatStringForOldFormatString(oldDateFormat);
    [self->_dateFormatter setDateFormat:newDateFormat];
    
    NSString *newResult = [self->_dateFormatter stringFromDate:self->_date];
    
    NSLog(@"[%@] -> [%@]: [%@] -> [%@]", oldDateFormat, newDateFormat, oldResult, newResult);
    
    if (shouldBeEqual)
        STAssertEqualObjects(oldResult, newResult, nil);

    if (expectedNewResult)
        STAssertEqualObjects(newResult, expectedNewResult, nil);
        
    [pool drain];
}

#define testFormat(format) _testFormat(self, (format), YES, nil)
#define testFormatXFAIL(format) _testFormat(self, (format), NO, nil)

- (void)testSingleSpecifiers;
{
    
    STAssertTrue([NSDateFormatter defaultFormatterBehavior] == NSDateFormatterBehavior10_4, @"Should default to the 10.4+ behavior when linked on 10.6");

    testFormat(@"%%");
    testFormat(@"%a");
    testFormat(@"%A");
    testFormat(@"%b");
    testFormat(@"%B");
    testFormatXFAIL(@"%c"); // Time zone names are different
    testFormat(@"%d");
    testFormat(@"%e");
    testFormatXFAIL(@"%F"); // Milliseconds round differently
    testFormat(@"%H");
    testFormat(@"%I");
    testFormat(@"%j");
    testFormat(@"%m");
    testFormat(@"%M");
    testFormat(@"%p");
    testFormat(@"%S");
    testFormatXFAIL(@"%w"); // Numeric weekdays are different
    testFormat(@"%x");
    testFormatXFAIL(@"%X"); // Time zone names are different
    testFormat(@"%y");
    testFormat(@"%Y");
    testFormatXFAIL(@"%Z"); // Time zone names are different
    testFormat(@"%z");
    testFormat(@"%U%N%K%N%O%W%N");
    testFormat(@"Random text");
    testFormat(@"Year: %Y, Month: %M, Day: %d");
    testFormat(@"Here's a year: %Y");
    
    // Some example formats from OmniGraffle's Reference stencil
    testFormat(@"%m/%d/%Y %I:%M %p");
    testFormat(@"%m/%d/%Y");
    testFormatXFAIL(@"%c"); // Time zone names are different
    testFormat(@"%m/%d/%y");
}

- (void)testSingleDigitSpecifiers;
{
    // normal specifiers do leading zero
    _testFormat(self, @"%m", YES, @"09");
    _testFormat(self, @"%d", YES, @"08");

    // %1d and %1m, which avoid the leading zero <http://developer.apple.com/mac/library/documentation/cocoa/conceptual/dataformatting/Articles/df100103.html#//apple_ref/doc/uid/TP40007972-SW1>
    _testFormat(self, @"%1m", YES, @"9");
    _testFormat(self, @"%1d", YES, @"8");
}

- (void)testQuoting;
{
    _testFormat(self, @"hi there %1d", YES, @"hi there 8");
    _testFormat(self, @"%1d/%1m", YES, @"8/9");
    _testFormat(self, @"'%1d/%1m'", YES, @"'8/9'");
    _testFormat(self, @"\"%1d/%1m\"", YES, @"\"8/9\"");
    _testFormat(self, @"'", YES, @"'");
    _testFormat(self, @"\"", YES, @"\"");
    _testFormat(self, @"'\"", YES, @"'\"");
    _testFormat(self, @"\"'", YES, @"\"'");
    _testFormat(self, @"%H o'clock", YES, @"13 o'clock");
}

@end

