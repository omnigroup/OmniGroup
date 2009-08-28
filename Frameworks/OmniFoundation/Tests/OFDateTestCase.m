// Copyright 2002-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/NSCalendarDate-OFExtensions.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@interface OFDateTestCase : OFTestCase
{
}

- (NSCalendarDate *)parseDate:(NSString *)spec;
- (void)testRoundingToHHMM:(NSArray *)testCase;
- (void)testRoundingToDOW:(NSArray *)testCase;

@end

@implementation OFDateTestCase

- (NSCalendarDate *)parseDate:(NSString *)spec
{
    // Parses a date with either a numeric offset time zone, or a symbolic time zone (which may carry DST behavior with it).

    NSCalendarDate *result;

    // We need to parse using the numeric time zone format first; otherwise, the date will acquire the current local time zone, which is not what we want.

    result = [[NSCalendarDate alloc] initWithString:spec]; // implicit format: "%Y-%m-%d %H:%M:%S %z"
    if (!result)
        result = [[NSCalendarDate alloc] initWithString:spec calendarFormat:@"%Y-%m-%d %H:%M:%S %Z"];  // try parsing symbolic date

    if (!result) {
        fail1(([NSString stringWithFormat:@"Cannot parse \"%@\" as NSCalendarDate", spec]));
    }

    return [result autorelease];
}

- (void)testRoundingToHHMM:(NSArray *)testCase;
{
    NSCalendarDate *input, *desired, *output;
    int hour, minute;

    input = [self parseDate:[testCase objectAtIndex:0]];
    hour = [[testCase objectAtIndex:1] intValue];
    minute = [[testCase objectAtIndex:2] intValue];
    desired = [self parseDate:[testCase objectAtIndex:3]];

    output = [input dateByRoundingToHourOfDay:hour minute:minute];

    shouldBeEqual1(output, desired,
                   ([NSString stringWithFormat:@"RoundToHHMM%@", [testCase description]]));
}

- (void)testRoundingToDOW:(NSArray *)testCase;
{
    NSCalendarDate *input, *desired, *output;
    int dayOfWeek;

    input = [self parseDate:[testCase objectAtIndex:0]];
    dayOfWeek = [[testCase objectAtIndex:1] intValue];
    desired = [self parseDate:[testCase objectAtIndex:2]];

    output = [input dateByRoundingToDayOfWeek:dayOfWeek];

    shouldBeEqual1(output, desired,
                   ([NSString stringWithFormat:@"RoundToDOW%@", [testCase description]]));
}

- (NSString *)name
{
    id firstArg;

    [[self invocation] getArgument:&firstArg atIndex:2];
    
    return [NSString stringWithFormat:@"-[%@ %@%@]", NSStringFromClass([self class]), NSStringFromSelector([[self invocation] selector]), [firstArg description]];
}

+ (id)defaultTestSuite
{
    return [self dataDrivenTestSuite];
}

@end


