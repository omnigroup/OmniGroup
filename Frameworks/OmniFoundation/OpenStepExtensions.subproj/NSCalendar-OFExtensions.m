// Copyright 2016-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSCalendar-OFExtensions.h>

#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$")

@implementation NSCalendar (OFExtensions)

+ (nonnull NSCalendar *)cachedCalendar;
{
    static NSCalendar *cachedCalendar = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cachedCalendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        OFPreference *preference = [NSCalendar firstDayOfTheWeekPreference];
        if ([preference hasNonDefaultValue])
            [cachedCalendar setFirstWeekday:[preference unsignedIntegerValue] + 1];
        else {
            NSCalendar *currentCalendar = [NSCalendar currentCalendar];
            if ([[currentCalendar calendarIdentifier] isEqualToString:NSCalendarIdentifierGregorian]) {
                [cachedCalendar setFirstWeekday:[currentCalendar firstWeekday]];
                [cachedCalendar setMinimumDaysInFirstWeek:[currentCalendar minimumDaysInFirstWeek]];
            }
        }
        
        OBASSERT(cachedCalendar);
    });
    
    return cachedCalendar;
}

+ (NSUInteger)preferredDayOfTheWeekOffset;
{
    OFPreference *preference = [NSCalendar firstDayOfTheWeekPreference];
    if ([preference hasNonDefaultValue])
        return [preference unsignedIntegerValue];
    else
        return [[NSCalendar cachedCalendar] firstWeekday] - 1;
}

+ (OFPreference *)firstDayOfTheWeekPreference;
{
    static OFPreference *firstDayOfTheWeek;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        firstDayOfTheWeek = [OFPreference preferenceForKey:@"FirstDayOfTheWeek"];
    });
    
    return firstDayOfTheWeek;
}

@end
