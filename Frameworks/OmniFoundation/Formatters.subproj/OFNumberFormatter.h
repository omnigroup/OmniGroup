// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <Foundation/NSNumberFormatter.h>


/*!
 @class OFNumberFormatter
 @discussion A subclass of NSNumberFormatter which adds the ability to clamp the returned value to the configured minimum and maximum values and to the configured precision.
 */

@interface OFNumberFormatter : NSNumberFormatter

/*!
 Specifies whether or not the formatter should clamp any returned object value to the configured minimum and maximum values. The default is to not clamp, in which case a string which represents a value outside of the minimum/maximum range will result in a nil object value. (This is the behavior from NSNumberFormatter.)
 */
@property (nonatomic) BOOL clampsRange;

/*!
 Specifies whether or not the formatter should clamp any returned object value to the configured precision. The default is to not clamp the precision, meaning that the object value for a string may be more precise than the string for a corresponding object value. For instance, an object value of 2.22 might, depending on formatter configuration, result in a string value of "2.2", yet a string value of "2.22" would result in an object value of 2.22 even with the same configuration for the formatter. (This is the behavior from NSNumberFormatter.)
 */
@property (nonatomic) BOOL clampsPrecision;

#ifdef DEBUG
/*!
 If the debug level is greater than zero, this instance will log certain information to the console to aid in tracking how a string value is clamped. The class must be compiled in debug mode for this property to be available.
 */
@property (nonatomic) NSInteger debugLevel;
#endif

@end

