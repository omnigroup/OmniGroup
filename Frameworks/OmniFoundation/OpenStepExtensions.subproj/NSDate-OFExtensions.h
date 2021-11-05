// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSDate.h>

@class NSCalendar, NSString, NSTimeZone;

NS_ASSUME_NONNULL_BEGIN

@interface NSDate (OFExtensions)

- (void)sleepUntilDate;

- (BOOL)isAfterDate: (NSDate *) otherDate;
- (BOOL)isBeforeDate: (NSDate *) otherDate;

// HTTP dates
// https://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html#sec3.3
- (nullable instancetype)initWithHTTPString:(NSString *)aString;
- (NSString *)descriptionWithHTTPFormat; // rfc1123 format with TZ forced to GMT

// XML Schema / ISO 8601 support
+ (NSTimeZone *)UTCTimeZone;
+ (NSCalendar *)gregorianUTCCalendar;

+ (NSCalendar *)gregorianLocalCalendar;

// date formatted according to http://www.w3.org/2001/XMLSchema-datatypes
- (nullable instancetype)initWithXMLDateString:(NSString *)xmlString;
- (NSString *)xmlDateString;

// dateTime formatted according to http://www.w3.org/2001/XMLSchema-datatypes
- (nullable instancetype)initWithXMLString:(NSString *)xmlString allowFloating:(BOOL)allowFloating outIsFloating:(BOOL * _Nullable)outIsFloating;
- (nullable instancetype)initWithXMLString:(NSString *)xmlString;
- (nullable instancetype)initWithXMLCString:(const char *)cString;
- (NSString *)xmlString; // UTC
- (NSString *)floatingTimeZoneXMLString; // Date in current time zone with no zone recorded

// date formatted according to iCal
- (nullable instancetype)initWithICSDateOnlyString:(NSString *)aString;
- (NSString *)icsDateOnlyString;

// datetime formatted according to iCal
- (nullable instancetype)initWithICSDateString:(NSString *)aString;
- (NSString *)icsDateString;

// datetime formatted for OmniFocus sync transactions
- (NSString *)omnifocusSyncTransactionDateString;

@end

NS_ASSUME_NONNULL_END

