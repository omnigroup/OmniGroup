// Copyright 2000-2008, 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFTimeSpanFormatter.h>

#import <OmniFoundation/OFTimeSpan.h>
#import <OmniFoundation/NSObject-OFExtensions.h>

#import <Foundation/NSCoder.h>
#import <Foundation/NSNumberFormatter.h>

RCS_ID("$Id$")

#if 0 && defined(DEBUG)
    #define DLOG(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DLOG(format, ...)
#endif

typedef float (*FLOAT_IMP)(id, SEL); 
typedef void (*SETFLOAT_IMP)(id, SEL, float);

typedef struct {
    NSString *localizedSingularString, *localizedPluralString, *localizedAbbreviatedString;
    NSString *singularString, *pluralString, *abbreviatedString;
    FLOAT_IMP spanGetImplementation;
    SETFLOAT_IMP spanSetImplementation;
    FLOAT_IMP formatterMultiplierImplementation;
    float fixedMultiplier;
} OFTimeSpanUnit;

@implementation OFTimeSpanFormatter

enum {
    UNITS_YEARS, UNITS_MONTHS, UNITS_WEEKS, UNITS_DAYS, UNITS_HOURS, UNITS_MINUTES, UNITS_SECONDS, UNITS_COUNT
};

static OFTimeSpanUnit timeSpanUnits[UNITS_COUNT];

+ (void)initialize;
{
    OBINITIALIZE;
    
    NSBundle *bundle = [self bundle];
    
    timeSpanUnits[UNITS_YEARS].localizedPluralString = NSLocalizedStringFromTableInBundle(@"years", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_YEARS].localizedSingularString = NSLocalizedStringFromTableInBundle(@"year", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_YEARS].localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"y", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_YEARS].pluralString = @"years";
    timeSpanUnits[UNITS_YEARS].singularString = @"year";
    timeSpanUnits[UNITS_YEARS].abbreviatedString = @"y";
    timeSpanUnits[UNITS_YEARS].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(years)];
    timeSpanUnits[UNITS_YEARS].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setYears:)];
    timeSpanUnits[UNITS_YEARS].formatterMultiplierImplementation = (FLOAT_IMP)[self instanceMethodForSelector:@selector(hoursPerYear)];
    timeSpanUnits[UNITS_YEARS].fixedMultiplier = 3600.0f;    
    
    timeSpanUnits[UNITS_MONTHS].localizedPluralString = NSLocalizedStringFromTableInBundle(@"months", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_MONTHS].localizedSingularString = NSLocalizedStringFromTableInBundle(@"month", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_MONTHS].localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"mo", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_MONTHS].pluralString = @"months";
    timeSpanUnits[UNITS_MONTHS].singularString = @"month";
    timeSpanUnits[UNITS_MONTHS].abbreviatedString = @"mo";
    timeSpanUnits[UNITS_MONTHS].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(months)];
    timeSpanUnits[UNITS_MONTHS].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setMonths:)];
    timeSpanUnits[UNITS_MONTHS].formatterMultiplierImplementation = (FLOAT_IMP)[self instanceMethodForSelector:@selector(hoursPerMonth)];    
    timeSpanUnits[UNITS_MONTHS].fixedMultiplier = 3600.0f;    
    
    timeSpanUnits[UNITS_WEEKS].localizedPluralString = NSLocalizedStringFromTableInBundle(@"weeks", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_WEEKS].localizedSingularString = NSLocalizedStringFromTableInBundle(@"week", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_WEEKS].localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"w", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_WEEKS].pluralString = @"weeks";
    timeSpanUnits[UNITS_WEEKS].singularString = @"week";
    timeSpanUnits[UNITS_WEEKS].abbreviatedString = @"w";
    timeSpanUnits[UNITS_WEEKS].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(weeks)];
    timeSpanUnits[UNITS_WEEKS].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setWeeks:)];
    timeSpanUnits[UNITS_WEEKS].formatterMultiplierImplementation = (FLOAT_IMP)[self instanceMethodForSelector:@selector(hoursPerWeek)];       
    timeSpanUnits[UNITS_WEEKS].fixedMultiplier = 3600.0f;    
     
    timeSpanUnits[UNITS_DAYS].localizedPluralString = NSLocalizedStringFromTableInBundle(@"days", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_DAYS].localizedSingularString = NSLocalizedStringFromTableInBundle(@"day", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_DAYS].localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"d", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_DAYS].pluralString = @"days";
    timeSpanUnits[UNITS_DAYS].singularString = @"day";
    timeSpanUnits[UNITS_DAYS].abbreviatedString = @"d";
    timeSpanUnits[UNITS_DAYS].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(days)];
    timeSpanUnits[UNITS_DAYS].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setDays:)];
    timeSpanUnits[UNITS_DAYS].formatterMultiplierImplementation = (FLOAT_IMP)[self instanceMethodForSelector:@selector(hoursPerDay)];  
    timeSpanUnits[UNITS_DAYS].fixedMultiplier = 3600.0f;    
              
    timeSpanUnits[UNITS_HOURS].localizedPluralString = NSLocalizedStringFromTableInBundle(@"hours", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_HOURS].localizedSingularString = NSLocalizedStringFromTableInBundle(@"hour", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_HOURS].localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"h", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_HOURS].pluralString = @"hours";
    timeSpanUnits[UNITS_HOURS].singularString = @"hour";
    timeSpanUnits[UNITS_HOURS].abbreviatedString = @"h";
    timeSpanUnits[UNITS_HOURS].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(hours)];
    timeSpanUnits[UNITS_HOURS].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setHours:)];
    timeSpanUnits[UNITS_HOURS].formatterMultiplierImplementation = NULL;    
    timeSpanUnits[UNITS_HOURS].fixedMultiplier = 3600.0f;    
    
    timeSpanUnits[UNITS_MINUTES].localizedPluralString = NSLocalizedStringFromTableInBundle(@"minutes", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_MINUTES].localizedSingularString = NSLocalizedStringFromTableInBundle(@"minute", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_MINUTES].localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"m", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_MINUTES].pluralString = @"minutes";
    timeSpanUnits[UNITS_MINUTES].singularString = @"minute";
    timeSpanUnits[UNITS_MINUTES].abbreviatedString = @"m";
    timeSpanUnits[UNITS_MINUTES].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(minutes)];
    timeSpanUnits[UNITS_MINUTES].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setMinutes:)];
    timeSpanUnits[UNITS_MINUTES].formatterMultiplierImplementation = NULL;
    timeSpanUnits[UNITS_MINUTES].fixedMultiplier = 60.0f;    
                        
    timeSpanUnits[UNITS_SECONDS].localizedPluralString = NSLocalizedStringFromTableInBundle(@"seconds", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_SECONDS].localizedSingularString = NSLocalizedStringFromTableInBundle(@"second", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_SECONDS].localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"s", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[UNITS_SECONDS].pluralString = @"seconds";
    timeSpanUnits[UNITS_SECONDS].singularString = @"second";
    timeSpanUnits[UNITS_SECONDS].abbreviatedString = @"s";
    timeSpanUnits[UNITS_SECONDS].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(seconds)];
    timeSpanUnits[UNITS_SECONDS].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setSeconds:)];    
    timeSpanUnits[UNITS_SECONDS].formatterMultiplierImplementation = NULL;    
    timeSpanUnits[UNITS_SECONDS].fixedMultiplier = 1.0f;    
}

- init;
{
    if (!(self = [super init]))
        return nil;

    numberFormatter = [[NSNumberFormatter alloc] init];
    [numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
    [numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
    [numberFormatter setGeneratesDecimalNumbers:NO];
    [numberFormatter setZeroSymbol:@"0"];

    [self setStandardWorkTime];
    [self setUseVerboseFormat:NO];
    _flags.returnNumber = YES;
    _flags.floatValuesInSeconds = NO;
    _flags.displayUnits = 0;
    _flags.usesArchiveUnitStrings = 0;
    [self setDisplayHours:YES];
    [self setDisplayDays:YES];
    [self setDisplayWeeks:YES];

    return self;
}

- (void)dealloc;
{
    [numberFormatter release];
    [super dealloc];
}

- (void)encodeWithCoder:(NSCoder *)coder;
{
    [super encodeWithCoder:coder];
    
    [numberFormatter encodeWithCoder:coder];
    [coder encodeValueOfObjCType:@encode(BOOL) at:&shouldUseVerboseFormat];
    [coder encodeValueOfObjCType:@encode(float) at:&hoursPerDay];
    [coder encodeValueOfObjCType:@encode(float) at:&hoursPerWeek];
    [coder encodeValueOfObjCType:@encode(float) at:&hoursPerMonth];
    [coder encodeValueOfObjCType:@encode(float) at:&hoursPerYear];
    [coder encodeValueOfObjCType:@encode(float) at:&roundingInterval];
    
    unsigned int returnNumber = _flags.returnNumber;
    unsigned int floatValuesInSeconds = _flags.floatValuesInSeconds;
    unsigned int displayUnits = _flags.displayUnits;
    unsigned int usesArchiveUnitStrings = _flags.usesArchiveUnitStrings;
    
    [coder encodeValueOfObjCType:@encode(unsigned int) at:&returnNumber];
    [coder encodeValueOfObjCType:@encode(unsigned int) at:&floatValuesInSeconds];
    [coder encodeValueOfObjCType:@encode(unsigned int) at:&displayUnits];
    [coder encodeValueOfObjCType:@encode(unsigned int) at:&usesArchiveUnitStrings];
}

- (id)initWithCoder:(NSCoder *)coder;
{
    self = [super initWithCoder:coder];
    
    numberFormatter = [[NSNumberFormatter alloc] initWithCoder:coder];
    [coder decodeValueOfObjCType:@encode(BOOL) at:&shouldUseVerboseFormat];
    [coder decodeValueOfObjCType:@encode(float) at:&hoursPerDay];
    [coder decodeValueOfObjCType:@encode(float) at:&hoursPerWeek];
    [coder decodeValueOfObjCType:@encode(float) at:&hoursPerMonth];
    [coder decodeValueOfObjCType:@encode(float) at:&hoursPerYear];
    [coder decodeValueOfObjCType:@encode(float) at:&roundingInterval];
    unsigned int returnNumber;
    unsigned int floatValuesInSeconds;
    unsigned int displayUnits;
    unsigned int usesArchiveUnitStrings;

    [coder decodeValueOfObjCType:@encode(unsigned int) at:&returnNumber];
    [coder decodeValueOfObjCType:@encode(unsigned int) at:&floatValuesInSeconds];
    [coder decodeValueOfObjCType:@encode(unsigned int) at:&displayUnits];
    [coder decodeValueOfObjCType:@encode(unsigned int) at:&usesArchiveUnitStrings];
    
    _flags.returnNumber = returnNumber;
    _flags.floatValuesInSeconds = floatValuesInSeconds;
    _flags.displayUnits = displayUnits;
    _flags.usesArchiveUnitStrings = usesArchiveUnitStrings;
    
    return self;
}

- (id)copyWithZone:(NSZone *)zone;
{
    OFTimeSpanFormatter *copy = [super copyWithZone:zone];
    copy->numberFormatter = [numberFormatter copyWithZone:zone];
    return copy;
}

- (NSNumberFormatter *)numberFormatter;
{
    return numberFormatter;
}

- (void)setUseVerboseFormat:(BOOL)shouldUseVerbose;
{
    shouldUseVerboseFormat = shouldUseVerbose;
}

- (BOOL)shouldUseVerboseFormat;
{
    return shouldUseVerboseFormat;
}

- (void)setShouldReturnNumber:(BOOL)shouldReturnNumber;
{
    _flags.returnNumber = shouldReturnNumber;
}

- (BOOL)shouldReturnNumber;
{
    return _flags.returnNumber;
}

- (void)setFloatValuesInSeconds:(BOOL)shouldTreatFloatValuesAsSeconds;
{
    _flags.floatValuesInSeconds = shouldTreatFloatValuesAsSeconds;
}

- (BOOL)floatValuesInSeconds;
{
    return _flags.floatValuesInSeconds;
}

- (void)setRoundingInterval:(float)interval;
{
    roundingInterval = interval;
}

- (float)roundingInterval;
{
    return roundingInterval;
}

- (void)setUsesArchiveUnitStrings:(BOOL)shouldUseArchiveUnitStrings;
{
    _flags.usesArchiveUnitStrings = shouldUseArchiveUnitStrings;
}

- (BOOL)usesArchiveUnitStrings;
{
    return _flags.usesArchiveUnitStrings;
}

- (float)hoursPerDay;
{
    return hoursPerDay;
}

- (float)hoursPerWeek;
{
    return hoursPerWeek;
}

- (float)hoursPerMonth;
{
    return hoursPerMonth;
}

- (float)hoursPerYear;
{
    return hoursPerYear;
}

- (void)setHoursPerDay:(float)hours;
{
    hoursPerDay = hours;
}

- (void)setHoursPerWeek:(float)hours;
{
    hoursPerWeek = hours;
}

- (void)setHoursPerMonth:(float)hours;
{
    hoursPerMonth = hours;
}

- (void)setHoursPerYear:(float)hours;
{
    hoursPerYear = hours;
}

- (BOOL)isStandardWorkTime;
{
    return hoursPerDay == STANDARD_WORK_HOURS_PER_DAY && hoursPerWeek == STANDARD_WORK_HOURS_PER_WEEK && hoursPerMonth == STANDARD_WORK_HOURS_PER_MONTH && hoursPerYear == STANDARD_WORK_HOURS_PER_YEAR;
}

- (BOOL)isStandardCalendarTime;
{
    return hoursPerDay == STANDARD_WORK_PER_DAY && hoursPerWeek == STANDARD_WORK_PER_WEEK && hoursPerMonth == STANDARD_WORK_PER_MONTH && hoursPerYear == STANDARD_WORK_PER_YEAR;
}

- (BOOL)displayUnmodifiedTimeSpan; // Overrides all display unit settings
{
    return _flags.displayUnmodifiedTimeSpan;
}

- (void)setDisplayUnmodifiedTimeSpan:(BOOL)aBool; // Overrides all display unit settings
{
    _flags.displayUnmodifiedTimeSpan = aBool;
}

- (BOOL)displaySeconds;
{
    return (_flags.displayUnits >> UNITS_SECONDS) & 1;
}

- (BOOL)displayMinutes;
{
    return (_flags.displayUnits >> UNITS_MINUTES) & 1;
}

- (BOOL)displayHours;
{
    return (_flags.displayUnits >> UNITS_HOURS) & 1;
}

- (BOOL)displayDays;
{
    return (_flags.displayUnits >> UNITS_DAYS) & 1;
}

- (BOOL)displayWeeks;
{
    return (_flags.displayUnits >> UNITS_WEEKS) & 1;
}

- (BOOL)displayMonths;
{
    return (_flags.displayUnits >> UNITS_MONTHS) & 1;
}

- (BOOL)displayYears;
{
    return (_flags.displayUnits >> UNITS_YEARS) & 1;
}

static void _setDisplayUnitBit(OFTimeSpanFormatter *self, unsigned bitIndex, BOOL value)
{
    if (value)
        self->_flags.displayUnits |= (1 << bitIndex);
    else
        self->_flags.displayUnits &= ~(1 << bitIndex);
}

- (void)setDisplaySeconds:(BOOL)aBool;
{
    _setDisplayUnitBit(self, UNITS_SECONDS, aBool);
}

- (void)setDisplayMinutes:(BOOL)aBool;
{
    _setDisplayUnitBit(self, UNITS_MINUTES, aBool);
}

- (void)setDisplayHours:(BOOL)aBool;
{
    _setDisplayUnitBit(self, UNITS_HOURS, aBool);
}

- (void)setDisplayDays:(BOOL)aBool;
{
    _setDisplayUnitBit(self, UNITS_DAYS, aBool);
}

- (void)setDisplayWeeks:(BOOL)aBool;
{
    _setDisplayUnitBit(self, UNITS_WEEKS, aBool);
}

- (void)setDisplayMonths:(BOOL)aBool;
{
    _setDisplayUnitBit(self, UNITS_MONTHS, aBool);
}

- (void)setDisplayYears:(BOOL)aBool;
{
    _setDisplayUnitBit(self, UNITS_YEARS, aBool);
}

- (void)setStandardWorkTime; // 8h = 1d, 40h = 1w, 160h = 1m
{
    hoursPerDay = STANDARD_WORK_HOURS_PER_DAY;
    hoursPerWeek = STANDARD_WORK_HOURS_PER_WEEK;
    hoursPerMonth = STANDARD_WORK_HOURS_PER_MONTH;
    hoursPerYear = STANDARD_WORK_HOURS_PER_YEAR;
}

- (void)setStandardCalendarTime; // 24h = 1d, 168h = 1w, 720h = 1m (30d = 1m), 8760h = 1y (365d = 1y)
{
    hoursPerDay = STANDARD_WORK_PER_DAY;
    hoursPerWeek = STANDARD_WORK_PER_WEEK;
    hoursPerMonth = STANDARD_WORK_PER_MONTH;
    hoursPerYear = STANDARD_WORK_PER_YEAR;
}

// bug://bugs/25124 We need to make sure that we display true and accurate information. This means that, if we hav an 
// input of 2h but are not displaying hours, then we must roll the fraction up into the next displayed value. If we
// don't do this then we'll get 0 as our return value.

- (float)_useRoundingOnValue:(float)value;
{
    if (!roundingInterval)
        return value;
        
    float valueRemainder = fmodf(value, roundingInterval);
            
    if (valueRemainder > (roundingInterval / 2))
        value += (roundingInterval - valueRemainder);
    else
        value -= valueRemainder;
    return value;
}

#define FLAGS_DISPLAY_ALL_UNITS ((1 << UNITS_COUNT) - 1)

- (NSString *)_displayStringForUnmodifiedTimeSpan:(OFTimeSpan *)timeSpan;
{
    NSMutableString *displayString = [NSMutableString string];
    unsigned int unitIndex;
    for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
        float value = 0.0f;
        switch (unitIndex) {
            case UNITS_YEARS: value = [timeSpan years]; break;
            case UNITS_MONTHS: value = [timeSpan months]; break;
            case UNITS_WEEKS: value = [timeSpan weeks]; break;
            case UNITS_DAYS: value = [timeSpan days]; break;
            case UNITS_HOURS: value = [timeSpan hours]; break;
            case UNITS_MINUTES: value = [timeSpan minutes]; break;
            case UNITS_SECONDS: value = [timeSpan seconds]; break;
        }
        if (value == 0.0f)
            continue;
        BOOL isNegative = NO;
        if (value < 0.0f) {
            isNegative = YES;
            value = -value;
        }

        NSString *valueString = [numberFormatter stringFromNumber:[NSNumber numberWithFloat:value]];
        if (valueString != nil) {
            if ([displayString length])
                [displayString appendString:@" "];
            else if (isNegative)
                [displayString appendString:@"-"];

            if (shouldUseVerboseFormat) {
                NSString *unitString = value > 1.0 ? timeSpanUnits[unitIndex].localizedPluralString : timeSpanUnits[unitIndex].localizedSingularString;
                [displayString appendFormat:@"%@ %@", valueString, unitString];
            } else
                [displayString appendFormat:@"%@%@", valueString, timeSpanUnits[unitIndex].localizedAbbreviatedString];
        }
    }
    return displayString;
}

- (NSString *)_stringForObjectValue:(id)object withRounding:(BOOL)withRounding;
{
    DLOG(@"building string for %@; displayUnits:0x%x", [object shortDescription], _flags.displayUnits);
    
    BOOL isNegative = NO;
    NSString *smallestUnitString = nil;
    NSString *roundingPrefix = @"";
    float secondsLeft;

    if ([object isKindOfClass:[NSArray class]] && [object count] != 0)
        object = [object objectAtIndex:0];
    if ([object isKindOfClass:[NSNumber class]])
	secondsLeft = [object floatValue] * (_flags.floatValuesInSeconds ? 1.0f : 3600.0f);
    else if ([object isKindOfClass:[OFTimeSpan class]]) {
        if (_flags.displayUnmodifiedTimeSpan)
            return [self _displayStringForUnmodifiedTimeSpan:object];

	secondsLeft = [object floatValueInSeconds];
    } else {
        DLOG(@">> empty");
	return @"";
    }
    DLOG(@"secondsLeft = %f", secondsLeft);
    
    if (secondsLeft < 0.0) {  
	isNegative = YES;
	secondsLeft = -secondsLeft;
    } 
	
    NSMutableString *result = [NSMutableString string];
    unsigned int unitIndex;
    for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
        if (_flags.displayUnits & (1 << unitIndex)) {
            BOOL willDisplaySmallerUnits = (_flags.displayUnits & ~((1 << (unitIndex+1))-1));
            
            DLOG(@"  unitIndex:%d willDisplaySmallerUnits:%d value:%f", unitIndex, willDisplaySmallerUnits, secondsLeft);
	    if (!willDisplaySmallerUnits) {
                if (_flags.usesArchiveUnitStrings)
		    smallestUnitString = timeSpanUnits[unitIndex].abbreviatedString;
		else if (shouldUseVerboseFormat) 
		    smallestUnitString = timeSpanUnits[unitIndex].localizedPluralString;
		else
		    smallestUnitString = timeSpanUnits[unitIndex].localizedAbbreviatedString;
	    }
	    
	    float secondsPerUnit = timeSpanUnits[unitIndex].fixedMultiplier;
	    if (timeSpanUnits[unitIndex].formatterMultiplierImplementation)
		secondsPerUnit *= timeSpanUnits[unitIndex].formatterMultiplierImplementation(self, NULL);
	    
	    float value = secondsLeft / secondsPerUnit;
	    secondsLeft -= floorf(value) * secondsPerUnit;

            NSString *numberString = nil;
            if (willDisplaySmallerUnits) {
		value = floorf(value);
                numberString = [numberFormatter stringFromNumber:[NSNumber numberWithInt:(int)value]];
            } else {
		if (withRounding) {
		    float roundedValue = [self _useRoundingOnValue:ABS(value)];
		    if (roundedValue != 0)
			numberString = [numberFormatter stringFromNumber:[NSNumber numberWithFloat:roundedValue]];
		    if (value != roundedValue)
			roundingPrefix = (value > roundedValue) ? @"> ": @"< ";
		} else
		    numberString = [numberFormatter stringFromNumber:[NSNumber numberWithFloat:value]];
                secondsLeft = 0.0f;
            }
            
            if (numberString && value != 0.0) {
                if ([result length])
                    [result appendString:@" "];
                else if (isNegative)
                    [result appendString:@"-"];

                if (_flags.usesArchiveUnitStrings)
                    [result appendFormat:@"%@%@", numberString, timeSpanUnits[unitIndex].abbreviatedString];
                else if (shouldUseVerboseFormat) {
                    NSString *unitString = value > 1.0 ? timeSpanUnits[unitIndex].localizedPluralString : timeSpanUnits[unitIndex].localizedSingularString;
                    [result appendFormat:@"%@ %@", numberString, unitString];
                } else
                    [result appendFormat:@"%@%@", numberString, timeSpanUnits[unitIndex].localizedAbbreviatedString];
            }
        }
    }
    
    if (![result length] && smallestUnitString != nil) {
	// Display 0 of the smallest enabled unit if we have no result
	result = [NSString stringWithFormat:@"0%@", smallestUnitString];
    }
    result = (id)[roundingPrefix stringByAppendingString:result];
    DLOG(@">> %@", result);
    return result;
}

- (NSString *)editingStringForObjectValue:(id)object;
{
    if (OFISNULL(object))
        return @"";
    if ([object isKindOfClass:[OFTimeSpan class]] && [object isZero])
        return @"";
    
    return [self _stringForObjectValue:object withRounding:NO];
}

- (NSString *)stringForObjectValue:(id)object;
{
    return [self _stringForObjectValue:object withRounding:YES];
}

- (NSNumber *)_scanNumberFromScanner:(NSScanner *)scanner;
{
    NSNumber *number = nil;
    NSError *error = nil;
    NSUInteger position = [scanner scanLocation];
    NSString *string = [[scanner string] substringFromIndex:position];
    NSRange range = NSMakeRange(0, [string length]);
    
    if (!range.length || ![numberFormatter getObjectValue:&number forString:string range:&range error:&error])
	return nil;    
    [scanner setScanLocation:position + NSMaxRange(range)];
    return number;
}

- (BOOL)getObjectValue:(out id *)obj forString:(NSString *)string errorDescription:(out NSString **)error;
{
    DLOG(@"parsing %@", string);
    
    BOOL gotAnythingValid = NO;
    float number;
    BOOL negativLand = NO;
    
    if (![string length]) {
        DLOG(@">> nil");
        *obj = nil;
        return YES;
    }
    
    OFTimeSpan *timeSpan = [[[OFTimeSpan alloc] initWithTimeSpanFormatter:self] autorelease]; // autorelease now since we have several early-outs on error

    NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet];
    NSCharacterSet *letterCharacterSet = [NSCharacterSet letterCharacterSet];
    NSCharacterSet *roundedCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"<>"];
    NSScanner *scanner = [NSScanner localizedScannerWithString:string];
    [scanner setCaseSensitive:NO];
    [scanner setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@""]];
    if ([scanner scanCharactersFromSet:roundedCharacterSet intoString:NULL]) {
        DLOG(@"-[%@ %s]: found rounding characters in '%@'", OBShortObjectDescription(self), _cmd, string);
    }
    while (1) {
        // Eat whitespace
        [scanner scanCharactersFromSet:whitespaceCharacterSet intoString:NULL];
        
        // Look for a sign.  Ace of Base would be proud.  Not supporting infix operator followed by unary sign: "1d - +1h".
        if ([scanner scanString:@"-" intoString:NULL])
            negativLand = YES;
        else if ([scanner scanString:@"+" intoString:NULL])
            negativLand = NO;

        // Eat more whitespace
        [scanner scanCharactersFromSet:whitespaceCharacterSet intoString:NULL];

	NSNumber *numberValue;
	if (!(numberValue = [self _scanNumberFromScanner:scanner])) {
            if (gotAnythingValid)
                break;
	    // if we get a ., we may still have a valid partial string.
	    if ([scanner scanString:@"." intoString:NULL] && [scanner isAtEnd]) {
		*obj = nil;
                DLOG(@">> nil");
		return YES;
	    }
	    if (error) {
                *error = NSLocalizedStringFromTableInBundle(@"Invalid time span format", @"OmniFoundation", [OFTimeSpanFormatter bundle], @"formatter input error");
                DLOG(@">> error %@", *error);
		return NO;
	    }
	}
	number = [numberValue floatValue];
	
	if ([scanner scanString:@"/" intoString:NULL]) {
	    NSNumber *denominator;
            if ([scanner isAtEnd]) {
		if (gotAnythingValid)
		    break;
                else {
                    *obj = nil;
                    DLOG(@">> nil");
                    return YES; 
                }
            }
	    if (!(denominator = [self _scanNumberFromScanner:scanner])) {
		if (gotAnythingValid)
		    break;
		if (error)
		    *error = NSLocalizedStringFromTableInBundle(@"Invalid time span format", @"OmniFoundation", [OFTimeSpanFormatter bundle], @"formatter input error");
                DLOG(@">> error %@", *error);
		return NO;
	    }
	    number /= [denominator floatValue];
        }
        
        if (negativLand)
            number *= -1.0f;
        
        // Eat more whitespace
        [scanner scanCharactersFromSet:whitespaceCharacterSet intoString:NULL];

        unsigned int unitIndex;
        if (_flags.usesArchiveUnitStrings) {
            // Only look for archive unit strings, not long forms or abbreviations
            for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
                if ([scanner scanString:timeSpanUnits[unitIndex].abbreviatedString intoString:NULL])
                    break;
            }
        } else {
            for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
                if ([scanner scanString:timeSpanUnits[unitIndex].localizedPluralString intoString:NULL] || [scanner scanString:timeSpanUnits[unitIndex].localizedSingularString intoString:NULL])
                    break;
            }
            if (unitIndex == UNITS_COUNT) 
                for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
                    // Didn't match any localized version, try non-localized
                    if ([scanner scanString:timeSpanUnits[unitIndex].pluralString intoString:NULL] || [scanner scanString:timeSpanUnits[unitIndex].singularString intoString:NULL])
                        break;
                }
            if (unitIndex == UNITS_COUNT) {
                // Didn't match any long forms, try abbreviations instead
                for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++)
                    if ([scanner scanString:timeSpanUnits[unitIndex].localizedAbbreviatedString intoString:NULL])
                        break;
            }
            if (unitIndex == UNITS_COUNT) {
                // unlocalized abbreviations?
                for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++)
                    if ([scanner scanString:timeSpanUnits[unitIndex].abbreviatedString intoString:NULL])
                        break;
            }
        }
        if (unitIndex != UNITS_COUNT) {
            float existingValue = timeSpanUnits[unitIndex].spanGetImplementation(timeSpan, NULL);
            timeSpanUnits[unitIndex].spanSetImplementation(timeSpan, NULL, number + existingValue);
        } else {
            // didn't match any abbreviation, so assume the lowest unit we display
            unitIndex = UNITS_COUNT;
            while (unitIndex-- != 0) {
                if (_flags.displayUnits & (1 << unitIndex)) {
                    float existingValue = timeSpanUnits[unitIndex].spanGetImplementation(timeSpan, NULL);
                    timeSpanUnits[unitIndex].spanSetImplementation(timeSpan, NULL, number + existingValue);
                    break;
                }
            }
        }
        gotAnythingValid = YES;
        [scanner scanCharactersFromSet:letterCharacterSet intoString:NULL];
    }

    if (_flags.returnNumber)
        *obj = [NSNumber numberWithFloat:[timeSpan floatValue]];
    else 
        *obj = timeSpan;
    DLOG(@">> %@", [*obj shortDescription]);
    return YES;
}

@end
