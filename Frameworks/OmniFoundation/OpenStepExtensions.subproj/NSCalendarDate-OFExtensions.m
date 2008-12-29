// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSCalendarDate-OFExtensions.h>

RCS_ID("$Id$")

@implementation NSCalendarDate (OFExtensions)

+ (NSCalendarDate *)unixReferenceDate;
{
    static NSCalendarDate *unixReferenceDate = nil;
    if (unixReferenceDate == nil)
        unixReferenceDate = [[NSCalendarDate dateWithTimeIntervalSince1970:0.0] retain];
    return unixReferenceDate;
}

- (void)setToUnixDateFormat;
{
    if ([self yearOfCommonEra] == [(NSCalendarDate *)[NSCalendarDate date] yearOfCommonEra])
	[self setCalendarFormat:@"%b %d %H:%M"];
    else
	[self setCalendarFormat:@"%b %d %Y"];
}

- initWithTime_t:(time_t)timeValue;
{
    NSCalendarDate *date;

    date = [self initWithTimeIntervalSinceReferenceDate: timeValue - NSTimeIntervalSince1970];
    [date setToUnixDateFormat];
    return date;
}

// We're going with Noon instead of midnight, since it's a bit more tolerant of
// time zone switching. (When you're adding days.)

- (NSCalendarDate *)safeReferenceDate;
{
    int year, month, day;

    year = [self yearOfCommonEra];
    month = [self monthOfYear];
    day = [self dayOfMonth];

    return [NSCalendarDate dateWithYear:year month:month day:day
                           hour:12 minute:0 second:0 timeZone:[NSTimeZone localTimeZone]];
}

- (NSCalendarDate *)firstDayOfMonth;
{
    NSCalendarDate *firstDay;

    firstDay = [[NSCalendarDate alloc] initWithYear:[self yearOfCommonEra]
        month:[self monthOfYear]
        day:1
        hour:12
        minute:0
        second:0
        timeZone:nil];
    return [firstDay autorelease];
}

- (NSCalendarDate *)lastDayOfMonth;
{
    return [[self firstDayOfMonth] dateByAddingYears:0 months:1 days:-1 hours:0 minutes:0 seconds:0];
}

- (int)numberOfDaysInMonth;
{
    return [[self lastDayOfMonth] dayOfMonth];
}

- (int)weekOfMonth;
{
    // Returns 1 through 6. Weeks are Sunday-Saturday.
    int dayOfMonth;
    int firstWeekDayOfMonth;
    
    dayOfMonth = [self dayOfMonth];
    firstWeekDayOfMonth = [[self firstDayOfMonth] dayOfWeek];
    return (dayOfMonth - 1 + firstWeekDayOfMonth) / 7 + 1;
}

- (BOOL)isInSameWeekAsDate:(NSCalendarDate *)otherDate;
{
    int weekOfMonth;

    // First, do a quick check to filter out dates which are more than a week away.
    if (abs([self dayOfCommonEra] - [otherDate dayOfCommonEra]) > 6)
        return NO;

    // Then, handle the simple case, when both dates are the same year and month.
    if ([self yearOfCommonEra] == [otherDate yearOfCommonEra] && [self monthOfYear] == [otherDate monthOfYear])
        return ([self weekOfMonth] == [otherDate weekOfMonth]);

    // Now we know the other date is within a week of us, and not in the same month. 
    weekOfMonth = [self weekOfMonth];
    if (weekOfMonth == 1) {
        // We are in the first week of the month. The otherDate is in the same week if its weekday is earlier than ours.
        return ([otherDate dayOfWeek] < [self dayOfWeek]);
    } else if (weekOfMonth == [[self lastDayOfMonth] weekOfMonth]) {
        // We are in the last week of the month. The otherDate is in the same week if its weekday is later than ours.
        return ([otherDate dayOfWeek] > [self dayOfWeek]);
    } else {
        // We are somewhere in the middle of the month, so the otherDate cannot be in the same week.
        return NO;
    }
}

static inline int nonnegativeModulus(int number, int base)
{
    if (number >= 0)
        return number % base;
    else
        return (base-1) - ( ( (base-1) - number ) % base );
}

/*"
Returns an NSCalendarDate adjusted to lie during the specified day of the week. This method will round forward or backwards in time to the nearer day.

The time of day (hours, minutes, seconds) is ignored during the comparison and the returned date will have the same time of day as the receiver.
"*/
- (NSCalendarDate *)dateByRoundingToDayOfWeek:(int)desiredDayOfWeek
{
    int deltaDays;

    // Compute the number of days we need to shift to be on the desired day
    deltaDays = desiredDayOfWeek - [self dayOfWeek];
    if (deltaDays == 0)
        return self;
    
    // convert deltaDays to the range 0 .. 6
    deltaDays = nonnegativeModulus(deltaDays, 7); // equivalent to deltaDays = ( deltaDays + BIGNUM*7 ) % 7 
    
    if (deltaDays <= 3)
        return [self dateByAddingYears:0 months:0 days:deltaDays hours:0 minutes:0 seconds:0];
    else /* if (deltaDays > 3) */
        return [self dateByAddingYears:0 months:0 days:(deltaDays - 7) hours:0 minutes:0 seconds:0];
} 

/*"
Returns the nearest calendar date with the specified hour and minute. The secondOfMinute of the returned date will be zero. This method will round forwards or backwards in time to arrive at the requested time of day.
"*/
- (NSCalendarDate *)dateByRoundingToHourOfDay:(int)desiredHour minute:(int)desiredMinute
{
    int myHour, myMinute, mySecond;
    int deltaSeconds;
    NSCalendarDate *roundedDate;

    myHour = [self hourOfDay];
    myMinute = [self minuteOfHour];
    mySecond = [self secondOfMinute];
    if (myHour == desiredHour && myMinute == desiredMinute && mySecond == 0)
        return self;

    deltaSeconds = 60 * ( desiredMinute + 60 * desiredHour ) -
        ( mySecond + 60 * ( myMinute + 60 * myHour ) );

    deltaSeconds = nonnegativeModulus(deltaSeconds, 60*60*24);

    if (deltaSeconds < (60*60*12)) {
        // Go forwards in time
        roundedDate = [self dateByAddingYears:0 months:0 days:0 hours:0 minutes:0  seconds:deltaSeconds];
    } else {
        // Go backwards in time
        roundedDate = [self dateByAddingYears:0 months:0 days:-1 hours:0 minutes:0 seconds:deltaSeconds];
    }

    // Check that we have the right hour: this adjusts for the hiccup around Daylight Savings Time
    myHour = [roundedDate hourOfDay];
    if (myHour != desiredHour)
        roundedDate = [roundedDate dateByAddingYears:0 months:0 days:0 hours:desiredHour - myHour minutes:0 seconds:0];

    return roundedDate;
}
    
@end
