// Copyright 2006-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRelativeDateFormatter.h>

#import <OmniFoundation/OFRelativeDateParser.h>
#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

@implementation OFRelativeDateFormatter

// Swift (for whatever reason) isn't seeing the initializer otherwise.
- init;
{
    self = [super init];
    if (self == nil)
        return nil;
    self.calendar = NSCalendar.autoupdatingCurrentCalendar;
    return self;
}

- (void)dealloc;
{
    [_defaultTimeDateComponents release];
    [_referenceDate release];
    [super dealloc];
}

#pragma mark API

- (void)setUseRelativeDayNames:(BOOL)useRelativeDayNames;
{
    // We either want our relative formatting or the system's, not both
    OBASSERT_IF(useRelativeDayNames, [self doesRelativeDateFormatting] == NO);
    
    _useRelativeDayNames = useRelativeDayNames;
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
    NSString *mins = [NSString stringWithFormat:@":%02ld", [comps minute]];
    NSString *timeString = [NSString stringWithFormat:@"%ld", hour];
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
- (nullable NSString *)stringForObjectValue:(nullable id)obj;
{
    if (!obj)
	return @"";
    
    // just return the basic NSDateFormatter values
    if (!_useRelativeDayNames && !_wantsTruncatedTime)
	return [super stringForObjectValue:obj];
    
    NSCalendar *cal = [self calendar];
    NSDateComponents *value = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitWeekday fromDate:obj];
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
    NSDateComponents *today = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:[NSDate date]];
    
    NSString * (^lowercaseIfNeeded)(NSString *) = ^NSString * (NSString *relativeDateString) {
        if (_wantsLowercaseRelativeDayNames) {
            return [relativeDateString lowercaseString];
        } else {
            return relativeDateString;
        }
    };

    // if today, and no time set, just say "Today", if there is a time, return the time
    if ([self dateStyle] == NSDateFormatterNoStyle) {
        DATE_STRING();
    } else if ([today year] == [value year] && [today month] == [value month] && [today day] == [value day]) {
        dateString = NSLocalizedStringFromTableInBundle(@"Today", @"OFDateProcessing", OMNI_BUNDLE, @"Today");
        dateString = lowercaseIfNeeded(dateString);
    } else if ([today year] == [value year] && [today month] == [value month] && [today day]+1 == [value day]) {
        dateString = NSLocalizedStringFromTableInBundle(@"Tomorrow", @"OFDateProcessing", OMNI_BUNDLE, @"Tomorrow");
        dateString = lowercaseIfNeeded(dateString);
    } else if ([today year] == [value year] && [today month] == [value month] && [today day]-1 == [value day]) {
        dateString = NSLocalizedStringFromTableInBundle(@"Yesterday", @"OFDateProcessing", OMNI_BUNDLE, @"Yesterday");
        dateString = lowercaseIfNeeded(dateString);
    } else {
        DATE_STRING();
    }
    
    if (_wantsTruncatedTime)
	return [[dateString stringByAppendingFormat:@" %@", truncatedTimeString(value, _defaultTimeDateComponents)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    
    NSDateFormatterStyle dateStyle = [self dateStyle];
    [self setDateStyle:NSDateFormatterNoStyle];
    NSString *timeString = [super stringForObjectValue:obj];
    if ( ! [NSString isEmptyString:timeString]) {
        dateString = [[dateString stringByAppendingFormat:@" %@", timeString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
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

- (nullable NSString *)editingStringForObjectValue:(id)obj;
{
    return [super stringForObjectValue:obj];
}

- (BOOL)getObjectValue:(out id _Nullable * _Nullable)obj forString:(NSString *)string errorDescription:(out NSString * _Nullable * _Nullable)error;
{
    // <bug:///101301> (Performance: Customers report ~1 second delays switch view modes [performance, slow, tab, perspective])
    // This was getting called during layout with Apple's text measurement string. No need to bother to try to parse it, which saves calling OFRelativeDateParser (which is relatively expensive).
    static NSString *appleLayoutString = @"Wj";
    if ([appleLayoutString isEqualToString:string]) {
        return NO;
    }

    // <bug:///101301> (Performance: Customers report ~1 second delays switch view modes [performance, slow, tab, perspective])
    // This happens when updating inspector text fields with @"". This case reports success but a nil *obj.
    if (string && [string isEqualToString:@""]) {
        *obj = nil;
        return YES;
    }

    NSError *relativeError = nil;
    NSDate *date = nil;
    
    BOOL success = [[OFRelativeDateParser sharedParser] getDateValue:&date forString:string fromStartingDate:_referenceDate useEndOfDuration:_useEndOfDuration defaultTimeDateComponents:_defaultTimeDateComponents calendar:[self calendar] withCustomFormat:self.dateFormat error:&relativeError];

    if (success) {
        *obj = date;
    }

#ifdef DEBUG
    if (!success) {

        // In case Apple's layout string changes, or we run into some other frequently-failing string we can test for, log failing cases when a certain count is reached.
        if (!string) {
            string = @"";
        }

        static NSCountedSet *failingCases = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            failingCases = [NSCountedSet new];
        });

        [failingCases addObject:string];
        NSInteger failureCount = [failingCases countForObject:string];

        static NSInteger failureCountThatTriggersLog = 25;
        if (failureCount == failureCountThatTriggersLog) {
            NSLog(@"-[OFRelativeDateFormatter getObjectValue:forString:errorDescription:] failed %@ times with the string: %@", @(failureCount), string);
        }
    }
#endif

    return success;
 }

- (BOOL)isPartialStringValid:(NSString * _Nonnull * _Nonnull)partialStringPtr proposedSelectedRange:(nullable NSRangePointer)proposedSelRangePtr originalString:(NSString *)origString originalSelectedRange:(NSRange)origSelRange errorDescription:(NSString * _Nullable * _Nullable)error;
{
    return YES;
}

- (BOOL)getObjectValue:(out id _Nullable * _Nullable)obj forString:(NSString *)string range:(inout nullable NSRange *)rangep error:(out NSError **)error;
{
    NSDate *date = nil;
    BOOL success = [[OFRelativeDateParser sharedParser] getDateValue:&date forString:string fromStartingDate:_referenceDate useEndOfDuration:_useEndOfDuration defaultTimeDateComponents:_defaultTimeDateComponents calendar:[self calendar] withCustomFormat:self.dateFormat error:error];

    if (success)
        *obj = date;

    return success;
}

#pragma mark NSCopying

- (id)copyWithZone:(nullable NSZone *)zone;
{
    OFRelativeDateFormatter *copy = [super copyWithZone:zone];
    copy->_defaultTimeDateComponents = [_defaultTimeDateComponents copy];
    copy->_useEndOfDuration = _useEndOfDuration;
    copy->_useRelativeDayNames = _useRelativeDayNames;
    copy->_wantsLowercaseRelativeDayNames = _wantsLowercaseRelativeDayNames;
    copy->_wantsTruncatedTime = _wantsTruncatedTime;
    return copy;
}

@end

NS_ASSUME_NONNULL_END

