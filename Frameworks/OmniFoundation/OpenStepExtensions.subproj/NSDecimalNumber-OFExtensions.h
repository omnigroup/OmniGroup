// Copyright 1999-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSDecimalNumber-OFExtensions.h 68913 2005-10-03 19:36:19Z kc $

#import <Foundation/NSDecimalNumber.h>

#define OF_IS_POSITIVE(value) (value != nil && [value doubleValue] > 0.0)

@interface NSDecimalNumber (OFExtensions)
- (NSDecimalNumber *)decimalNumberByConvertingFromAnnualizedPercentageRateToMonthlyRate;
- (NSDecimalNumber *)decimalNumberByConvertingFromMonthlyRateToAnnualizedPercentageRate;
- (NSDecimalNumber *)decimalNumberByRoundingToScale:(short)scale roundingMode:(NSRoundingMode)roundingMode;
- (NSDecimalNumber *)decimalNumberByRoundingToScale:(short)scale withFactor:(NSDecimalNumber *)factor roundingMode:(NSRoundingMode)roundingMode;

- (NSDecimalNumber *)decimalNumberBySafelyAdding:(NSDecimalNumber *)decimalNumber;
- (NSDecimalNumber *)decimalNumberBySafelySubtracting:(NSDecimalNumber *)decimalNumber;
- (NSDecimalNumber *)decimalNumberBySafelyMultiplyingBy:(NSDecimalNumber *)decimalNumber;

+ (BOOL)decimalNumberIsEqualToZero:(NSDecimalNumber *)decimalNumber;
// Returns YES if the number is equal to zero or is nil
+ (BOOL)decimalNumberIsNotEqualToZero:(NSDecimalNumber *)decimalNumber;
// Returns YES if the number is not equal to zero or is nil
+ (BOOL)decimalNumberIsGreaterThanZero:(NSDecimalNumber *)decimalNumber;
+ (BOOL)decimalNumberIsGreaterThanOrEqualToZero:(NSDecimalNumber *)decimalNumber;
+ (BOOL)numberIsLessThanZero:(NSDecimalNumber *)decimalNumber;

- (BOOL)isGreaterThanDecimalNumber:(NSDecimalNumber *)aDecimalNumber;
- (BOOL)isLessThanDecimalNumber:(NSDecimalNumber *)aDecimalNumber;

- (BOOL)isGreaterThanOrEqualToDecimalNumber:(NSDecimalNumber *)aDecimalNumber;
- (BOOL)isLessThanOrEqualToDecimalNumber:(NSDecimalNumber *)aDecimalNumber;

- (BOOL)isNotANumber;

@end
