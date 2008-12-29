// Copyright 2000-2008 Omni Development, Inc.  All rights reserved.
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
    NSString *singularString, *pluralString, *abbreviatedString, *archiveString;
    FLOAT_IMP spanGetImplementation;
    SETFLOAT_IMP spanSetImplementation;
    FLOAT_IMP formatterMultiplierImplementation;
    float fixedMultiplier;
} OFTimeSpanUnit;

@implementation OFTimeSpanFormatter

#define TIME_SPAN_UNITS 7

static OFTimeSpanUnit timeSpanUnits[TIME_SPAN_UNITS];

+ (void)initialize;
{
    OBINITIALIZE;
    
    NSBundle *bundle = [self bundle];
    
    timeSpanUnits[0].pluralString = NSLocalizedStringFromTableInBundle(@"years", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[0].singularString = NSLocalizedStringFromTableInBundle(@"year", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[0].abbreviatedString = NSLocalizedStringFromTableInBundle(@"y", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[0].archiveString = @"y";
    timeSpanUnits[0].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(years)];
    timeSpanUnits[0].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setYears:)];
    timeSpanUnits[0].formatterMultiplierImplementation = (FLOAT_IMP)[self instanceMethodForSelector:@selector(hoursPerYear)];
    timeSpanUnits[0].fixedMultiplier = 3600.0f;    
    
    timeSpanUnits[1].pluralString = NSLocalizedStringFromTableInBundle(@"months", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[1].singularString = NSLocalizedStringFromTableInBundle(@"month", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[1].abbreviatedString = NSLocalizedStringFromTableInBundle(@"mo", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[1].archiveString = @"mo";
    timeSpanUnits[1].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(months)];
    timeSpanUnits[1].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setMonths:)];
    timeSpanUnits[1].formatterMultiplierImplementation = (FLOAT_IMP)[self instanceMethodForSelector:@selector(hoursPerMonth)];    
    timeSpanUnits[1].fixedMultiplier = 3600.0f;    
    
    timeSpanUnits[2].pluralString = NSLocalizedStringFromTableInBundle(@"weeks", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[2].singularString = NSLocalizedStringFromTableInBundle(@"week", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[2].abbreviatedString = NSLocalizedStringFromTableInBundle(@"w", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[2].archiveString = @"w";
    timeSpanUnits[2].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(weeks)];
    timeSpanUnits[2].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setWeeks:)];
    timeSpanUnits[2].formatterMultiplierImplementation = (FLOAT_IMP)[self instanceMethodForSelector:@selector(hoursPerWeek)];       
    timeSpanUnits[2].fixedMultiplier = 3600.0f;    
     
    timeSpanUnits[3].pluralString = NSLocalizedStringFromTableInBundle(@"days", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[3].singularString = NSLocalizedStringFromTableInBundle(@"day", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[3].abbreviatedString = NSLocalizedStringFromTableInBundle(@"d", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[3].archiveString = @"d";
    timeSpanUnits[3].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(days)];
    timeSpanUnits[3].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setDays:)];
    timeSpanUnits[3].formatterMultiplierImplementation = (FLOAT_IMP)[self instanceMethodForSelector:@selector(hoursPerDay)];  
    timeSpanUnits[3].fixedMultiplier = 3600.0f;    
              
    timeSpanUnits[4].pluralString = NSLocalizedStringFromTableInBundle(@"hours", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[4].singularString = NSLocalizedStringFromTableInBundle(@"hour", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[4].abbreviatedString = NSLocalizedStringFromTableInBundle(@"h", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[4].archiveString = @"h";
    timeSpanUnits[4].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(hours)];
    timeSpanUnits[4].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setHours:)];
    timeSpanUnits[4].formatterMultiplierImplementation = NULL;    
    timeSpanUnits[4].fixedMultiplier = 3600.0f;    
    
    timeSpanUnits[5].pluralString = NSLocalizedStringFromTableInBundle(@"minutes", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[5].singularString = NSLocalizedStringFromTableInBundle(@"minute", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[5].abbreviatedString = NSLocalizedStringFromTableInBundle(@"m", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[5].archiveString = @"m";
    timeSpanUnits[5].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(minutes)];
    timeSpanUnits[5].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setMinutes:)];
    timeSpanUnits[5].formatterMultiplierImplementation = NULL;
    timeSpanUnits[5].fixedMultiplier = 60.0f;    
                        
    timeSpanUnits[6].pluralString = NSLocalizedStringFromTableInBundle(@"seconds", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[6].singularString = NSLocalizedStringFromTableInBundle(@"second", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[6].abbreviatedString = NSLocalizedStringFromTableInBundle(@"s", @"OmniFoundation", bundle, @"time span formatter span");
    timeSpanUnits[6].archiveString = @"s";
    timeSpanUnits[6].spanGetImplementation = (FLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(seconds)];
    timeSpanUnits[6].spanSetImplementation = (SETFLOAT_IMP)[OFTimeSpan instanceMethodForSelector:@selector(setSeconds:)];    
    timeSpanUnits[6].formatterMultiplierImplementation = NULL;    
    timeSpanUnits[6].fixedMultiplier = 1.0f;    
}

- init;
{
    [super init];

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
    OFTimeSpanFormatter *copy = NSCopyObject(self, 0, zone);
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

- (BOOL)displaySeconds;
{
    return (_flags.displayUnits >> 6) & 1;
}

- (BOOL)displayMinutes;
{
    return (_flags.displayUnits >> 5) & 1;
}

- (BOOL)displayHours;
{
    return (_flags.displayUnits >> 4) & 1;
}

- (BOOL)displayDays;
{
    return (_flags.displayUnits >> 3) & 1;
}

- (BOOL)displayWeeks;
{
    return (_flags.displayUnits >> 2) & 1;
}

- (BOOL)displayMonths;
{
    return (_flags.displayUnits >> 1) & 1;
}

- (BOOL)displayYears;
{
    return (_flags.displayUnits >> 0) & 1;
}

- (void)setDisplaySeconds:(BOOL)aBool;
{
    if (aBool)
        _flags.displayUnits |= (1 << 6);
    else
        _flags.displayUnits &= ~(1 << 6);
}

- (void)setDisplayMinutes:(BOOL)aBool;
{
    if (aBool)
        _flags.displayUnits |= (1 << 5);
    else
        _flags.displayUnits &= ~(1 << 5);
}

- (void)setDisplayHours:(BOOL)aBool;
{
    if (aBool)
        _flags.displayUnits |= (1 << 4);
    else
        _flags.displayUnits &= ~(1 << 4);
}

- (void)setDisplayDays:(BOOL)aBool;
{
    if (aBool)
        _flags.displayUnits |= (1 << 3);
    else
        _flags.displayUnits &= ~(1 << 3);
}

- (void)setDisplayWeeks:(BOOL)aBool;
{
    if (aBool)
        _flags.displayUnits |= (1 << 2);
    else
        _flags.displayUnits &= ~(1 << 2);
}

- (void)setDisplayMonths:(BOOL)aBool;
{
    if (aBool)
        _flags.displayUnits |= (1 << 1);
    else
        _flags.displayUnits &= ~(1 << 1);
}

- (void)setDisplayYears:(BOOL)aBool;
{
    if (aBool)
        _flags.displayUnits |= (1 << 0);
    else
        _flags.displayUnits &= ~(1 << 0);
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

- (NSString *)_stringForObjectValue:(id)object withRounding:(BOOL)withRounding;
{
    DLOG(@"building string for %@; displayUnits:0x%x", [object shortDescription], _flags.displayUnits);
    
    BOOL isNegative = NO;
    NSString *smallestUnitString = nil;
    NSMutableString *result = [NSMutableString string];
    NSString *roundingPrefix = @"";
    float secondsLeft;

    if ([object isKindOfClass:[NSArray class]] && [object count] != 0)
        object = [object objectAtIndex:0];
    if ([object isKindOfClass:[NSNumber class]])
	secondsLeft = [object floatValue] * (_flags.floatValuesInSeconds ? 1.0 : 3600.0);
    else if ([object isKindOfClass:[OFTimeSpan class]]) 
	secondsLeft = [object floatValueInSeconds];
    else {
        DLOG(@">> empty");
	return @"";
    }
    DLOG(@"secondsLeft = %f", secondsLeft);
    
    if (secondsLeft < 0.0) {  
	isNegative = YES;
	secondsLeft = -secondsLeft;
    } 
	
    int unitIndex;
    for (unitIndex = 0; unitIndex < TIME_SPAN_UNITS; unitIndex++) {
        if (_flags.displayUnits & (1 << unitIndex)) {
            BOOL willDisplaySmallerUnits = (_flags.displayUnits & ~((1 << (unitIndex+1))-1));
            
            DLOG(@"  unitIndex:%d willDisplaySmallerUnits:%d value:%f", unitIndex, willDisplaySmallerUnits, secondsLeft);
	    if (!willDisplaySmallerUnits) {
                if (_flags.usesArchiveUnitStrings)
		    smallestUnitString = timeSpanUnits[unitIndex].archiveString;
		else if (shouldUseVerboseFormat) 
		    smallestUnitString = timeSpanUnits[unitIndex].pluralString;
		else
		    smallestUnitString = timeSpanUnits[unitIndex].abbreviatedString;
	    }
	    
	    float secondsPerUnit = timeSpanUnits[unitIndex].fixedMultiplier;
	    if (timeSpanUnits[unitIndex].formatterMultiplierImplementation)
		secondsPerUnit *= timeSpanUnits[unitIndex].formatterMultiplierImplementation(self, NULL);
	    
	    float value = secondsLeft / secondsPerUnit;
	    secondsLeft -= floor(value) * secondsPerUnit;

            NSString *numberString = nil;
            if (willDisplaySmallerUnits) {
		value = floor(value);
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
                secondsLeft = 0.0;
            }
            
            if (numberString && value != 0.0) {
                if ([result length])
                    [result appendString:@" "];
		else if (isNegative)
                    [result appendString:@"-"];

                if (_flags.usesArchiveUnitStrings)
                    [result appendFormat:@"%@%@", numberString, timeSpanUnits[unitIndex].archiveString];
                else if (shouldUseVerboseFormat) {
                    NSString *unitString = value > 1.0 ? timeSpanUnits[unitIndex].pluralString : timeSpanUnits[unitIndex].singularString;
                    [result appendFormat:@"%@ %@", numberString, unitString];
                } else
                    [result appendFormat:@"%@%@", numberString, timeSpanUnits[unitIndex].abbreviatedString];
            }
        }
    }
    
    if (![result length] && (!withRounding || [roundingPrefix length])) {
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
    int position = [scanner scanLocation];
    NSString *string = [[scanner string] substringFromIndex:position];
    NSRange range = NSMakeRange(0, [string length]);
    
    if (!range.length || ![numberFormatter getObjectValue:&number forString:string range:&range error:&error])
	return nil;    
    [scanner setScanLocation:position + NSMaxRange(range)];
    return number;
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error;
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
        int unitIndex;
        for (unitIndex = 0; unitIndex < TIME_SPAN_UNITS; unitIndex++) {
            if ((_flags.usesArchiveUnitStrings && [scanner scanString:timeSpanUnits[unitIndex].archiveString intoString:NULL]) || 
                 [scanner scanString:timeSpanUnits[unitIndex].abbreviatedString intoString:NULL]) {
                float existingValue = timeSpanUnits[unitIndex].spanGetImplementation(timeSpan, NULL);
                timeSpanUnits[unitIndex].spanSetImplementation(timeSpan, NULL, number + existingValue);
                break;
            }
        }
        if (unitIndex == TIME_SPAN_UNITS) {
            // didn't match any abbreviation, so assume the lowest unit we display
            for (unitIndex = TIME_SPAN_UNITS; unitIndex >= 0; unitIndex--) {
                if (_flags.displayUnits & (1 << unitIndex)) {
                    float existingValue = timeSpanUnits[unitIndex].spanGetImplementation(timeSpan, NULL);
                    timeSpanUnits[unitIndex].spanSetImplementation(timeSpan, NULL, number + existingValue);
                    break;
                }
            }
	}
        gotAnythingValid = YES;

        // eat anything remaining since we might be parsing long forms... Yes... this sucks. (ryan)
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
