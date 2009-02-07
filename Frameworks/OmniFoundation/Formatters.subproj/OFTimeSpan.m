// Copyright 2006-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFTimeSpan.h>

#import <OmniBase/rcsid.h>

#import <OmniFoundation/OFTimeSpanFormatter.h>

RCS_ID("$Id$")

@implementation OFTimeSpan

- initWithTimeSpanFormatter:(OFTimeSpanFormatter *)aFormatter;
{
    OBPRECONDITION(aFormatter); // Needed for converting to seconds.
    
    [super init];
    createdByFormatter = [aFormatter retain];
    memset(&_components, 0, sizeof(_components));
    return self;
}

- (void)dealloc;
{
    [createdByFormatter release];
    [super dealloc];
}

- (void)setYears:(float)aValue;
{
    _components.years = aValue;
}

- (void)setMonths:(float)aValue;
{
    _components.months = aValue;
}

- (void)setWeeks:(float)aValue;
{
    _components.weeks = aValue;
}

- (void)setDays:(float)aValue;
{
    _components.days = aValue;
}

- (void)setHours:(float)aValue;
{
    _components.hours = aValue;
}

- (void)setMinutes:(float)aValue;
{
    _components.minutes = aValue;
}

- (void)setSeconds:(float)aValue;
{
    _components.seconds = aValue;
}

- (float)years;
{
    return _components.years;
}

- (float)months;
{
    return _components.months;
}

- (float)weeks;
{
    return _components.weeks;
}

- (float)days;
{
    return _components.days;
}

- (float)hours;
{
    return _components.hours;
}

- (float)minutes;
{
    return _components.minutes;
}

- (float)seconds;
{   
    return _components.seconds;
}

- (float)floatValue;
{
    float result = [self floatValueInSeconds];
    if (![createdByFormatter floatValuesInSeconds])
	result /= 3600.0;
    return result;
}

- (float)floatValueInSeconds;
{
    return (_components.years * (float)[createdByFormatter hoursPerYear] + _components.months * (float)[createdByFormatter hoursPerMonth] + _components.weeks * (float)[createdByFormatter hoursPerWeek] + _components.days * (float)[createdByFormatter hoursPerDay] + _components.hours) * 3600.0 + _components.minutes*60.0 + _components.seconds;
}

- (BOOL)isZero;
{
    unsigned int componentIndex = sizeof(_components) / sizeof(float);
    const float *component = (const float *)&_components;
    while (componentIndex--) {
        if (fabs(component[componentIndex]) != 0.0f) // negative zero ftw.
            return NO;
    }
    return YES;
}

#pragma mark -
#pragma mark Comparison

- (BOOL)isEqual:(id)otherObject;
{
    if (![otherObject isKindOfClass:[self class]])
        return NO;
    
    OFTimeSpan *otherSpan = otherObject;
    return (memcmp(&_components, &otherSpan->_components, sizeof(_components)) == 0);
}

- (NSUInteger)hash;
{
    OBASSERT_NOT_REACHED("-isEqual: defined, but -hash not -- this would break hashing invariants");
    return 0;
}

#pragma mark -
#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    OFTimeSpan *result = [[OFTimeSpan allocWithZone:zone] initWithTimeSpanFormatter:createdByFormatter];
    memcpy(&result->_components, &_components, sizeof(_components));
    return result;
}

#pragma mark -
#pragma mark Debugging

- (NSString *)shortDescription;
{
    NSMutableString *result = [NSMutableString stringWithFormat:@"<%@: %p --", NSStringFromClass([self class]), self];
    
    if (_components.years != 0.0f)
        [result appendFormat:@" %gy", _components.years];
    if (_components.months != 0.0f)
        [result appendFormat:@" %gmo", _components.months];
    if (_components.weeks != 0.0f)
        [result appendFormat:@" %gw", _components.weeks];
    if (_components.days != 0.0f)
        [result appendFormat:@" %gd", _components.days];
    if (_components.hours != 0.0f)
        [result appendFormat:@" %gh", _components.hours];
    if (_components.minutes != 0.0f)
        [result appendFormat:@" %gm", _components.minutes];
    if (_components.seconds != 0.0f)
        [result appendFormat:@" %gs", _components.seconds];
    [result appendString:@" >"];
    return result;
}

@end
