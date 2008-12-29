// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSCalendarDate.h>
#include <sys/types.h>

@interface NSCalendarDate (OFExtensions)

+ (NSCalendarDate *)unixReferenceDate;
- (void)setToUnixDateFormat;
- initWithTime_t:(time_t)time;

- (NSCalendarDate *)safeReferenceDate;
- (NSCalendarDate *)firstDayOfMonth;
- (NSCalendarDate *)lastDayOfMonth;
- (int)numberOfDaysInMonth;
- (int)weekOfMonth;
    // Returns 1 through 6. Weeks are Sunday-Saturday.
- (BOOL)isInSameWeekAsDate:(NSCalendarDate *)otherDate;

- (NSCalendarDate *)dateByRoundingToDayOfWeek:(int)desiredDayOfWeek;
- (NSCalendarDate *)dateByRoundingToHourOfDay:(int)desiredHour minute:(int)desiredMinute;

@end
