// Copyright 2006-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSCalendar, NSDate, NSDateComponents, NSError, NSLocale;

// WARNING: Do not use this yet, it's still a work in progress

@interface OFRelativeDateParser : OFObject

+ (OFRelativeDateParser *)sharedParser; // most applications will use the shared parser which uses your current locale.

- (instancetype)initWithLocale:(NSLocale *)locale;

- (NSLocale *)locale;
- (void)setLocale:(NSLocale *)locale;

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string error:(NSError **)error;

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string fromStartingDate:(NSDate *)startingDate useEndOfDuration:(BOOL)useEndOfDuration defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents calendar:(NSCalendar *)calendar error:(NSError **)error;
- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string fromStartingDate:(NSDate *)startingDate useEndOfDuration:(BOOL)useEndOfDuration defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents calendar:(NSCalendar *)calendar withCustomFormat:(NSString *)customFormat error:(NSError **)error;

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string fromStartingDate:(NSDate *)startingDate calendar:(NSCalendar *)calendar withShortDateFormat:(NSString *)shortFormat withMediumDateFormat:(NSString *)mediumFormat withLongDateFormat:(NSString *)longFormat withTimeFormat:(NSString *)timeFormat error:(NSError **)error;
- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string fromStartingDate:(NSDate *)startingDate calendar:(NSCalendar *)calendar withCustomFormat:(NSString *)customFormat withShortDateFormat:(NSString *)shortFormat withMediumDateFormat:(NSString *)mediumFormat withLongDateFormat:(NSString *)longFormat withTimeFormat:(NSString *)timeFormat error:(NSError **)error;

- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string fromStartingDate:(NSDate *)startingDate calendar:(NSCalendar *)calendar withShortDateFormat:(NSString *)shortFormat withMediumDateFormat:(NSString *)mediumFormat withLongDateFormat:(NSString *)longFormat withTimeFormat:(NSString *)timeFormat useEndOfDuration:(BOOL)useEndOfDuration defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents error:(NSError **)error;
- (BOOL)getDateValue:(NSDate **)date forString:(NSString *)string fromStartingDate:(NSDate *)startingDate calendar:(NSCalendar *)calendar withCustomFormat:(NSString *)customFormat withShortDateFormat:(NSString *)shortFormat withMediumDateFormat:(NSString *)mediumFormat withLongDateFormat:(NSString *)longFormat withTimeFormat:(NSString *)timeFormat useEndOfDuration:(BOOL)useEndOfDuration defaultTimeDateComponents:(NSDateComponents *)defaultTimeDateComponents error:(NSError **)error;

- (NSString *)stringForDate:(NSDate *)date withDateFormat:(NSString *)dateFormat withTimeFormat:(NSString *)timeFormat;
- (NSString *)stringForDate:(NSDate *)date withDateFormat:(NSString *)dateFormat withTimeFormat:(NSString *)timeFormat calendar:(NSCalendar *)calendar;

@end

