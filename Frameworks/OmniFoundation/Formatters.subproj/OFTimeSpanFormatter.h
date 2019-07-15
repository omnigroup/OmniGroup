// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSFormatter.h>

#define STANDARD_WORK_HOURS_PER_DAY 8.0f
#define STANDARD_WORK_HOURS_PER_WEEK (5.0f * STANDARD_WORK_HOURS_PER_DAY)
#define STANDARD_WORK_HOURS_PER_MONTH (4.0f * STANDARD_WORK_HOURS_PER_WEEK)
#define STANDARD_WORK_HOURS_PER_YEAR (12.0f * STANDARD_WORK_HOURS_PER_MONTH)

#define STANDARD_WORK_PER_DAY 24.0f
#define STANDARD_WORK_PER_WEEK (7.0f * STANDARD_WORK_PER_DAY)
#define STANDARD_WORK_PER_MONTH (30.0f * STANDARD_WORK_PER_DAY)
#define STANDARD_WORK_PER_YEAR (365.0f * STANDARD_WORK_PER_DAY)

typedef NS_ENUM(NSUInteger, OFTimeSpanFormatterUnit) {
    // Order must match +initalize
    UNITS_YEARS, UNITS_MONTHS, UNITS_WEEKS, UNITS_DAYS, UNITS_HOURS, UNITS_MINUTES, UNITS_SECONDS, UNITS_COUNT
};

@class NSNumberFormatter;
@class OFTimeSpan;

@interface OFTimeSpanFormatter : NSFormatter
{
    NSNumberFormatter *numberFormatter;
    BOOL shouldUseVerboseFormat;
    float hoursPerDay, hoursPerWeek, hoursPerMonth, hoursPerYear;
    float roundingInterval;
    
    struct {
	unsigned int returnNumber : 1;
	unsigned int displayUnmodifiedTimeSpan : 1;
	unsigned int floatValuesInSeconds : 1;
	unsigned int displayUnits : 7; /* Bits should match UNITS_COUNT */
        unsigned int usesArchiveUnitStrings : 1;
        unsigned int allowsElapsedUnits: 1;
    } _flags;
}

+ (NSString *)localizedPluralStringForUnits:(OFTimeSpanFormatterUnit)unit;
+ (NSString *)localizedSingularStringForUnits:(OFTimeSpanFormatterUnit)unit;
+ (NSString *)localizedAbbreviationStringForUnits:(OFTimeSpanFormatterUnit)unit;
+ (NSString *)localizedElapsedStringForUnits:(OFTimeSpanFormatterUnit)unit;

- (NSNumberFormatter *)numberFormatter;

@property (nonatomic, assign, getter = shouldUseVerboseFormat) BOOL useVerboseFormat; // "12w 3d" vs "12 weeks 3 days"
@property (nonatomic, assign) BOOL shouldReturnNumber; // whether -getObjectValue:… returns an NSNumber instead of an OFTimeSpan
@property (nonatomic, assign) BOOL floatValuesInSeconds; // whether incoming NSNumber floats are seconds or hours
@property (nonatomic, assign) float roundingInterval;
@property (nonatomic, assign) BOOL usesArchiveUnitStrings;

- (OFTimeSpan *)timeSpanValueForNumberValue:(NSNumber *)aNumber;
- (OFTimeSpan *)timeSpanValueForString:(NSString *)string errorDescription:(out NSString **)error;

- (NSString *)placeholderString;  // 0 of the lowest enabled unit, localized, unrounded, obeying the above flags but will not displayUnmodifiedTimeSpan even if the receiver does

@property (nonatomic, assign) float hoursPerDay;
@property (nonatomic, assign) float hoursPerWeek;
@property (nonatomic, assign) float hoursPerMonth;
@property (nonatomic, assign) float hoursPerYear;

@property (nonatomic, assign) BOOL displayUnmodifiedTimeSpan; // overrides all display unit settings

@property (nonatomic, assign) BOOL displaySeconds;
@property (nonatomic, assign) BOOL displayMinutes;
@property (nonatomic, assign) BOOL displayHours;
@property (nonatomic, assign) BOOL displayDays;
@property (nonatomic, assign) BOOL displayWeeks;
@property (nonatomic, assign) BOOL displayMonths;
@property (nonatomic, assign) BOOL displayYears;

@property (nonatomic, assign) BOOL allowsElapsedUnits;

- (BOOL)isStandardWorkTime;
- (BOOL)isStandardCalendarTime;

- (void)setStandardWorkTime; // 8h = 1d, 40h = 1w, 160h = 1m, 1920h = 1y (12m = 1y)
- (void)setStandardCalendarTime; // 24h = 1d, 168h = 1w, 720h = 1m (30d = 1m), 8760h = 1y (365d = 1y)

@end
