// Copyright 1999-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSDecimalNumber-OFExtensions.h>

RCS_ID("$Id$")

@implementation NSDecimalNumber (OFExtensions)

- (NSDecimalNumber *)decimalNumberByConvertingFromAnnualizedPercentageRateToMonthlyRate;
{
    return [self decimalNumberByDividingBy:(NSDecimalNumber *)[NSDecimalNumber numberWithUnsignedInt:1200]];
}

- (NSDecimalNumber *)decimalNumberByConvertingFromMonthlyRateToAnnualizedPercentageRate;
{
    return [self decimalNumberByMultiplyingBy:(NSDecimalNumber *)[NSDecimalNumber numberWithUnsignedInt:1200]];
}

- (NSDecimalNumber *)decimalNumberByRoundingToScale:(short)scale roundingMode:(NSRoundingMode)roundingMode;
{
    NSDecimal decimalToRound;
    NSDecimal result;

    decimalToRound = [self decimalValue];
    NSDecimalRound(&result, &decimalToRound, scale, roundingMode);

    return [NSDecimalNumber decimalNumberWithDecimal:result];
}

- (NSDecimalNumber *)decimalNumberByRoundingToScale:(short)scale withFactor:(NSDecimalNumber *)factor roundingMode:(NSRoundingMode)roundingMode;
{
    NSDecimalNumber *numberToRound;
    NSDecimalNumber *roundedNumber;

    numberToRound = [self decimalNumberByMultiplyingBy:factor];
    roundedNumber = [numberToRound decimalNumberByRoundingToScale:scale roundingMode:roundingMode];

    return [roundedNumber decimalNumberByDividingBy:factor];
}

- (NSDecimalNumber *)decimalNumberBySafelyAdding:(NSDecimalNumber *)decimalNumber;
{
    if (decimalNumber == nil)
        return self;

    return [self decimalNumberByAdding:decimalNumber];
}

- (NSDecimalNumber *)decimalNumberBySafelySubtracting:(NSDecimalNumber *)decimalNumber;
{
    if (decimalNumber == nil)
        return self;

    return [self decimalNumberBySubtracting:decimalNumber];
}

- (NSDecimalNumber *)decimalNumberBySafelyMultiplyingBy:(NSDecimalNumber *)decimalNumber;
{
    if (decimalNumber == nil)
        return nil;

    return [self decimalNumberByMultiplyingBy:decimalNumber];
}

+ (BOOL)decimalNumberIsEqualToZero:(NSDecimalNumber *)decimalNumber;
{
    return [decimalNumber compare:[NSDecimalNumber zero]] == NSOrderedSame;
}

+ (BOOL)decimalNumberIsNotEqualToZero:(NSDecimalNumber *)decimalNumber;
{
    return [decimalNumber compare:[NSDecimalNumber zero]] != NSOrderedSame;
}

+ (BOOL)decimalNumberIsGreaterThanZero:(NSDecimalNumber *)decimalNumber;
{
    return [decimalNumber compare:[NSDecimalNumber zero]] == NSOrderedDescending;
}

+ (BOOL)decimalNumberIsGreaterThanOrEqualToZero:(NSDecimalNumber *)decimalNumber;
{
    return [decimalNumber compare:[NSDecimalNumber zero]] != NSOrderedAscending;
}

+ (BOOL)numberIsLessThanZero:(NSDecimalNumber *)decimalNumber;
{
    return [decimalNumber compare:[NSDecimalNumber zero]] == NSOrderedAscending;
}

- (BOOL)isGreaterThanDecimalNumber:(NSDecimalNumber *)aDecimalNumber;
{
    return [self compare:aDecimalNumber] == NSOrderedDescending;
}

- (BOOL)isLessThanDecimalNumber:(NSDecimalNumber *)aDecimalNumber;
{
    return [self compare:aDecimalNumber] == NSOrderedAscending;
}

- (BOOL)isGreaterThanOrEqualToDecimalNumber:(NSDecimalNumber *)aDecimalNumber;
{
    return [self compare:aDecimalNumber] != NSOrderedAscending;
}

- (BOOL)isLessThanOrEqualToDecimalNumber:(NSDecimalNumber *)aDecimalNumber;
{
    return [self compare:aDecimalNumber] != NSOrderedDescending;
}

- (BOOL)isNotANumber;
{
    NSDecimal decimalValue;

    decimalValue = [self decimalValue];
    return NSDecimalIsNotANumber(&decimalValue);
}

@end
