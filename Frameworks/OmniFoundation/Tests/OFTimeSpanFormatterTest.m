// Copyright 2005-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

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
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-53w 1d 1h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y -1mo -1w -1d 1h";
    expectedTimeSpanString = @"-53w 1d 1h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y1mo1w1d1h";
    expectedTimeSpanString = @"-53w 1d 1h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y1mo1w1d1h";
    expectedTimeSpanString = @"-53w 1d 1h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"1w - 1d 1h";
    expectedTimeSpanString = @"3d 7h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"1w-1d1h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"1w-1d1h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"1w-1d+1h";
    expectedTimeSpanString = @"4d 1h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"2d";
    expectedTimeSpanString = @"2d";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
}

- (void)testArchiveUnitFormatter;
{
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    [formatter setUsesArchiveUnitStrings:YES];
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"2d";
    NSString *expectedTimeSpanString = @"2d";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
}

- (void)testArchiveUnitFormatterAllowsElapsed;
{
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    formatter.usesArchiveUnitStrings = YES;
    formatter.allowsElapsedUnits = YES;
    formatter.shouldReturnNumber = NO;
    formatter.displayUnmodifiedTimeSpan = YES;
    OFTimeSpan *timeSpan;
    NSString *timeSpanString = @"2ed 3eh";
    NSString *expectedTimeSpanString = @"2ed 3eh";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
}

- (void)testStandardCalendarTimeFormatter;
{
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];
    [formatter setStandardCalendarTime];
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1y";
    NSString *expectedTimeSpanString = @"52w 1d";
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y";
    expectedTimeSpanString = @"-52w 1d";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
}

- (void)testAllFormats;
{
    NSDecimalNumber *timeSpan;
    NSString *timeSpanString = @"1y 1mo 1w 1d 1h";
    NSString *expectedTimeSpanString = @"1y 1mo 1w 1d 1h";
    OFTimeSpanFormatter *formatter = [[OFTimeSpanFormatter alloc] init];

    [formatter setDisplayMonths:YES];
    [formatter setDisplayYears:YES];
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-1y 1mo 1w 1d 1h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

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
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1y -1m -1w -1d -1h";
    expectedTimeSpanString = @"";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

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
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-13mo 1w 1d 1h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

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
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-1y 5w 1d 1h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

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
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-1y 1mo 6d 1h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

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
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-1y 1mo 1w 9h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

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
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1y -1mo -1w -1d -1h";
    expectedTimeSpanString = @"-1y 1mo 1w 1.125d";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

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
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1";
    expectedTimeSpanString = @"-1h";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

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
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1";
    expectedTimeSpanString = @"-1d";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

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
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1";
    expectedTimeSpanString = @"-1w";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

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
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1";
    expectedTimeSpanString = @"-1mo";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
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
    
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);

    timeSpanString = @"-1";
    expectedTimeSpanString = @"-1y";
    XCTAssertTrue ([formatter getObjectValue:&timeSpan forString:timeSpanString errorDescription:nil]);
    XCTAssertEqualObjects (expectedTimeSpanString, [formatter stringForObjectValue:timeSpan]);
    
}


@end

