// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSArray, NSCalendar, NSDate, NSDateComponents, NSError, NSLocale, NSTimeZone;

// WARNING: Do not use this yet, it's still a work in progress

@interface OFRelativeDateParser : OFObject
{
    // the locale of this parser
    NSLocale *_locale;
    NSCalendar *currentCalendar;   
    
    // locale specific, change when setLocale is called
    NSArray *_weekdays;
    NSArray *_shortdays;
    NSArray *_months;
    NSArray *_shortmonths;
}

+ (OFRelativeDateParser *)sharedParser; // most applications will use the shared parser which uses your current locale.

- initWithLocale:(NSLocale *)locale;

- (NSLocale *)locale;
- (void)setLocale:(NSLocale *)locale;

- (BOOL)getDateValue:(NSDate **)date 
	   forString:(NSString *)string
   	       error:(NSError **)error;

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string useEndOfDuration:(BOOL)useEndOfDuration defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents error:(NSError **)error;

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

- (NSString *)stringForDate:(NSDate *)date withDateFormat:(NSString *)dateFormat withTimeFormat:(NSString *)timeFormat;
- (NSString *)stringForDate:(NSDate *)date withDateFormat:(NSString *)dateFormat withTimeFormat:(NSString *)timeFormat withTimeZone:(NSTimeZone *)timeZone withCalendarIdentifier:(NSString *)nsLocaleCalendarKey ;

@end

