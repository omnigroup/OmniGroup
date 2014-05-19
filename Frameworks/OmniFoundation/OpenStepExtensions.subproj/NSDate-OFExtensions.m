// Copyright 1997-2005, 2007-2008, 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSDate-OFExtensions.h>

#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFNull.h>

#import <Foundation/NSDateFormatter.h>

RCS_ID("$Id$")

@implementation NSDate (OFExtensions)

- (NSString *)descriptionWithHTTPFormat; // rfc1123 format with TZ forced to GMT
{
    // See rfc2616 [3.3.1].  For example: "Mon, 01 Jan 2001 00:00:00 GMT"
    static NSDateFormatter *dateFormatter = nil;
    if (dateFormatter == nil) {
        dateFormatter = [[NSDateFormatter alloc] init];
        NSLocale* us_en_locale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease];
        [dateFormatter setLocale:us_en_locale];
        [dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
        [dateFormatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss 'GMT'"];
    }
    return [dateFormatter stringFromDate:self];
}

- (void)sleepUntilDate;
{
    NSTimeInterval timeIntervalSinceNow;

    timeIntervalSinceNow = [self timeIntervalSinceNow];
    if (timeIntervalSinceNow < 0)
	return;
    [NSThread sleepUntilDate:self];
}

- (BOOL)isAfterDate:(NSDate *)otherDate
{
    return [self compare:otherDate] == NSOrderedDescending;
}

- (BOOL)isBeforeDate:(NSDate *)otherDate
{
    return [self compare:otherDate] == NSOrderedAscending;
}

#pragma mark -
#pragma mark XML Schema / ISO 8601 support

+ (NSTimeZone *)UTCTimeZone;
{
    static NSTimeZone *tz = nil;
    
    if (!tz) {
        tz = [[NSTimeZone timeZoneWithName:@"UTC"] retain];
        OBASSERT(tz);
        if (!tz) // another approach...
            tz = [NSTimeZone timeZoneForSecondsFromGMT:0];
        OBASSERT(tz);
    }
    return tz;
}

+ (NSCalendar *)gregorianUTCCalendar;
{
    static NSCalendar *cal = nil;
    
    if (!cal) {
        cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
        OBASSERT(cal);
        
        [cal setTimeZone:[self UTCTimeZone]];
    }
    return cal;
}

#if 0 && defined(DEBUG)
    #define DEBUG_XML_STRING(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_XML_STRING(format, ...)
#endif

// plain -release w/o -init will crash on 10.4.11/Intel
#define BAD_INIT do { \
    self = [self init]; \
    OB_RELEASE(self); \
    return nil; \
} while(0)

#define GET_DIGIT(d, delta) do { \
  char c = buf[offset+delta]; \
  if (c < '0' || c > '9') BAD_INIT; \
  d = (c - '0'); \
} while(0)

#define READ_CHAR(c) do { \
  if (buf[offset] != c) BAD_INIT; \
  offset++; \
} while(0)

#define READ_2UINT(u) do { \
  uint_fast8_t d10, d1; \
  GET_DIGIT(d10, 0); \
  GET_DIGIT(d1, 1); \
  u = 10*d10 + d1; \
  offset += 2; \
} while(0)

#define READ_4UINT(u) do { \
    uint_fast16_t d1000, d100, d10, d1; \
    GET_DIGIT(d1000, 0); \
    GET_DIGIT(d100, 1); \
    GET_DIGIT(d10, 2); \
    GET_DIGIT(d1, 3); \
    u = 1000*d1000 + 100*d100 + 10*d10 + d1; \
    offset += 4; \
} while(0)

/*
 Expects a string in the XML Schema / RFC 3339 / ISO 8601 format, such as YYYY-MM-ddTHH:mm:ss(.S+)(Z|[+-]HH:MM).  This doesn't attempts to be very forgiving in parsing; the goal should be to feed in a conforming string. No support is included for negative years, though XML Schema and ISO 8601 allow it (RFC 3339 doesn't). Any deviation from the supported grammar will result in a nil return value.
 
 References:
 <http://www.w3.org/TR/xmlschema-2/#dateTime>
 <http://www.faqs.org/rfcs/rfc3339.html>
 
 */

static NSDate *_initDateFromXMLString(NSDate *self, const char *buf, size_t length)
{
    // Since we read forward, we'll catch a early NUL with digit or specific character checks.
    CFGregorianDate date;
    unsigned offset = 0;
    READ_4UINT(date.year);
    READ_CHAR('-');
    READ_2UINT(date.month);
    READ_CHAR('-');
    READ_2UINT(date.day);
    
    READ_CHAR('T'); // RFC 3339 allows 't' here too, but we don't right now.
    READ_2UINT(date.hour);
    READ_CHAR(':');
    READ_2UINT(date.minute);
    READ_CHAR(':');
    READ_2UINT(date.second); // Just the integer part ... fractional part comes next
    
    // Everything to this point is fixed width.
    OBASSERT(offset == 19);
    
    if (buf[offset] == '.') {
        offset++; // skip the decimal.
        
        // Fractional second.  There must be at least one digit.
        unsigned fractionNumerator;
        GET_DIGIT(fractionNumerator, 0);
        unsigned fractionDenominator = 10; // for our one digit read already.
        
        // 32-bits can hold 9 digits w/o overflow.  We've read one already.  If we get anywhere near this limit, you're using an inappropriate format.
        unsigned digitIndex;
        for (digitIndex = 1; digitIndex < 9; digitIndex++) {
            char digitChar = buf[offset + digitIndex];
            if (digitChar < '0' || digitChar > '9')
                break; // Read one digit already; non-digit just terminates this portion.
            unsigned digit = digitChar - '0';
            fractionNumerator = 10*fractionNumerator + digit;
            fractionDenominator = 10*fractionDenominator;
        }
        
        offset += digitIndex;

        date.second += (NSTimeInterval)fractionNumerator / (NSTimeInterval)fractionDenominator;
    }
    
    NSTimeZone *timeZone;
    if (buf[offset] == 'Z') { // RFC 3339 allows 'z' here too, but we don't right now.
        if (buf[offset + 1] != 0)
            BAD_INIT; // Crud after the 'Z'.
        timeZone = [NSDate UTCTimeZone];
    } else if (buf[offset] == '-' || buf[offset] == '+') {
        BOOL negate = (buf[offset] == '-');
        offset++;
        
        unsigned tzHour, tzMinute;
        READ_2UINT(tzHour);
        READ_CHAR(':');
        READ_2UINT(tzMinute);
        
        // This isn't going to perform as well as the Z case.
        NSInteger tzOffset = tzHour*3600+tzMinute*60;
        if (negate)
            tzOffset = -tzOffset;
        
        timeZone = [NSTimeZone timeZoneForSecondsFromGMT:tzOffset];
    } else {
        // Unrecognized cruft where the timezone should have been.
        BAD_INIT;
    }
    
    if (!CFGregorianDateIsValid(date, kCFGregorianAllUnits)) {
        BAD_INIT;
    }
        
    // NOTE: CFCalendarComposeAbsoluteTime is not thread-safe and doesn't deal with floating-point seconds, but CFGregorianDateGetAbsoluteTime is and has nicer API for what we need.
    // TODO: Leap seconds can cause the maximum allowed second value to be 58 or 60 depending on whether the adjustment is +/-1.  RFC 3339 has a table of some leap seconds up to 1998 that we could test with.
    CFAbsoluteTime absoluteTime = CFGregorianDateGetAbsoluteTime(date, (OB_BRIDGE CFTimeZoneRef)timeZone);
    
    DEBUG_XML_STRING(@"absoluteTime: %f", absoluteTime);
        
    NSDate *result = [self initWithTimeIntervalSinceReferenceDate:absoluteTime];
    DEBUG_XML_STRING(@"result: %@ %f", result, [result timeIntervalSinceReferenceDate]);
    
    return result;
}

- initWithXMLString:(NSString *)xmlString;
{
    static const NSUInteger OFXMLDateStringMaximumLength = 100; // The true maximum isn't fixed since the fractional seconds part is variable length.  Anything hugely long will be rejected.
    
    NSUInteger length = [xmlString length];
    if (length == 0 || length > OFXMLDateStringMaximumLength)
        BAD_INIT;
    
    char buf[OFXMLDateStringMaximumLength+1]; // Allow room for the terminating NUL
    if (![xmlString getCString:buf maxLength:sizeof(buf) encoding:NSASCIIStringEncoding]) { // ... which this will append.
        OBASSERT_NOT_REACHED("Unexpected encoding in XML date");
        BAD_INIT;
    }

    NSDate *result = _initDateFromXMLString(self, buf, length);
    OBPOSTCONDITION_EXPENSIVE(OFISEQUAL([result xmlString], xmlString));
    return result;
}

// Since XML dates are always ASCII, mentioning the encoding in the API is redundant.
- initWithXMLCString:(const char *)cString;
{
    NSDate *result = _initDateFromXMLString(self, cString, strlen(cString));
    OBPOSTCONDITION_EXPENSIVE(strcmp([[result xmlString] UTF8String], cString) == 0);
    return result;
}

static uint_fast8_t _digitAt(const char *buf, unsigned int offset)
{
    char c = buf[offset];
    OBASSERT(c >= '0' && c <= '9');
    return c - '0';
}
static uint_fast8_t _parse2Digits(const char *buf, unsigned int offset)
{
    return 10*_digitAt(buf, offset) + _digitAt(buf, offset+1);
}
static unsigned int _parse4Digits(const char *buf, unsigned int offset)
{
    return 1000*_digitAt(buf, offset+0) + 100*_digitAt(buf, offset+1) + 10*_digitAt(buf, offset+2) + _digitAt(buf, offset+3);
}

// Expects a calendar date string in the XML Schema / ISO 8601 format: YYYY-MM-DD.  This doesn't attempts to be very forgiving in parsing; the goal should be to feed in either nil/empty or a conforming string.
- initWithXMLDateString:(NSString *)xmlString;
{
    // We expect exactly the length above, or an empty string.
    static const unsigned OFXMLDateStringLength = 10;
    static NSTimeZone *cachedTimeZone;
    if (!cachedTimeZone) {
        cachedTimeZone = [[NSTimeZone localTimeZone] retain];
        OBASSERT(cachedTimeZone);
    }
    
    NSUInteger length = [xmlString length];
    if (length != OFXMLDateStringLength) {
        OBASSERT(length == 0);
        BAD_INIT;
    }
    
    char buf[OFXMLDateStringLength+1];
    if (![xmlString getCString:buf maxLength:sizeof(buf) encoding:NSASCIIStringEncoding]) {
        OBASSERT_NOT_REACHED("Unexpected encoding in XML date");
	BAD_INIT;
    }
    
    // TODO: Not checking the delimiters or digit-ness of number ranges yet.
    CFGregorianDate date = {0};
    date.year = _parse4Digits(buf, 0);
    date.month = _parse2Digits(buf, 5);
    date.day = _parse2Digits(buf, 8);
    
    if (!CFGregorianDateIsValid(date, kCFGregorianAllUnits)) {
        BAD_INIT;
    }
    CFAbsoluteTime absoluteTime = CFGregorianDateGetAbsoluteTime(date, (OB_BRIDGE CFTimeZoneRef)cachedTimeZone);

    DEBUG_XML_STRING(@"absoluteTime: %f", absoluteTime);
    
    NSDate *result = [self initWithTimeIntervalSinceReferenceDate:absoluteTime];
    DEBUG_XML_STRING(@"result: %@ %f", result, [result timeIntervalSinceReferenceDate]);
    
    OBPOSTCONDITION_EXPENSIVE(OFISEQUAL([result xmlDateString], xmlString));
    return result;
}

static NSString *_xmlStyleDateStringWithFormat(NSDate *self, SEL _cmd, NSString *formatString, BOOL currentTimeZone)
{
    DEBUG_XML_STRING(@"%s: input: %@ %f", __PRETTY_FUNCTION__, self, [self timeIntervalSinceReferenceDate]);
    
    CFTimeZoneRef timeZone = (OB_BRIDGE CFTimeZoneRef)(currentTimeZone ? [NSTimeZone localTimeZone] : [NSDate UTCTimeZone]);
    CFAbsoluteTime timeInterval = CFDateGetAbsoluteTime((CFDateRef)self);
    
    CFGregorianDate date = CFAbsoluteTimeGetGregorianDate(timeInterval, timeZone);
    DEBUG_XML_STRING(@"components: year:%d month:%d day:%d hour:%d minute:%d second:%f", date.year, date.month, date.day, date.hour, date.minute, date.second);
    
    // Figure out the milliseconds portion
    NSTimeInterval fractionalSeconds = date.second - floor(date.second);
    OBASSERT(fractionalSeconds >= 0.0);
    DEBUG_XML_STRING(@"fractionalSeconds: %f", fractionalSeconds);
    
    // Convert the milliseconds to an integer.  If this rolls over to the next second due to rounding, deal with it.
    unsigned milliseconds = (unsigned)rint(fractionalSeconds * 1000.0);
    if (milliseconds >= 1000) {
        milliseconds = 0;
        timeInterval += 1.0;
        date = CFAbsoluteTimeGetGregorianDate(timeInterval, timeZone);
    }
    
    NSString *result = [NSString stringWithFormat:formatString, date.year, date.month, date.day, date.hour, date.minute, (unsigned)floor(date.second), milliseconds];
    DEBUG_XML_STRING(@"result: %@", result);
    return result;
}

// date
- (NSString *)xmlDateString;
{
    return _xmlStyleDateStringWithFormat(self, _cmd, @"%04d-%02d-%02d", YES);
}

// dateTime
- (NSString *)xmlString;
{
    return _xmlStyleDateStringWithFormat(self, _cmd, @"%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", NO);
}

// Expects a string in the ICS format: YYYYMMdd.  This doesn't attempt to be very forgiving in parsing; the goal should be to feed in either nil/empty or a conforming string.
- initWithICSDateOnlyString:(NSString *)aString;
{
    // We expect exactly the length above, or an empty string.
    static const unsigned OFDateStringLength = 8;
    static NSTimeZone *cachedTimeZone;
    if (!cachedTimeZone) {
        cachedTimeZone = [[NSTimeZone localTimeZone] retain];
        OBASSERT(cachedTimeZone);
    }
    
    NSUInteger length = [aString length];
    if (length != OFDateStringLength) {
        OBASSERT(length == 0);
        BAD_INIT;
    }
    
    char buf[OFDateStringLength+1];
    if (![aString getCString:buf maxLength:sizeof(buf) encoding:NSASCIIStringEncoding]) {
        OBASSERT_NOT_REACHED("Unexpected encoding in ICS date");
	BAD_INIT;
    }
    
    CFGregorianDate date = {0};
    date.year = _parse4Digits(buf, 0);
    date.month = _parse2Digits(buf, 4);
    date.day = _parse2Digits(buf, 6);
    
    if (!CFGregorianDateIsValid(date, kCFGregorianAllUnits)) {
        OBASSERT_NOT_REACHED("Invalid component in ICS date");
	BAD_INIT;
    }
        
    CFAbsoluteTime absoluteTime = CFGregorianDateGetAbsoluteTime(date, (OB_BRIDGE CFTimeZoneRef)cachedTimeZone);

    DEBUG_XML_STRING(@"absoluteTime: %f", absoluteTime);
    
    NSDate *result = [self initWithTimeIntervalSinceReferenceDate:absoluteTime];
    DEBUG_XML_STRING(@"result: %@ %f", result, [result timeIntervalSinceReferenceDate]);
    
    OBPOSTCONDITION_EXPENSIVE(OFISEQUAL([result icsDateOnlyString], aString));
    return result;
}

- (NSString *)icsDateOnlyString;
{
    return _xmlStyleDateStringWithFormat(self, _cmd, @"%04d%02d%02d", YES);
}

// Expects a string in the ICS format: YYYYMMddTHHmmssZ.  This doesn't attempt to be very forgiving in parsing; the goal should be to feed in either nil/empty or a conforming string.
- initWithICSDateString:(NSString *)aString;
{
    // We expect exactly the length above, or an empty string.
    static const unsigned OFDateStringLength = 16;
    static NSTimeZone *cachedTimeZone;
    if (!cachedTimeZone) {
        cachedTimeZone = [[[self class] UTCTimeZone] retain];
        OBASSERT(cachedTimeZone);
    }
    
    NSUInteger length = [aString length];
    
    // allow omitting the trailing Z, and handle timezones outside of this method
    if (length != OFDateStringLength && length != (OFDateStringLength-1)) {
        OBASSERT(length == 0);
        BAD_INIT;
    }
    
    char buf[OFDateStringLength+1];
    if (![aString getCString:buf maxLength:sizeof(buf) encoding:NSASCIIStringEncoding]) {
        OBASSERT_NOT_REACHED("Unexpected encoding in ICS date");
	BAD_INIT;
    }
    
    CFGregorianDate date = {0};
    date.year = _parse4Digits(buf, 0);
    date.month = _parse2Digits(buf, 4);
    date.day = _parse2Digits(buf, 6);
    date.hour = _parse2Digits(buf, 9);
    date.minute = _parse2Digits(buf, 11);
    date.second = _parse2Digits(buf, 13);
    
    if (!CFGregorianDateIsValid(date, kCFGregorianAllUnits))
        BAD_INIT;

    CFAbsoluteTime absoluteTime = CFGregorianDateGetAbsoluteTime(date, (OB_BRIDGE CFTimeZoneRef)cachedTimeZone);

    DEBUG_XML_STRING(@"absoluteTime: %f", absoluteTime);
    
    NSDate *result = [self initWithTimeIntervalSinceReferenceDate:absoluteTime];
    DEBUG_XML_STRING(@"result: %@ %f", result, [result timeIntervalSinceReferenceDate]);
    
    OBPOSTCONDITION_EXPENSIVE(OFISEQUAL([result icsDateString], aString));
    return result;
}

- (NSString *)icsDateString;
{
    return _xmlStyleDateStringWithFormat(self, _cmd, @"%04d%02d%02dT%02d%02d%02dZ", NO);
}

- (NSString *)omnifocusSyncTransactionDateString;
{
    return _xmlStyleDateStringWithFormat(self, _cmd, @"%04d%02d%02d%02d%02d%02d", NO);
}

@end
