// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
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
- (nullable instancetype)initWithXMLString:(NSString *)xmlString;
- (nullable instancetype)initWithXMLCString:(const char *)cString;
- (NSString *)xmlString;

// date formatted according to iCal
- (nullable instancetype)initWithICSDateOnlyString:(NSString *)aString;
- (NSString *)icsDateOnlyString;

// datetime formatted according to iCal
- (nullable instancetype)initWithICSDateString:(NSString *)aString;
- (NSString *)icsDateString;

// datetime formatted for OmniFocus sync transactions
- (NSString *)omnifocusSyncTransactionDateString;

@end

// For old versions of Foundation w/o -dateByAddingTimeInterval:.
static inline NSDate *OFDateByAddingTimeInterval(NSDate *date, NSTimeInterval interval)
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE && (!defined(__IPHONE_4_0) || __IPHONE_4_0 > __IPHONE_OS_VERSION_MIN_REQUIRED)
    return [date addTimeInterval:interval];
#else
    return [date dateByAddingTimeInterval:interval];
#endif
}

NS_ASSUME_NONNULL_END

