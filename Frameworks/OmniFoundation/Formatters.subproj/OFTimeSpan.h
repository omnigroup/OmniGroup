// Copyright 2006-2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/Formatters.subproj/OFTimeSpan.h 89466 2007-08-01 23:35:13Z kc $

#import <Foundation/NSObject.h>

@class OFTimeSpanFormatter;

@interface OFTimeSpan : NSObject <NSCopying>
{
    OFTimeSpanFormatter *createdByFormatter;
    struct {
        float years, months, weeks, days, hours, minutes, seconds;
    } _components;
}

- initWithTimeSpanFormatter:(OFTimeSpanFormatter *)aFormatter;

- (void)setYears:(float)aValue;
- (void)setMonths:(float)aValue;
- (void)setWeeks:(float)aValue;
- (void)setDays:(float)aValue;
- (void)setHours:(float)aValue;
- (void)setMinutes:(float)aValue;
- (void)setSeconds:(float)aValue;

- (float)years;
- (float)months;
- (float)weeks;
- (float)days;
- (float)hours;
- (float)minutes;
- (float)seconds;

- (float)floatValue;
- (float)floatValueInSeconds;

- (BOOL)isZero;

@end
