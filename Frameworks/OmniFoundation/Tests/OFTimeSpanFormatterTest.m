// Copyright 2005-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/OFTimeSpanFormatter.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@interface OFTimeSpanFormatterTest : OFTestCase
{
}

@end

@implementation OFTimeSpanFormatterTest

- (void)testDefaultFormatter;
{
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1y 1mo 1w 1d 1h";
    NSString *expectedTimeSpanString = @"53w 1d 1h";
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-53w 1d 1h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y -1mo -1w -1d 1h";
    expectedTimeSpanString = @"-53w 1d 1h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y1mo1w1d1h";
    expectedTimeSpanString = @"-53w 1d 1h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y1mo1w1d1h";
    expectedTimeSpanString = @"-53w 1d 1h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"1w - 1d 1h";
    expectedTimeSpanString = @"3d 7h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"1w-1d1h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"1w-1d1h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"1w-1d+1h";
    expectedTimeSpanString = @"4d 1h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    [formatter release];
}

- (void)testStandardCalendarTimeFormatter;
{
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    [formatter setStandardCalendarTime];
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1y";
    NSString *expectedTimeSpanString = @"52w 1d";
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y";
    expectedTimeSpanString = @"-52w 1d";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    [formatter release];
}

- (void)testAllFormats;
{
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1y 1mo 1w 1d 1h";
    NSString *expectedTimeSpanString = @"1y 1mo 1w 1d 1h";
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];

    [formatter setDisplayMonths:YES];
    [formatter setDisplayYears:YES];
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-1y 1mo 1w 1d 1h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    [formatter release];
}

- (void)testNoFormats;
{
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1y 1m 1w 1d 1h";
    NSString *expectedTimeSpanString = @"";
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    
    [formatter setDisplayHours:NO];
    [formatter setDisplayDays:NO];
    [formatter setDisplayWeeks:NO];
    [formatter setDisplayMonths:NO];
    [formatter setDisplayYears:NO];
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1y -1m -1w -1d -1h";
    expectedTimeSpanString = @"";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    [formatter release];
}


- (void)testNoYear;
{
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1y 1mo 1w 1d 1h";
    NSString *expectedTimeSpanString = @"13mo 1w 1d 1h";
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    
    [formatter setDisplayHours:YES];
    [formatter setDisplayDays:YES];
    [formatter setDisplayWeeks:YES];
    [formatter setDisplayMonths:YES];
    [formatter setDisplayYears:NO];
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-13mo 1w 1d 1h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    [formatter release];
}

- (void)testNoMonth;
{
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1y 1mo 1w 1d 1h";
    NSString *expectedTimeSpanString = @"1y 5w 1d 1h";
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    
    [formatter setDisplayHours:YES];
    [formatter setDisplayDays:YES];
    [formatter setDisplayWeeks:YES];
    [formatter setDisplayMonths:NO];
    [formatter setDisplayYears:YES];
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-1y 5w 1d 1h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    [formatter release];
}

- (void)testNoWeeks;
{
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1y 1mo 1w 1d 1h";
    NSString *expectedTimeSpanString = @"1y 1mo 6d 1h";
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    
    [formatter setDisplayHours:YES];
    [formatter setDisplayDays:YES];
    [formatter setDisplayWeeks:NO];
    [formatter setDisplayMonths:YES];
    [formatter setDisplayYears:YES];
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-1y 1mo 6d 1h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    [formatter release];
}

- (void)testNoDays;
{
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1y 1mo 1w 1d 1h";
    NSString *expectedTimeSpanString = @"1y 1mo 1w 9h";
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    
    [formatter setDisplayHours:YES];
    [formatter setDisplayDays:NO];
    [formatter setDisplayWeeks:YES];
    [formatter setDisplayMonths:YES];
    [formatter setDisplayYears:YES];
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-1y 1mo 1w 9h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    [formatter release];
}

- (void)testNoHours;
{
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1y 1mo 1w 1d 1h";
    NSString *expectedTimeSpanString = @"1y 1mo 1w 1.125d";
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    
    [formatter setDisplayHours:NO];
    [formatter setDisplayDays:YES];
    [formatter setDisplayWeeks:YES];
    [formatter setDisplayMonths:YES];
    [formatter setDisplayYears:YES];
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-1y 1mo 1w 1.125d";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    [formatter release];
}

- (void)testDefaultEntryHours;
{
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1";
    NSString *expectedTimeSpanString = @"1h";
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    
    [formatter setDisplayHours:YES];
    [formatter setDisplayDays:YES];
    [formatter setDisplayWeeks:YES];
    [formatter setDisplayMonths:YES];
    [formatter setDisplayYears:YES];
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1";
    expectedTimeSpanString = @"-1h";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    [formatter release];
}

- (void)testDefaultEntryDays;
{
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1";
    NSString *expectedTimeSpanString = @"1d";
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    
    [formatter setDisplayHours:NO];
    [formatter setDisplayDays:YES];
    [formatter setDisplayWeeks:YES];
    [formatter setDisplayMonths:YES];
    [formatter setDisplayYears:YES];
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1";
    expectedTimeSpanString = @"-1d";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    [formatter release];
}

- (void)testDefaultEntryWeeks;
{
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1";
    NSString *expectedTimeSpanString = @"1w";
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    
    [formatter setDisplayHours:NO];
    [formatter setDisplayDays:NO];
    [formatter setDisplayWeeks:YES];
    [formatter setDisplayMonths:YES];
    [formatter setDisplayYears:YES];
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1";
    expectedTimeSpanString = @"-1w";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    [formatter release];
}

- (void)testDefaultEntryMonths;
{
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1";
    NSString *expectedTimeSpanString = @"1mo";
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    
    [formatter setDisplayHours:NO];
    [formatter setDisplayDays:NO];
    [formatter setDisplayWeeks:NO];
    [formatter setDisplayMonths:YES];
    [formatter setDisplayYears:YES];
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1";
    expectedTimeSpanString = @"-1mo";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    [formatter release];
}

- (void)testDefaultEntryYears;
{
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1";
    NSString *expectedTimeSpanString = @"1y";
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    
    [formatter setDisplayHours:NO];
    [formatter setDisplayDays:NO];
    [formatter setDisplayWeeks:NO];
    [formatter setDisplayMonths:NO];
    [formatter setDisplayYears:YES];
    
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1";
    expectedTimeSpanString = @"-1y";
    should ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    shouldBeEqual (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    [formatter release];
}


@end

