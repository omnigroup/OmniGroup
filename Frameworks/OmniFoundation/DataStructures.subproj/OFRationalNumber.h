// Copyright 2005-2006, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/DataStructures.subproj/OFRationalNumber.h 104581 2008-09-06 21:18:23Z kc $

#import <Foundation/NSValue.h>

struct OFRationalNumberStruct {
    unsigned long numerator, denominator;    
    unsigned short negative: 1;
    unsigned short lop: 1;
};

#define OFRationalZero ((struct OFRationalNumberStruct){0, 0, 0, 0})  // Our only denormal
#define OFRationalOne  ((struct OFRationalNumberStruct){1, 1, 0, 0})

/* Conversions between OFRational and other formats */

struct OFRationalNumberStruct OFRationalFromRatio(int numerator, int denominator);
struct OFRationalNumberStruct OFRationalFromDouble(double d);
struct OFRationalNumberStruct OFRationalFromLong(long l);
double OFRationalToDouble(struct OFRationalNumberStruct v);
long OFRationalToLong(struct OFRationalNumberStruct v);

NSString *OFRationalToStringForStorage(struct OFRationalNumberStruct a);
NSString *OFRationalToStringForLocale(struct OFRationalNumberStruct a, NSDictionary *dict);
BOOL OFRationalFromStringForStorage(NSString *s, struct OFRationalNumberStruct *n);

/* Operations on OFRationals */
void OFRationalMAdd(struct OFRationalNumberStruct *a, struct OFRationalNumberStruct b, int c);
struct OFRationalNumberStruct OFRationalMultiply(struct OFRationalNumberStruct a, struct OFRationalNumberStruct b);
struct OFRationalNumberStruct OFRationalInverse(struct OFRationalNumberStruct n);
BOOL OFRationalIsEqual(struct OFRationalNumberStruct a, struct OFRationalNumberStruct b);
NSComparisonResult OFRationalCompare(struct OFRationalNumberStruct a, struct OFRationalNumberStruct b);
BOOL OFRationalIsWellFormed(struct OFRationalNumberStruct n);
void OFRationalRound(struct OFRationalNumberStruct *n, unsigned long max_denominator);

@interface OFRationalNumber : NSNumber
{
    struct OFRationalNumberStruct r;
}

@end

@interface NSNumber (OFRationalNumberValue)

+ numberWithRatio:(struct OFRationalNumberStruct)r;
+ numberWithRatio:(int)numerator :(int)denominator;

- (struct OFRationalNumberStruct)rationalValue;

@end

#if 0 // Eventually, make an NSNumber subclass
#import <Foundation/NSFormatter.h>
@interface OFRationalNumberFormatter : NSFormatter
{
    NSNumberFormatter *componentFormatter;
}

@end

#endif
