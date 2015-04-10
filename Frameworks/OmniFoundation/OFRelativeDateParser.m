// Copyright 2006-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRelativeDateParser.h>

#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFErrors.h>

#import <Foundation/NSDateFormatter.h>
#import <Foundation/NSRegularExpression.h>
#import <Foundation/NSCache.h>

#import <OmniFoundation/NSRegularExpression-OFExtensions.h>
#import <OmniFoundation/OFRegularExpressionMatch.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>

// This must be the last include, due to the localized string hack it includes
#import "OFRelativeDateParser-Internal.h"

RCS_ID("$Id$");

// http://userguide.icu-project.org/strings/regexp
// http://icu.sourceforge.net/userguide/formatDateTime.html

static NSDictionary *__localizedRelativeDateNames;
static NSDictionary *__englishRelativeDateNames;
static NSDictionary *__localizedSpecialCaseTimeNames;
static NSDictionary *__englishSpecialCaseTimeNames;
static NSDictionary *__localizedCodes;
static NSDictionary *__englishCodes;
static NSDictionary *__localizedModifiers;
static NSDictionary *__englishModifiers;

static const unsigned unitFlags = NSCalendarUnitSecond | NSCalendarUnitMinute | NSCalendarUnitHour | NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear | NSCalendarUnitEra;

static OFRelativeDateParser *sharedParser;

// english 
static NSArray *englishWeekdays;
static NSArray *englishShortdays;

#if 0 && defined(DEBUG)
    #define DEBUG_DATE(format, ...) NSLog(@"DATE: " format , ## __VA_ARGS__)
#else
    #define DEBUG_DATE(format, ...) do {} while (0)
#endif

typedef enum {
    DPHour = 0,
    DPDay = 1,
    DPWeek = 2,
    DPMonth = 3,
    DPYear = 4,
} DPCode;

typedef enum {
    OFRelativeDateParserNoRelativity = 0, // no modfier 
    OFRelativeDateParserCurrentRelativity = 2, // "this"
    OFRelativeDateParserFutureRelativity = -1, // "next"
    OFRelativeDateParserPastRelativity = 1, // "last"
} OFRelativeDateParserRelativity;

static NSRegularExpression *_createRegex(NSString *pattern)
{
    NSError *error;
    NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:pattern options:0 error:&error];
    if (!regex) {
        NSLog(@"Error creating regular expression from pattern: %@ --> %@", pattern, [error toPropertyList]);
    }
    return regex;
}

static NSCalendar *_defaultCalendar(void)
{
    // Not caching in case the time zone changes.
    NSCalendar *calendar = [[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease];
    [calendar setTimeZone:[NSTimeZone localTimeZone]];
    return calendar;
}

enum {
    OFRelativeDateParserNormalizeOptionsDefault = (OFStringNormlizationOptionLowercase | OFStringNormilzationOptionStripCombiningMarks),
    OFRelativeDateParserNormalizeOptionsAbbreviations = (OFRelativeDateParserNormalizeOptionsDefault | OFStringNormilzationOptionStripPunctuation)
};

@implementation OFRelativeDateParser
{
    // the locale of this parser
    NSLocale *_locale;
    
    // locale specific, change when setLocale is called
    NSArray *_weekdays;
    NSArray *_shortdays;
    NSArray *_alternateShortdays;
    NSArray *_months;
    NSArray *_shortmonths;
    NSArray *_alternateShortmonths;
    NSDictionary *_relativeDateNames;
    NSDictionary *_specialCaseTimeNames;
    NSDictionary *_codes;
    NSDictionary *_modifiers;
}

// creates a new relative date parser with your current locale
+ (OFRelativeDateParser *)sharedParser;
{
    if (!sharedParser) {
	sharedParser = [[OFRelativeDateParser alloc] initWithLocale:[NSLocale currentLocale]];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(currentLocaleDidChange:) name:NSCurrentLocaleDidChangeNotification object:nil];
    }
    return sharedParser;
}

static NSString * const FallbackLocaleIdentifier = @"en_US";

+ (OFRelativeDateParser *)_fallbackParser;
{
    static OFRelativeDateParser *fallbackParser = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fallbackParser = [[OFRelativeDateParser alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:FallbackLocaleIdentifier]];
    });
    return fallbackParser;
}

+ (void)currentLocaleDidChange:(NSNotification *)notification;
{
    [sharedParser setLocale:[NSLocale currentLocale]];
}

static NSMutableDictionary *_localizedRelativeDateNames;
static NSMutableDictionary *_englishRelativeDateNames;

+ (void)_registerRelativeDateName:(NSString *)englishName code:(DPCode)code number:(int)number relativity:(OFRelativeDateParserRelativity)relativity timeSpecific:(BOOL)timeSpecific monthSpecific:(BOOL)monthSpecific daySpecific:(BOOL)daySpecific localizedName:(NSString *)localizedName;
{
    OBPRECONDITION(_localizedRelativeDateNames != nil && _englishRelativeDateNames != nil);

     NSArray *value = [NSArray arrayWithObjects:[NSNumber numberWithInt:code], [NSNumber numberWithInt:number], [NSNumber numberWithInt:relativity], [NSNumber numberWithBool:timeSpecific], [NSNumber numberWithBool:monthSpecific], [NSNumber numberWithBool:daySpecific], nil];
     [_localizedRelativeDateNames setObject:value forKey:localizedName];
     [_englishRelativeDateNames setObject:value forKey:englishName];
}

static NSMutableDictionary *_localizedShorthandCodes;
static NSMutableDictionary *_englishShorthandCodes;

+ (void)_registerShorthandCode:(NSString *)englishName code:(DPCode)code localizedName:(NSString *)localizedName;
{
    OBPRECONDITION(_localizedShorthandCodes != nil && _englishShorthandCodes != nil);
    [_localizedShorthandCodes setObject:@(code) forKey:localizedName];
    [_englishShorthandCodes setObject:@(code) forKey:englishName];
}

static NSMutableDictionary *_localizedModifiers;
static NSMutableDictionary *_englishModifiers;

+ (void)_registerModifierName:(NSString *)englishName relativity:(OFRelativeDateParserRelativity)relativity localizedName:(NSString *)localizedName;
{
    OBPRECONDITION(_localizedModifiers != nil && _englishModifiers != nil);
    [_localizedModifiers setObject:@(relativity) forKey:localizedName];
    [_englishModifiers setObject:@(relativity) forKey:englishName];
}

static NSMutableDictionary *_localizedSpecialCaseTimeNames;
static NSMutableDictionary *_englishSpecialCaseTimeNames;

+ (void)_registerSpecialCaseTimeName:(NSString *)englishName substitutionString:(NSString *)substitutionString localizedName:(NSString *)localizedName;
{
    OBPRECONDITION(_localizedSpecialCaseTimeNames != nil && _englishSpecialCaseTimeNames != nil);
    [_localizedSpecialCaseTimeNames setObject:substitutionString forKey:localizedName];
    [_englishSpecialCaseTimeNames setObject:substitutionString forKey:englishName];
}

+ (void)initialize;
{
    OBINITIALIZE;

    NSLocale *currentLocale = [NSLocale currentLocale];
    NSLocale *englishLocale = [[NSLocale alloc] initWithLocaleIdentifier:FallbackLocaleIdentifier];

    _localizedSpecialCaseTimeNames = [[NSMutableDictionary alloc] init];
    _englishSpecialCaseTimeNames = [[NSMutableDictionary alloc] init];
    [self _registerSpecialCaseTimeName:@"this week" substitutionString:@"$(START_END_OF_THIS_WEEK)" localizedName:NSLocalizedStringFromTableInBundle(@"this week", @"OFDateProcessing", OMNI_BUNDLE, @"time, used for scanning user input. Do NOT add whitespace")];
    [self _registerSpecialCaseTimeName:@"next week" substitutionString:@"$(START_END_OF_NEXT_WEEK)" localizedName:NSLocalizedStringFromTableInBundle(@"next week", @"OFDateProcessing", OMNI_BUNDLE, @"time, used for scanning user input. Do NOT add whitespace")];
    [self _registerSpecialCaseTimeName:@"last week" substitutionString:@"$(START_END_OF_LAST_WEEK)" localizedName:NSLocalizedStringFromTableInBundle(@"last week", @"OFDateProcessing", OMNI_BUNDLE, @"time, used for scanning user input. Do NOT add whitespace")];
    __localizedSpecialCaseTimeNames = [[self _dictionaryByNormalizingKeysInDictionary:_localizedSpecialCaseTimeNames options:OFRelativeDateParserNormalizeOptionsDefault locale:currentLocale] retain];
    __englishSpecialCaseTimeNames = [[self _dictionaryByNormalizingKeysInDictionary:_englishSpecialCaseTimeNames options:OFRelativeDateParserNormalizeOptionsDefault locale:englishLocale] retain];

    // TODO: Can't do seconds offsets for day math due to daylight savings
    // TODO: Make this a localized .plist where it looks something like:
    /*
     "demain" = {day:1}
     "avant-hier" = {day:-2}
     */
    _localizedRelativeDateNames = [[NSMutableDictionary alloc] init];
    _englishRelativeDateNames = [[NSMutableDictionary alloc] init];

    /* Specified Time, Use Current Time */
    [self _registerRelativeDateName:@"now" code:DPDay number:0 relativity:OFRelativeDateParserCurrentRelativity timeSpecific:YES monthSpecific:YES daySpecific:YES localizedName:NSLocalizedStringFromTableInBundle(@"now", @"OFDateProcessing", OMNI_BUNDLE, @"now, used for scanning user input. Do NOT add whitespace")];
    /* Specified Time*/
    [self _registerRelativeDateName:@"noon" code:DPHour number:12 relativity:OFRelativeDateParserCurrentRelativity timeSpecific:NO monthSpecific:YES daySpecific:YES localizedName:NSLocalizedStringFromTableInBundle(@"noon", @"OFDateProcessing", OMNI_BUNDLE, @"noon, used for scanning user input. Do NOT add whitespace")];
    [self _registerRelativeDateName:@"tonight" code:DPHour number:23 relativity:OFRelativeDateParserCurrentRelativity timeSpecific:NO monthSpecific:YES daySpecific:YES localizedName:NSLocalizedStringFromTableInBundle(@"tonight", @"OFDateProcessing", OMNI_BUNDLE, @"tonight, used for scanning user input. Do NOT add whitespace")];
    /* Use default time */
    [self _registerRelativeDateName:@"today" code:DPDay number:0 relativity:OFRelativeDateParserCurrentRelativity timeSpecific:NO monthSpecific:YES daySpecific:YES localizedName:NSLocalizedStringFromTableInBundle(@"today", @"OFDateProcessing", OMNI_BUNDLE, @"today, used for scanning user input. Do NOT add whitespace")];
    [self _registerRelativeDateName:@"tod" code:DPDay number:0 relativity:OFRelativeDateParserCurrentRelativity timeSpecific:NO monthSpecific:YES daySpecific:YES localizedName:NSLocalizedStringFromTableInBundle(@"tod", @"OFDateProcessing", OMNI_BUNDLE, @"\"tod\" this should be an abbreviation for \"today\" that makes sense for the given language, used for scanning user input. Do NOT add whitespace")];
    [self _registerRelativeDateName:@"tomorrow" code:DPDay number:1 relativity:OFRelativeDateParserFutureRelativity timeSpecific:NO monthSpecific:YES daySpecific:YES localizedName:NSLocalizedStringFromTableInBundle(@"tomorrow", @"OFDateProcessing", OMNI_BUNDLE, @"tomorrow")];
    [self _registerRelativeDateName:@"tom" code:DPDay number:1 relativity:OFRelativeDateParserFutureRelativity timeSpecific:NO monthSpecific:YES daySpecific:YES localizedName:NSLocalizedStringFromTableInBundle(@"tom", @"OFDateProcessing", OMNI_BUNDLE, @"\"tom\" this should be an abbreviation for \"tomorrow\" that makes sense for the given language, used for scanning user input. Do NOT add whitespace")];
    [self _registerRelativeDateName:@"yesterday" code:DPDay number:1 relativity:OFRelativeDateParserPastRelativity timeSpecific:NO monthSpecific:YES daySpecific:YES localizedName:NSLocalizedStringFromTableInBundle(@"yesterday", @"OFDateProcessing", OMNI_BUNDLE, @"yesterday, used for scanning user input. Do NOT add whitespace")];
    [self _registerRelativeDateName:@"yes" code:DPDay number:1 relativity:OFRelativeDateParserPastRelativity timeSpecific:NO monthSpecific:YES daySpecific:YES localizedName:NSLocalizedStringFromTableInBundle(@"yes", @"OFDateProcessing", OMNI_BUNDLE, @"\"yes\" this should be an abbreviation for \"yesterday\" that makes sense for the given language, used for scanning user input. Do NOT add whitespace")];
    /* use default day */
    [self _registerRelativeDateName:@"this month" code:DPMonth number:0 relativity:OFRelativeDateParserCurrentRelativity timeSpecific:NO monthSpecific:YES daySpecific:NO localizedName:NSLocalizedStringFromTableInBundle(@"this month", @"OFDateProcessing", OMNI_BUNDLE, @"this month, used for scanning user input. Do NOT add whitespace")];
    [self _registerRelativeDateName:@"next month" code:DPMonth number:1 relativity:OFRelativeDateParserFutureRelativity timeSpecific:NO monthSpecific:YES daySpecific:NO localizedName:NSLocalizedStringFromTableInBundle(@"next month", @"OFDateProcessing", OMNI_BUNDLE, @"next month, used for scanning user input. Do NOT add whitespace")];
    [self _registerRelativeDateName:@"last month" code:DPMonth number:1 relativity:OFRelativeDateParserPastRelativity timeSpecific:NO monthSpecific:YES daySpecific:NO localizedName:NSLocalizedStringFromTableInBundle(@"last month", @"OFDateProcessing", OMNI_BUNDLE, @"last month, used for scanning user input. Do NOT add whitespace")];
    [self _registerRelativeDateName:@"this year" code:DPYear number:0 relativity:OFRelativeDateParserCurrentRelativity timeSpecific:NO monthSpecific:NO daySpecific:NO localizedName:NSLocalizedStringFromTableInBundle(@"this year", @"OFDateProcessing", OMNI_BUNDLE, @"this year, used for scanning user input. Do NOT add whitespace")];
    [self _registerRelativeDateName:@"next year" code:DPYear number:1 relativity:OFRelativeDateParserFutureRelativity timeSpecific:NO monthSpecific:NO daySpecific:NO localizedName:NSLocalizedStringFromTableInBundle(@"next year", @"OFDateProcessing", OMNI_BUNDLE, @"next year, used for scanning user input. Do NOT add whitespace")];
    [self _registerRelativeDateName:@"last year" code:DPYear number:1 relativity:OFRelativeDateParserPastRelativity timeSpecific:NO monthSpecific:NO daySpecific:NO localizedName:NSLocalizedStringFromTableInBundle(@"last year", @"OFDateProcessing", OMNI_BUNDLE, @"last year, used for scanning user input. Do NOT add whitespace")];

    __localizedRelativeDateNames = [[self _dictionaryByNormalizingKeysInDictionary:_localizedRelativeDateNames options:OFRelativeDateParserNormalizeOptionsDefault locale:currentLocale] retain];
    __englishRelativeDateNames = [[self _dictionaryByNormalizingKeysInDictionary:_englishRelativeDateNames options:OFRelativeDateParserNormalizeOptionsDefault locale:englishLocale] retain];
    
    // short hand codes
    _localizedShorthandCodes = [NSMutableDictionary dictionary];
    _englishShorthandCodes = [NSMutableDictionary dictionary];
    [self _registerShorthandCode:@"h" code:DPHour localizedName:NSLocalizedStringFromTableInBundle(@"h", @"OFDateProcessing", OMNI_BUNDLE, @"one-letter abbreviation for hour or hours, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"hour" code:DPHour localizedName:NSLocalizedStringFromTableInBundle(@"hour", @"OFDateProcessing", OMNI_BUNDLE, @"hour, singular, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"hours" code:DPHour localizedName:NSLocalizedStringFromTableInBundle(@"hours", @"OFDateProcessing", OMNI_BUNDLE, @"hours, plural, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"d" code:DPDay localizedName:NSLocalizedStringFromTableInBundle(@"d", @"OFDateProcessing", OMNI_BUNDLE, @"one-letter abbreviation for day or days, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"day" code:DPDay localizedName:NSLocalizedStringFromTableInBundle(@"day", @"OFDateProcessing", OMNI_BUNDLE, @"day, singular, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"days" code:DPDay localizedName:NSLocalizedStringFromTableInBundle(@"days", @"OFDateProcessing", OMNI_BUNDLE, @"days, plural, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"w" code:DPWeek localizedName:NSLocalizedStringFromTableInBundle(@"w", @"OFDateProcessing", OMNI_BUNDLE, @"one-letter abbreviation for week or weeks, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"week" code:DPWeek localizedName:NSLocalizedStringFromTableInBundle(@"week", @"OFDateProcessing", OMNI_BUNDLE, @"week, singular, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"weeks" code:DPWeek localizedName:NSLocalizedStringFromTableInBundle(@"weeks", @"OFDateProcessing", OMNI_BUNDLE, @"weeks, plural, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"m" code:DPMonth localizedName:NSLocalizedStringFromTableInBundle(@"m", @"OFDateProcessing", OMNI_BUNDLE, @"one-letter abbreviation for month or months, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"month" code:DPMonth localizedName:NSLocalizedStringFromTableInBundle(@"month", @"OFDateProcessing", OMNI_BUNDLE, @"month, singular, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"months" code:DPMonth localizedName:NSLocalizedStringFromTableInBundle(@"months", @"OFDateProcessing", OMNI_BUNDLE, @"months, plural, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"y" code:DPYear localizedName:NSLocalizedStringFromTableInBundle(@"y", @"OFDateProcessing", OMNI_BUNDLE, @"one-letter abbreviation for year or years, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"year" code:DPYear localizedName:NSLocalizedStringFromTableInBundle(@"year", @"OFDateProcessing", OMNI_BUNDLE, @"year, singular, used for scanning user input. Do NOT add whitespace")];
    [self _registerShorthandCode:@"years" code:DPYear localizedName:NSLocalizedStringFromTableInBundle(@"years", @"OFDateProcessing", OMNI_BUNDLE, @"years, plural, used for scanning user input. Do NOT add whitespace")];
    __localizedCodes = [[self _dictionaryByNormalizingKeysInDictionary:_localizedShorthandCodes options:OFRelativeDateParserNormalizeOptionsDefault locale:currentLocale] retain];
    __englishCodes = [[self _dictionaryByNormalizingKeysInDictionary:_englishShorthandCodes options:OFRelativeDateParserNormalizeOptionsDefault locale:englishLocale] retain];

    // time modifiers
    _localizedModifiers = [NSMutableDictionary dictionary];
    _englishModifiers = [NSMutableDictionary dictionary];
    [self _registerModifierName:@"+" relativity:OFRelativeDateParserFutureRelativity localizedName:NSLocalizedStringFromTableInBundle(@"+", @"OFDateProcessing", OMNI_BUNDLE, @"modifier, used for scanning user input. Do NOT add whitespace")];
    [self _registerModifierName:@"next" relativity:OFRelativeDateParserFutureRelativity localizedName:NSLocalizedStringFromTableInBundle(@"next", @"OFDateProcessing", OMNI_BUNDLE, @"modifier, the most commonly used translation of \"next\", or some other shorthand way of saying things like \"next week\", used for scanning user input. Do NOT add whitespace")];
    [self _registerModifierName:@"-" relativity:OFRelativeDateParserPastRelativity localizedName:NSLocalizedStringFromTableInBundle(@"-", @"OFDateProcessing", OMNI_BUNDLE, @"modifier, used for scanning user input. Do NOT add whitespace")];
    [self _registerModifierName:@"last" relativity:OFRelativeDateParserPastRelativity localizedName:NSLocalizedStringFromTableInBundle(@"last", @"OFDateProcessing", OMNI_BUNDLE, @"modifier, used for scanning user input. Do NOT add whitespace")];
    [self _registerModifierName:@"~" relativity:OFRelativeDateParserCurrentRelativity localizedName:NSLocalizedStringFromTableInBundle(@"~", @"OFDateProcessing", OMNI_BUNDLE, @"modifier, used for scanning user input. Do NOT add whitespace")];
    [self _registerModifierName:@"this" relativity:OFRelativeDateParserCurrentRelativity localizedName:NSLocalizedStringFromTableInBundle(@"this", @"OFDateProcessing", OMNI_BUNDLE, @"modifier, the most commonly used translation of \"this\", or some other shorthand way of saying things like \"this week\", used for scanning user input. Do NOT add whitespace")];
    __localizedModifiers = [[self _dictionaryByNormalizingKeysInDictionary:_localizedModifiers options:OFRelativeDateParserNormalizeOptionsDefault locale:currentLocale] retain];
    __englishModifiers = [[self _dictionaryByNormalizingKeysInDictionary:_englishModifiers options:OFRelativeDateParserNormalizeOptionsDefault locale:currentLocale] retain];

    // english 
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease]; 
    [formatter setLocale:englishLocale];
    englishWeekdays = [[self _arrayByNormalizingValuesInArray:[formatter weekdaySymbols] options:OFRelativeDateParserNormalizeOptionsDefault locale:englishLocale] retain];
    englishShortdays = [[self _arrayByNormalizingValuesInArray:[formatter shortWeekdaySymbols] options:OFRelativeDateParserNormalizeOptionsDefault locale:englishLocale] retain];
    [englishLocale release];
}

- initWithLocale:(NSLocale *)locale;
{
    if (!(self = [super init]))
        return nil;
    [self setLocale:locale];
    return self;
}

- (void)dealloc
{
    [_locale release];
    [_weekdays release];
    [_shortdays release];
    [_alternateShortdays release];
    [_months release];
    [_shortmonths release];
    [_alternateShortmonths release];
    [_relativeDateNames release];
    [_specialCaseTimeNames release];
    [_codes release];
    [_modifiers release];
    
    [super dealloc];
}

- (NSLocale *)locale;
{
    return _locale;
}

- (void)setLocale:(NSLocale *)locale;
{
    if (_locale == locale)
        return;

    [_locale release];
    _locale = [locale retain];
    
    BOOL isEnglish = OFISEQUAL(locale.localeIdentifier, FallbackLocaleIdentifier);

    // Rebuild the weekday/month name arrays for a new locale
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setLocale:locale];
    
    [_weekdays release];
    _weekdays = [[self _arrayByNormalizingValuesInArray:[formatter weekdaySymbols] options:OFRelativeDateParserNormalizeOptionsDefault] retain];
    
    [_shortdays release];
    _shortdays = [[self _arrayByNormalizingValuesInArray:[formatter shortWeekdaySymbols] options:OFRelativeDateParserNormalizeOptionsDefault] retain];
    
    [_alternateShortdays release];
    _alternateShortdays = [[self _arrayByNormalizingValuesInArray:[formatter shortWeekdaySymbols] options:OFRelativeDateParserNormalizeOptionsAbbreviations] retain];
    
    [_months release];
    _months = [[self _arrayByNormalizingValuesInArray:[formatter monthSymbols] options:OFRelativeDateParserNormalizeOptionsDefault] retain];
    
    [_shortmonths release];
    _shortmonths = [[self _arrayByNormalizingValuesInArray:[formatter shortMonthSymbols] options:OFRelativeDateParserNormalizeOptionsDefault] retain];

    [_alternateShortmonths release];
    _alternateShortmonths = [[self _arrayByNormalizingValuesInArray:[formatter shortMonthSymbols] options:OFRelativeDateParserNormalizeOptionsAbbreviations] retain];

    // NOTE: The rest of these values actually come from the app's current localization rather than from the specified locale. We just bypass this localization for our English fallback parser.

    [_relativeDateNames release];
    _relativeDateNames = isEnglish ? [__englishRelativeDateNames retain] : [__localizedRelativeDateNames retain];

    [_specialCaseTimeNames release];
    _specialCaseTimeNames = isEnglish ? [__englishSpecialCaseTimeNames retain] : [__localizedSpecialCaseTimeNames retain];

    [_codes release];
    _codes = isEnglish ? [__englishCodes retain] : [__localizedCodes retain];

    [_modifiers release];
    _modifiers = isEnglish ? [__englishModifiers retain] : [__localizedModifiers retain];
}

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string error:(NSError **)error;
{
    return [self getDateValue:date forString:string fromStartingDate:nil useEndOfDuration:NO defaultTimeDateComponents:nil calendar:nil error:error];
}

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string fromStartingDate:(NSDate *)startingDate useEndOfDuration:(BOOL)useEndOfDuration defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents calendar:(NSCalendar *)calendar error:(NSError **)error;
{
    return [self getDateValue:date forString:string fromStartingDate:startingDate useEndOfDuration:useEndOfDuration defaultTimeDateComponents:defaultTimeDateComponents calendar:calendar withCustomFormat:nil error:error];
}

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string fromStartingDate:(NSDate *)startingDate useEndOfDuration:(BOOL)useEndOfDuration defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents calendar:(NSCalendar *)calendar withCustomFormat:(NSString *)customFormat error:(NSError **)error;
{
    if (!calendar)
        calendar = _defaultCalendar();

    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];

    [formatter setCalendar:calendar];
    [formatter setLocale:_locale];

    [formatter setDateStyle:NSDateFormatterShortStyle];
    [formatter setTimeStyle:NSDateFormatterNoStyle];
    NSString *shortFormat = [[[formatter dateFormat] copy] autorelease];

    [formatter setDateStyle:NSDateFormatterMediumStyle];
    NSString *mediumFormat = [[[formatter dateFormat] copy] autorelease];

    [formatter setDateStyle:NSDateFormatterLongStyle];
    NSString *longFormat = [[[formatter dateFormat] copy] autorelease];

    [formatter setDateStyle:NSDateFormatterNoStyle];
    [formatter setTimeStyle:NSDateFormatterShortStyle];
    NSString *timeFormat = [[[formatter dateFormat] copy] autorelease];

    return [self getDateValue:date forString:string fromStartingDate:startingDate calendar:calendar withCustomFormat:customFormat withShortDateFormat:shortFormat withMediumDateFormat:mediumFormat withLongDateFormat:longFormat withTimeFormat:timeFormat useEndOfDuration:useEndOfDuration defaultTimeDateComponents:defaultTimeDateComponents error:error];
}

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string fromStartingDate:(NSDate *)startingDate calendar:(NSCalendar *)calendar withShortDateFormat:(NSString *)shortFormat withMediumDateFormat:(NSString *)mediumFormat withLongDateFormat:(NSString *)longFormat withTimeFormat:(NSString *)timeFormat error:(NSError **)error;
{
    return [self getDateValue:date forString:string fromStartingDate:startingDate calendar:calendar withCustomFormat:nil withShortDateFormat:shortFormat withMediumDateFormat:mediumFormat withLongDateFormat:longFormat withTimeFormat:timeFormat error:error];
}

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string fromStartingDate:(NSDate *)startingDate calendar:(NSCalendar *)calendar withCustomFormat:(NSString *)customFormat withShortDateFormat:(NSString *)shortFormat withMediumDateFormat:(NSString *)mediumFormat withLongDateFormat:(NSString *)longFormat withTimeFormat:(NSString *)timeFormat error:(NSError **)error;
{
    return [self getDateValue:date forString:string fromStartingDate:startingDate calendar:calendar withCustomFormat:customFormat  withShortDateFormat:shortFormat withMediumDateFormat:mediumFormat withLongDateFormat:longFormat withTimeFormat:timeFormat useEndOfDuration:NO defaultTimeDateComponents:nil /* not needed for unit tests */ error:error];
}

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string fromStartingDate:(NSDate *)startingDate calendar:(NSCalendar *)calendar withShortDateFormat:(NSString *)shortFormat withMediumDateFormat:(NSString *)mediumFormat withLongDateFormat:(NSString *)longFormat withTimeFormat:(NSString *)timeFormat useEndOfDuration:(BOOL)useEndOfDuration defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents error:(NSError **)error;
{
    return [self getDateValue:date forString:string fromStartingDate:startingDate calendar:calendar withCustomFormat:nil withShortDateFormat:shortFormat withMediumDateFormat:mediumFormat withLongDateFormat:longFormat withTimeFormat:timeFormat useEndOfDuration:useEndOfDuration defaultTimeDateComponents:defaultTimeDateComponents error:error];
}

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string fromStartingDate:(NSDate *)startingDate calendar:(NSCalendar *)calendar withCustomFormat:(NSString *)customFormat withShortDateFormat:(NSString *)shortFormat withMediumDateFormat:(NSString *)mediumFormat withLongDateFormat:(NSString *)longFormat withTimeFormat:(NSString *)timeFormat useEndOfDuration:(BOOL)useEndOfDuration defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents error:(NSError **)error;
{
    return [self _getDateValue:date forString:string fromStartingDate:startingDate calendar:calendar withCustomFormat:customFormat withShortDateFormat:shortFormat mediumDateFormat:mediumFormat longDateFormat:longFormat timeFormat:timeFormat useEndOfDuration:useEndOfDuration defaultTimeDateComponents:defaultTimeDateComponents error:error];
}

- (NSDateComponents *)_parseTimeString:(NSString *)timeString withTimeFormat:(NSString *)timeFormat calendar:(NSCalendar *)calendar;
{
    NSRange usedStringRange;
    NSDateComponents *strictTimeComponents = [self _parseStrictTimeString:timeString timeFormat:timeFormat calendar:calendar usedStringRange:&usedStringRange error:NULL];
    if (strictTimeComponents != nil && usedStringRange.length == timeString.length)
        return strictTimeComponents;

    OFCreateRegularExpression(ignorableExpression, @"^\\s*(at|@|,\\s)\\s*"); // We try string parsing once before looking for things to ignore and trying again
    timeString = [ignorableExpression stringByReplacingMatchesInString:timeString options:0 range:(NSRange){0, timeString.length} withTemplate:@""];

    strictTimeComponents = [self _parseStrictTimeString:timeString timeFormat:timeFormat calendar:calendar usedStringRange:&usedStringRange error:NULL];
    if (strictTimeComponents != nil && usedStringRange.length == timeString.length)
        return strictTimeComponents;

    if ([self _stringMatchesTime:timeString withTimeFormat:timeFormat calendar:calendar])
        return [self _parseTimeString:timeString meridianString:nil withDate:[NSDate dateWithTimeIntervalSinceReferenceDate:0] withTimeFormat:timeFormat calendar:calendar];

    return nil;
}

- (BOOL)_getDateValue:(NSDate **)outDate forString:(NSString *)string fromStartingDate:(NSDate *)startingDate calendar:(NSCalendar *)calendar withCustomFormat:(NSString *)customFormat withShortDateFormat:(NSString *)shortFormat mediumDateFormat:(NSString *)mediumFormat longDateFormat:(NSString *)longFormat timeFormat:(NSString *)timeFormat useEndOfDuration:(BOOL)useEndOfDuration defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents error:(NSError **)outError;
{
    // return nil instead of the current date on empty string
    string = [string stringByRemovingSurroundingWhitespace];
    if ([NSString isEmptyString:string]) {
        if (outDate != NULL)
            *outDate = nil;
	return YES;
    }
    
    if (startingDate == nil)
        startingDate = [NSDate date];
    
    if (calendar == nil)
        calendar = _defaultCalendar();

    BOOL usedCustomFormat = NO;
    NSDate *date = nil;
    NSRange usedStringRange;
    NSError *strictDateError = nil;
    if ([self _getStrictDateValue:&date usedCustomFormat:&usedCustomFormat forString:string fromStartingDate:startingDate calendar:calendar withCustomFormat:customFormat  withShortDateFormat:shortFormat mediumDateFormat:mediumFormat longDateFormat:longFormat usedStringRange:&usedStringRange error:&strictDateError]) {
        if (usedStringRange.length == 0)
            date = startingDate;
        NSUInteger timeLocation = NSMaxRange(usedStringRange);
        NSUInteger stringLength = string.length;
        NSRange remainingRange = (NSRange){timeLocation, stringLength - timeLocation};
        NSString *remainingString = [[string substringWithRange:remainingRange] stringByRemovingSurroundingWhitespace];
        NSDateComponents *timeComponents = nil;
        if (usedCustomFormat) {
            if ([NSString isEmptyString:remainingString]) {
                if (outDate != NULL)
                    *outDate = date;
                return YES;
            }
        } else {
            if (![NSString isEmptyString:remainingString])
                timeComponents = [self _parseTimeString:remainingString withTimeFormat:timeFormat calendar:calendar];
            if (timeComponents == nil)
                timeComponents = defaultTimeDateComponents;

            if (timeComponents != nil) {
                NSDate *combinedDate = [self _dateWithDate:date timeComponents:timeComponents calendar:calendar];
                OBASSERT(combinedDate != nil);
                if (outDate != NULL)
                    *outDate = combinedDate;
                return YES;
            }
        }
    }

    return [self _getHeuristicDateValue:outDate forString:string fromStartingDate:startingDate calendar:calendar withShortDateFormat:shortFormat mediumDateFormat:mediumFormat longDateFormat:longFormat timeFormat:timeFormat useEndOfDuration:useEndOfDuration defaultTimeDateComponents:defaultTimeDateComponents error:outError];
}

- (BOOL)_getStrictDateValue:(NSDate **)outDate usedCustomFormat:(BOOL *)usedCustomFormat forString:(NSString *)string fromStartingDate:(NSDate *)startingDate calendar:(NSCalendar *)calendar withCustomFormat:(NSString *)customFormat withShortDateFormat:(NSString *)shortFormat mediumDateFormat:(NSString *)mediumFormat longDateFormat:(NSString *)longFormat usedStringRange:(NSRange *)outUsedStringRange error:(NSError **)outError;
{
    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    dateFormatter.calendar = calendar;
    dateFormatter.timeZone = calendar.timeZone;
    dateFormatter.locale = _locale;
    dateFormatter.dateFormat = customFormat;
    NSRange range = (NSRange){0, string.length};
    *usedCustomFormat = YES;
    if (!customFormat || ![dateFormatter getObjectValue:outDate forString:string range:&range error:outError]) {
        *usedCustomFormat = NO;
        dateFormatter.dateFormat = shortFormat;
        if (![dateFormatter getObjectValue:outDate forString:string range:&range error:outError]) {
            dateFormatter.dateFormat = mediumFormat;
            if (![dateFormatter getObjectValue:outDate forString:string range:&range error:NULL]) {
                dateFormatter.dateFormat = longFormat;
                if (![dateFormatter getObjectValue:outDate forString:string range:&range error:NULL]) {
                    return NO;
                }
            }
        }
    }

    if (outUsedStringRange != NULL)
        *outUsedStringRange = range;
    return YES;
}

- (NSDateComponents *)_parseStrictTimeString:(NSString *)timeString timeFormat:(NSString *)timeFormat calendar:(NSCalendar *)calendar usedStringRange:(NSRange *)outUsedStringRange error:(NSError **)outError;
{
    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    dateFormatter.calendar = calendar;
    dateFormatter.timeZone = calendar.timeZone;
    dateFormatter.locale = _locale;
    dateFormatter.dateFormat = timeFormat;

    NSRange range = (NSRange){0, timeString.length};
    NSDate *date = nil;
    if (![dateFormatter getObjectValue:&date forString:timeString range:&range error:outError])
        return nil;

    if (outUsedStringRange != NULL)
        *outUsedStringRange = range;
    NSDateComponents *dateComponents = [calendar components:NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitSecond fromDate:date];
    return dateComponents;
}

- (BOOL)_getHeuristicDateValue:(NSDate **)outDate forString:(NSString *)string fromStartingDate:(NSDate *)startingDate calendar:(NSCalendar *)calendar withShortDateFormat:(NSString *)shortFormat mediumDateFormat:(NSString *)mediumFormat longDateFormat:(NSString *)longFormat timeFormat:(NSString *)timeFormat useEndOfDuration:(BOOL)useEndOfDuration defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents error:(NSError **)error;
{
    string = [[string lowercaseString] stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace];
    NSString *dateString = nil;
    NSString *timeString = nil; // just the "hh:mm" part
    NSString *meridianString = nil;
    
    // first see if we have an @, if so then we can easily split the date and time portions of the string
    string = [string stringByReplacingOccurrencesOfString:@" at " withString:@"@"];
    if ([string containsString:@"@"]) {
	
	NSArray *dateAndTime = [string componentsSeparatedByString:@"@"];
	
	if ([dateAndTime count] > 2) {
#ifdef DEBUG_xmas
#error this code needs a code in OFErrors -- zero is not valid
#endif
	    OFError(error, // error
		    0,  // code enum
		    @"accepted strings are of the form \"DATE @ TIME\", there was an extra \"@\" sign", // description
                    nil
		    );
	    
	    return NO;
	}
	
	// allow for the string to start with the time, and have no time, an "@" must always precede the time
	if ([string hasPrefix:@"@"]) {
	    DEBUG_DATE( @"string starts w/ an @ , so there is no date");
	    timeString = [dateAndTime objectAtIndex:1];
	} else {
	    dateString = [dateAndTime objectAtIndex:0];
	    if ([dateAndTime count] == 2) 
		timeString = [dateAndTime objectAtIndex:1];
	}

        if (![timeString containsCharacterInSet:[NSCharacterSet decimalDigitCharacterSet]]) {
            // No numerals found in the time; treat the @ sign as whitespace
            dateString = [dateAndTime componentsJoinedByString:@" "];
            timeString = nil;
        }

        DEBUG_DATE( @"contains @, dateString: %@, timeString: %@", dateString, timeString );
    } else {
	DEBUG_DATE(@"-----------'%@' starting date:%@", string, startingDate);

	NSArray *stringComponents = [string componentsSeparatedByString:@" "];
	NSUInteger maxComponentIndex = [stringComponents count] - 1;
	
	// Test for a time at the end of the string. This will only match things that are probably times (has colons), or am/pm. We assume the time (and optionally) meridian are together at the end of the string. We allow "<time> <meridian>" and "<meridian> <time>" (for Korean).
        NSString *lastComponent = stringComponents[maxComponentIndex];
        NSString *secondToLastComponent = (maxComponentIndex > 0) ? stringComponents[maxComponentIndex-1] : nil;
        
        if (secondToLastComponent && ([self _stringMatchesTime:secondToLastComponent withTimeFormat:timeFormat calendar:calendar] || [self _stringIsNumber:secondToLastComponent]) && [self _isMeridianString:lastComponent calendar:calendar]) {
            // Explicit time and meridian in separate components ("4:00 pm" or "4 pm" -- the -_stringIsNumber: check is for the second of these)
            timeString = secondToLastComponent;
            meridianString = lastComponent;
            dateString = [[stringComponents subarrayWithRange:NSMakeRange(0, maxComponentIndex-1)] componentsJoinedByString:@" "];
        } else if (secondToLastComponent && [self _isMeridianString:secondToLastComponent calendar:calendar] && ([self _stringMatchesTime:lastComponent withTimeFormat:timeFormat calendar:calendar] || [self _stringIsNumber:lastComponent])) {
            // Explicit meridian first, time second (Korean, for example)
            timeString = lastComponent;
            meridianString = secondToLastComponent;
            dateString = [[stringComponents subarrayWithRange:NSMakeRange(0, maxComponentIndex-1)] componentsJoinedByString:@" "];
        } else if ([self _stringMatchesTime:lastComponent withTimeFormat:timeFormat calendar:calendar]) {
            // No meridian, or meridian combined ("4pm" or "下午4:00")e
            timeString = lastComponent;
            dateString = [[stringComponents subarrayWithRange:NSMakeRange(0, maxComponentIndex)] componentsJoinedByString:@" "];
	} else if ([self _stringIsNumber:lastComponent]) {
            // Plain time string w/o meridian or hour/minute separator
	    int number = [lastComponent intValue];
	    int minutes = number % 100;
	    if (([timeFormat isEqualToString:@"HHmm"] || [timeFormat isEqualToString:@"kkmm"]) && ([lastComponent length] == 4)) {
		if (number < 2500 && minutes < 60) {
		    DEBUG_DATE(@"The time format is 24 hour time with the format: %@.  The number is: %d, and is less than 2500. The minutes are: %d, and are less than 60", timeFormat, number, minutes);
                    timeString = lastComponent;
                    dateString = [[stringComponents subarrayWithRange:NSMakeRange(0, maxComponentIndex)] componentsJoinedByString:@" "];
		}
	    } 
	}

        if (!timeString) {
            // No date found -- use the whole thing as a date
            dateString = string;
        }
        
	DEBUG_DATE( @"NO @, dateString: %@, timeString: %@", dateString, timeString );
    }
    
    BOOL timeSpecific = NO;
    NSDate *date;

    if (![NSString isEmptyString:dateString]) {
        NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
        dateFormatter.calendar = calendar;
        dateFormatter.timeZone = calendar.timeZone;
        dateFormatter.locale = _locale;
        dateFormatter.dateFormat = shortFormat;
        if (![dateFormatter getObjectValue:&date forString:dateString range:NULL error:NULL]) {
            // Some formats have dots and spaces as a separator and will fail to match our formattedDateRegex otherwise
            if ([dateString rangeOfString:@". "].location != NSNotFound) {
                dateString = [dateString stringByReplacingOccurrencesOfString:@". " withString:@"."];
            }
            
            OFCreateRegularExpression(spacedDateRegex, @"^(\\d{1,4})\\s(\\d{1,4})\\s?(\\d{0,4})$");
            OFCreateRegularExpression(formattedDateRegex, @"^\\w+([\\./-])\\w+");
            OFCreateRegularExpression(unseparatedDateRegex, @"^(\\d{2,4})(\\d{2})(\\d{2})$");
            
            OFRegularExpressionMatch *spacedDateMatch = [spacedDateRegex of_firstMatchInString:dateString];
            OFRegularExpressionMatch *formattedDateMatch = [formattedDateRegex of_firstMatchInString:dateString];
            OFRegularExpressionMatch *unseparatedDateMatch = [unseparatedDateRegex of_firstMatchInString:dateString];
            
            if (unseparatedDateMatch) {
                dateString = [NSString stringWithFormat:@"%@-%@-%@", [unseparatedDateMatch captureGroupAtIndex:0], [unseparatedDateMatch captureGroupAtIndex:1], [unseparatedDateMatch captureGroupAtIndex:2]];
            }
            
            if (formattedDateMatch || unseparatedDateMatch || spacedDateMatch) {
                NSString *separator = @" ";
                if (unseparatedDateMatch) {
                    DEBUG_DATE(@"found an 'unseparated' date");
                    separator = @"-";
                } else if (formattedDateMatch) {
                    DEBUG_DATE(@"formatted date found with the separator as: %@", [formattedDateMatch captureGroupAtIndex:0]);
                    separator = [formattedDateMatch captureGroupAtIndex:0];
                } else if (spacedDateMatch) {
                    DEBUG_DATE(@"numerical space delimited date found");
                    separator = @" ";
                }
                
                date = [self _parseFormattedDate:dateString withDate:startingDate withShortDateFormat:shortFormat withMediumDateFormat:mediumFormat withLongDateFormat:longFormat withseparator:separator calendar:calendar];
                OBASSERT(date != nil);
            } else {
                date = [self _parseDateNaturalLanguage:dateString withDate:startingDate timeSpecific:&timeSpecific useEndOfDuration:useEndOfDuration calendar:calendar error:error];
                if (date == nil) {
                    if (outDate != NULL)
                        *outDate = nil;
                    return NO;
                }
            }
        }
    } else {
	date = startingDate;
        OBASSERT(date != nil);
    }
    
    if (timeString != nil) {
        if (!date) {
            // In case of a nil date, don't crash <bug:///112326> (Crasher: Crash in OFRelativeDateParser: [__NSCFCalendar components:fromDate:]: date cannot be nil), but just log instead.
            NSLog(@"Unable to parse date from string \"%@\"", string);
            NSLog(@"  startingDate %@", startingDate);
            NSLog(@"  calendar %@", calendar);
            NSLog(@"  shortFormat %@", shortFormat);
            NSLog(@"  mediumFormat %@", mediumFormat);
            NSLog(@"  longFormat %@", longFormat);
            NSLog(@"  timeFormat %@", timeFormat);
            NSLog(@"  useEndOfDuration %d", useEndOfDuration);
            NSLog(@"  defaultTimeDateComponents %@", defaultTimeDateComponents);
            if (outDate != NULL)
                *outDate = nil;
            return NO;
        }
        
	date = [calendar dateFromComponents:[self _parseTimeString:timeString meridianString:meridianString withDate:date withTimeFormat:timeFormat calendar:calendar]];
        OBASSERT(date);
    } else {
	static NSRegularExpression *hourCodeRegex = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSString *shortHourString = NSLocalizedStringFromTableInBundle(@"h", @"OFDateProcessing", OMNI_BUNDLE, @"one-letter abbreviation for hour or hours, used for scanning user input. Do NOT add whitespace");
            NSString *hourString = NSLocalizedStringFromTableInBundle(@"hour", @"OFDateProcessing", OMNI_BUNDLE, @"hour, singular, used for scanning user input. Do NOT add whitespace");
            NSString *pluralHourString = NSLocalizedStringFromTableInBundle(@"hours", @"OFDateProcessing", OMNI_BUNDLE, @"hours, plural, used for scanning user input. Do NOT add whitespace");
            NSString *patternString = [NSString stringWithFormat:@"\\d+(%@|%@|%@|h|hour|hours)", shortHourString, hourString, pluralHourString];
            
            __autoreleasing NSError *expressionError = nil;
	    hourCodeRegex = [[NSRegularExpression alloc] initWithPattern:patternString options:0 error:&expressionError];
            if (!hourCodeRegex) {
                NSLog(@"Error creating regular expression: %@", [expressionError toPropertyList]);
                OBASSERT_NOT_REACHED("Fix regular expression");
            }
        });

	OFRegularExpressionMatch *hourCode = [hourCodeRegex of_firstMatchInString:string];
	if (!hourCode && date != nil && !timeSpecific) {
	    date = [self _dateWithDate:date timeComponents:defaultTimeDateComponents calendar:calendar];
	}
    }
    DEBUG_DATE(@"Return date: %@", date);
    //if (!*date) {
    //OBErrorWithInfo(&*error, "date parse error", @"GAH");  
    //return NO;
    //}
    if (outDate != NULL)
        *outDate = date;
    return YES;
}

- (NSDate *)_dateWithDate:(NSDate *)date timeComponents:(NSDateComponents *)timeComponents calendar:(NSCalendar *)calendar;
{
    NSDateComponents *dateComponents = [calendar components:NSCalendarUnitDay|NSCalendarUnitMonth|NSCalendarUnitYear|NSCalendarUnitEra fromDate:date];
    [dateComponents setHour:[timeComponents hour]];
    [dateComponents setMinute:[timeComponents minute]];
    [dateComponents setSecond:[timeComponents second]];
    NSDate *dateWithTime = [calendar dateFromComponents:dateComponents];
    return dateWithTime;
}

- (NSString *)stringForDate:(NSDate *)date withDateFormat:(NSString *)dateFormat withTimeFormat:(NSString *)timeFormat;
{
    
    return [self stringForDate:date withDateFormat:dateFormat withTimeFormat:timeFormat calendar:nil];
}

- (NSString *)stringForDate:(NSDate *)date withDateFormat:(NSString *)dateFormat withTimeFormat:(NSString *)timeFormat calendar:(NSCalendar *)calendar;
{
    if (!calendar)
        calendar = _defaultCalendar();

    NSDateComponents *components = [calendar components:unitFlags fromDate:date];

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    
    [formatter setCalendar:calendar];
    [formatter setLocale:_locale];
    [formatter setDateFormat:dateFormat];
    
    if ([components hour] != NSDateComponentUndefined) 
	[formatter setDateFormat:[[dateFormat stringByAppendingString:@" "] stringByAppendingString:timeFormat]];
    NSString *result = [formatter stringFromDate:date];
    [formatter release];

    return result;
}

#pragma mark -
#pragma mark Private

- (BOOL)_stringIsNumber:(NSString *)string;
{
    //test for just a single number, note that [NSString intValue] won't work since it returns 0 on failure, and 0 is an allowed number
    OFCreateRegularExpression(numberRegex, @"^(\\d*)$");
    OFRegularExpressionMatch *numberMatch = [numberRegex of_firstMatchInString:string];
    return (numberMatch != nil);
}

- (BOOL)_stringMatchesTime:(NSString *)firstString withTimeFormat:(NSString *)timeFormat calendar:(NSCalendar *)calendar;
{
    // see if we have a european date
    OFCreateRegularExpression(timeDotRegex, @"^(\\d{1,2})\\.(\\d{1,2})\\.?(\\d{0,2})$");
    OFCreateRegularExpression(timeFormatDotRegex, @"[HhkK]'?\\.'?[m]");
    BOOL dotMatched = [timeDotRegex hasMatchInString:firstString];
    BOOL timeFormatDotMatched = [timeFormatDotRegex hasMatchInString:timeFormat];
    if (dotMatched && timeFormatDotMatched)
	return YES;
    
    // see if we have some colons in a dately way
    OFCreateRegularExpression(timeColonRegex, @"(\\d{1,2}):(\\d{0,2}):?(\\d{0,2})");
    BOOL colonMatched = [timeColonRegex hasMatchInString:firstString];
    if (colonMatched)
	return YES;
    
    OFCreateRegularExpression(digitRegex, @"\\d");
    if ([digitRegex hasMatchInString:firstString] && ([firstString containsString:AMSymbolForCalendar(calendar)] || [firstString containsString:PMSymbolForCalendar(calendar)]))
        return YES; // Time and meridian in one word

    // see if we match a meridan at the end of our string ("4pm" or "4p"). This doesn't work with meridians other than 'am' and 'pm'.
    OFCreateRegularExpression(timeEndRegex, @"\\d[apAP][mM]?$");
    OFRegularExpressionMatch *timeEndMatch = [timeEndRegex of_firstMatchInString:firstString];
    if (timeEndMatch)
	return YES;
    
    return NO;
}

#if (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE)
static NSString *AMPMSymbolForCalendar(NSCalendar *calendar, BOOL isPM)
{
    static dispatch_once_t onceToken;
    static NSCache *AMCache;
    static NSCache *PMCache;
    dispatch_once(&onceToken, ^{
        AMCache = [[NSCache alloc] init];
        PMCache = [[NSCache alloc] init];
    });
    
    NSString *localeIdentifier = calendar.locale.localeIdentifier;
    
    NSString *symbol = [(isPM ? PMCache : AMCache) objectForKey:localeIdentifier];
    if (!symbol) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setCalendar:calendar];
        [formatter setLocale:calendar.locale];
        
        symbol = [formatter AMSymbol];
        if (!symbol) {
            OBASSERT_NOT_REACHED("Not expecting a nil AM symbol");
            symbol = @"";
        }
        [AMCache setObject:symbol forKey:localeIdentifier];
        
        symbol = [formatter PMSymbol];
        if (!symbol) {
            OBASSERT_NOT_REACHED("Not expecting a nil PM symbol");
            symbol = @"";
        }
        [PMCache setObject:symbol forKey:localeIdentifier];
        
        [formatter release];
        
        symbol = [(isPM ? PMCache : AMCache) objectForKey:localeIdentifier];
        OBASSERT(symbol);
    }

    return symbol;
}
#endif


// Sadly, the -[NSCalendar AMSymbol] and -PMSymbol methods are not included in iOS yet.
static NSString *AMSymbolForCalendar(NSCalendar *calendar)
{
#if (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE)
    return AMPMSymbolForCalendar(calendar, NO/*isPM*/);
#else
    return calendar.AMSymbol;
#endif
}

static NSString *PMSymbolForCalendar(NSCalendar *calendar)
{
#if (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE)
    return AMPMSymbolForCalendar(calendar, YES/*isPM*/);
#else
    return calendar.PMSymbol;
#endif
}

- (BOOL)_isAntemeridianString:(NSString *)string calendar:(NSCalendar *)calendar;
{
    if (([string caseInsensitiveCompare:AMSymbolForCalendar(calendar)] == NSOrderedSame))
        return YES;
    
    // Allow "am", and "a" input in any locale
    return ([string caseInsensitiveCompare:@"a"] == NSOrderedSame) || ([string caseInsensitiveCompare:@"am"] == NSOrderedSame);
}

- (BOOL)_isPostmeridianString:(NSString *)string calendar:(NSCalendar *)calendar;
{
    if (([string caseInsensitiveCompare:PMSymbolForCalendar(calendar)] == NSOrderedSame))
        return YES;
    
    // Allow "pm", and "p" input in any locale
    return ([string caseInsensitiveCompare:@"p"] == NSOrderedSame) || ([string caseInsensitiveCompare:@"pm"] == NSOrderedSame);
}

- (BOOL)_isMeridianString:(NSString *)string calendar:(NSCalendar *)calendar;
{
    return [self _isAntemeridianString:string calendar:calendar] || [self _isPostmeridianString:string calendar:calendar];
}

- (NSDateComponents *)_parseTimeString:(NSString *)timeString meridianString:(NSString *)meridianString withDate:(NSDate *)date withTimeFormat:(NSString *)timeFormat calendar:(NSCalendar *)calendar;
{
    OBPRECONDITION([timeString isEqual:[timeString stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace]], "The caller already collapsed whitespace and broke components up by spaces");

    if (!meridianString) {
        // The time and meridian might have been combined
        NSInteger letterIndex = [timeString rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].location;
        NSInteger digitIndex = [timeString rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location;
        if (letterIndex != NSNotFound && digitIndex != NSNotFound) {
            // Need to strip surrounding whitespace if we get here from the explicit '@' case with something like '@5 pm'
            if (letterIndex == 0) {
                // 下午4:00
                meridianString = [[timeString substringToIndex:digitIndex] stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace];
                timeString = [[timeString substringFromIndex:digitIndex] stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace];
            } else {
                // 4pm
                meridianString = [[timeString substringFromIndex:letterIndex] stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace];
                timeString = [[timeString substringToIndex:letterIndex] stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace];
            }
        }
    }

    BOOL isPM = meridianString ? [self _isPostmeridianString:meridianString calendar:calendar] : NO;
    
    static dispatch_once_t onceToken;
    static NSRegularExpression *timeSeperatorRegex = nil;
    dispatch_once(&onceToken, ^{
	timeSeperatorRegex = _createRegex(@"^\\d{1,4}([:.])?");
    });
    OFRegularExpressionMatch *timeSeperatorMatch = [timeSeperatorRegex of_firstMatchInString:timeString];
    DEBUG_DATE(@"timeSeperatorMatch = %@", timeSeperatorMatch);
    NSString *separator = [timeSeperatorMatch captureGroupAtIndex:0];
    if ([NSString isEmptyString:separator])
	separator = @":";

    NSArray *timeComponents = [[timeString stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace] componentsSeparatedByString:separator];
    DEBUG_DATE( @"TimeToken: %@, isPM: %d", timeToken, isPM);
    DEBUG_DATE(@"time comps: %@", timeComponents);
    
    int hours = -1;
    int minutes = -1;
    int seconds = -1;
    unsigned int timeMarker;
    for (timeMarker = 0; timeMarker < [timeComponents count]; ++timeMarker) {
	switch (timeMarker) {
	    case 0:
		hours = [[timeComponents objectAtIndex:timeMarker] intValue];
		break;
	    case 1:
		minutes = [[timeComponents objectAtIndex:timeMarker] intValue];
		break;
	    case 2:
		seconds = [[timeComponents objectAtIndex:timeMarker] intValue];
		break;
	}
    }
    if (isPM && hours < 12) {
	DEBUG_DATE(@"isPM was true, adding 12 to: %d", hours);
	hours += 12;
    }  else if ([[timeComponents objectAtIndex:0] length] == 4 && [timeComponents count] == 1 && hours <= 2500 ) {
	//24hour time
	minutes = hours % 100;
	hours = hours / 100;
	DEBUG_DATE(@"time in 4 digit notation");
    } else if (![timeFormat hasPrefix:@"H"] && ![timeFormat hasPrefix:@"k"] && hours == 12 && !isPM) {
	DEBUG_DATE(@"time format doesn't have 'H', at 12 hours, setting to 0");
	hours = 0;
    }
    
    // if 1-24 "k" format, then 24 means 0
    if ([timeFormat hasPrefix:@"k"]) { 
	if (hours == 24) {
	    DEBUG_DATE(@"time format has 'k', at 24 hours, setting to 0");
	    hours = 0;
	}
	
    }
    DEBUG_DATE( @"hours: %d, minutes: %d, seconds: %d", hours, minutes, seconds );
    if (hours == -1)
	return nil;
    
    OBASSERT(date);
    NSDateComponents *components = [calendar components:unitFlags fromDate:date];
    if (seconds != -1)
	[components setSecond:seconds];
    else
	[components setSecond:0];
    
    if (minutes != -1) 
	[components setMinute:minutes];
    else
	[components setMinute:0];
    
    if (hours != -1)
	[components setHour:hours];
    
    return components;
}

- (NSDate *)_parseFormattedDate:(NSString *)dateString withDate:(NSDate *)date withShortDateFormat:(NSString *)shortFormat withMediumDateFormat:(NSString *)mediumFormat withLongDateFormat:(NSString *)longFormat withseparator:(NSString *)separator calendar:(NSCalendar *)calendar;
{
    OBPRECONDITION(calendar);
    
    DEBUG_DATE(@"parsing formatted dateString: %@", dateString );
    NSDateComponents *currentComponents = [calendar components:unitFlags fromDate:date]; // the given date as components
    
    OBASSERT(separator);
    NSMutableArray *dateComponents = [NSMutableArray arrayWithArray:[dateString componentsSeparatedByString:separator]];
    if ([NSString isEmptyString:[dateComponents lastObject]]) 
	[dateComponents removeLastObject];
    
    DEBUG_DATE(@"determined date components as: %@", dateComponents);
    
    NSString *dateFormat = shortFormat;
    OFCreateRegularExpression(mediumMonthRegex, @"[a-z]{3}");
    OFRegularExpressionMatch *mediumMonthMatch = [mediumMonthRegex of_firstMatchInString:dateString];
    if (mediumMonthMatch) {
	DEBUG_DATE(@"using medium format: %@", mediumFormat);
	dateFormat = mediumFormat;
    } else {
	OFCreateRegularExpression(longMonthRegex, @"[a-z]{3,}");
	OFRegularExpressionMatch *longMonthMatch = [longMonthRegex of_firstMatchInString:dateString];
	if (longMonthMatch) {
	    DEBUG_DATE(@"using long format: %@", longFormat);
	    dateFormat = longFormat;
	}
    }
    DEBUG_DATE(@"using date format: %@", dateFormat);
    OFCreateRegularExpression(formatseparatorRegex, @"^\\w+([\\./-])");
    OFRegularExpressionMatch *formattedDateMatch = [formatseparatorRegex of_firstMatchInString:dateFormat];
    NSString *formatStringseparator = nil;
    if (formattedDateMatch)
	formatStringseparator = [formattedDateMatch captureGroupAtIndex:0];
    
    
    DatePosition datePosition;
    if ([separator isEqualToString:@"-"] && ![formatStringseparator isEqualToString:@"-"]) { // use (!mediumMonthMatch/longMonthMatch instead of formatStringseparator?
	DEBUG_DATE(@"setting ISO DASH order, formatseparator: %@", formatStringseparator);
	datePosition.year = 1;
	datePosition.month = 2;
	datePosition.day = 3;
	datePosition.separator = @"-";
    } else {
	DEBUG_DATE(@"using DETERMINED, formatseparator: %@", formatStringseparator);
	datePosition= [self _dateElementOrderFromFormat:dateFormat];
    }
    
    // <bug://bugs/39123> 
    NSUInteger count = [dateComponents count];
    if (count == 2) {
	DEBUG_DATE(@"only 2 numbers, one needs to be the day, the other the month, if the month comes before the day, and the month comes before the year, then assign the first number to the month");
	if (datePosition.month >= 2 && datePosition.day == 1) {
	    datePosition.month = 2;
	    datePosition.year = 3;
	} else if (datePosition.month <= 2 && datePosition.day == 3) {
	    datePosition.month = 1;
	    datePosition.day = 2;
	    datePosition.year = 3;
	} 
    }
    
    OBASSERT(datePosition.day != 0);
    OBASSERT(datePosition.month != 0);
    OBASSERT(datePosition.year != 0);
    
    DEBUG_DATE(@"the date positions being used to assign are: day:%ld month:%ld, year:%ld", datePosition.day, datePosition.month, datePosition.year);
    
    DateSet dateSet = [self _dateSetFromArray:dateComponents withPositions:datePosition];
    DEBUG_DATE(@"date components: %@, SETTING TO: day:%ld month:%ld, year:%ld", dateComponents, dateSet.day, dateSet.month, dateSet.year);
    if (dateSet.day == -1 && dateSet.month == -1 && dateSet.year == -1)
	return nil;
        
    // set unset year to next year
    if (dateSet.year == -1) {
	if (dateSet.month < [currentComponents month])
	    dateSet.year = [currentComponents year]+1;
    }
	
    // set the month day and year components if they exist
    if (dateSet.day > 0)
	[currentComponents setDay:dateSet.day];
    else
	[currentComponents setDay:1];
    
    if (dateSet.month > 0)
	[currentComponents setMonth:dateSet.month];
    
    if (dateSet.year > 0)
	[currentComponents setYear:dateSet.year];
    
    DEBUG_DATE(@"year: %ld, month: %ld, day: %ld", [currentComponents year], [currentComponents month], [currentComponents day]);
    date = [calendar dateFromComponents:currentComponents];
    return date;
}

- (DateSet)_dateSetFromArray:(NSArray *)dateComponents withPositions:(DatePosition)datePosition;
{
    DateSet dateSet;
    dateSet.day = -1;
    dateSet.month = -1;
    dateSet.year = -1;
    
    NSUInteger count = [dateComponents count];
    DEBUG_DATE(@"date components: %@, day:%ld month:%ld, year:%ld", dateComponents, datePosition.day, datePosition.month, datePosition.year);
    /**Initial Setting**/
    BOOL didSwap = NO;
    // day
    if (datePosition.day <= count) {
	dateSet.day= [[dateComponents objectAtIndex:datePosition.day-1] intValue];
	if (dateSet.day == 0) {
	    // the only way for zero to get set is for intValue to be unable to return an int, which means its probably a month, swap day and month
	    NSInteger position = datePosition.day;
	    datePosition.day = datePosition.month;
	    datePosition.month = position;
	    dateSet.day= [[dateComponents objectAtIndex:datePosition.day-1] intValue];
	    didSwap = YES;
	}
    }
    
    // year
    BOOL readYear = NO;
    if (datePosition.year <= count) {
	readYear = YES;
	dateSet.year = [[dateComponents objectAtIndex:datePosition.year-1] intValue];
	if (dateSet.year == 0) {
	    NSString *yearString = [[dateComponents objectAtIndex:datePosition.year-1] lowercaseString];
	    if (![yearString hasPrefix:@"0"])
		dateSet.year = -1;
	    if (dateSet.year == -1 && !didSwap) {
		// the only way for zero to get set is for intValue to be unable to return an int, which means its probably a month, swap day and month
		NSInteger position = datePosition.year;
		datePosition.year = datePosition.month;
		datePosition.month = position;
		dateSet.year = [[dateComponents objectAtIndex:datePosition.year-1] intValue];
	    }
	}
    }
    // month
    if (datePosition.month <= count) {
	NSString *monthName = [[dateComponents objectAtIndex:datePosition.month-1] lowercaseString];
	
	NSString *match;
	NSEnumerator *monthEnum = [_months objectEnumerator];
	while ((match = [monthEnum nextObject]) && dateSet.month == -1) {
	    match = [match lowercaseString];
	    if ([match isEqualToString:monthName]) {
		dateSet.month = [self _monthIndexForString:match];
	    }
	}
	NSEnumerator *shortMonthEnum = [_shortmonths objectEnumerator];
	while ((match = [shortMonthEnum nextObject]) && dateSet.month == -1) {
	    match = [match lowercaseString];
	    if ([match isEqualToString:monthName]) {
		dateSet.month = [self _monthIndexForString:match];
	    }
	}
	NSEnumerator *alternateShortmonthEnum = [_alternateShortmonths objectEnumerator];
	while ((match = [alternateShortmonthEnum nextObject]) && dateSet.month == -1) {
	    match = [match lowercaseString];
	    if ([match isEqualToString:monthName]) {
		dateSet.month = [self _monthIndexForString:match];
	    }
	}
	
	if (dateSet.month == -1 )
	    dateSet.month = [monthName intValue];
	else
	    dateSet.month++;	
    }	
    
    /**Sanity Check**/
    int sanity = 2;
    while (sanity--) {
	DEBUG_DATE(@"%d SANITY: day: %ld month: %ld year: %ld", sanity, dateSet.day, dateSet.month, dateSet.year);
	if (count == 1) {
	    if (dateSet.day > 31) {
		DEBUG_DATE(@"single digit is too high for a day, set to year: %ld", dateSet.day);
		dateSet.year = dateSet.day;
		dateSet.day = -1;
	    } else if (dateSet.month > 12 ) {
		DEBUG_DATE(@"single digit is too high for a day, set to month: %ld", dateSet.month);
		dateSet.day = dateSet.month;
		dateSet.month = -1;
	    }
	} else if (count == 2) {
	    if (dateSet.day > 31) {
		DEBUG_DATE(@"swap day and year");
		NSInteger year = dateSet.year;
		dateSet.year = dateSet.day;
		dateSet.day = year;
	    } else if (dateSet.month > 12 ) {
		DEBUG_DATE(@"swap month and year");
		NSInteger year = dateSet.year;
		dateSet.year = dateSet.month;
		dateSet.month = year;
	    } else if (dateSet.day > 0 && dateSet.year > 0 && dateSet.month < 0 ) {
		DEBUG_DATE(@"swap month and day");
		NSInteger day = dateSet.day;
		dateSet.day = dateSet.month;
		dateSet.month = day;
	    }
	}else if (count == 3 ) {
	    DEBUG_DATE(@"sanity checking a 3 compoent date. Day: %ld, Month: %ld Year: %ld", dateSet.day, dateSet.month, dateSet.year);
	    if (dateSet.day > 31) {
		DEBUG_DATE(@"swap day and year");
		NSInteger year = dateSet.year;
		dateSet.year = dateSet.day;
		dateSet.day = year;
	    } else if (dateSet.month > 12 && dateSet.day <= 31 && dateSet.year <= 12) {
		DEBUG_DATE(@"swap month and year");
		NSInteger year = dateSet.year;
		dateSet.year = dateSet.month;
		dateSet.month = year;
	    } else if ( dateSet.day <= 12 && dateSet.month > 12 ) {
		DEBUG_DATE(@"swap day and month");
		NSInteger day = dateSet.day;
		dateSet.day = dateSet.month;
		dateSet.month = day;
	    }
	    DEBUG_DATE(@"after any swaps we're now at: Day: %ld, Month: %ld Year: %ld", dateSet.day, dateSet.month, dateSet.year);
	}
    }
    
    // unacceptable date
    if (dateSet.month > 12 || dateSet.day > 31) {
	DEBUG_DATE(@"Insane Date, month: %ld is greater than 12, or day: %ld is greater than 31", dateSet.month, dateSet.day);
	dateSet.day = -1;
	dateSet.month = -1;
	dateSet.year = -1;    
	return dateSet;
    }
    
    // fiddle with year
    if (readYear) {
	if (dateSet.year >= 90 && dateSet.year <= 99)
	    dateSet.year += 1900;
	else if (dateSet.year < 90)
	    dateSet.year +=2000;
    } 
 
    return dateSet;
}

- (BOOL)shouldUseFallbackParser;
{
    return OFISEQUAL(_locale.localeIdentifier, FallbackLocaleIdentifier);
}

- (NSDate *)_parseDateNaturalLanguage:(NSString *)dateString withDate:(NSDate *)date timeSpecific:(BOOL *)timeSpecific useEndOfDuration:(BOOL)useEndOfDuration calendar:(NSCalendar *)calendar error:(NSError **)outError;
{
    NSDate *returnValue = [self _parseDateNaturalLanguage:dateString withDate:date timeSpecific:timeSpecific useEndOfDuration:useEndOfDuration calendar:calendar relativeDateNames:_relativeDateNames error:outError];
    if (returnValue == nil && ![self shouldUseFallbackParser])
        returnValue = [[[self class] _fallbackParser] _parseDateNaturalLanguage:dateString withDate:date timeSpecific:timeSpecific useEndOfDuration:useEndOfDuration calendar:calendar error:NULL];
    return returnValue;
}

- (NSDate *)_parseDateNaturalLanguage:(NSString *)dateString withDate:(NSDate *)date timeSpecific:(BOOL *)timeSpecific useEndOfDuration:(BOOL)useEndOfDuration calendar:(NSCalendar *)calendar relativeDateNames:(NSDictionary *)relativeDateNames error:(NSError **)outError;
{
    DEBUG_DATE(@"Parse Natural Language Date String (before normalization): \"%@\"", dateString );
    
    dateString = [dateString stringByNormalizingWithOptions:OFRelativeDateParserNormalizeOptionsDefault locale:[self locale]];

    DEBUG_DATE(@"Parse Natural Language Date String (after normalization): \"%@\"", dateString );

    OFRelativeDateParserRelativity modifier = OFRelativeDateParserNoRelativity; // look for a modifier as the first part of the string
    NSDateComponents *currentComponents = [calendar components:unitFlags fromDate:date]; // the given date as components
    
    DEBUG_DATE(@"PRE comps. m: %ld, d: %ld, y: %ld", [currentComponents month], [currentComponents day], [currentComponents year]);
    int multiplier = [self _multiplierForModifer:modifier];
    
    NSInteger month = -1;
    NSInteger weekday = -1;
    NSInteger day = -1;
    NSInteger year = -1;
    NSDateComponents *componentsToAdd = [[[NSDateComponents alloc] init] autorelease];
    
    int number = -1;
    DPCode dpCode = -1;
    dateString = [dateString stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace];
    NSScanner *scanner = [NSScanner localizedScannerWithString:dateString];
    NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet];
    [scanner setCaseSensitive:NO];
    BOOL needToProcessNumber = NO;
    BOOL modifierForNumber = NO;
    BOOL daySpecific = NO;
    while (![scanner isAtEnd] || needToProcessNumber) {
	[scanner scanCharactersFromSet:whitespaceCharacterSet intoString:NULL];
	
	BOOL scanned = NO;	
	BOOL isYear = NO;
	BOOL isTickYear = NO;
	if (![scanner isAtEnd]) {
	    
	    // relativeDateNames
	    {
		// use a reverse sorted key array so that abbreviations come last
		NSMutableArray *sortedKeyArray = [relativeDateNames mutableCopyKeys];
                [sortedKeyArray sortUsingSelector:@selector(caseInsensitiveCompare:)];
                [sortedKeyArray reverse];
		for(NSString *name in sortedKeyArray) {
		    NSString *match;
                    NSUInteger savedScanLocation = [scanner scanLocation];
		    if ([scanner scanString:name intoString:&match]) {
                        // This is pretty terrible. We frontload parsing of relative day names, but we shouldn't consume 'dom' (Italian) if the user entered 'Domenica'.
                        // If we are in the middle of a word, don't consume the match.
                        // When we clean up this code (rewrite the parsing loop?) we should probably make it so that we have a flattened list of words and associated quanitites that we parse all at once, preferring longest match.
                        if (![scanner isAtEnd]) {
                            unichar ch = [[scanner string] characterAtIndex:[scanner scanLocation]];
                            if ([[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:ch]) {
                                [scanner setScanLocation:savedScanLocation];
                                continue;
                            }
                        }
                    
                    
			// array info: Code, Number, Relativitity, timeSpecific, monthSpecific, daySpecific
			NSArray *dateOffset = [relativeDateNames objectForKey:match];
			DEBUG_DATE(@"found relative date match: %@", match);
			daySpecific = [[dateOffset objectAtIndex:5] boolValue];
			*timeSpecific = [[dateOffset objectAtIndex:3] boolValue];
			if (!*timeSpecific) {
			    // clear times
			    [currentComponents setHour:0];
			    [currentComponents setMinute:0];
			    [currentComponents setSecond:0];
			}
			
			BOOL monthSpecific = [[dateOffset objectAtIndex:4] boolValue];
			if (!monthSpecific) 
			    [currentComponents setMonth:1];
			 			
			// apply the codes from the dateOffset array
			int codeInt = [[dateOffset objectAtIndex:1] intValue];
			if (codeInt != 0) {
			    int codeString = [[dateOffset objectAtIndex:0] intValue];
			    if (codeString == DPHour)
				*timeSpecific = YES;
			    
			    [self _addToComponents:currentComponents codeString:codeString codeInt:codeInt withMultiplier:[self _multiplierForModifer:[[dateOffset objectAtIndex:2] intValue]]];
			}
		    }
		}
                [sortedKeyArray release];
	    }
	    
	    // specialCaseTimeNames
	    {
		// use a reverse sorted key array so that abbreviations come last
                NSMutableArray *sortedKeyArray = [_specialCaseTimeNames mutableCopyKeys];
		[sortedKeyArray sortUsingSelector:@selector(caseInsensitiveCompare:)];
                [sortedKeyArray reverse];
		for(NSString *name in sortedKeyArray) {
		    NSString *match;
		    if ([scanner scanString:name intoString:&match]) {
			DEBUG_DATE(@"found special case match: %@", match);
			daySpecific = YES;
			if (!*timeSpecific) {
			    // clear times
			    [currentComponents setHour:0];
			    [currentComponents setMinute:0];
			    [currentComponents setSecond:0];
			}
			
			NSString *dayName;
			if (useEndOfDuration) 
			    dayName = [_weekdays lastObject];
			else 
			    dayName = [_weekdays objectAtIndex:0];
			
			NSString *start_end_of_next_week = [NSString stringWithFormat:@"+ %@", dayName];
			NSString *start_end_of_last_week = [NSString stringWithFormat:@"- %@", dayName];
			NSString *start_end_of_this_week = [NSString stringWithFormat:@"~ %@", dayName];
			NSDictionary *keywordDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
							   start_end_of_next_week, @"START_END_OF_NEXT_WEEK",
							   start_end_of_last_week, @"START_END_OF_LAST_WEEK",
							   start_end_of_this_week, @"START_END_OF_THIS_WEEK", 
							   nil];
			
			NSString *replacementString = [[_specialCaseTimeNames objectForKey:match] stringByReplacingKeysInDictionary:keywordDictionary startingDelimiter:@"$(" endingDelimiter:@")" removeUndefinedKeys:YES];
			DEBUG_DATE(@"found: %@, replaced with: %@ from dict: %@", [_specialCaseTimeNames objectForKey:match], replacementString, keywordDictionary);
			date = [self _parseDateNaturalLanguage:replacementString withDate:date timeSpecific:timeSpecific useEndOfDuration:useEndOfDuration calendar:calendar relativeDateNames:relativeDateNames error:outError];
			currentComponents = [calendar components:unitFlags fromDate:date]; // update the components
			DEBUG_DATE(@"RETURN from replacement call");
		    }
		}
		[sortedKeyArray release];
	    }
	   	    
	    // check for any modifier after we check the relative date names, as the relative date names can be phrases that we want to match with
	    NSEnumerator *patternEnum = [_modifiers keyEnumerator];
	    NSString *pattern;
	    while ((pattern = [patternEnum nextObject])) {
		NSString *match;
		if ([scanner scanString:pattern intoString:&match]) {
		    modifier = [[_modifiers objectForKey:pattern] intValue];
		    DEBUG_DATE(@"Found Modifier: %@", match);
		    multiplier = [self _multiplierForModifer:modifier];
		    modifierForNumber = YES;
		}
	    } 
	    
	    // test for month names, but only match full months here (to avoid ambiguity with partial conflicts. i.e. mar could be Marzo or Martes in Spanish)
            if (month == -1) {
                for (NSString *name in _months) {
                    NSString *match;
                    NSUInteger savedScanLocation = [scanner scanLocation];
                    if ([scanner scanString:name intoString:&match]) {

                        // don't consume a partial match
                        if (![scanner isAtEnd]) {
                            unichar ch = [[scanner string] characterAtIndex:[scanner scanLocation]];
                            if ([[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:ch]) {
                                [scanner setScanLocation:savedScanLocation];
                                continue;
                            }
                        }

                        month = [self _monthIndexForString:match];
                        scanned = YES;
                        DEBUG_DATE(@"matched name: %@ to match: %@", name, match);
                        break;
                    }

                    if (month != -1)
                        break;
                }            
            }

	    //look for a year '
	    if ([scanner scanString:@"'" intoString:NULL]) {
		isYear = YES;
		isTickYear = YES;
		scanned = YES;
	    } 
	    [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
	}
	
	if (number != -1) {
	    needToProcessNumber = NO;

            NSArray *keys = [_codes allKeys];
            NSDictionary *codesTable = _codes;
            NSArray *sortedKeyArray = [keys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
            NSEnumerator *codeEnum = [[sortedKeyArray reversedArray] objectEnumerator];
            NSString *codeString = nil;
            BOOL foundCode = NO;
            while ((codeString = [codeEnum nextObject]) && !foundCode && (![scanner isAtEnd])) {
                if ([scanner scanString:codeString intoString:NULL]) {
                    dpCode = [[codesTable objectForKey:codeString] intValue];
                    if (number != 0) // if we aren't going to add anything don't call
                        [self _addToComponents:componentsToAdd codeString:dpCode codeInt:number withMultiplier:multiplier];
                    DEBUG_DATE( @"codeString:%@, number:%d, mult:%d", codeString, number, multiplier );
                    daySpecific = YES;
                    isYear = NO; // '97d gets you 97 days
                    foundCode = YES;
                    scanned = YES;
                    modifierForNumber = NO;
                    number = -1;
                }
            }

	    if (isYear) {
		year = number;
		number = -1;
	    } else if (!foundCode) {
		if (modifierForNumber) {
		    // we had a modifier with no code attached, assume day
		    if (day == -1) {
			if (number < 31 )
			    day = number;
			else
			    year = number;
		    } else {
			year = number;
		    }
		    modifierForNumber = NO;
		    daySpecific = YES;
		    DEBUG_DATE(@"free number, marking added to day as true");
		} else if (number > 31 || day != -1) {
		    year = number;
		    if (year > 90 && year < 100)
			year += 1900;
		    else if (year < 90)
			year +=2000;
		} else {
		    day = number;
		    daySpecific = YES;
		}
		number = -1;  
	    } else if (isTickYear) {
		if (year > 90)
		    year += 1900;
		else 
		    year +=2000;
	    }
	}

        // scan weekday names
        if (weekday == -1) {
            for (NSString *name in _weekdays) {
                NSString *match;
                if ([scanner scanString:name intoString:&match]) {
                    weekday = [self _weekdayIndexForString:match];
                    daySpecific = YES;
                    scanned = YES;
                    DEBUG_DATE(@"matched name: %@ to match: %@ weekday: %ld", name, match, weekday);
                }
            }
        }
        [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];

	// scan short weekdays after codes to allow for months to be read instead of mon
	if (weekday == -1) {
            for (NSString *name in _shortdays) {
		NSString *match;
		if ([scanner scanString:name intoString:&match]) {
		    weekday = [self _weekdayIndexForString:match];
		    daySpecific = YES;
		    scanned = YES;
		    DEBUG_DATE(@"matched name: %@ to match: %@", name, match);
		}
	    }
	}
	[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
        
        // scan the alternate short weekdays (stripped of punctuation)
	if (weekday == -1) {
            for (NSString *name in _alternateShortdays) {
		NSString *match;
		if ([scanner scanString:name intoString:&match]) {
		    weekday = [self _weekdayIndexForString:match];
		    daySpecific = YES;
		    scanned = YES;
		    DEBUG_DATE(@"matched name: %@ to match: %@", name, match);
		}
	    }
	}
	[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];

        // scan short month names after scanning weekday names
        if (month == -1) {
            for (NSString *name in _shortmonths) {
                NSString *match;
                if ([scanner scanString:name intoString:&match]) {
                    month = [self _monthIndexForString:match];
                    scanned = YES;
                    DEBUG_DATE(@"matched name: %@ to match: %@", name, match);
                }
            }
        }
        [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];

        // scan the alternate short month names (stripped of punctuation)
        if (month == -1) {
            for (NSString *name in _alternateShortmonths) {
                NSString *match;
                if ([scanner scanString:name intoString:&match]) {
                    month = [self _monthIndexForString:match];
                    scanned = YES;
                    DEBUG_DATE(@"matched name: %@ to match: %@", name, match);
                }
            }
        }
        [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
	// scan english short weekdays after codes to allow for months to be read instead of mon
	if (weekday == -1) {
	    NSEnumerator *shortdaysEnum = [englishShortdays objectEnumerator];
	    NSString *name;
	    while ((name = [shortdaysEnum nextObject])) {
		NSString *match;
		if ([scanner scanString:name intoString:&match]) {
		    weekday = [self _weekdayIndexForString:match];
		    daySpecific = YES;
		    scanned = YES;
		    DEBUG_DATE(@"ENGLISH matched name: %@ to match: %@", name, match);
		}
	    }
	}
	[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
	
	if (weekday != -1) {
	    date = [self _modifyDate:date withWeekday:weekday withModifier:modifier calendar:calendar];
	    currentComponents = [calendar components:unitFlags fromDate:date];
	    weekday = -1;
	    modifier = 0;
	    multiplier = [self _multiplierForModifer:modifier];
	}
	
	//check for any modifier again, before checking for numbers, so that we can record the proper modifier
	NSEnumerator *patternEnum = [_modifiers keyEnumerator];
	NSString *pattern;
	while ((pattern = [patternEnum nextObject])) {
	    NSString *match;
	    if ([scanner scanString:pattern intoString:&match]) {
		modifier = [[_modifiers objectForKey:pattern] intValue];
		multiplier = [self _multiplierForModifer:modifier];
		modifierForNumber = YES;
	    }
	} 
	
	// look for a number
	if ([scanner scanInt:&number]) {
	    needToProcessNumber = YES;
	    scanned = YES;
	}
	[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
	
	// eat any punctuation
	BOOL punctuation = NO;
	if ([scanner scanCharactersFromSet:[NSCharacterSet punctuationCharacterSet] intoString:NULL]) {
	    DEBUG_DATE(@"scanned some symbols");
	    punctuation = YES;
	}
	
	if ([scanner scanLocation] == [[scanner string] length] && !needToProcessNumber) {
	    break;
	} else {
	    if (!scanned) {
		[scanner setScanLocation:[scanner scanLocation]+1];
	    }
	}
	DEBUG_DATE(@"end of scanning cycle. month: %ld, day: %ld, year: %ld, weekday: %ld, number: %d, modifier: %d", month, day, year, weekday, number, multiplier);
	//OBError(&*error, // error
	//		0,  // code enum
	//		@"we were unable to parse something, return an error for string" // description
	//		);
	if (number == -1 && !scanned) {
	    if (!punctuation) {
		DEBUG_DATE(@"ERROR String: %@, number: %d loc: %ld", dateString, number, [scanner scanLocation]);
		return nil;
	    }
	}
	
    } // scanner
    
    if (!daySpecific) {
	if (useEndOfDuration) {
	    // find the last day of the month of the components ?
	}
	day = 1;
	DEBUG_DATE(@"setting the day to 1 as a default");
    }
    if (day != -1) {
	[currentComponents setDay:day];
    }
    
    // TODO: default month?
    if (month != -1) {
	if (useEndOfDuration) {
	    // find the last month of the year ?
	}
	month+=1;
	[currentComponents setYear:[self _determineYearForMonth:month withModifier:modifier fromCurrentMonth:[currentComponents month] fromGivenYear:[currentComponents year]]];
	[currentComponents setMonth:month];
    }
    
    // TODO: default year?
    if (year != -1) 
	[currentComponents setYear:year];
    
    date = [calendar dateFromComponents:currentComponents];
    DEBUG_DATE(@"comps. m: %ld, d: %ld, y: %ld", [currentComponents month], [currentComponents day], [currentComponents year]);
    DEBUG_DATE(@"date before modifying with the components: %@", date) ;

    // componetsToAdd is all of the collected relative date codes
    date = [calendar dateByAddingComponents:componentsToAdd toDate:date options:0];
    return date;
}

- (int)_multiplierForModifer:(int)modifier;
{
    if (modifier == OFRelativeDateParserPastRelativity)
	return -1;
    return 1;
}

- (NSUInteger)_monthIndexForString:(NSString *)token;
{
    // return the the value of the month according to its position on the array, or -1 if nothing matches.
    NSUInteger monthIndex = [_months count];
    while (monthIndex--) {
	if ([token isEqualToString:[_shortmonths objectAtIndex:monthIndex]] || [token isEqualToString:[_alternateShortmonths objectAtIndex:monthIndex]] || [token isEqualToString:[_months objectAtIndex:monthIndex]]) {
	    return monthIndex;
	}
    }
    return -1;
}

- (NSUInteger)_weekdayIndexForString:(NSString *)token;
{
    // return the the value of the weekday according to its position on the array, or -1 if nothing matches.
    
    NSUInteger dayIndex = [_weekdays count];
    token = [token lowercaseString];
    while (dayIndex--) {
        DEBUG_DATE(@"token: %@, weekdays: %@, short: %@, Ewdays: %@, EShort: %@", token, [[_weekdays objectAtIndex:dayIndex] lowercaseString], [[_shortdays objectAtIndex:dayIndex] lowercaseString], [[englishWeekdays objectAtIndex:dayIndex] lowercaseString], [[englishShortdays objectAtIndex:dayIndex] lowercaseString]);
	if ([token isEqualToString:[_alternateShortdays objectAtIndex:dayIndex]] ||
            [token isEqualToString:[_shortdays objectAtIndex:dayIndex]] ||
            [token isEqualToString:[_weekdays objectAtIndex:dayIndex]]) {
	    return dayIndex;
        }
	
	// test the english weekdays
	if ([token isEqualToString:[englishShortdays objectAtIndex:dayIndex]] || [token isEqualToString:[englishWeekdays objectAtIndex:dayIndex]])
            return dayIndex;
    }

    DEBUG_DATE(@"weekday index not found for: %@", token);
    
    return -1;
}

- (NSInteger)_determineYearForMonth:(NSUInteger)month withModifier:(OFRelativeDateParserRelativity)modifier fromCurrentMonth:(NSUInteger)currentMonth fromGivenYear:(NSInteger)givenYear;
{
    // current month equals the requested month
    if (currentMonth == month) {
	switch (modifier) {
	    case OFRelativeDateParserFutureRelativity:
		return (givenYear+1);
	    case OFRelativeDateParserPastRelativity:
		return (givenYear-1);
	    default:
		return givenYear;
	} 
    } else if (currentMonth > month) {
	if ( modifier != OFRelativeDateParserPastRelativity ) {
	    return (givenYear +1);
	} 
    } else {
	if (modifier == OFRelativeDateParserPastRelativity) {
	    return (givenYear-1);
	}
    }
    return givenYear;
}

- (NSDate *)_modifyDate:(NSDate *)date withWeekday:(NSUInteger)requestedWeekday withModifier:(OFRelativeDateParserRelativity)modifier calendar:(NSCalendar *)calendar;
{
    OBPRECONDITION(date);
    OBPRECONDITION(calendar);
    
    requestedWeekday+=1; // add one to the index since weekdays are 1 based, but we detect them zero-based
    NSDateComponents *weekdayComp = [calendar components:NSCalendarUnitWeekday fromDate:date];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    NSUInteger currentWeekday = [weekdayComp weekday];
    
    DEBUG_DATE(@"Modifying the date based on weekdays with modifer: %d, Current Weekday: %ld, Requested Weekday: %ld", modifier, currentWeekday, requestedWeekday);
    
    // if there is no modifier then we just take the current day if its a match, or the next instance of the requested day
    if (modifier == OFRelativeDateParserNoRelativity) {
	DEBUG_DATE(@"NO Modifier");
	if (currentWeekday == requestedWeekday) {
	    DEBUG_DATE(@"return today");
            [components release];
	    return date; 
	} else if (currentWeekday > requestedWeekday) {
	    DEBUG_DATE( @"set the weekday to the next instance of the requested day, %ld days in the future", (7-(currentWeekday - requestedWeekday)));
	    [components setDay:(7-(currentWeekday - requestedWeekday))];
	} else if (currentWeekday < requestedWeekday) {
	    DEBUG_DATE( @"set the weekday to the next instance of the requested day, %ld days in the future", (requestedWeekday- currentWeekday) );
	    [components setDay:(requestedWeekday- currentWeekday)];
	}
    } else {
	
	// if there is a modifier, add a week if its "next", sub a week if its "last", or stay in the current week if its "this"
	int dayModification = 0;
	switch(modifier) {    
	    case OFRelativeDateParserNoRelativity:
	    case OFRelativeDateParserCurrentRelativity:
		break;
	    case OFRelativeDateParserFutureRelativity: // "next"
		dayModification = 7;
		DEBUG_DATE(@"CURRENT Modifier \"this\"");
		break;
	    case OFRelativeDateParserPastRelativity: // "last"
		dayModification = -7;
		DEBUG_DATE(@"PAST Modifier \"last\"");
		break;
	}
	
	DEBUG_DATE( @"set the weekday to: %ld days difference from the current weekday: %ld, BUT add %d days", (requestedWeekday- currentWeekday), currentWeekday, dayModification );
	[components setDay:(requestedWeekday- currentWeekday)+dayModification];
    }
    
    NSDate *result = [calendar dateByAddingComponents:components toDate:date options:0];; //return next week
    [components release];
    return result;
}

- (void)_addToComponents:(NSDateComponents *)components codeString:(DPCode)dpCode codeInt:(int)codeInt withMultiplier:(int)multiplier;
{
    codeInt*=multiplier;
    switch (dpCode) {
	case DPHour:
	    if ([components hour] == NSDateComponentUndefined)
		[components setHour:codeInt];
	    else
		[components setHour:[components hour] + codeInt];
	    DEBUG_DATE( @"Added %d hours to the components, now at: %ld hours", codeInt, [components hour] );
	    break;
	    case DPDay:
	    if ([components day] == NSDateComponentUndefined)
		[components setDay:codeInt];
	    else 
		[components setDay:[components day] + codeInt];
	    DEBUG_DATE( @"Added %d days to the components, now at: %ld days", codeInt, [components day] );
	    break;
	    case DPWeek:
	    if ([components day] == NSDateComponentUndefined)
		[components setDay:codeInt*7];
	    else
		[components setDay:[components day] + codeInt*7];
	    DEBUG_DATE( @"Added %d weeks(ie. days) to the components, now at: %ld days", codeInt, [components day] );
	    break;
	    case DPMonth:
	    if ([components month] == NSDateComponentUndefined)
		[components setMonth:codeInt];
	    else 
		[components setMonth:[components month] + codeInt];
	    DEBUG_DATE( @"Added %d months to the components, now at: %ld months", codeInt, [components month] );
	    break;
	    case DPYear:
	    if ([components year] == NSDateComponentUndefined)
		[components setYear:codeInt];
	    else 
		[components setYear:[components year] + codeInt];
	    DEBUG_DATE( @"Added %d years to the components, now at: %ld years", codeInt, [components year] );
	    break;
    }
}

// This group of methods (class and instance) normalize strings for scanning and matching user input.
// We use this to normalize localized strings and user input so that users can type ASCII-equivalent values and still get the benefit of the natural language parser
// See <bug:///73212>

+ (NSDictionary *)_dictionaryByNormalizingKeysInDictionary:(NSDictionary *)dictionary options:(NSUInteger)options locale:(NSLocale *)locale;
{
    OBPRECONDITION(dictionary);
    
    NSMutableDictionary *normalizedDictionary = [NSMutableDictionary dictionary];
    NSEnumerator *keyEnumerator = [dictionary keyEnumerator];
    NSString *key = nil;
    
    while (nil != (key = [keyEnumerator nextObject])) {
        NSString *newKey = [key stringByNormalizingWithOptions:options locale:locale];
        NSString *value = [dictionary objectForKey:key];
        [normalizedDictionary setObject:value forKey:newKey];
    }

    return [[normalizedDictionary copy] autorelease];
}

+ (NSDictionary *)_dictionaryByNormalizingValuesInDictionary:(NSDictionary *)dictionary options:(NSUInteger)options locale:(NSLocale *)locale;
{
    OBPRECONDITION(dictionary);
    
    NSMutableDictionary *normalizedDictionary = [NSMutableDictionary dictionary];
    NSEnumerator *keyEnumerator = [dictionary keyEnumerator];
    NSString *key = nil;
    
    while (nil != (key = [keyEnumerator nextObject])) {
        NSString *value = [[dictionary objectForKey:key] stringByNormalizingWithOptions:options locale:locale];
        [normalizedDictionary setObject:value forKey:key];
    }

    return [[normalizedDictionary copy] autorelease];
}

+ (NSArray *)_arrayByNormalizingValuesInArray:(NSArray *)array options:(NSUInteger)options locale:(NSLocale *)locale;
{
    OBPRECONDITION(array);
    
    NSMutableArray *normalizedArray = [NSMutableArray array];
    
    NSUInteger i, count = [array count];
    for (i = 0; i < count; i++) {
        NSString *string = [[array objectAtIndex:i] stringByNormalizingWithOptions:options locale:locale];
        [normalizedArray addObject:string];
    }
    
    return [[normalizedArray mutableCopy] autorelease];
}

- (NSDictionary *)_dictionaryByNormalizingKeysInDictionary:(NSDictionary *)dictionary options:(NSUInteger)options;
{
    return [[self class] _dictionaryByNormalizingKeysInDictionary:dictionary options:options locale:[self locale]];
}

- (NSDictionary *)_dictionaryByNormalizingValuesInDictionary:(NSDictionary *)dictionary options:(NSUInteger)options;
{
    return [[self class] _dictionaryByNormalizingValuesInDictionary:dictionary options:options locale:[self locale]];
}

- (NSArray *)_arrayByNormalizingValuesInArray:(NSArray *)array options:(NSUInteger)options;
{
    return [[self class] _arrayByNormalizingValuesInArray:array options:options locale:[self locale]];
}

@end

@implementation OFRelativeDateParser (OFInternalAPI)

- (DatePosition)_dateElementOrderFromFormat:(NSString *)dateFormat;
{
    OBASSERT(dateFormat);
    
    DatePosition datePosition;
    datePosition.day = 1;
    datePosition.month = 2;
    datePosition.year = 3;
    datePosition.separator = @" ";
    
    OFCreateRegularExpression(mdyRegex, @"[mM]+(\\s?)(\\S?)(\\s?)d+(\\s?)(\\S?)(\\s?)y+");
    OFRegularExpressionMatch *match = [mdyRegex of_firstMatchInString:dateFormat];
    if (match) {
	datePosition.day = 2;
	datePosition.month = 1;
	datePosition.year = 3;
	datePosition.separator = [match captureGroupAtIndex:0];
	return datePosition;
    }
    
    OFCreateRegularExpression(dmyRegex, @"d+(\\s?)(\\S?)(\\s?)[mM]+(\\s?)(\\S?)(\\s?)y+");
    match = [dmyRegex of_firstMatchInString:dateFormat];
    if (match) {
	datePosition.day = 1;
	datePosition.month = 2;
	datePosition.year = 3;
	datePosition.separator = [match captureGroupAtIndex:0];
	return datePosition;
    }
    
    OFCreateRegularExpression(ymdRegex, @"y+(.*?)[mM]+(.*?)d+");
    match = [ymdRegex of_firstMatchInString:dateFormat];
    if (match) {
	datePosition.day = 3;
	datePosition.month = 2;
	datePosition.year = 1;
	datePosition.separator = [match captureGroupAtIndex:0];
	return datePosition;
    }
    
    OFCreateRegularExpression(ydmRegex, @"y+(\\s?)(\\S?)(\\s?)d+(\\s?)(\\S?)(\\s?)[mM]+");
    match = [ydmRegex of_firstMatchInString:dateFormat];
    if (match) {
	datePosition.day = 2;
	datePosition.month = 3;
	datePosition.year = 1;
	datePosition.separator = [match captureGroupAtIndex:0];
	return datePosition;
    }
    
    // log inavlid dates and use the american default, for now
    
    {
	NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];

	[formatter setDateStyle:NSDateFormatterShortStyle]; 
	[formatter setTimeStyle:NSDateFormatterNoStyle]; 
	NSString *shortFormat = [[[formatter dateFormat] copy] autorelease];
        
	[formatter setDateStyle:NSDateFormatterMediumStyle]; 
	NSString *mediumFormat = [[[formatter dateFormat] copy] autorelease];
        
	[formatter setDateStyle:NSDateFormatterLongStyle]; 
	NSString *longFormat = [[[formatter dateFormat] copy] autorelease];
        
	NSLog(@"**PLEASE REPORT THIS LINE TO: support@omnigroup.com | Unparseable Custom Date Format. Date Format trying to parse is: %@; Short Format: %@; Medium Format: %@; Long Format: %@", dateFormat, shortFormat, mediumFormat, longFormat);
    }
    return datePosition;
}

@end

