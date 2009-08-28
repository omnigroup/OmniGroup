// Copyright 1998-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDateFormatter.h>

#import <OmniFoundation/NSObject-OFExtensions.h>
#import <Foundation/NSCalendarDate.h>

RCS_ID("$Id$")

@implementation OFDateFormatter

enum DateState {
    ScanMonth, ScanLongMonth, ScanLateMonth, ScanMonthSlash, ScanDay, ScanLongDay, ScanDaySlash, ScanYear, ScanCentury, ScanDecade, ScanYearLast, Done
};

static unsigned int lastPossibleDayOfMonth[12] = {31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

#warning Localize this.
// Different locales use different date formats; in particular the order of the day, month, and year is different in different parts of the world. See /System/Library/Frameworks/Foundation.framework/Versions/Current/Resources/Languages/Default for a list of all locale-specific information.

- (NSString *)stringForObjectValue:(id)object;
{
    if ([object isKindOfClass:[NSCalendarDate class]])
        return [(NSCalendarDate *)object descriptionWithCalendarFormat:@"%m/%d/%Y"];
    else
        return nil;
}

- (BOOL)getObjectValue:(id *)anObject forString:(NSString *)string errorDescription:(NSString **)error;
{
    if (!anObject)
        return YES;
    
    if ([string length] == 8) {
        *anObject = [NSCalendarDate dateWithString:string calendarFormat:@"%m/%d/%y"];
        if ([string characterAtIndex:6] <= '3')
            *anObject = [*anObject dateByAddingYears:100 months:0 days:0 hours:0 minutes:0 seconds:0];
        return YES;
    } else if ([string length] == 10) {
        *anObject = [NSCalendarDate dateWithString:string calendarFormat:@"%m/%d/%Y"];
        return YES;
    } else if (!string || ![string length]) {
        *anObject = nil;
        return YES;
    } else {
        if (error)
            *error = NSLocalizedStringFromTableInBundle(@"That is not a valid date.", @"OmniFoundation", [OFDateFormatter bundle], @"formatter input error");
        *anObject = nil;
        return NO;
    }
}

- (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error;
{
    unsigned int length = [partialString length];
    unsigned int characterIndex;
    enum DateState state = ScanMonth;
    unichar result[12];
    unichar *resultPtr = result;
    unichar c;
    BOOL changed = NO;
    unsigned int month = 0;
    unsigned int day = 0;
   
    for (characterIndex = 0; characterIndex < length; characterIndex++) {
	changed = NO;
        c = [partialString characterAtIndex:characterIndex];

        switch(state) {
        case ScanMonth:
            if (c == '0') {
                *resultPtr++ = c;
                state = ScanLongMonth;            
            } else if (c == '1') {
                *resultPtr++ = c;
                state = ScanLateMonth;
            } else if ((c >= '2') && (c <= '9')) {
                *resultPtr++ = '0';
                *resultPtr++ = c;
                state = ScanMonthSlash;
                changed = YES;
            } else {
                changed = YES;
            }
            break;
        case ScanLongMonth:
            if ((c >= '1') && (c <= '9')) {
                *resultPtr++ = c;
                state = ScanMonthSlash;
                month = c - '0';
            } else {
                changed = YES;
            }
            break;
        case ScanLateMonth:
            if ((c >= '0') && (c <= '2')) {
                *resultPtr++ = c;
                month = 10 + c - '0';
                state = ScanMonthSlash;
            } else if (c == '/') {
                resultPtr[-1] = '0';
                *resultPtr++ = '1';
                *resultPtr++ = '/';
                month = 1;
                state = ScanDay;
                changed = YES;
            } else if (c == '3') {
                resultPtr[-1] = '0';
                *resultPtr++ = '1';
                *resultPtr++ = '/';
                *resultPtr++ = c;
                month = 1;
                state = ScanLongDay;
                day = 10 * (c - '0');
                changed = YES;
            } else if ((c >= '4') && (c <= '9')) {
                resultPtr[-1] = '0';
                *resultPtr++ = '1';
                *resultPtr++ = '/';
                *resultPtr++ = '0';
                *resultPtr++ = c;
                month = 1;
                state = ScanDaySlash;
                day = c - '0';
                changed = YES;
            } else {
                changed = YES;
            }
            break;
        case ScanMonthSlash:
            if (c == '/') {
                *resultPtr++ = c;
                state = ScanDay;
            } else if ((c >= '0') && (c <= '9')) {
                *resultPtr++ = '/';
                characterIndex--;
                state = ScanDay;
                changed = YES;
            } else {
                changed = YES;
            }
            break;
        case ScanDay:
            if ((c >= '0') && (c <= '2')) {
                *resultPtr++ = c;
                day = (c - '0') * 10;
                state = ScanLongDay;
            } else if (c == '3') {
                if (month == 2) {
                    *resultPtr++ = '0';
                    *resultPtr++ = c;
                    day = c - '0';
                    state = ScanDaySlash;
                    changed = YES;
                } else {
                    *resultPtr++ = c;
                    day = (c - '0') * 10;
                    state = ScanLongDay;                 
                }
            } else if ((c >= '4') && (c <= '9')) {
                *resultPtr++ = '0';
                *resultPtr++ = c;
                day = c - '0';
                state = ScanDaySlash;
                changed = YES;
            } else {
                changed = YES;
            }
            break;
        case ScanLongDay:
            if ((c >= '0') && (c <= '9')) {
                day += c - '0';
                if (day > lastPossibleDayOfMonth[month-1]) {
                    day -= c - '0';
                    *resultPtr = resultPtr[-1];
                    resultPtr[-1] = '0';
                    resultPtr++;
                    *resultPtr++ = '/';
                    characterIndex--;
                    state = ScanYear;
                    changed = YES;
                } else {
                    *resultPtr++ = c;
                    state = ScanDaySlash;
                }
            } else if (c == '/') {
                *resultPtr = resultPtr[-1];
                resultPtr[-1] = '0';
                resultPtr++;
                *resultPtr++ = '/';
                state = ScanYear;
                changed = YES;
            } else {
                changed = YES;
            }
            break;
        case ScanDaySlash:
            if (c == '/') {
                *resultPtr++ = c;
                state = ScanYear;
            } else if ((c >= '0') && (c <= '9')) {
                *resultPtr++ = '/';
                characterIndex--;
                state = ScanYear;
                changed = YES;
            } else {
                changed = YES;
            }
            break;
        case ScanYear:
            if ((c == '1') || (c == '2')) {
                *resultPtr++ = c;
                state = ScanCentury;
            } else if ((c == '0') || (c == '3')) {
                *resultPtr++ = '2';
                *resultPtr++ = '0';
                *resultPtr++ = c;
                state = ScanYearLast;
                changed = YES;
            } else if ((c >= '4') && (c <= '9')) {
                *resultPtr++ = '1';
                *resultPtr++ = '9';
                *resultPtr++ = c;
                state = ScanYearLast;
                changed = YES;
            } else {
                changed = YES;
            }
            break;
        case ScanCentury:
            if (((resultPtr[-1] == '1') && (c == '9')) || ((resultPtr[-1] == '2') && (c == '0'))) {
                *resultPtr++ = c;
                state = ScanDecade;
            } else if ((c >= '0') && (c <= '9')) {
                unichar decade = resultPtr[-1];

                if (decade >= '4') {
                    resultPtr[-1] = '1';
                    *resultPtr++ = '9';
                    *resultPtr++ = decade;
                    *resultPtr++ = c;
                    changed = YES;
                    state = Done;
                } else {
                    resultPtr[-1] = '2';
                    *resultPtr++ = '0';
                    *resultPtr++ = decade;
                    *resultPtr++ = c;
                    changed = YES;
                    state = Done;
                }
            } else {
                changed = YES;
            }
            break;
        case ScanDecade:
            if (c >= '0' && c <= '9') {
                *resultPtr++ = c;
                state = ScanYearLast;
            } else {
                changed = YES;
            }
            break;
        case ScanYearLast:
            if (c >= '0' && c <= '9') {
                *resultPtr++ = c;
                state = Done;
            } else {
                changed = YES;
            }
            break;
        case Done:
            changed = YES;
            break;
        }
    }
    if (changed)
        *newString = [NSString stringWithCharacters:result length:(resultPtr - result)];
    return !changed;
}

@end
