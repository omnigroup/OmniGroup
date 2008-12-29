// Copyright 2000-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/Formatters.subproj/OFTimeSpanFormatter.h 98221 2008-03-04 21:06:19Z kc $

#import <Foundation/NSFormatter.h>

#define STANDARD_WORK_HOURS_PER_DAY 8.0f
#define STANDARD_WORK_HOURS_PER_WEEK (5.0f * STANDARD_WORK_HOURS_PER_DAY)
#define STANDARD_WORK_HOURS_PER_MONTH (4.0f * STANDARD_WORK_HOURS_PER_WEEK)
#define STANDARD_WORK_HOURS_PER_YEAR (12.0f * STANDARD_WORK_HOURS_PER_MONTH)

#define STANDARD_WORK_PER_DAY 24.0f
#define STANDARD_WORK_PER_WEEK (7.0f * STANDARD_WORK_PER_DAY)
#define STANDARD_WORK_PER_MONTH (30.0f * STANDARD_WORK_PER_DAY)
#define STANDARD_WORK_PER_YEAR (365.0f * STANDARD_WORK_PER_DAY)

@class NSNumberFormatter;

@interface OFTimeSpanFormatter : NSFormatter
{
    NSNumberFormatter *numberFormatter;
    BOOL shouldUseVerboseFormat;
    float hoursPerDay, hoursPerWeek, hoursPerMonth, hoursPerYear;
    float roundingInterval;
    
    struct {
	unsigned int returnNumber : 1;
	unsigned int floatValuesInSeconds : 1;
	unsigned int displayUnits : 7;
        unsigned int usesArchiveUnitStrings : 1;
    } _flags;
}

- (NSNumberFormatter *)numberFormatter;

- (void)setUseVerboseFormat:(BOOL)shouldUseVerbose;
- (BOOL)shouldUseVerboseFormat;

- (void)setShouldReturnNumber:(BOOL)shouldReturnNumber;
- (BOOL)shouldReturnNumber;

- (void)setFloatValuesInSeconds:(BOOL)shouldTreatFloatValuesAsSeconds;
- (BOOL)floatValuesInSeconds;

- (void)setRoundingInterval:(float)interval;
- (float)roundingInterval;

- (void)setUsesArchiveUnitStrings:(BOOL)shouldUseArchiveUnitStrings;
- (BOOL)usesArchiveUnitStrings;

- (float)hoursPerDay;
- (float)hoursPerWeek;
- (float)hoursPerMonth;
- (float)hoursPerYear;

- (void)setHoursPerDay:(float)hours;
- (void)setHoursPerWeek:(float)hours;
- (void)setHoursPerMonth:(float)hours;
- (void)setHoursPerYear:(float)hours;

- (BOOL)isStandardWorkTime;
- (BOOL)isStandardCalendarTime;

- (BOOL)displaySeconds;
- (BOOL)displayMinutes;
- (BOOL)displayHours;
- (BOOL)displayDays;
- (BOOL)displayWeeks;
- (BOOL)displayMonths;
- (BOOL)displayYears;

- (void)setDisplaySeconds:(BOOL)aBool;
- (void)setDisplayMinutes:(BOOL)aBool;
- (void)setDisplayHours:(BOOL)aBool;
- (void)setDisplayDays:(BOOL)aBool;
- (void)setDisplayWeeks:(BOOL)aBool;
- (void)setDisplayMonths:(BOOL)aBool;
- (void)setDisplayYears:(BOOL)aBool;

- (void)setStandardWorkTime; // 8h = 1d, 40h = 1w, 160h = 1m, 1920h = 1y (12m = 1y)
- (void)setStandardCalendarTime; // 24h = 1d, 168h = 1w, 720h = 1m (30d = 1m), 8760h = 1y (365d = 1y)

@end
