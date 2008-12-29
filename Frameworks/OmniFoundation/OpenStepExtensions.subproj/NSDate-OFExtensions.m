// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSDate-OFExtensions.h>

#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFNull.h>

#import <Foundation/NSCalendarDate.h>
#import <Foundation/NSDateFormatter.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSDate-OFExtensions.m 104651 2008-09-09 07:09:15Z kc $")

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
        tz = [[NSTimeZone timeZoneWithAbbreviation:@"UTC"] retain];
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

    static void _appendUnit(NSDateComponents *self, NSMutableString *str, NSString *name, int value) {
        if (value != NSUndefinedDateComponent)
            [str appendFormat:@" %@:%d", name, value];
    }
#define APPEND(x) _appendUnit(self, desc, @#x, [self x])
    static NSString *_comp(NSDateComponents *self) {
        NSMutableString *desc = [NSMutableString stringWithString:@"<components:"];
        
        APPEND(era);
        APPEND(year);
        APPEND(month);
        APPEND(day);
        APPEND(hour);
        APPEND(minute);
        APPEND(second);
        APPEND(week);
        APPEND(weekday);
        APPEND(weekdayOrdinal);
#undef APPEND
        
        [desc appendString:@">"];
        return desc;
    }
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

// The setup of this formatter cannot be changed willy-nilly.  This is used in XML archiving, and our file formats need to be stable.  Luckily this is a nicely defined format.
static NSDateFormatter *formatterWithoutMilliseconds(void)
{
    static NSDateFormatter *DateFormatter = nil;
    
    if (!DateFormatter) {
        DateFormatter = [[NSDateFormatter alloc] init];
        [DateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
        OBASSERT([DateFormatter formatterBehavior] == NSDateFormatterBehavior10_4);
        
        NSCalendar *cal = [NSDate gregorianUTCCalendar];
        if (!cal)
            OBASSERT_NOT_REACHED("Built-in calendar missing");
        else {
            OBASSERT([cal timeZone] == [NSDate UTCTimeZone]); // Should have been set in the creation.
            
            [DateFormatter setCalendar:cal];
            
            NSTimeZone *tz = [NSDate UTCTimeZone];
            if (!tz)
                OBASSERT_NOT_REACHED("Can't find UTC time zone");
            else {
                // NOTE: NSDateComponents has busted API since -second returns an integer instead of a floating point (Radar 4867971).  Otherwise, we could conceivably implement our formatting by getting the components for the date and then using NSString formatting directly.
                // Asking the date formatter to do the seconds doesn't work either -- Radar 4886510; NSDateFormatter/ICU is truncating the milliseconds instead of rounding it.
                // So, we format up to the milliseconds and -xmlString does the rest.  Sigh.
                [DateFormatter setTimeZone:tz];
                [DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss'."];
            }
        }
    }
    
    OBPOSTCONDITION([DateFormatter formatterBehavior] == NSDateFormatterBehavior10_4);
    return DateFormatter;
}

// The setup of this formatter cannot be changed willy-nilly.  This is used in XML archiving, and our file formats need to be stable.  Luckily this is a nicely defined format.
static NSDateFormatter *formatterWithoutTime(void)
{
    static NSDateFormatter *DateFormatter = nil;
    
    if (!DateFormatter) {
        DateFormatter = [[NSDateFormatter alloc] init];
        [DateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
	[DateFormatter setTimeStyle:NSDateFormatterNoStyle];
	
        OBASSERT([DateFormatter formatterBehavior] == NSDateFormatterBehavior10_4);
        
        NSCalendar *cal = [NSDate gregorianUTCCalendar];
        if (!cal)
            OBASSERT_NOT_REACHED("Built-in calendar missing");
        else {
            OBASSERT([cal timeZone] == [NSDate UTCTimeZone]); // Should have been set in the creation.
            
            [DateFormatter setCalendar:cal];
            
            NSTimeZone *tz = [NSDate UTCTimeZone];
            if (!tz)
                OBASSERT_NOT_REACHED("Can't find UTC time zone");
            else {
                [DateFormatter setTimeZone:tz];
                [DateFormatter setDateFormat:@"yyyy'-'MM'-'dd'"];
            }
        }
    }
    
    OBPOSTCONDITION([DateFormatter formatterBehavior] == NSDateFormatterBehavior10_4);
    return DateFormatter;
}

// date
- (NSString *)xmlDateString;
{
    DEBUG_XML_STRING(@"-xmlString -- input: %@ %f", self, [self timeIntervalSinceReferenceDate]);
    
    NSString *result = [formatterWithoutTime() stringFromDate:self];
    
    DEBUG_XML_STRING(@"result: %@", result);
    
    return result;
}

// dateTime
- (NSString *)xmlString;
{
    DEBUG_XML_STRING(@"-xmlString -- input: %@ %f", self, [self timeIntervalSinceReferenceDate]);

    // Convert ourselves to date components and back, which drops the milliseconds.
    NSCalendar *calendar = [NSDate gregorianUTCCalendar];
    NSDateComponents *components = [calendar components:NSEraCalendarUnit|NSYearCalendarUnit|NSMonthCalendarUnit|NSDayCalendarUnit|NSHourCalendarUnit|NSMinuteCalendarUnit|NSSecondCalendarUnit fromDate:self];
    DEBUG_XML_STRING(@"components: %@", _comp(components));

    NSDate *truncated = [calendar dateFromComponents:components];

    DEBUG_XML_STRING(@"truncated: %@", truncated);

    // Figure out the milliseconds that got dropped
    NSTimeInterval milliseconds = [self timeIntervalSinceReferenceDate] - [truncated timeIntervalSinceReferenceDate];
    
    DEBUG_XML_STRING(@"milliseconds: %f", milliseconds);

    // Append the milliseconds, using rounding.
    NSString *formattedString = [formatterWithoutMilliseconds() stringFromDate:self];
    DEBUG_XML_STRING(@"formattedString: %@", formattedString);
    
    NSString *result = [formattedString stringByAppendingFormat:@"%03dZ", (int)rint(milliseconds * 1000.0)];
    DEBUG_XML_STRING(@"result: %@", result);
    
    return result;
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
