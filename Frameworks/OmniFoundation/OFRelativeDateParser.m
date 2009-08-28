// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRelativeDateParser.h>

#import <OmniFoundation/OFPreference.h>

#import <Foundation/NSDateFormatter.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>

#import <OmniFoundation/OFRegularExpression.h>
#import <OmniFoundation/OFRegularExpressionMatch.h>
#import "OFRelativeDateParser-Internal.h"

RCS_ID("$Id$");

// http://icu.sourceforge.net/userguide/formatDateTime.html

static NSDictionary *relativeDateNames;
static NSDictionary *specialCaseTimeNames;
static NSDictionary *codes;
static NSDictionary *modifiers;

static const unsigned unitFlags = NSSecondCalendarUnit | NSMinuteCalendarUnit | NSHourCalendarUnit | NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit | NSEraCalendarUnit;

static OFRelativeDateParser *sharedParser;

// english 
static NSArray *englishWeekdays;
static NSArray *englishShortdays;

//#define DEBUG_date (1)

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

@interface OFRelativeDateParser (Private)
-(int)_multiplierForModifer:(int)modifier;
- (unsigned int)_monthIndexForString:(NSString *)token;
- (unsigned int)_weekdayIndexForString:(NSString *)token;
- (NSDate *)_modifyDate:(NSDate *)date withWeekday:(unsigned int)requestedWeekday withModifier:(OFRelativeDateParserRelativity)modifier;
- (void)_addToComponents:(NSDateComponents *)components codeString:(DPCode)dpCode codeInt:(int)codeInt withMultiplier:(int)multiplier;
- (int)_determineYearForMonth:(unsigned int)month withModifier:(OFRelativeDateParserRelativity)modifier fromCurrentMonth:(unsigned int)currentMonth fromGivenYear:(int)givenYear;
- (NSDateComponents *)parseTime:(NSString *)timeString withDate:(NSDate *)date withTimeFormat:(NSString *)timeFormat;
- (NSDate *)parseFormattedDate:(NSString *)dateString withDate:(NSDate *)date withShortDateFormat:(NSString *)shortFormat withMediumDateFormat:(NSString *)mediumFormat withLongDateFormat:(NSString *)longFormat withseparator:(NSString *)separator;
- (DateSet)_dateSetFromArray:(NSArray *)dateComponents withPositions:(DatePosition)datePosition;
- (NSDate *)parseDateNaturalLangauge:(NSString *)dateString withDate:(NSDate *)date timeSpecific:(BOOL *)timeSpecific useEndOfDuration:(BOOL)useEndOfDuration error:(NSError **)error;
- (BOOL)_stringMatchesTime:(NSString *)firstString optionalSecondString:(NSString *)secondString withTimeFormat:(NSString *)timeFormat;
- (BOOL)_stringIsNumber:(NSString *)string;
@end

@implementation OFRelativeDateParser
// creates a new relative date parser with your current locale
+ (OFRelativeDateParser *)sharedParser;
{
    if (!sharedParser) 
	sharedParser = [[OFRelativeDateParser alloc] initWithLocale:[NSLocale currentLocale]];
    return sharedParser;
}

+ (void)initialize;
{
    OBINITIALIZE;
    specialCaseTimeNames = [[NSDictionary alloc] initWithObjectsAndKeys:
			    @"$(START_END_OF_THIS_WEEK)", NSLocalizedStringFromTableInBundle(@"this week", @"DateProcessing", OMNI_BUNDLE, @"time"),
			    @"$(START_END_OF_NEXT_WEEK)", NSLocalizedStringFromTableInBundle(@"next week", @"DateProcessing", OMNI_BUNDLE, @"time"),
			    @"$(START_END_OF_LAST_WEEK)", NSLocalizedStringFromTableInBundle(@"last week", @"DateProcessing", OMNI_BUNDLE, @"time"),
			    nil];
    // TODO: Can't do seconds offsets for day math due to daylight savings
    // TODO: Make this a localized .plist where it looks something like:
    /*
     "demain" = {day:1}
     "avant-hier" = {day:-2}
     */
    // array info: Code, Number, Relativitity, timeSpecific, monthSpecific, daySpecific
    relativeDateNames = [[NSDictionary alloc] initWithObjectsAndKeys:
			 /* Specified Time, Use Current Time */
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:0], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"now", @"DateProcessing", OMNI_BUNDLE, @"now"), 
			 /* Specified Time*/
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPHour], [NSNumber numberWithInt:12], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"noon", @"DateProcessing", OMNI_BUNDLE, @"noon"), 
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPHour], [NSNumber numberWithInt:23], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"tonight", @"DateProcessing", OMNI_BUNDLE, @"tonight"), 
			 /* Use default time */
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:0], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"today", @"DateProcessing", OMNI_BUNDLE, @"today"), 
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:0], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"tod", @"DateProcessing", OMNI_BUNDLE, @"\"tod\" this should be an abbreviation for \"today\" that makes sense for the given language"), 
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserFutureRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"tomorrow", @"DateProcessing", OMNI_BUNDLE, @"tomorrow"), 
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserFutureRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"tom", @"DateProcessing", OMNI_BUNDLE, @"\"tom\" this should be an abbreviation for \"tomorrow\" that makes sense for the given language"), 
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserPastRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"yesterday", @"DateProcessing", OMNI_BUNDLE, @"yesterday"), 
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPDay], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserPastRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:YES], nil], NSLocalizedStringFromTableInBundle(@"yes", @"DateProcessing", OMNI_BUNDLE, @"\"yes\" this should be an abbreviation for \"yesterday\" that makes sense for the given language"), 
			 /* use default day */
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPMonth], [NSNumber numberWithInt:0], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity],  [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:NO], nil], NSLocalizedStringFromTableInBundle(@"this month", @"DateProcessing", OMNI_BUNDLE, @"this month"),
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPMonth], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserFutureRelativity], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:NO], nil], NSLocalizedStringFromTableInBundle(@"next month", @"DateProcessing", OMNI_BUNDLE, @"next month"), 
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPMonth], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserPastRelativity],  [NSNumber numberWithBool:NO], [NSNumber numberWithBool:YES], [NSNumber numberWithBool:NO], nil], NSLocalizedStringFromTableInBundle(@"last month", @"DateProcessing", OMNI_BUNDLE, @"last month"),
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPYear], [NSNumber numberWithInt:0], [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity],  [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], nil], NSLocalizedStringFromTableInBundle(@"this year", @"DateProcessing", OMNI_BUNDLE, @"this year"), 
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPYear], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserFutureRelativity],  [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], nil], NSLocalizedStringFromTableInBundle(@"next year", @"DateProcessing", OMNI_BUNDLE, @"next year"), 
			 [NSArray arrayWithObjects:[NSNumber numberWithInt:DPYear], [NSNumber numberWithInt:1], [NSNumber numberWithInt:OFRelativeDateParserPastRelativity],  [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], [NSNumber numberWithBool:NO], nil], NSLocalizedStringFromTableInBundle(@"last year", @"DateProcessing", OMNI_BUNDLE, @"last year"),
			 
			 nil];
    
    // short hand codes
    codes = [[NSDictionary alloc] initWithObjectsAndKeys:
	     [NSNumber numberWithInt:DPHour], NSLocalizedStringFromTableInBundle(@"h", @"DateProcessing", OMNI_BUNDLE, @"the first letter of \"hour\""), 
	     [NSNumber numberWithInt:DPHour], NSLocalizedStringFromTableInBundle(@"hour", @"DateProcessing", OMNI_BUNDLE, @"hours"), 
	     [NSNumber numberWithInt:DPHour], NSLocalizedStringFromTableInBundle(@"hours", @"DateProcessing", OMNI_BUNDLE, @"hours"), 
	     [NSNumber numberWithInt:DPDay], NSLocalizedStringFromTableInBundle(@"d", @"DateProcessing", OMNI_BUNDLE, @"the first letter of \"day\""), 
	     [NSNumber numberWithInt:DPDay], NSLocalizedStringFromTableInBundle(@"day", @"DateProcessing", OMNI_BUNDLE, @"days"), 
	     [NSNumber numberWithInt:DPDay], NSLocalizedStringFromTableInBundle(@"days", @"DateProcessing", OMNI_BUNDLE, @"days"), 
	     [NSNumber numberWithInt:DPWeek], NSLocalizedStringFromTableInBundle(@"w", @"DateProcessing", OMNI_BUNDLE, @"weeks"), 
	     [NSNumber numberWithInt:DPWeek], NSLocalizedStringFromTableInBundle(@"week", @"DateProcessing", OMNI_BUNDLE, @"weeks"), 
	     [NSNumber numberWithInt:DPWeek], NSLocalizedStringFromTableInBundle(@"weeks", @"DateProcessing", OMNI_BUNDLE, @"weeks"), 
	     [NSNumber numberWithInt:DPMonth],NSLocalizedStringFromTableInBundle(@"m", @"DateProcessing", OMNI_BUNDLE, @"the first letter of \"month\""), 
	     [NSNumber numberWithInt:DPMonth], NSLocalizedStringFromTableInBundle(@"month", @"DateProcessing", OMNI_BUNDLE, @"month"), 
	     [NSNumber numberWithInt:DPMonth], NSLocalizedStringFromTableInBundle(@"months", @"DateProcessing", OMNI_BUNDLE, @"months"), 
	     [NSNumber numberWithInt:DPYear], NSLocalizedStringFromTableInBundle(@"y", @"DateProcessing", OMNI_BUNDLE, @"the first letter of \"year\""), 
	     [NSNumber numberWithInt:DPYear], NSLocalizedStringFromTableInBundle(@"year", @"DateProcessing", OMNI_BUNDLE, @"years"), 
	     [NSNumber numberWithInt:DPYear], NSLocalizedStringFromTableInBundle(@"years", @"DateProcessing", OMNI_BUNDLE, @"years"),  
	     nil];
    
    // time modifiers
    modifiers = [[NSDictionary alloc] initWithObjectsAndKeys:
		 [NSNumber numberWithInt:OFRelativeDateParserFutureRelativity], NSLocalizedStringFromTableInBundle(@"+", @"DateProcessing", OMNI_BUNDLE, @"modifier"), 
		 [NSNumber numberWithInt:OFRelativeDateParserFutureRelativity], NSLocalizedStringFromTableInBundle(@"next", @"DateProcessing", OMNI_BUNDLE, @"modifier, the most commonly used translation of \"next\", or some other shorthand way of saying things like \"next week\""),  
		 [NSNumber numberWithInt:OFRelativeDateParserPastRelativity], NSLocalizedStringFromTableInBundle(@"-", @"DateProcessing", OMNI_BUNDLE, @"modifier"), 
		 [NSNumber numberWithInt:OFRelativeDateParserPastRelativity], NSLocalizedStringFromTableInBundle(@"last", @"DateProcessing", OMNI_BUNDLE, @"modifier"), 
		 [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], NSLocalizedStringFromTableInBundle(@"~", @"DateProcessing", OMNI_BUNDLE, @"modifier"), 
		 [NSNumber numberWithInt:OFRelativeDateParserCurrentRelativity], NSLocalizedStringFromTableInBundle(@"this", @"DateProcessing", OMNI_BUNDLE, @"modifier, the most commonly used translation of \"this\", or some other shorthand way of saying things like \"this week\""), 
		 nil];
    
    // english 
    [NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4]; 
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease]; 
    NSLocale *en_US = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    [formatter setLocale:en_US];
    englishWeekdays = [[formatter weekdaySymbols] copy];
    englishShortdays = [[formatter shortWeekdaySymbols] copy];
    [en_US release];
}

- initWithLocale:(NSLocale *)locale;
{
    if (![super init])
	return nil;
    [self setLocale:locale];
    return self;
}

- (void) dealloc 
{
    [_locale release];
    [_weekdays release];
    [_shortdays release];
    [_months release];
    [_shortmonths release];
    
    [super dealloc];
}

- (NSLocale *)locale;
{
    return _locale;
}

- (void)setLocale:(NSLocale *)locale;
{
    if (_locale != locale) {
	[_locale release];
	_locale = [locale retain];
	
	//remake the weekday/month name arrays for a new locale
	[NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4]; 
	NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease]; 
	[formatter setLocale:locale];
	
	[_weekdays release];
	_weekdays = [[formatter weekdaySymbols] copy];
	
	[_shortdays release];
	_shortdays = [[formatter shortWeekdaySymbols] copy];
	
	[_months release];
	_months = [[formatter monthSymbols] copy];
	
	[_shortmonths release];
	_shortmonths = [[formatter shortMonthSymbols] copy];
    }
    
}

- (BOOL)getDateValue:(NSDate **)date 
	   forString:(NSString *)string
   	       error:(NSError **)error;
{
    return [self getDateValue:date forString:string useEndOfDuration:NO defaultTimeDateComponents:nil error:error];
}

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string useEndOfDuration:(BOOL)useEndOfDuration defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents error:(NSError **)error;
{
    [NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4]; 
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease]; 
    [formatter setDateStyle:NSDateFormatterShortStyle]; 
    [formatter setTimeStyle:NSDateFormatterNoStyle]; 
    NSMutableString *shortFormat =
    [NSMutableString stringWithString:[formatter dateFormat]];
    [formatter setDateStyle:NSDateFormatterMediumStyle]; 
    NSMutableString *mediumFormat =
    [NSMutableString stringWithString:[formatter dateFormat]];
    [formatter setDateStyle:NSDateFormatterLongStyle]; 
    NSMutableString *longFormat =
    [NSMutableString stringWithString:[formatter dateFormat]];
    
    
    
    [formatter setDateStyle:NSDateFormatterNoStyle]; 
    [formatter setTimeStyle:NSDateFormatterShortStyle]; 
    NSString *timeFormat = [formatter dateFormat]; 
    
    return [self getDateValue:date 
		    forString:string 
	     fromStartingDate:[NSDate date] 
		 withTimeZone:[NSTimeZone localTimeZone] 
       withCalendarIdentifier:NSGregorianCalendar 
	  withShortDateFormat:shortFormat
	 withMediumDateFormat:mediumFormat
	   withLongDateFormat:longFormat
	       withTimeFormat:timeFormat
	     useEndOfDuration:useEndOfDuration
    defaultTimeDateComponents:defaultTimeDateComponents
			error:error];
}

- (BOOL)getDateValue:(NSDate **)date 
	   forString:(NSString *)string 
    fromStartingDate:(NSDate *)startingDate 
	withTimeZone:(NSTimeZone *)timeZone 
withCalendarIdentifier:(NSString *)nsLocaleCalendarKey 
 withShortDateFormat:(NSString *)shortFormat 
withMediumDateFormat:(NSString *)mediumFormat 
  withLongDateFormat:(NSString *)longFormat 
      withTimeFormat:(NSString *)timeFormat
	       error:(NSError **)error;
{
    return [self getDateValue:date 
		    forString:string 
	     fromStartingDate:startingDate 
		 withTimeZone:timeZone 
       withCalendarIdentifier:nsLocaleCalendarKey 
	  withShortDateFormat:shortFormat
	 withMediumDateFormat:mediumFormat
	   withLongDateFormat:longFormat
	       withTimeFormat:timeFormat
	     useEndOfDuration:NO
    defaultTimeDateComponents:nil // not needed for unit tests
			error:error];
}

- (BOOL)getDateValue:(NSDate **)date 
	   forString:(NSString *)string 
    fromStartingDate:(NSDate *)startingDate 
	withTimeZone:(NSTimeZone *)timeZone 
withCalendarIdentifier:(NSString *)nsLocaleCalendarKey 
 withShortDateFormat:(NSString *)shortFormat 
withMediumDateFormat:(NSString *)mediumFormat 
  withLongDateFormat:(NSString *)longFormat 
      withTimeFormat:(NSString *)timeFormat
    useEndOfDuration:(BOOL)useEndOfDuration
defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents
 	       error:(NSError **)error;
{
    
    // return nil instead of the current date on empty string
    if ([NSString isEmptyString:string]) {
	date = nil;
	return YES;
    }
    
    // set the calendar according to the requested calendar and time zone
    currentCalendar = [[[NSCalendar alloc] initWithCalendarIdentifier:nsLocaleCalendarKey] autorelease];
    if ( timeZone != nil )
	[currentCalendar setTimeZone:timeZone];
    
    string = [[string lowercaseString] stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace];
    NSString *dateString = nil;
    NSString *timeString = nil;
    
    // first see if we have an @, if so then we can easily split the date and time portions of the string
    string = [string stringByReplacingAllOccurrencesOfString:@" at " withString:@"@"];
    if ([string containsString:@"@"]) {
	
	NSArray *dateAndTime = [string componentsSeparatedByString:@"@"];
	
	if ([dateAndTime count] > 2) {
	    OBError(error, // error
		    0,  // code enum
		    @"accepted strings are of the form \"DATE @ TIME\", there was an extra \"@\" sign" // description
		    );
	    
	    return NO;
	}
	
	// allow for the string to start with the time, and have no time, an "@" must always precede the time
	if ([string hasPrefix:@"@"]) {
#ifdef DEBUG_date
	    NSLog( @"string starts w/ an @ , so there is no date");
#endif
	    timeString = [dateAndTime objectAtIndex:1];
	} else {
	    dateString = [dateAndTime objectAtIndex:0];
	    if ([dateAndTime count] == 2) 
		timeString = [dateAndTime objectAtIndex:1];
	}
#ifdef DEBUG_date
	NSLog( @"contains @, dateString: %@, timeString: %@", dateString, timeString );
#endif
    } else {
#ifdef DEBUG_date
	NSLog(@"-----------'%@' starting date:%@", string, startingDate);
#endif	
	NSArray *stringComponents = [string componentsSeparatedByString:@" "];
	unsigned int maxComponentIndex = [stringComponents count] - 1;
	
	// test for a time at the end of the string.  This will only match things that are clearly times, ie, has colons, or am/pm
	int timeMatchIndex = -1;
	if (maxComponentIndex >= 0 && [self _stringMatchesTime:[stringComponents objectAtIndex:maxComponentIndex] optionalSecondString:nil withTimeFormat:timeFormat]) {
	    //NSLog(@"returned a true for _stringMatchesTime and the previous thing WASN't A MONTH for the end of the string: %@", [stringComponents objectAtIndex:maxComponentIndex]);
	    timeMatchIndex = maxComponentIndex;
	} else if (maxComponentIndex >= 1 && [self _stringMatchesTime:[stringComponents objectAtIndex:maxComponentIndex-1] optionalSecondString:[stringComponents objectAtIndex:maxComponentIndex] withTimeFormat:timeFormat]) {
	    //NSLog(@"returned a true for _stringMatchesTime for (with 2 comps): %@ & %@", [stringComponents objectAtIndex:maxComponentIndex-1], [stringComponents objectAtIndex:maxComponentIndex]);
	    timeMatchIndex = maxComponentIndex -1;
	} else if ([self _stringIsNumber:[stringComponents objectAtIndex:maxComponentIndex]]) {
	    int number = [[stringComponents objectAtIndex:maxComponentIndex] intValue];
	    int minutes = number % 100;
	    if (([timeFormat isEqualToString:@"HHmm"] || [timeFormat isEqualToString:@"kkmm"])&& ([[stringComponents objectAtIndex:maxComponentIndex] length] == 4)) {
		if (number < 2500 && minutes < 60) {
#ifdef DEBUG_date
		    NSLog(@"The time format is 24 hour time with the format: %@.  The number is: %d, and is less than 2500. The minutes are: %d, and are less than 60", timeFormat, number, minutes);
#endif
		    timeMatchIndex = maxComponentIndex;
		}
	    } 
	} 
	
	if (timeMatchIndex != -1) {
#ifdef DEBUG_date
	    NSLog(@"Time String found, the time match index is: %d", timeMatchIndex);
#endif
	    if (maxComponentIndex == 0 && (unsigned)timeMatchIndex == 0) {
		//NSLog(@"count = index = 0");
		timeString = string;
	    } else { 
		//NSLog(@"maxComponentIndex: %d, timeMatchIndex: %d", maxComponentIndex, timeMatchIndex);
		NSArray *timeComponents = [stringComponents subarrayWithRange:NSMakeRange(timeMatchIndex, maxComponentIndex-timeMatchIndex+1)];
		timeString = [timeComponents componentsJoinedByString:@" "];
		NSArray *dateComponents = [stringComponents subarrayWithRange:NSMakeRange(0, timeMatchIndex)];
		dateString = [dateComponents componentsJoinedByString:@" "];
	    }
	} else {
	    dateString = string;
	}
#ifdef DEBUG_date
	NSLog( @"NO @, dateString: %@, timeString: %@", dateString, timeString );
#endif
    } 
    
    BOOL timeSpecific = NO;
    
    if (![NSString isEmptyString:dateString]) { 
	static OFRegularExpression *spacedDateRegex = nil;
	if (!spacedDateRegex)
	    spacedDateRegex = [[OFRegularExpression alloc] initWithString:@"^(\\d\\d?\\d?\\d?)\\s(\\d\\d?\\d?\\d?)\\s?(\\d?\\d?\\d?\\d?)$"];
	OFRegularExpressionMatch *spacedDateMatch = [spacedDateRegex matchInString:dateString];
	
	static OFRegularExpression *formattedDateRegex = nil;
	if (!formattedDateRegex)
	    formattedDateRegex = [[OFRegularExpression alloc] initWithString:@"^\\w+([\\./-])\\w+"];
	OFRegularExpressionMatch *formattedDateMatch = [formattedDateRegex matchInString:dateString];
	
	static OFRegularExpression *unSeperatedDateRegex = nil;
	if (!unSeperatedDateRegex)
	    unSeperatedDateRegex = [[OFRegularExpression alloc] initWithString:@"^(\\d\\d\\d?\\d?)(\\d\\d)(\\d\\d)$"];
	OFRegularExpressionMatch *unSeperatedDateMatch = [unSeperatedDateRegex matchInString:dateString];
	
	if (unSeperatedDateMatch)
	    dateString = [NSString stringWithFormat:@"%@-%@-%@", [unSeperatedDateMatch subexpressionAtIndex:0], [unSeperatedDateMatch subexpressionAtIndex:1], [unSeperatedDateMatch subexpressionAtIndex:2]];
	
	if (formattedDateMatch || unSeperatedDateMatch || spacedDateMatch) {
	    NSString *separator = @" ";
	    if (unSeperatedDateMatch) {
#ifdef DEBUG_date
		NSLog(@"found an 'unseperated' date");
#endif
		separator = @"-";
	    } else if (formattedDateMatch) {
#ifdef DEBUG_date
		NSLog(@"formatted date found with the seperator as: %@", [formattedDateMatch subexpressionAtIndex:0]);
#endif
		separator = [formattedDateMatch subexpressionAtIndex:0];
	    } else if (spacedDateMatch) {
#ifdef DEBUG_date
		NSLog(@"numerical space delimted date found");
#endif
		separator = @" ";
	    }
	    
	    *date = [self parseFormattedDate:dateString withDate:startingDate withShortDateFormat:shortFormat withMediumDateFormat:mediumFormat withLongDateFormat:longFormat withseparator:separator];
	} else 
	    *date = [self parseDateNaturalLangauge:dateString withDate:startingDate timeSpecific:&timeSpecific useEndOfDuration:useEndOfDuration error:error];
    } else 
	*date = startingDate;
    
    if (timeString != nil)  
	*date = [currentCalendar dateFromComponents:[self parseTime:timeString withDate:*date withTimeFormat:timeFormat]];
    else {
	static OFRegularExpression *hourCodeRegex;
	if (!hourCodeRegex)
	    hourCodeRegex = [[OFRegularExpression alloc] initWithString:@"\\dh"];
	OFRegularExpressionMatch *hourCode = [hourCodeRegex matchInString:string];
	if (!hourCode && *date && !timeSpecific) {
	    //NSLog(@"no date information, and no hour codes, set to midnight");
	    NSDateComponents *defaultTime = [currentCalendar components:NSDayCalendarUnit|NSMonthCalendarUnit|NSYearCalendarUnit|NSEraCalendarUnit fromDate:*date];
	    [defaultTime setHour:[defaultTimeDateComponents hour]];
	    [defaultTime setMinute:[defaultTimeDateComponents minute]];
	    [defaultTime setSecond:[defaultTimeDateComponents second]];
	    *date = [currentCalendar dateFromComponents:defaultTime];
	}
    }
#ifdef DEBUG_date
    NSLog(@"Return date: %@", *date);
#endif
    //if (!*date) {
    //OBErrorWithInfo(&*error, "date parse error", @"GAH");  
    //return NO;
    //}
    return YES;
}

- (NSString *)stringForDate:(NSDate *)date withDateFormat:(NSString *)dateFormat withTimeFormat:(NSString *)timeFormat;
{
    return [self stringForDate:date withDateFormat:dateFormat withTimeFormat:timeFormat withTimeZone:[NSTimeZone localTimeZone] withCalendarIdentifier:NSGregorianCalendar];
}

- (NSString *)stringForDate:(NSDate *)date withDateFormat:(NSString *)dateFormat withTimeFormat:(NSString *)timeFormat withTimeZone:(NSTimeZone *)timeZone withCalendarIdentifier:(NSString *)nsLocaleCalendarKey ;
{
    // set the calendar according to the requested calendar and time zone
    currentCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:nsLocaleCalendarKey];
    if ( timeZone != nil )
	[currentCalendar setTimeZone:timeZone];
    NSDateComponents *components = [currentCalendar components:unitFlags fromDate:date];
    [NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:dateFormat];
    if ([components hour] != NSUndefinedDateComponent) 
	[formatter setDateFormat:[[dateFormat stringByAppendingString:@" "] stringByAppendingString:timeFormat]];
    NSString *result = [formatter stringFromDate:date];
    [formatter release];
    [currentCalendar release];
    return result;
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
    
    static OFRegularExpression *mdyRegex;
    if (!mdyRegex)
	mdyRegex = [[OFRegularExpression alloc] initWithString:@"[mM]+(\\s?)(\\S?)(\\s?)d+(\\s?)(\\S?)(\\s?)y+"];
    OFRegularExpressionMatch *match = [mdyRegex matchInString:dateFormat];
    if (match) {
	datePosition.day = 2;
	datePosition.month = 1;
	datePosition.year = 3;
	datePosition.separator = [match subexpressionAtIndex:0];
	return datePosition;
    }     
    static OFRegularExpression *dmyRegex;
    if (!dmyRegex)
	dmyRegex = [[OFRegularExpression alloc] initWithString:@"d+(\\s?)(\\S?)(\\s?)[mM]+(\\s?)(\\S?)(\\s?)y+"];
    match = [dmyRegex matchInString:dateFormat];
    if (match) {
	datePosition.day = 1;
	datePosition.month = 2;
	datePosition.year = 3;
	datePosition.separator = [match subexpressionAtIndex:0];
	return datePosition;
    }
    
    static OFRegularExpression *ymdRegex;
    if (!ymdRegex)
	ymdRegex = [[OFRegularExpression alloc] initWithString:@"y+(\\s?)(\\S?)(\\s?)[mM]+(\\s?)(\\S?)(\\s?)d+"];
    match = [ymdRegex matchInString:dateFormat];
    if (match) {
	datePosition.day = 3;
	datePosition.month = 2;
	datePosition.year = 1;
	datePosition.separator = [match subexpressionAtIndex:0];
	return datePosition;
    }
    
    static OFRegularExpression *ydmRegex;
    if (!ydmRegex)
	ydmRegex = [[OFRegularExpression alloc] initWithString:@"y+(\\s?)(\\S?)(\\s?)d+(\\s?)(\\S?)(\\s?)[mM]+"];
    match = [ydmRegex matchInString:dateFormat];
    if (match) {
	datePosition.day = 2;
	datePosition.month = 3;
	datePosition.year = 1;
	datePosition.separator = [match subexpressionAtIndex:0];
	return datePosition;
    }
    
    // log inavlid dates and use the american default, for now
    
    {
	[NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4]; 
	NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease]; 
	[formatter setDateStyle:NSDateFormatterShortStyle]; 
	[formatter setTimeStyle:NSDateFormatterNoStyle]; 
	NSMutableString *shortFormat =
	[NSMutableString stringWithString:[formatter dateFormat]];
	[formatter setDateStyle:NSDateFormatterMediumStyle]; 
	NSMutableString *mediumFormat =
	[NSMutableString stringWithString:[formatter dateFormat]];
	[formatter setDateStyle:NSDateFormatterLongStyle]; 
	NSMutableString *longFormat =
	[NSMutableString stringWithString:[formatter dateFormat]];
		
	NSLog(@"**PLEASE REPORT THIS LINE TO: omnifocus@omnigroup.com | Unparseable Custom Date Format. Date Format trying to parse is: @%; Short Format: %@; Medium Format: %@; Long Format: %@", dateFormat, shortFormat, mediumFormat, longFormat);
    }
    return datePosition;
}

@end

@implementation OFRelativeDateParser (Private)

- (BOOL)_stringIsNumber:(NSString *)string;
{
    //test for just a single number, note that [NSString intValue] won't work since it returns 0 on failure, and 0 is an allowed number
    static OFRegularExpression *numberRegex;
    if (!numberRegex)
	numberRegex = [[OFRegularExpression alloc] initWithString:@"^(\\d*)$"];
    OFRegularExpressionMatch *numberMatch = [numberRegex matchInString:string];
    if (numberMatch) 
	return YES;
    return NO;
}

- (BOOL)_stringMatchesTime:(NSString *)firstString optionalSecondString:(NSString *)secondString withTimeFormat:(NSString *)timeFormat;
{
    if (secondString) {
	if (!(([secondString hasPrefix:@"a"] || [secondString hasPrefix:@"p"]) && [secondString length] <= 2)) 
	    return NO;
	
	if ([self _stringIsNumber:firstString])
	    return YES;
    }
    
    // see if we have a european date
    static OFRegularExpression *timeDotRegex;
    if (!timeDotRegex)
	timeDotRegex = [[OFRegularExpression alloc] initWithString:@"^(\\d\\d?)\\.(\\d\\d?)\\.?(\\d?\\d?)$"];
    OFRegularExpressionMatch *dotMatch = [timeDotRegex matchInString:firstString];
    static OFRegularExpression *timeFormatDotRegex = nil;
    if (!timeFormatDotRegex)
	timeFormatDotRegex = [[OFRegularExpression alloc] initWithString:@"[HhkK]\\.[m]"];
    OFRegularExpressionMatch *timeFormatDotMatch = [timeFormatDotRegex matchInString:timeFormat];
    if (dotMatch&&timeFormatDotMatch)
	return YES;
    
    // see if we have some colons in a dately way
    static OFRegularExpression *timeColonRegex;
    if (!timeColonRegex)
	timeColonRegex = [[OFRegularExpression alloc] initWithString:@"^(\\d\\d?):(\\d?\\d?):?(\\d?\\d?)"];
    OFRegularExpressionMatch *colonMatch = [timeColonRegex matchInString:firstString];
    if (colonMatch)
	return YES;
    
    // see if we match a meridan at the end of our string
    static OFRegularExpression *timeEndRegex;
    if (!timeEndRegex)
	timeEndRegex = [[OFRegularExpression alloc] initWithString:@"\\d[apAP][mM]?$"];
    OFRegularExpressionMatch *timeEndMatch = [timeEndRegex matchInString:firstString];
    if (timeEndMatch)
	return YES;
    
    return NO;
}

- (NSDateComponents *)parseTime:(NSString *)timeString withDate:(NSDate *)date withTimeFormat:(NSString *)timeFormat;
{
    timeString = [timeString stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace];
    NSScanner *timeScanner = [NSScanner localizedScannerWithString:timeString];
    [timeScanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
    
    NSString *timeToken = nil; // this will be all of the string until we get to letters, i.e. am/pm
    BOOL isPM = NO; // TODO: Make a default.
    [timeScanner scanUpToCharactersFromSet:[NSCharacterSet letterCharacterSet] intoString:&timeToken];
    [timeScanner setCaseSensitive:NO];
    while (![timeScanner isAtEnd]) {
	if ([timeScanner scanString:@"p" intoString:NULL]) {
	    isPM = YES;
	    break;
	} else if ([timeScanner scanString:@"a" intoString:NULL]) {
	    isPM = NO;
	    break;
	} else
	    [timeScanner setScanLocation:[timeScanner scanLocation]+1];
	
	
	// note to self: do I need this? I think I don't, and that I'm missing the last char
	if ([timeScanner scanLocation] == [[timeScanner string] length])
	    break;
    }
    
    static OFRegularExpression *timeSeperatorRegex = nil;
    if (!timeSeperatorRegex)
	timeSeperatorRegex = [[OFRegularExpression alloc] initWithString:@"^\\d\\d?\\d?\\d?([:.])?"];
    OFRegularExpressionMatch *timeSeperatorMatch = [timeSeperatorRegex matchInString:timeToken];
    NSString *seperator = [timeSeperatorMatch subexpressionAtIndex:0];
    if ([NSString isEmptyString:seperator])
	seperator = @":";
    
    NSArray *timeComponents = [[timeToken stringByCollapsingWhitespaceAndRemovingSurroundingWhitespace] componentsSeparatedByString:seperator];
#ifdef DEBUG_date
    NSLog( @"TimeToken: %@, isPM: %d", timeToken, isPM );
    NSLog (@"time comps: %@", timeComponents );
#endif 
    
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
#ifdef DEBUG_date
	NSLog(@"isPM was true, adding 12 to: %d", hours);
#endif
	hours += 12;
    }  else if ([[timeComponents objectAtIndex:0] length] == 4 && [timeComponents count] == 1 && hours <= 2500 ) {
	//24hour time
	minutes = hours % 100;
	hours = hours / 100;
#ifdef DEBUG_date
	NSLog(@"time in 4 digit notation");
#endif
    } else if (![timeFormat hasPrefix:@"H"] && ![timeFormat hasPrefix:@"k"] && hours == 12 && !isPM) {
#ifdef DEBUG_date
	NSLog(@"time format doesn't have 'H', at 12 hours, setting to 0");
#endif
	hours = 0;
    }
    
    // if 1-24 "k" format, then 24 means 0
    if ([timeFormat hasPrefix:@"k"]) { 
	if (hours == 24) {
#ifdef DEBUG_date
	    NSLog(@"time format has 'k', at 24 hours, setting to 0");
#endif
	    hours = 0;
	}
	
    }
#ifdef DEBUG_date
    NSLog( @"hours: %d, minutes: %d, seconds: %d", hours, minutes, seconds );
#endif
    if (hours == -1)
	return nil;
    
    NSDateComponents *components = [currentCalendar components:unitFlags fromDate:date];
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

- (NSDate *)parseFormattedDate:(NSString *)dateString withDate:(NSDate *)date withShortDateFormat:(NSString *)shortFormat withMediumDateFormat:(NSString *)mediumFormat withLongDateFormat:(NSString *)longFormat withseparator:(NSString *)separator;
{
#ifdef DEBUG_date
    NSLog(@"parsing formatted dateString: %@", dateString );
#endif
    NSDateComponents *currentComponents = [currentCalendar components:unitFlags fromDate:date]; // the given date as components
    
    OBASSERT(separator);
    NSMutableArray *dateComponents = [NSMutableArray arrayWithArray:[dateString componentsSeparatedByString:separator]];
    if ([NSString isEmptyString:[dateComponents lastObject]]) 
	[dateComponents removeLastObject];
    
#ifdef DEBUG_date
    NSLog(@"determined date componets as: %@", dateComponents);
#endif
    
    NSString *dateFormat = shortFormat;
    static OFRegularExpression *mediumMonthRegex;
    if (!mediumMonthRegex)
	mediumMonthRegex = [[OFRegularExpression alloc] initWithString:@"[a-z][a-z][a-z]"];
    OFRegularExpressionMatch *mediumMonthMatch = [mediumMonthRegex matchInString:dateString];
    if (mediumMonthMatch) {
#ifdef DEBUG_date
	NSLog(@"using medium format: %@", mediumFormat);
#endif
	dateFormat = mediumFormat;
    } else {
	static OFRegularExpression *longMonthRegex;
	if (!longMonthRegex)
	    longMonthRegex = [[OFRegularExpression alloc] initWithString:@"[a-z][a-z][a-z]+"];
	OFRegularExpressionMatch *longMonthMatch = [longMonthRegex matchInString:dateString];
	if (longMonthMatch) {
#ifdef DEBUG_date
	    NSLog(@"using long format: %@", longFormat);
#endif
	    dateFormat = longFormat;
	}
    }
#ifdef DEBUG_date
    NSLog(@"using date format: %@", dateFormat);
#endif
    static OFRegularExpression *formatseparatorRegex = nil;
    if (!formatseparatorRegex)
	formatseparatorRegex = [[OFRegularExpression alloc] initWithString:@"^\\w+([\\./-])"];
    OFRegularExpressionMatch *formattedDateMatch = [formatseparatorRegex matchInString:dateFormat];
    NSString *formatStringseparator = nil;
    if (formattedDateMatch)
	formatStringseparator = [formattedDateMatch subexpressionAtIndex:0];
    
    
    DatePosition datePosition;
    if ([separator isEqualToString:@"-"] && ![formatStringseparator isEqualToString:@"-"]) { // use (!mediumMonthMatch/longMonthMatch instead of formatStringseparator?
#ifdef DEBUG_date
	NSLog(@"setting ISO DASH order, formatseparator: %@", formatStringseparator);
#endif
	datePosition.year = 1;
	datePosition.month = 2;
	datePosition.day = 3;
	datePosition.separator = @"-";
    } else {
#ifdef DEBUG_date
	NSLog(@"using DETERMINED, formatseparator: %@", formatStringseparator);
#endif
	datePosition= [self _dateElementOrderFromFormat:dateFormat];
    }
    
    // <bug://bugs/39123> 
    unsigned int count = [dateComponents count];
    if (count == 2) {
#ifdef DEBUG_date
	NSLog(@"only 2 numbers, one needs to be the day, the other the month, if the month comes before the day, and the month comes before the year, then assign the first number to the month");
#endif
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
    
#ifdef DEBUG_date
    NSLog(@"the date positions being used to assign are: day:%d month:%d, year:%d", datePosition.day, datePosition.month, datePosition.year);
#endif  
    
    DateSet dateSet = [self _dateSetFromArray:dateComponents withPositions:datePosition];
#ifdef DEBUG_date
    NSLog(@"date components: %@, SETTING TO: day:%d month:%d, year:%d", dateComponents, dateSet.day, dateSet.month, dateSet.year);
#endif    
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
    
#ifdef DEBUG_date
    NSLog(@"year: %d, month: %d, day: %d", [currentComponents year], [currentComponents month], [currentComponents day]);
#endif
    date = [currentCalendar dateFromComponents:currentComponents];
    return date;
}

- (DateSet)_dateSetFromArray:(NSArray *)dateComponents withPositions:(DatePosition)datePosition;
{
    DateSet dateSet;
    dateSet.day = -1;
    dateSet.month = -1;
    dateSet.year = -1;
    
    unsigned int count = [dateComponents count];
#ifdef DEBUG_date
    NSLog(@"date components: %@, day:%d month:%d, year:%d", dateComponents, datePosition.day, datePosition.month, datePosition.year);
#endif    
    /**Initial Setting**/
    BOOL didSwap = NO;
    // day
    if (datePosition.day <= count) {
	dateSet.day= [[dateComponents objectAtIndex:datePosition.day-1] intValue];
	if (dateSet.day == 0) {
	    // the only way for zero to get set is for intValue to be unable to return an int, which means its probably a month, swap day and month
	    int position = datePosition.day;
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
		int position = datePosition.year;
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
	
	if (dateSet.month == -1 )
	    dateSet.month = [monthName intValue];
	else
	    dateSet.month++;	
    }	
    
    /**Sanity Check**/
    int sanity = 2;
    while (sanity--) {
#ifdef DEBUG_date
	NSLog(@"%d SANITY: day: %d month: %d year: %d", sanity, dateSet.day, dateSet.month, dateSet.year);
#endif
	if (count == 1) {
	    if (dateSet.day > 31) {
#ifdef DEBUG_date
		NSLog(@"single digit is too high for a day, set to year: %d", dateSet.day);
#endif
		dateSet.year = dateSet.day;
		dateSet.day = -1;
	    } else if (dateSet.month > 12 ) {
#ifdef DEBUG_date
		NSLog(@"single digit is too high for a day, set to month: %d", dateSet.month);
#endif
		dateSet.day = dateSet.month;
		dateSet.month = -1;
	    }
	} else if (count == 2) {
	    if (dateSet.day > 31) {
#ifdef DEBUG_date
		NSLog(@"swap day and year");
#endif
		int year = dateSet.year;
		dateSet.year = dateSet.day;
		dateSet.day = year;
	    } else if (dateSet.month > 12 ) {
#ifdef DEBUG_date
		NSLog(@"swap month and year");
#endif
		int year = dateSet.year;
		dateSet.year = dateSet.month;
		dateSet.month = year;
	    } else if (dateSet.day > 0 && dateSet.year > 0 && dateSet.month < 0 ) {
#ifdef DEBUG_date
		NSLog(@"swap month and day");
#endif
		int day = dateSet.day;
		dateSet.day = dateSet.month;
		dateSet.month = day;
	    }
	}else if (count == 3 ) {
#ifdef DEBUG_date
	    NSLog(@"sanity checking a 3 compoent date. Day: %d, Month: %d Year: %d", dateSet.day, dateSet.month, dateSet.year);
#endif
	    if (dateSet.day > 31) {
#ifdef DEBUG_date
		NSLog(@"swap day and year");
#endif
		int year = dateSet.year;
		dateSet.year = dateSet.day;
		dateSet.day = year;
	    } else if (dateSet.month > 12 && dateSet.day <= 31 && dateSet.year <= 12) {
#ifdef DEBUG_date
		NSLog(@"swap month and year");
#endif
		int year = dateSet.year;
		dateSet.year = dateSet.month;
		dateSet.month = year;
	    } else if ( dateSet.day <= 12 && dateSet.month > 12 ) {
#ifdef DEBUG_date
		NSLog(@"swap day and month");
#endif
		int day = dateSet.day;
		dateSet.day = dateSet.month;
		dateSet.month = day;
	    }
#ifdef DEBUG_date
	    NSLog(@"after any swaps we're now at: Day: %d, Month: %d Year: %d", dateSet.day, dateSet.month, dateSet.year);
#endif
	    
	}
    }
    
    // unacceptable date
    if (dateSet.month > 12 || dateSet.day > 31) {
#ifdef DEBUG_date
	NSLog(@"Insane Date, month: %d is greater than 12, or day: %d is greater than 31", dateSet.month, dateSet.day);
#endif
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

- (NSDate *)parseDateNaturalLangauge:(NSString *)dateString withDate:(NSDate *)date timeSpecific:(BOOL *)timeSpecific useEndOfDuration:(BOOL)useEndOfDuration error:(NSError **)error;
{
#ifdef DEBUG_date
    NSLog(@"Parse Natural Language Date String: \"%@\"", dateString );
#endif
    OFRelativeDateParserRelativity modifier = OFRelativeDateParserNoRelativity; // look for a modifier as the first part of the string
    NSDateComponents *currentComponents = [currentCalendar components:unitFlags fromDate:date]; // the given date as components
    
#ifdef DEBUG_date
    NSLog(@"PRE comps. m: %d, d: %d, y: %d", [currentComponents month], [currentComponents day], [currentComponents year]);
#endif
    int multiplier = [self _multiplierForModifer:modifier];
    
    int month = -1;
    int weekday = -1;
    int day = -1;
    int year = -1;
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
		    if ([scanner scanString:name intoString:&match]) {
			// array info: Code, Number, Relativitity, timeSpecific, monthSpecific, daySpecific
			NSArray *dateOffset = [relativeDateNames objectForKey:match];
#ifdef DEBUG_date
			NSLog(@"found relative date match: %@", match);
#endif
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
                NSMutableArray *sortedKeyArray = [specialCaseTimeNames mutableCopyKeys];
		[sortedKeyArray sortUsingSelector:@selector(caseInsensitiveCompare:)];
                [sortedKeyArray reverse];
		for(NSString *name in sortedKeyArray) {
		    NSString *match;
		    if ([scanner scanString:name intoString:&match]) {
#ifdef DEBUG_date
			NSLog(@"found special case match: %@", match);
#endif
			daySpecific = YES;
			if (!*timeSpecific) {
			    // clear times
			    [currentComponents setHour:0];
			    [currentComponents setMinute:0];
			    [currentComponents setSecond:0];
			}
			
			NSString *day;
			if (useEndOfDuration) 
			    day = [_weekdays lastObject];
			else 
			    day = [_weekdays objectAtIndex:0];
			
			NSString *start_end_of_next_week = [NSString stringWithFormat:@"+ %@", day];
			NSString *start_end_of_last_week = [NSString stringWithFormat:@"- %@", day];
			NSString *start_end_of_this_week = [NSString stringWithFormat:@"~ %@", day];
			NSDictionary *keywordDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
							   start_end_of_next_week, @"START_END_OF_NEXT_WEEK",
							   start_end_of_last_week, @"START_END_OF_LAST_WEEK",
							   start_end_of_this_week, @"START_END_OF_THIS_WEEK", 
							   nil];
			
			NSString *replacementString = [[specialCaseTimeNames objectForKey:match] stringByReplacingKeysInDictionary:keywordDictionary startingDelimiter:@"$(" endingDelimiter:@")" removeUndefinedKeys:YES]; 
#ifdef DEBUG_date
			NSLog(@"found: %@, replaced with: %@ from dict: %@", [specialCaseTimeNames objectForKey:match], replacementString, keywordDictionary);
#endif			   
			date = [self parseDateNaturalLangauge:replacementString withDate:date timeSpecific:timeSpecific useEndOfDuration:useEndOfDuration error:error];
			currentComponents = [currentCalendar components:unitFlags fromDate:date]; // update the components
#ifdef DEBUG_date
			NSLog(@"RETURN from replacement call");
#endif	
		    }
		}
		[sortedKeyArray release];
	    }
	   	    
	    NSString *name;
	    // check for any modifier after we check the relative date names, as the relative date names can be phrases that we want to match with
	    NSEnumerator *patternEnum = [modifiers keyEnumerator];
	    NSString *pattern;
	    while ((pattern = [patternEnum nextObject])) {
		NSString *match;
		if ([scanner scanString:pattern intoString:&match]) {
		    modifier = [[modifiers objectForKey:pattern] intValue];
#ifdef DEBUG_date
		    NSLog(@"Found Modifier: %@", match);
#endif
		    multiplier = [self _multiplierForModifer:modifier];
		    modifierForNumber = YES;
		}
	    } 
	    
	    // test for month names
	    if (month == -1) {
		NSEnumerator *monthEnum = [_months objectEnumerator];
		while ((name = [monthEnum nextObject])) {
		    NSString *match;
		    if ([scanner scanString:name intoString:&match]) {
			month = [self _monthIndexForString:match];
			scanned = YES;
#ifdef DEBUG_date
			NSLog(@"matched name: %@ to match: %@", name, match);
#endif
		    }
		}
	    }
	    [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
	    
	    if (month == -1) {
		NSEnumerator *shortMonthEnum = [_shortmonths objectEnumerator];
		while ((name = [shortMonthEnum nextObject])) {
		    NSString *match;
		    if ([scanner scanString:name intoString:&match]) {
			month = [self _monthIndexForString:match];
			scanned = YES;
#ifdef DEBUG_date
			NSLog(@"matched name: %@ to match: %@", name, match);
#endif
		    }
		}
	    }
	    [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
	    
	    // test for weekday names
	    if (weekday == -1) {
		NSEnumerator *weekdaysEnum = [_weekdays objectEnumerator];
		while ((name = [weekdaysEnum nextObject])) {
		    NSString *match;
		    if ([scanner scanString:name intoString:&match]) {
			weekday = [self _weekdayIndexForString:match];
			daySpecific = YES;
			scanned = YES;
#ifdef DEBUG_date
			NSLog(@"matched name: %@ to match: %@ weekday: %d", name, match, weekday);
#endif
		    }
		}
	    }
	    [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
	    
	    // test for english weekday names
	    if (weekday == -1) {
		NSEnumerator *weekdaysEnum = [englishWeekdays objectEnumerator];
		while ((name = [weekdaysEnum nextObject])) {
		    NSString *match;
		    if ([scanner scanString:name intoString:&match]) {
			weekday = [self _weekdayIndexForString:match];
			daySpecific = YES;
			scanned = YES;
#ifdef DEBUG_date
			NSLog(@"ENGLISH matched name: %@ to match: %@ weekday: %d", name, match, weekday);
#endif
		    }
		}
	    }
	    [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
	    
	    if (weekday != -1) {
		date = [self _modifyDate:date withWeekday:weekday withModifier:modifier];
		currentComponents = [currentCalendar components:unitFlags fromDate:date];
		weekday = -1;
		modifier = 0;
		multiplier = [self _multiplierForModifer:modifier];
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
	    BOOL foundCode = NO;
	    NSString *codeString;
            NSMutableArray *sortedKeyArray = [codes mutableCopyKeys];
	    [sortedKeyArray sortUsingSelector:@selector(caseInsensitiveCompare:)];
	    NSEnumerator *codeEnum = [sortedKeyArray reverseObjectEnumerator];
	    while ((codeString = [codeEnum nextObject]) && !foundCode && (![scanner isAtEnd])) {
		if ([scanner scanString:codeString intoString:NULL]) {
		    dpCode = [[codes objectForKey:codeString] intValue];
		    if (number != 0) // if we aren't going to add anything don't call
			[self _addToComponents:componentsToAdd codeString:dpCode codeInt:number withMultiplier:multiplier];
#ifdef DEBUG_date
		    NSLog( @"codeString:%@, number:%d, mult:%d", codeString, number, multiplier );
#endif
		    daySpecific = YES;
		    isYear = NO; // '97d gets you 97 days
		    foundCode= YES;
		    scanned = YES;
		    modifierForNumber = NO;
		    number = -1;  
		}
	    }
            [sortedKeyArray release];
	    
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
#ifdef DEBUG_date
		    NSLog(@"free number, marking added to day as true");
#endif
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
	
	// scan short weekdays after codes to allow for months to be read instead of mon
	if (weekday == -1) {
	    NSEnumerator *shortdaysEnum = [_shortdays objectEnumerator];
	    NSString *name;
	    while ((name = [shortdaysEnum nextObject])) {
		NSString *match;
		if ([scanner scanString:name intoString:&match]) {
		    weekday = [self _weekdayIndexForString:match];
		    daySpecific = YES;
		    scanned = YES;
#ifdef DEBUG_date
		    NSLog(@"matched name: %@ to match: %@", name, match);
#endif
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
#ifdef DEBUG_date
		    NSLog(@"ENGLISH matched name: %@ to match: %@", name, match);
#endif
		}
	    }
	}
	[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
	
	if (weekday != -1) {
	    date = [self _modifyDate:date withWeekday:weekday withModifier:modifier];
	    currentComponents = [currentCalendar components:unitFlags fromDate:date];
	    weekday = -1;
	    modifier = 0;
	    multiplier = [self _multiplierForModifer:modifier];
	}
	
	//check for any modifier again, before checking for numbers, so that we can record the proper modifier
	NSEnumerator *patternEnum = [modifiers keyEnumerator];
	NSString *pattern;
	while ((pattern = [patternEnum nextObject])) {
	    NSString *match;
	    if ([scanner scanString:pattern intoString:&match]) {
		modifier = [[modifiers objectForKey:pattern] intValue];
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
#ifdef DEBUG_date
	    NSLog(@"scanned some symbols");
#endif
	    punctuation = YES;
	}
	
	if ([scanner scanLocation] == [[scanner string] length] && !needToProcessNumber) {
	    break;
	} else {
	    if (!scanned) {
		[scanner setScanLocation:[scanner scanLocation]+1];
	    }
	}
#ifdef DEBUG_date
	NSLog(@"end of scanning cycle. month: %d, day: %d, year: %d, weekday: %d, number: %d, modifier: %d", month, day, year, weekday, number, multiplier);
#endif
	//OBError(&*error, // error
	//		0,  // code enum
	//		@"we were unable to parse something, return an error for string" // description
	//		);
	if (number == -1 && !scanned) {
	    if (!punctuation) {
#ifdef DEBUG_date
		NSLog(@"ERROR String: %@, number: %d loc: %d", dateString, number, [scanner scanLocation]);
#endif
		return nil;
	    }
	}
	
    } // scanner
    
    if (!daySpecific) {
	if (useEndOfDuration) {
	    // find the last day of the month of the components ?
	}
	day = 1;
#ifdef DEBUG_date
	NSLog(@"setting the day to 1 as a default");
#endif
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
    
    date = [currentCalendar dateFromComponents:currentComponents];
#ifdef DEBUG_date    
    NSLog(@"comps. m: %d, d: %d, y: %d", [currentComponents month], [currentComponents day], [currentComponents year]);
    NSLog( @"date before modifying with the components: %@", date) ;
#endif

    // componetsToAdd is all of the collected relative date codes
    date = [currentCalendar dateByAddingComponents:componentsToAdd toDate:date options:0];
    return date;
}

- (int)_multiplierForModifer:(int)modifier;
{
    if (modifier == OFRelativeDateParserPastRelativity)
	return -1;
    return 1;
}

- (unsigned int)_monthIndexForString:(NSString *)token;
{
    // return the the value of the month according to its position on the array, or -1 if nothing matches.
    unsigned int monthIndex = [_months count];
    while (monthIndex--) {
	if ([token isEqualToString:[[_shortmonths objectAtIndex:monthIndex] lowercaseString]] || [token isEqualToString:[[_months objectAtIndex:monthIndex] lowercaseString]]) {
	    return monthIndex;
	}
    }
    return -1;
}

- (unsigned int)_weekdayIndexForString:(NSString *)token;
{
    // return the the value of the weekday according to its position on the array, or -1 if nothing matches.
    
    unsigned int dayIndex = [_weekdays count];
    token = [token lowercaseString];
    while (dayIndex--) {
#ifdef DEBUG_date
	if (dayIndex >= 0)
	    NSLog(@"token: %@, weekdays: %@, short: %@, Ewdays: %@, EShort: %@", token, [[_weekdays objectAtIndex:dayIndex] lowercaseString], [[_shortdays objectAtIndex:dayIndex] lowercaseString], [[englishWeekdays objectAtIndex:dayIndex] lowercaseString], [[englishShortdays objectAtIndex:dayIndex] lowercaseString]);
#endif
	if ([token isEqualToString:[[_shortdays objectAtIndex:dayIndex] lowercaseString]] || [token isEqualToString:[[_weekdays objectAtIndex:dayIndex] lowercaseString]])
	    return dayIndex;
	
	// test the english weekdays
	if ([token isEqualToString:[[englishShortdays objectAtIndex:dayIndex] lowercaseString]] || [token isEqualToString:[[englishWeekdays objectAtIndex:dayIndex] lowercaseString]])
		    return dayIndex;
    }

#ifdef DEBUG_date
    NSLog(@"weekday index not found for: %@", token);
#endif
    
    return -1;
}

- (int)_determineYearForMonth:(unsigned int)month withModifier:(OFRelativeDateParserRelativity)modifier fromCurrentMonth:(unsigned int)currentMonth fromGivenYear:(int)givenYear;
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

- (NSDate *)_modifyDate:(NSDate *)date withWeekday:(unsigned int)requestedWeekday withModifier:(OFRelativeDateParserRelativity)modifier;
{
    requestedWeekday+=1; // add one to the index since weekdays are 1 based, but we detect them zero-based
    NSDateComponents *weekdayComp = [currentCalendar components:NSWeekdayCalendarUnit fromDate:date];
    NSDateComponents *components = [[NSDateComponents alloc] init];
    unsigned int currentWeekday = [weekdayComp weekday];
    
#ifdef DEBUG_date    
    NSLog(@"Modifying the date based on weekdays with modifer: %d, Current Weekday: %d, Requested Weekday: %d", modifier, currentWeekday, requestedWeekday);
#endif
    
    // if there is no modifier then we just take the current day if its a match, or the next instance of the requested day
    if (modifier == OFRelativeDateParserNoRelativity) {
#ifdef DEBUG_date    
	NSLog(@"NO Modifier");
#endif
	if (currentWeekday == requestedWeekday) {
#ifdef DEBUG_date
	    NSLog(@"return today");
#endif	
            [components release];
	    return date; 
	} else if (currentWeekday > requestedWeekday) {
#ifdef DEBUG_date    
	    NSLog( @"set the weekday to the next instance of the requested day, %d days in the future", (7-(currentWeekday - requestedWeekday)));
#endif		
	    [components setDay:(7-(currentWeekday - requestedWeekday))];
	} else if (currentWeekday < requestedWeekday) {
#ifdef DEBUG_date    
	    NSLog( @"set the weekday to the next instance of the requested day, %d days in the future", (requestedWeekday- currentWeekday) );
#endif
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
#ifdef DEBUG_date    
		NSLog(@"CURRENT Modifier \"this\"");
#endif
		break;
	    case OFRelativeDateParserPastRelativity: // "last"
		dayModification = -7;
#ifdef DEBUG_date    
		NSLog(@"PAST Modifier \"last\"");
#endif
		break;
	}
	
#ifdef DEBUG_date    
	NSLog( @"set the weekday to: %d days difference from the current weekday: %d, BUT add %d days", (requestedWeekday- currentWeekday), currentWeekday, dayModification );
#endif
	[components setDay:(requestedWeekday- currentWeekday)+dayModification];
    }
    
    NSDate *result = [currentCalendar dateByAddingComponents:components toDate:date options:0];; //return next week
    [components release];
    return result;
}

- (void)_addToComponents:(NSDateComponents *)components codeString:(DPCode)dpCode codeInt:(int)codeInt withMultiplier:(int)multiplier;
{
    codeInt*=multiplier;
    switch (dpCode) {
	case DPHour:
	    if ([components hour] == NSUndefinedDateComponent)
		[components setHour:codeInt];
	    else
		[components setHour:[components hour] + codeInt];
#ifdef DEBUG_date    
	    NSLog( @"Added %d hours to the components, now at: %d hours", codeInt, [components hour] );
#endif
	    break;
	    case DPDay:
	    if ([components day] == NSUndefinedDateComponent)
		[components setDay:codeInt];
	    else 
		[components setDay:[components day] + codeInt];
#ifdef DEBUG_date    
	    NSLog( @"Added %d days to the components, now at: %d days", codeInt, [components day] );
#endif
	    break;
	    case DPWeek:
	    if ([components day] == NSUndefinedDateComponent)
		[components setDay:codeInt*7];
	    else
		[components setDay:[components day] + codeInt*7];
#ifdef DEBUG_date    
	    NSLog( @"Added %d weeks(ie. days) to the components, now at: %d days", codeInt, [components day] );
#endif
	    break;
	    case DPMonth:
	    if ([components month] == NSUndefinedDateComponent)
		[components setMonth:codeInt];
	    else 
		[components setMonth:[components month] + codeInt];
#ifdef DEBUG_date    
	    NSLog( @"Added %d months to the components, now at: %d months", codeInt, [components month] );
#endif
	    break;
	    case DPYear:
	    if ([components year] == NSUndefinedDateComponent)
		[components setYear:codeInt];
	    else 
		[components setYear:[components year] + codeInt];
#ifdef DEBUG_date    
	    NSLog( @"Added %d years to the components, now at: %d years", codeInt, [components year] );
#endif
	    break;
    }
}
@end
