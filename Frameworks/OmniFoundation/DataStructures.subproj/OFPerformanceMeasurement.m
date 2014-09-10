// Copyright 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFPerformanceMeasurement.h>

#if OF_PERFORMANCE_MEASUREMENT_ENABLED

RCS_ID("$Id$");

@implementation OFPerformanceMeasurement
{
    NSMutableArray *_values;
}

// Not intented to be super-high precision, but reasonable for larger operations (100ths of seconds).

- init;
{
    if (!(self = [super init]))
        return nil;
    
    _values = [[NSMutableArray alloc] init];
    
    return self;
}

- (void)addValue:(double)value;
{
    NSNumber *valueNumber = [[NSNumber alloc] initWithDouble:value];
    [_values addObject:valueNumber];
    [valueNumber release];
}

- (void)addValueWithAction:(void (^)(void))action;
{
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    action();
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    [self addValue:end - start];
}

- (void)addValues:(NSUInteger)trials withAction:(void (^)(void))action;
{
    for (NSUInteger trial = 0; trial < trials; trial++) {
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        action();
        CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
        [self addValue:end - start];
    }
}

// Assumes sorted.
static double _median(NSArray *values)
{
    NSUInteger count = [values count];
    if (count == 0)
        return 0;

    if (count & 0x1) {
        // Exact middle value since this rounds down and we have zero-based indexing.
        return [values[count/2] doubleValue];
    } else {
        // Average the two values in the middle
        double value1 = [values[count/2 - 1] doubleValue];
        double value2 = [values[count/2] doubleValue];
        return 0.5 * (value1 + value2);
    }
}

- (NSString *)description;
{
    NSUInteger count = [_values count];
    if (count == 0)
        return @"empty";

    [_values sortUsingComparator:^NSComparisonResult(NSNumber *number1, NSNumber *number2) {
        double value1 = [number1 doubleValue];
        double value2 = [number2 doubleValue];
        
        if (value1 < value2)
            return NSOrderedAscending;
        if (value1 > value2)
            return NSOrderedDescending;
        return NSOrderedSame;
    }];

    double median = _median(_values);
    
    double min = DBL_MAX, max = DBL_MIN, total = 0;
    for (NSNumber *valueNumber in _values) {
        double value = [valueNumber doubleValue];
        min = MIN(min, value);
        max = MAX(max, value);
        total += value;
    }
    
    double mean = total / count;
    
    double totalVariant = 0;
    for (NSNumber *valueNumber in _values) {
        double diff = mean - [valueNumber doubleValue];
        totalVariant += diff*diff;
    }
    double deviation = sqrt(totalVariant/count);
    
    NSMutableArray *filtered = [[_values mutableCopy] autorelease];
    NSUInteger filterIndex = [filtered count];
    while (filterIndex--) {
        NSNumber *valueNumber = filtered[filterIndex];
        double value = [valueNumber doubleValue];
        
        if (fabs(value - mean) > 3*deviation)
            [filtered removeObjectAtIndex:filterIndex];
    }
    double medianAfterFilter = _median(filtered);
    
    return [NSString stringWithFormat:@"total:%f min:%f max:%f mean:%f median:%f std:%f excluded:%ld/%ld filtered:%f", total, min, max, mean, median, deviation, count - [filtered count], count, medianAfterFilter];
}

@end
#endif
