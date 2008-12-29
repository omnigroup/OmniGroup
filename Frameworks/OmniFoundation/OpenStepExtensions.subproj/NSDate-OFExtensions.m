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
static unsigned int _parse3Digits(const char *buf, unsigned int offset)
{
    return 100*_digitAt(buf, offset+0) + 10*_digitAt(buf, offset+1) + _digitAt(buf, offset+2);
}
static unsigned int _parse4Digits(const char *buf, unsigned int offset)
{
    return 1000*_digitAt(buf, offset+0) + 100*_digitAt(buf, offset+1) + 10*_digitAt(buf, offset+2) + _digitAt(buf, offset+3);
}

// Expects a string in the XML Schema / ISO 8601 format: YYYY-MM-ddTHH:mm:ss.SSSZ.  This doesn't attempts to be very forgiving in parsing; the goal should be to feed in either nil/empty or a conforming string.
- initWithXMLString:(NSString *)xmlString;
{
    // We expect exactly the length above, or an empty string.
    static const unsigned OFXMLDateStringLength = 24;
    
    unsigned length = [xmlString length];
    if (length != OFXMLDateStringLength) {
        OBASSERT(length == 0);
        [[self init] release]; // plain -release w/o -init will crash on 10.4.11/Intel
        return nil;
    }
    
    char buf[OFXMLDateStringLength+1];
    if (![xmlString getCString:buf maxLength:sizeof(buf) encoding:NSASCIIStringEncoding]) {
        OBASSERT_NOT_REACHED("Unexpected encoding in XML date");
	[[self init] release]; // plain -release w/o -init will crash on 10.4.11/Intel
        return nil;
    }
    
    // TODO: Not checking the delimiters or digit-ness of number ranges yet.
    
    unsigned year = _parse4Digits(buf, 0);
    unsigned month = _parse2Digits(buf, 5);
    unsigned day = _parse2Digits(buf, 8);
    
    unsigned hour = _parse2Digits(buf, 11);
    unsigned minute = _parse2Digits(buf, 14);
    unsigned intSecond = _parse2Digits(buf, 17);
    unsigned intMillisecond = _parse3Digits(buf, 20);
    
    NSCalendar *gregorianUTCCalendar = [NSDate gregorianUTCCalendar];
    OBASSERT([gregorianUTCCalendar timeZone] == [NSDate UTCTimeZone]); // Should have been set in the creation.
    
    // NOTE: This API doesn't deal with floating seconds.  Avoid some rounding error by passing in zero seconds and converting adding on the seconds an milliseconds to the result together.
    CFAbsoluteTime absoluteTime;
    const char *components = "yMdHms";
    if (!CFCalendarComposeAbsoluteTime((CFCalendarRef)gregorianUTCCalendar, &absoluteTime, components, year, month, day, hour, minute, 0)) {
	[[self init] release]; // plain -release w/o -init will crash on 10.4.11/Intel
        return nil;
    }
    DEBUG_XML_STRING(@"absoluteTime: %f", absoluteTime);
    
    NSTimeInterval seconds = 0.001 * (1000*intSecond + intMillisecond);
    DEBUG_XML_STRING(@"seconds: %f", seconds);
    
    NSDate *result = [self initWithTimeIntervalSinceReferenceDate:absoluteTime + seconds];
    DEBUG_XML_STRING(@"result: %@ %f", result, [result timeIntervalSinceReferenceDate]);
    
    OBPOSTCONDITION_EXPENSIVE(OFISEQUAL([result xmlString], xmlString));
    return result;
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
        [[self init] release]; // plain -release w/o -init will crash on 10.4.11/Intel
        return nil;
    }
    
    char buf[OFXMLDateStringLength+1];
    if (![xmlString getCString:buf maxLength:sizeof(buf) encoding:NSASCIIStringEncoding]) {
        OBASSERT_NOT_REACHED("Unexpected encoding in XML date");
	[[self init] release]; // plain -release w/o -init will crash on 10.4.11/Intel
        return nil;
    }
    
    // TODO: Not checking the delimiters or digit-ness of number ranges yet.
    
    unsigned year = _parse4Digits(buf, 0);
    unsigned month = _parse2Digits(buf, 5);
    unsigned day = _parse2Digits(buf, 8);
    
    // NOTE: This API doesn't deal with floating seconds.  Avoid some rounding error by passing in zero seconds and converting adding on the seconds an milliseconds to the result together.
    CFAbsoluteTime absoluteTime;
    const char *components = "yMd";
    if (!CFCalendarComposeAbsoluteTime((CFCalendarRef)cachedCalendar, &absoluteTime, components, year, month, day,  0)) {
	[[self init] release]; // plain -release w/o -init will crash on 10.4.11/Intel
        return nil;
    }
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
