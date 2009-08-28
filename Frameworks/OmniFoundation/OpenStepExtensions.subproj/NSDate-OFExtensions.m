// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
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
        dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
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
    [[self init] release]; \
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
  unsigned d10, d1; \
  GET_DIGIT(d10, 0); \
  GET_DIGIT(d1, 1); \
  u = 10*d10 + d1; \
  offset += 2; \
} while(0)

#define READ_4UINT(u) do { \
    unsigned d1000, d100, d10, d1; \
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
    unsigned offset = 0;
    unsigned year, month, day;
    READ_4UINT(year);
    READ_CHAR('-');
    READ_2UINT(month);
    READ_CHAR('-');
    READ_2UINT(day);
    
    READ_CHAR('T'); // RFC 3339 allows 't' here too, but we don't right now.
    unsigned hour, minute, second;
    READ_2UINT(hour);
    READ_CHAR(':');
    READ_2UINT(minute);
    READ_CHAR(':');
    READ_2UINT(second);
    
    // Everything to this point is fixed width.
    OBASSERT(offset == 19);
    
    NSTimeInterval secondFraction = 0.0;
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
        secondFraction = (NSTimeInterval)fractionNumerator / (NSTimeInterval)fractionDenominator;
    }
    
    BOOL releaseCalendar = NO;
    NSCalendar *calendar;
    if (buf[offset] == 'Z') { // RFC 3339 allows 'z' here too, but we don't right now.
        if (buf[offset + 1] != 0)
            BAD_INIT; // Crud after the 'Z'.
        calendar = [NSDate gregorianUTCCalendar];
        OBASSERT([calendar timeZone] == [NSDate UTCTimeZone]); // Should have been set in the creation.
    } else if (buf[offset] == '-' || buf[offset] == '+') {
        BOOL negate = (buf[offset] == '-');
        offset++;
        
        unsigned tzHour, tzMinute;
        READ_2UINT(tzHour);
        READ_CHAR(':');
        READ_2UINT(tzMinute);
        
        // This isn't going to perform as well as the Z case.
        releaseCalendar = YES;
        calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
        
        NSInteger tzOffset = tzHour*3600+tzMinute*60;
        if (negate)
            tzOffset = -tzOffset;
        
        [calendar setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:tzOffset]];
    } else {
        // Unrecognized cruft where the timezone should have been.
        BAD_INIT;
    }
    
    // TODO: Leap seconds can cause the maximum allowed second value to be 58 or 60 depending on whether the adjustment is +/-1.  RFC 3339 has a table of some leap seconds up to 1998 that we could test with.
    // NOTE: This API doesn't deal with floating seconds.  Avoid some rounding error by passing in zero seconds and converting adding on the seconds an milliseconds to the result together.
    CFAbsoluteTime absoluteTime;
    const char *components = "yMdHms";
    Boolean success = CFCalendarComposeAbsoluteTime((CFCalendarRef)calendar, &absoluteTime, components, year, month, day, hour, minute, 0/*seconds*/);
    if (releaseCalendar)
        [calendar release];
    if (!success)
        BAD_INIT; // Bad components, most likely?  Month of 13 or the like.
    
    DEBUG_XML_STRING(@"absoluteTime: %f", absoluteTime);
    
    NSTimeInterval seconds = second + secondFraction;
    DEBUG_XML_STRING(@"seconds: %f", seconds);
    
    NSDate *result = [self initWithTimeIntervalSinceReferenceDate:absoluteTime + seconds];
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

static unsigned int _digitAt(const char *buf, unsigned int offset)
{
    char c = buf[offset];
    OBASSERT(c >= '0' && c <= '9');
    return c - '0';
}
static unsigned int _parse2Digits(const char *buf, unsigned int offset)
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
    static NSCalendar *cachedCalendar = nil;
    if (!cachedCalendar) {
        cachedCalendar = [[NSCalendar currentCalendar] retain];
        OBASSERT(cachedCalendar);
    }
    
    unsigned length = [xmlString length];
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
    
    unsigned year = _parse4Digits(buf, 0);
    unsigned month = _parse2Digits(buf, 5);
    unsigned day = _parse2Digits(buf, 8);
    
    // NOTE: This API doesn't deal with floating seconds.  Avoid some rounding error by passing in zero seconds and converting adding on the seconds an milliseconds to the result together.
    CFAbsoluteTime absoluteTime;
    const char *components = "yMd";
    if (!CFCalendarComposeAbsoluteTime((CFCalendarRef)cachedCalendar, &absoluteTime, components, year, month, day,  0))
        BAD_INIT;

    DEBUG_XML_STRING(@"absoluteTime: %f", absoluteTime);
    
    NSDate *result = [self initWithTimeIntervalSinceReferenceDate:absoluteTime];
    DEBUG_XML_STRING(@"result: %@ %f", result, [result timeIntervalSinceReferenceDate]);
    
    OBPOSTCONDITION_EXPENSIVE(OFISEQUAL([result xmlDateString], xmlString));
    return result;
}

static NSString *xmlDateStringIncludingTime(NSDate *self, SEL _cmd, BOOL includeTime)
{
    DEBUG_XML_STRING(@"%s: input: %@ %f", __PRETTY_FUNCTION__, self, [self timeIntervalSinceReferenceDate]);
    
    CFCalendarRef gregorianUTCCalendar = (CFCalendarRef)[NSDate gregorianUTCCalendar];
    CFAbsoluteTime timeInterval = CFDateGetAbsoluteTime((CFDateRef)self);
    
    // Extract the non-millisecond portion.
    unsigned year, month, day, hour, minute, second;
    const char *components = "yMdHms"; // signature of CFCalendarComposeAbsoluteTime is fixed in newer headers to take signed instead of unsigned, avoiding need for the cast.
    if (!CFCalendarDecomposeAbsoluteTime(gregorianUTCCalendar, timeInterval, components, &year, &month, &day, &hour, &minute, &second)) {
        OBRejectInvalidCall(self, _cmd, @"Cannot decompose date %@!", self);
        return nil;
    }
    DEBUG_XML_STRING(@"components: year:%d month:%d day:%d hour:%d minute:%d second:%d", year, month, day, hour, minute, second);
    
    // Figure out the milliseconds that got dropped
    NSTimeInterval fractionalSeconds = timeInterval - floor(timeInterval);
    OBASSERT(fractionalSeconds >= 0.0);
    DEBUG_XML_STRING(@"fractionalSeconds: %f", fractionalSeconds);
    
    // Convert the milliseconds to an integer.  If this rolls over to the next second due to rounding, deal with it.
    unsigned milliseconds = (unsigned)rint(fractionalSeconds * 1000.0);
    if (milliseconds >= 1000) {
        milliseconds = 0;
        timeInterval += 1.0;
        if (!CFCalendarDecomposeAbsoluteTime(gregorianUTCCalendar, timeInterval, components, &year, &month, &day, &hour, &minute, &second)) {
            OBRejectInvalidCall(self, _cmd, @"Cannot decompose time interval %f", timeInterval);
            return nil;
        }
    }
    
    NSString *result;
    
    if (includeTime)
        result = [NSString stringWithFormat:@"%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", year, month, day, hour, minute, second, milliseconds];
    else
        result = [NSString stringWithFormat:@"%04d-%02d-%02d", year, month, day];
    
    DEBUG_XML_STRING(@"result: %@", result);
    
    return result;
}

// date
- (NSString *)xmlDateString;
{
    return xmlDateStringIncludingTime(self, _cmd, NO);
}

// dateTime
- (NSString *)xmlString;
{
    return xmlDateStringIncludingTime(self, _cmd, YES);
}

@end

// 10.4 has a bug where -copyWithZone: apparently calls [self allocWithZone:] instead of [[self class] allocWithZone:].
#if defined(MAC_OS_X_VERSION_10_4) && MAC_OS_X_VERSION_MIN_ALLOWED <= MAC_OS_X_VERSION_10_4
#import <Foundation/NSCalendar.h>
@interface NSDateComponents (OFTigerFixes)
@end
@implementation NSDateComponents (OFTigerFixes)
- (id)allocWithZone:(NSZone *)zone;
{
    return [[self class] allocWithZone:zone];
}
@end
#endif
