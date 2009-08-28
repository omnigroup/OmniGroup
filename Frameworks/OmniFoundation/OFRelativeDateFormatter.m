// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRelativeDateFormatter.h>

#import <OmniFoundation/OFRelativeDateParser.h>
#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$");

@implementation OFRelativeDateFormatter

- (void)dealloc;
{
    [_defaultTimeDateComponents release];
    [super dealloc];
}

#pragma mark API

@synthesize defaultTimeDateComponents = _defaultTimeDateComponents;
@synthesize useEndOfDuration = _useEndOfDuration;

- (void)setUseRelativeDayNames:(BOOL)useRelativeDayNames;
{
    _useRelativeDayNames = useRelativeDayNames;
}

- (BOOL)useRelativeDayNames;
{
    return _useRelativeDayNames;
}

- (void)setWantsTruncatedTime:(BOOL)wantsTruncatedTime;
{
    _wantsTruncatedTime = wantsTruncatedTime;
}

- (BOOL)wantsTruncatedTime;
{
    return _wantsTruncatedTime;   
}

#pragma mark NSFomatter subclass

static NSString *truncatedTimeString(NSDateComponents *comps, NSDateComponents *defaultDateComps)
{
    NSInteger defaultHour = 0;
    NSInteger defaultMinute = 0;
    if (defaultDateComps) {
	defaultHour = [defaultDateComps hour];
	defaultMinute = [defaultDateComps minute];
    }
    // don't display the time if its the default time
    if ([comps hour] == defaultHour && [comps minute] == defaultMinute)
	return @"";
    
    NSInteger hour = [comps hour];
    if (hour > 12)
	hour-=12;
    NSString *meridian = ([comps hour] < 12) ? @"a" : @"p";
    NSString *mins = [NSString stringWithFormat:@":%02d", [comps minute]];
    NSString *timeString = [NSString stringWithFormat:@"%d", hour];
    if ([comps minute] != 0)
	timeString = [timeString stringByAppendingString:mins];
    timeString = [timeString stringByAppendingString:meridian];
    return timeString;
}

#define DATE_STRING() do { \
[self setTimeStyle:NSDateFormatterNoStyle]; \
dateString = [super stringForObjectValue:obj]; \
[self setTimeStyle:timeStyle]; \
} while (0)

#if 1
- (NSString *)stringForObjectValue:(id)obj;
{
    if (!obj)
	return @"";
    
    // just return the basic NSDateFormatter values
    if (!_useRelativeDayNames && !_wantsTruncatedTime)
	return [super stringForObjectValue:obj];
    
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *value = [cal components:NSYearCalendarUnit|NSMonthCalendarUnit|NSDayCalendarUnit|NSHourCalendarUnit|NSMinuteCalendarUnit|NSWeekdayCalendarUnit fromDate:obj];
    NSDateFormatterStyle timeStyle = [self timeStyle];
    NSString *dateString = @"";

    // return truncated time, but not relative day names (if we're set to return the date at all)
    if (!_useRelativeDayNames && _wantsTruncatedTime) {
	if (timeStyle != NSDateFormatterNoStyle) {
	    // get the default date string, but make our own truncated time
	    DATE_STRING();
	    return [dateString stringByAppendingFormat:@" %@", truncatedTimeString(value, _defaultTimeDateComponents)];
	}
    }
    
    // construct relative day names
    NSDateComponents *today = [cal components:NSYearCalendarUnit|NSMonthCalendarUnit|NSDayCalendarUnit fromDate:[NSDate date]];
        
    // if today, and no time set, just say "Today", if there is a time, return the time
    if ([today year] == [value year] && [today month] == [value month] && [today day] == [value day])
	dateString = NSLocalizedStringFromTableInBundle(@"Today", @"DateProcessing", OMNI_BUNDLE, @"Today");
    else if ([today year] == [value year] && [today month] == [value month] && [today day]+1 == [value day])
	dateString = NSLocalizedStringFromTableInBundle(@"Tomorrow", @"DateProcessing", OMNI_BUNDLE, @"Tomorrow");
    else if ([today year] == [value year] && [today month] == [value month] && [today day]-1 == [value day])
	dateString = NSLocalizedStringFromTableInBundle(@"Yesterday", @"DateProcessing", OMNI_BUNDLE, @"Yesterday");
    else 
	DATE_STRING();
    
    if (_wantsTruncatedTime)
	return [dateString stringByAppendingFormat:@" %@", truncatedTimeString(value, _defaultTimeDateComponents)];
    
    NSDateFormatterStyle dateStyle = [self dateStyle];
    [self setDateStyle:NSDateFormatterNoStyle];
    dateString = [dateString stringByAppendingFormat:@" %@", [super stringForObjectValue:obj]]; 
    [self setDateStyle:dateStyle];
    return dateString;
}
#endif

#if 0
- (NSAttributedString *)attributedStringForObjectValue:(id)obj withDefaultAttributes:(NSDictionary *)attrs;
{
    NSAttributedString *result = [super attributedStringForObjectValue:obj withDefaultAttributes:attrs];
    //NSLog(@"%s: obj:%@ result:%@", __PRETTY_FUNCTION__, obj, result);
    return result;
}
#endif

- (NSString *)editingStringForObjectValue:(id)obj;
{
    return [super stringForObjectValue:obj];
}

- (BOOL)getObjectValue:(out id *)obj forString:(NSString *)string errorDescription:(out NSString **)error;
{
    NSError *relativeError = nil;
    NSDate *date = nil;
    
    BOOL success = [[OFRelativeDateParser sharedParser] getDateValue:&date forString:string useEndOfDuration:_useEndOfDuration defaultTimeDateComponents:_defaultTimeDateComponents error:&relativeError];

    if (success)
        *obj = date;
    
    return success;
 }

- (BOOL)isPartialStringValid:(NSString **)partialStringPtr proposedSelectedRange:(NSRangePointer)proposedSelRangePtr originalString:(NSString *)origString originalSelectedRange:(NSRange)origSelRange errorDescription:(NSString **)error;
{
    NSError *relativeError = nil;
    NSDate *date = nil;
    return [[OFRelativeDateParser sharedParser] getDateValue:&date forString:*partialStringPtr useEndOfDuration:_useEndOfDuration defaultTimeDateComponents:_defaultTimeDateComponents error:&relativeError];
}

- (BOOL)getObjectValue:(out id *)obj forString:(NSString *)string range:(inout NSRange *)rangep error:(out NSError **)error;
{
    NSDate *date = nil;
    BOOL success = [[OFRelativeDateParser sharedParser] getDateValue:&date forString:string useEndOfDuration:_useEndOfDuration defaultTimeDateComponents:_defaultTimeDateComponents error:error];

    if (success)
        *obj = date;

    return success;
}

- (NSString *)stringFromDate:(NSDate *)date;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (NSDate *)dateFromString:(NSString *)string;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    OFRelativeDateFormatter *copy = [super copyWithZone:zone];
    copy->_defaultTimeDateComponents = [_defaultTimeDateComponents copy];
    return copy;
}

@end
