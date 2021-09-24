// Copyright 2000-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFTimeSpanFormatter.h>

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFTimeSpan.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/OFNull.h>

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

@interface OFTimeSpanUnit : NSObject
@property(nonatomic,copy) NSString *localizedSingularString;
@property(nonatomic,copy) NSString *localizedPluralString;
@property(nonatomic,copy) NSString *localizedAbbreviatedString;
@property(nonatomic,copy) NSString *localizedElapsedString;

@property(nonatomic,copy) NSString *singularString;
@property(nonatomic,copy) NSString *pluralString;
@property(nonatomic,copy) NSString *abbreviatedString;
@property(nonatomic,copy) NSString *elapsedString;

@property(nonatomic) FLOAT_IMP spanGetImplementation;
@property(nonatomic) SETFLOAT_IMP spanSetImplementation;
@property(nonatomic) FLOAT_IMP formatterMultiplierImplementation;

@property(nonatomic) float fixedMultiplier;
@end
@implementation OFTimeSpanUnit
@end

@implementation OFTimeSpanFormatter
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

static NSArray *TimeSpanUnits = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    NSBundle *bundle = [self bundle];
    NSString *localizedPluralString = nil;
    NSString *localizedSingularString = nil;
    NSString *localizedAbbreviatedString = nil;
    NSString *localizedElapsedString = nil;


    localizedPluralString = NSLocalizedStringFromTableInBundle(@"years", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedSingularString = NSLocalizedStringFromTableInBundle(@"year", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"y", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedElapsedString = NSLocalizedStringFromTableInBundle(@"ey", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    
    NSMutableArray *timeSpanUnits = [NSMutableArray new];
    OFTimeSpanUnit *unit;
    
    // Set up order must match the enum
    [timeSpanUnits addObject:(unit = [OFTimeSpanUnit new])];
    unit.localizedPluralString = [localizedPluralString copy];
    unit.localizedSingularString = [localizedSingularString copy];
    unit.localizedAbbreviatedString = [localizedAbbreviatedString copy];
    unit.localizedElapsedString = [localizedElapsedString copy];
    unit.pluralString = @"years";
    unit.singularString = @"year";
    unit.abbreviatedString = @"y";
    unit.elapsedString = @"ey";
    unit.spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(years)];
    unit.spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setYears:)];
    unit.formatterMultiplierImplementation = (FLOAT_IMP)[self instanceMethodForSelector:@selector(hoursPerYear)];
    unit.fixedMultiplier = 3600.0f;    
    
    localizedPluralString = NSLocalizedStringFromTableInBundle(@"months", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedSingularString = NSLocalizedStringFromTableInBundle(@"month", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"mo", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace (month)");
    localizedElapsedString = NSLocalizedStringFromTableInBundle(@"emo", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");

    [timeSpanUnits addObject:(unit = [OFTimeSpanUnit new])];
    unit.localizedPluralString = [localizedPluralString copy];
    unit.localizedSingularString = [localizedSingularString copy];
    unit.localizedAbbreviatedString = [localizedAbbreviatedString copy];
    unit.localizedElapsedString = [localizedElapsedString copy];
    unit.pluralString = @"months";
    unit.singularString = @"month";
    unit.abbreviatedString = @"mo";
    unit.elapsedString = @"emo";
    unit.spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(months)];
    unit.spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setMonths:)];
    unit.formatterMultiplierImplementation = (FLOAT_IMP)[self instanceMethodForSelector:@selector(hoursPerMonth)];
    unit.fixedMultiplier = 3600.0f;    
    
    localizedPluralString = NSLocalizedStringFromTableInBundle(@"weeks", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedSingularString = NSLocalizedStringFromTableInBundle(@"week", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"w", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedElapsedString = NSLocalizedStringFromTableInBundle(@"ew", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");

    [timeSpanUnits addObject:(unit = [OFTimeSpanUnit new])];
    unit.localizedPluralString = [localizedPluralString copy];
    unit.localizedSingularString = [localizedSingularString copy];
    unit.localizedAbbreviatedString = [localizedAbbreviatedString copy];
    unit.localizedElapsedString = [localizedElapsedString copy];
    unit.pluralString = @"weeks";
    unit.singularString = @"week";
    unit.abbreviatedString = @"w";
    unit.elapsedString = @"ew";
    unit.spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(weeks)];
    unit.spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setWeeks:)];
    unit.formatterMultiplierImplementation = (FLOAT_IMP)[self instanceMethodForSelector:@selector(hoursPerWeek)];
    unit.fixedMultiplier = 3600.0f;    
     
    localizedPluralString = NSLocalizedStringFromTableInBundle(@"days", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedSingularString = NSLocalizedStringFromTableInBundle(@"day", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"d", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedElapsedString = NSLocalizedStringFromTableInBundle(@"ed", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");

    [timeSpanUnits addObject:(unit = [OFTimeSpanUnit new])];
    unit.localizedPluralString = [localizedPluralString copy];
    unit.localizedSingularString = [localizedSingularString copy];
    unit.localizedAbbreviatedString = [localizedAbbreviatedString copy];
    unit.localizedElapsedString = [localizedElapsedString copy];
    unit.pluralString = @"days";
    unit.singularString = @"day";
    unit.abbreviatedString = @"d";
    unit.elapsedString = @"ed";
    unit.spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(days)];
    unit.spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setDays:)];
    unit.formatterMultiplierImplementation = (FLOAT_IMP)[self instanceMethodForSelector:@selector(hoursPerDay)];
    unit.fixedMultiplier = 3600.0f;    
              
    localizedPluralString = NSLocalizedStringFromTableInBundle(@"hours", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedSingularString = NSLocalizedStringFromTableInBundle(@"hour", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"h", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedElapsedString = NSLocalizedStringFromTableInBundle(@"eh", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");

    [timeSpanUnits addObject:(unit = [OFTimeSpanUnit new])];
    unit.localizedPluralString = [localizedPluralString copy];
    unit.localizedSingularString = [localizedSingularString copy];
    unit.localizedAbbreviatedString = [localizedAbbreviatedString copy];
    unit.localizedElapsedString = [localizedElapsedString copy];
    unit.pluralString = @"hours";
    unit.singularString = @"hour";
    unit.abbreviatedString = @"h";
    unit.elapsedString = @"eh";
    unit.spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(hours)];
    unit.spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setHours:)];
    unit.formatterMultiplierImplementation = NULL;
    unit.fixedMultiplier = 3600.0f;    
    
    localizedPluralString = NSLocalizedStringFromTableInBundle(@"minutes", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedSingularString = NSLocalizedStringFromTableInBundle(@"minute", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"m", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace (minute)");
    localizedElapsedString = NSLocalizedStringFromTableInBundle(@"em", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");

    [timeSpanUnits addObject:(unit = [OFTimeSpanUnit new])];
    unit.localizedPluralString = [localizedPluralString copy];
    unit.localizedSingularString = [localizedSingularString copy];
    unit.localizedAbbreviatedString = [localizedAbbreviatedString copy];
    unit.localizedElapsedString = [localizedElapsedString copy];
    unit.pluralString = @"minutes";
    unit.singularString = @"minute";
    unit.abbreviatedString = @"m";
    unit.elapsedString = @"em";
    unit.spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(minutes)];
    unit.spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setMinutes:)];
    unit.formatterMultiplierImplementation = NULL;
    unit.fixedMultiplier = 60.0f;    
                        
    localizedPluralString = NSLocalizedStringFromTableInBundle(@"seconds", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedSingularString = NSLocalizedStringFromTableInBundle(@"second", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedAbbreviatedString = NSLocalizedStringFromTableInBundle(@"s", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");
    localizedElapsedString = NSLocalizedStringFromTableInBundle(@"es", @"OmniFoundation", bundle, @"time span formatter span - DO NOT add leading or trailing whitespace");

    [timeSpanUnits addObject:(unit = [OFTimeSpanUnit new])];
    unit.localizedPluralString = [localizedPluralString copy];
    unit.localizedSingularString = [localizedSingularString copy];
    unit.localizedAbbreviatedString = [localizedAbbreviatedString copy];
    unit.localizedElapsedString = [localizedElapsedString copy];
    unit.pluralString = @"seconds";
    unit.singularString = @"second";
    unit.abbreviatedString = @"s";
    unit.elapsedString = @"es";
    unit.spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(seconds)];
    unit.spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setSeconds:)];
    unit.formatterMultiplierImplementation = NULL;
    unit.fixedMultiplier = 1.0f;    

    TimeSpanUnits = [timeSpanUnits copy];
    OBASSERT([TimeSpanUnits count] == UNITS_COUNT);
}

+ (NSString *)localizedPluralStringForUnits:(OFTimeSpanFormatterUnit)unit;
{
    OFTimeSpanUnit *timeSpan = TimeSpanUnits[unit];
    return timeSpan.localizedPluralString;
}

+ (NSString *)localizedSingularStringForUnits:(OFTimeSpanFormatterUnit)unit;
{
    OFTimeSpanUnit *timeSpan = TimeSpanUnits[unit];
    return timeSpan.localizedSingularString;
}

+ (NSString *)localizedAbbreviationStringForUnits:(OFTimeSpanFormatterUnit)unit;
{
    OFTimeSpanUnit *timeSpan = TimeSpanUnits[unit];
    return timeSpan.localizedAbbreviatedString;
}

+ (NSString *)localizedElapsedStringForUnits:(OFTimeSpanFormatterUnit)unit;
{
    OFTimeSpanUnit *timeSpan = TimeSpanUnits[unit];
    return timeSpan.localizedElapsedString;
}

- init;
{
    if (!(self = [super init]))
        return nil;

    numberFormatter = [[NSNumberFormatter alloc] init];
    OBASSERT([numberFormatter formatterBehavior] == NSNumberFormatterBehavior10_4 || ([numberFormatter formatterBehavior] == NSNumberFormatterBehaviorDefault && [NSNumberFormatter defaultFormatterBehavior] == NSNumberFormatterBehavior10_4));
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

- (void)encodeWithCoder:(NSCoder *)coder;
{
    [super encodeWithCoder:coder];
    
    [numberFormatter encodeWithCoder:coder];
    OFEncodeValueFrom(coder, &shouldUseVerboseFormat);
    OFEncodeValueFrom(coder, &hoursPerDay);
    OFEncodeValueFrom(coder, &hoursPerWeek);
    OFEncodeValueFrom(coder, &hoursPerMonth);
    OFEncodeValueFrom(coder, &hoursPerYear);
    OFEncodeValueFrom(coder, &roundingInterval);
    
    unsigned int returnNumber = _flags.returnNumber;
    unsigned int floatValuesInSeconds = _flags.floatValuesInSeconds;
    unsigned int displayUnits = _flags.displayUnits;
    unsigned int usesArchiveUnitStrings = _flags.usesArchiveUnitStrings;
    
    OFEncodeValueFrom(coder, &returnNumber);
    OFEncodeValueFrom(coder, &floatValuesInSeconds);
    OFEncodeValueFrom(coder, &displayUnits);
    OFEncodeValueFrom(coder, &usesArchiveUnitStrings);
}

- (id)initWithCoder:(NSCoder *)coder;
{
    self = [super initWithCoder:coder];
    
    numberFormatter = [[NSNumberFormatter alloc] initWithCoder:coder];
    OFDecodeValueInto(coder, &shouldUseVerboseFormat);
    OFDecodeValueInto(coder, &hoursPerDay);
    OFDecodeValueInto(coder, &hoursPerWeek);
    OFDecodeValueInto(coder, &hoursPerMonth);
    OFDecodeValueInto(coder, &hoursPerYear);
    OFDecodeValueInto(coder, &roundingInterval);
    unsigned int returnNumber;
    unsigned int floatValuesInSeconds;
    unsigned int displayUnits;
    unsigned int usesArchiveUnitStrings;

    OFDecodeValueInto(coder, &returnNumber);
    OFDecodeValueInto(coder, &floatValuesInSeconds);
    OFDecodeValueInto(coder, &displayUnits);
    OFDecodeValueInto(coder, &usesArchiveUnitStrings);
    
    _flags.returnNumber = returnNumber;
    _flags.floatValuesInSeconds = floatValuesInSeconds;
    _flags.displayUnits = displayUnits;
    _flags.usesArchiveUnitStrings = usesArchiveUnitStrings;
    
    return self;
}

- (id)copyWithZone:(NSZone *)zone;
{
    OFTimeSpanFormatter *copy = [[[self class] alloc] init];
    
    copy->numberFormatter = [numberFormatter copyWithZone:zone];
    
    copy->shouldUseVerboseFormat = shouldUseVerboseFormat;
    copy->hoursPerDay = hoursPerDay;
    copy->hoursPerWeek = hoursPerWeek;
    copy->hoursPerMonth = hoursPerMonth;
    copy->hoursPerYear = hoursPerYear;
    copy->roundingInterval = roundingInterval;
    
    copy->_flags.returnNumber = _flags.returnNumber;
    copy->_flags.displayUnmodifiedTimeSpan = _flags.displayUnmodifiedTimeSpan;
    copy->_flags.floatValuesInSeconds = _flags.floatValuesInSeconds;
    copy->_flags.displayUnits = _flags.displayUnits;
    copy->_flags.usesArchiveUnitStrings = _flags.usesArchiveUnitStrings;
    copy->_flags.allowsElapsedUnits = _flags.allowsElapsedUnits;

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

- (BOOL)allowsElapsedUnits;
{
    return _flags.allowsElapsedUnits;
}

- (void)setAllowsElapsedUnits:(BOOL)allowsElapsedUnits;
{
    _flags.allowsElapsedUnits = allowsElapsedUnits;
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
    if (roundingInterval == 0.0)
        return value;
        
    float valueRemainder = fmodf(value, roundingInterval);
            
    if (valueRemainder > (roundingInterval / 2))
        value += (roundingInterval - valueRemainder);
    else
        value -= valueRemainder;
    return value;
}

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

            OFTimeSpanUnit *unit = TimeSpanUnits[unitIndex];
            NSString *unitString;
            if (_flags.usesArchiveUnitStrings) {
                if (timeSpan.elapsed && self.allowsElapsedUnits)
                    unitString = unit.elapsedString;
                else
                    unitString = unit.abbreviatedString;
                [displayString appendFormat:@"%@%@", valueString, unitString];
            } else if (shouldUseVerboseFormat) {
                if (timeSpan.elapsed && self.allowsElapsedUnits)
                    unitString = unit.localizedElapsedString;
                else
                    unitString = value > 1.0 ? unit.localizedPluralString : unit.localizedSingularString;
                [displayString appendFormat:@"%@ %@", valueString, unitString];
            } else {
                if (timeSpan.elapsed && self.allowsElapsedUnits)
                    unitString = unit.localizedElapsedString;
                else
                    unitString = unit.localizedAbbreviatedString;
                [displayString appendFormat:@"%@%@", valueString, unitString];
            }
        }
    }
    return displayString;
}

- (OFTimeSpan *)timeSpanValueForNumberValue:(NSNumber *)aNumber;
{
    OFTimeSpan *result = [[OFTimeSpan alloc] initWithTimeSpanFormatter:self];
    float secondsLeft = [aNumber floatValue];
    BOOL negative = secondsLeft < 0;
    if (!_flags.floatValuesInSeconds)
        secondsLeft *= 3600.0f;
    if (negative)
        secondsLeft *= -1.0f;
    
    unsigned int unitIndex;
    for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
        if (_flags.displayUnits & (1 << unitIndex)) {
            OFTimeSpanUnit *unit = TimeSpanUnits[unitIndex];
            BOOL willDisplaySmallerUnits = (_flags.displayUnits & ~((1 << (unitIndex+1))-1));
	    float secondsPerUnit = unit.fixedMultiplier;
	    if (unit.formatterMultiplierImplementation)
		secondsPerUnit *= unit.formatterMultiplierImplementation(self, NULL);
	    
	    float value = secondsLeft / secondsPerUnit;
	    secondsLeft -= floorf(value) * secondsPerUnit;
            
            if (willDisplaySmallerUnits) {
		value = floorf(value);
            } else {
                secondsLeft = 0.0f;
            }
            if (negative)
                value = -value;
            
            switch (unitIndex) {
                case UNITS_YEARS: result.years = value; break;
                case UNITS_MONTHS: result.months = value; break;
                case UNITS_WEEKS: result.weeks = value; break;
                case UNITS_DAYS: result.days = value; break;
                case UNITS_HOURS: result.hours = value; break;
                case UNITS_MINUTES: result.minutes = value; break;
                case UNITS_SECONDS: result.seconds = value; break;
            }
        }
    }
    return result;
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
    
    secondsLeft = roundf(secondsLeft); // not interested in showing anything smaller than a single second difference, so round to nearest second
    if (secondsLeft < 0.0) {  
	isNegative = YES;
	secondsLeft = -secondsLeft;
    } 
	
    NSMutableString *result = [NSMutableString string];
    unsigned int unitIndex;
    for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
        if (_flags.displayUnits & (1U << unitIndex)) {
            OFTimeSpanUnit *unit = TimeSpanUnits[unitIndex];
            BOOL willDisplaySmallerUnits = (_flags.displayUnits & ~((1U << (unitIndex+1))-1)) != 0;
            
            DLOG(@"  unitIndex:%d willDisplaySmallerUnits:0x%x value:%f", unitIndex, willDisplaySmallerUnits, secondsLeft);
	    if (!willDisplaySmallerUnits) {
                if (_flags.usesArchiveUnitStrings)
		    smallestUnitString = unit.abbreviatedString;
		else if (shouldUseVerboseFormat) 
		    smallestUnitString = unit.localizedPluralString;
		else
		    smallestUnitString = unit.localizedAbbreviatedString;
	    }
	    
	    float secondsPerUnit = unit.fixedMultiplier;
	    if (unit.formatterMultiplierImplementation)
		secondsPerUnit *= unit.formatterMultiplierImplementation(self, NULL);
	    
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
                    [result appendFormat:@"%@%@", numberString, unit.abbreviatedString];
                else if (shouldUseVerboseFormat) {
                    NSString *unitString = value > 1.0 ? unit.localizedPluralString : unit.localizedSingularString;
                    [result appendFormat:@"%@ %@", numberString, unitString];
                } else
                    [result appendFormat:@"%@%@", numberString, unit.localizedAbbreviatedString];
            }
        }
    }
    
    if (![result length] && smallestUnitString != nil) {
	// Display 0 of the smallest enabled unit if we have no result
	result = [[NSString stringWithFormat:@"0%@", smallestUnitString] mutableCopy];
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

- (NSString *)placeholderString
{
    return [self _stringForObjectValue:@0 withRounding:NO];
}

- (NSNumber *)_scanNumberFromScanner:(NSScanner *)scanner;
{
    __autoreleasing NSNumber *number = nil;
    __autoreleasing NSError *error = nil;
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
    
    OFTimeSpan *timeSpan = [[OFTimeSpan alloc] initWithTimeSpanFormatter:self];

    NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet];
    NSCharacterSet *letterCharacterSet = [NSCharacterSet letterCharacterSet];
    NSCharacterSet *roundedCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"<>"];
    NSScanner *scanner = [NSScanner localizedScannerWithString:string];
    [scanner setCaseSensitive:NO];
    [scanner setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@""]];
    if ([scanner scanCharactersFromSet:roundedCharacterSet intoString:NULL]) {
        DLOG(@"-[%@ %@]: found rounding characters in '%@'", OBShortObjectDescription(self), NSStringFromSelector(_cmd), string);
    }

    unsigned int lastMatchedUnit = UNITS_COUNT;
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

        NSNumber *numberValue = [self _scanNumberFromScanner:scanner];
	if (numberValue == nil) {
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
            if ([scanner isAtEnd]) {
		if (gotAnythingValid)
		    break;
                else {
                    *obj = nil;
                    DLOG(@">> nil");
                    return YES; 
                }
            }

            NSNumber *denominator = [self _scanNumberFromScanner:scanner];
	    if (denominator == nil) {
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
        
        unsigned int unitIndex = UNITS_COUNT;
        if (_flags.usesArchiveUnitStrings) {
            if (_flags.allowsElapsedUnits) {
                for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
                    OFTimeSpanUnit *unit = TimeSpanUnits[(lastMatchedUnit+unitIndex) % UNITS_COUNT];
                    if ([scanner scanString:unit.elapsedString intoString:NULL]) {
                        lastMatchedUnit = (lastMatchedUnit+unitIndex) % UNITS_COUNT;
                        [timeSpan setElapsed:YES];
                        break;
                    }
                }
            }
            if (!_flags.allowsElapsedUnits || unitIndex == UNITS_COUNT) {
                // Only look for archive unit strings, not long forms or abbreviations
                for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
                    OFTimeSpanUnit *unit = TimeSpanUnits[unitIndex];
                    if ([scanner scanString:unit.abbreviatedString intoString:NULL]) {
                        lastMatchedUnit = unitIndex;
                        break;
                    }
                }
            }
        } else {
            if (_flags.allowsElapsedUnits) {
                for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
                    OFTimeSpanUnit *unit = TimeSpanUnits[(lastMatchedUnit+unitIndex) % UNITS_COUNT];
                    if ([scanner scanString:unit.localizedElapsedString intoString:NULL]) {
                        lastMatchedUnit = (lastMatchedUnit+unitIndex) % UNITS_COUNT;
                        [timeSpan setElapsed:YES];
                        break;
                    }
                }
            }
            if (unitIndex == UNITS_COUNT) {
                for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
                    OFTimeSpanUnit *unit = TimeSpanUnits[(lastMatchedUnit+unitIndex) % UNITS_COUNT];
                    if ([scanner scanString:unit.localizedPluralString intoString:NULL] || [scanner scanString:unit.localizedSingularString intoString:NULL]) {
                        lastMatchedUnit = (lastMatchedUnit+unitIndex) % UNITS_COUNT;
                        break;
                    }
                }
            }
            if (unitIndex == UNITS_COUNT) {
                // Didn't match any long forms, try abbreviations instead
                for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
                    OFTimeSpanUnit *unit = TimeSpanUnits[(lastMatchedUnit+unitIndex) % UNITS_COUNT];
                    if ([scanner scanString:unit.localizedAbbreviatedString intoString:NULL]) {
                        lastMatchedUnit = (lastMatchedUnit+unitIndex) % UNITS_COUNT;
                        break;
                    }
                }
            }
            if (unitIndex == UNITS_COUNT)
                for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
                    OFTimeSpanUnit *unit = TimeSpanUnits[(lastMatchedUnit+unitIndex) % UNITS_COUNT];
                    // Didn't match any localized version, try non-localized
                    if ([scanner scanString:unit.pluralString intoString:NULL] || [scanner scanString:unit.singularString intoString:NULL]) {
                        lastMatchedUnit = (lastMatchedUnit+unitIndex) % UNITS_COUNT;
                        break;
                    }
                }
            if (unitIndex == UNITS_COUNT) {
                // unlocalized abbreviations?
                for (unitIndex = 0; unitIndex < UNITS_COUNT; unitIndex++) {
                    OFTimeSpanUnit *unit = TimeSpanUnits[(lastMatchedUnit+unitIndex) % UNITS_COUNT];
                    if ([scanner scanString:unit.abbreviatedString intoString:NULL]) {
                        lastMatchedUnit = (lastMatchedUnit+unitIndex) % UNITS_COUNT;
                        break;
                    }
                }
            }
        }
        if (unitIndex != UNITS_COUNT) {
            OFTimeSpanUnit *unit = TimeSpanUnits[lastMatchedUnit];
            float existingValue = unit.spanGetImplementation(timeSpan, NULL);
            unit.spanSetImplementation(timeSpan, NULL, number + existingValue);
        } else {
            // didn't match any abbreviation, so assume the lowest unit we display
            unitIndex = UNITS_COUNT;
            while (unitIndex-- != 0) {
                if (_flags.displayUnits & (1 << unitIndex)) {
                    OFTimeSpanUnit *unit = TimeSpanUnits[unitIndex];
                    float existingValue = unit.spanGetImplementation(timeSpan, NULL);
                    unit.spanSetImplementation(timeSpan, NULL, number + existingValue);
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

- (OFTimeSpan *)timeSpanValueForString:(NSString *)string errorDescription:(out NSString **)error;
{
    OFTimeSpan *result;
    if ([self getObjectValue:&result forString:string errorDescription:error])
        return result;
    return nil;
}

@end
