// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSNumber-OFExtensions.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>

#import <Foundation/Foundation.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

struct numericTypeAttributes {
    unsigned short width;
    BOOL siGned;
    BOOL integral;
};

static struct numericTypeAttributes numericTypeAttributes(NSNumber *n);
static NSNumber *performOperationWithWidth(char op, unsigned short requiredWidth, BOOL requiresSign, BOOL integral, NSNumber *v1, NSNumber *v2);

@implementation NSNumber (OFExtensions)

static NSCharacterSet *dotCharacterSet = nil;

// Convenience initializers warn incorrectly with -Wobjc-designated-initializers when returning a new object <http://llvm.org/bugs/show_bug.cgi?id=20390>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
- initWithString:(NSString *)aString;
{
    /*
     * Currently this is a little lame -- it only will figure out a few types
     * of numbers.
     */
    NSRange range;

    if (!dotCharacterSet)
	dotCharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@"."] retain];

    range = [aString rangeOfCharacterFromSet:dotCharacterSet];
    if (!range.length) {
	[self release];
	return [[NSNumber alloc] initWithInt:[aString intValue]];
    } else {
	[self release];
	return [[NSNumber alloc] initWithFloat:[aString floatValue]];
    }
}
#pragma clang diagnostic pop

+ (NSNumber *)numberByPerformingOperation:(OFArithmeticOperation)op withNumber:(NSNumber *)v1 andNumber:(NSNumber *)v2
{
    struct numericTypeAttributes myTypeInfo, otherTypeInfo;
    
    myTypeInfo = numericTypeAttributes(v1);
    otherTypeInfo = numericTypeAttributes(v2);
    
    if (myTypeInfo.width == 0 || otherTypeInfo.width == 0)
        return nil;
    
    return performOperationWithWidth(op,
                                     (myTypeInfo.width > otherTypeInfo.width) ? myTypeInfo.width : otherTypeInfo.width,
                                     myTypeInfo.siGned || otherTypeInfo.siGned,
                                     myTypeInfo.integral && otherTypeInfo.integral,
                                     v1, v2);
}

- (BOOL)isExact
{
    if (CFGetTypeID((CFTypeRef)self) == CFNumberGetTypeID()) {
        return !CFNumberIsFloatType((CFTypeRef)self);
    } else {
        return NO;
    }
}

@end

static struct numericTypeAttributes numericTypeAttributes(NSNumber *n)
{
    if (CFGetTypeID((CFTypeRef)n) == CFNumberGetTypeID()) {
        CFTypeRef cfn = (__bridge CFTypeRef)n;
        OBASSERT(CFNumberGetByteSize((CFTypeRef)n) < USHRT_MAX);
        return (struct numericTypeAttributes){
            .width = (unsigned short)CFNumberGetByteSize((CFTypeRef)n),
            .siGned = ( CFNumberGetType(cfn) != kCFNumberCFIndexType ),  // CFNumber only has one signed type; see Radar #3513632
            .integral = !CFNumberIsFloatType(cfn)
        };
    }
    
    const char *ntype = [n objCType];
    if (ntype[0] && !ntype[1]) {
        switch(ntype[0]) {
            case _C_CHR:     return (struct numericTypeAttributes){ CHAR_BIT - 1,                          YES, YES };
            case _C_UCHR:    return (struct numericTypeAttributes){ CHAR_BIT,                              NO,  YES };
            case _C_SHT:     return (struct numericTypeAttributes){ CHAR_BIT * sizeof(short) - 1,          YES, YES };
            case _C_USHT:    return (struct numericTypeAttributes){ CHAR_BIT * sizeof(unsigned short),     NO,  YES };
            case _C_INT:     return (struct numericTypeAttributes){ CHAR_BIT * sizeof(int) - 1,            YES, YES };
            case _C_UINT:    return (struct numericTypeAttributes){ CHAR_BIT * sizeof(unsigned int),       NO,  YES };
            case _C_LNG:     return (struct numericTypeAttributes){ CHAR_BIT * sizeof(long) - 1,           YES, YES };
            case _C_ULNG:    return (struct numericTypeAttributes){ CHAR_BIT * sizeof(unsigned long),      NO,  YES };
            case _C_LNG_LNG: return (struct numericTypeAttributes){ CHAR_BIT * sizeof(long long) - 1,      YES, YES };
            case _C_ULNG_LNG: return (struct numericTypeAttributes){ CHAR_BIT * sizeof(unsigned long long), NO,  YES };
                
            case _C_FLT:     return (struct numericTypeAttributes){ CHAR_BIT * sizeof(float),              YES, NO  };
            case _C_DBL:     return (struct numericTypeAttributes){ CHAR_BIT * sizeof(double),             YES, NO  };
        }
    }
    
    OBRejectInvalidCall(n, NULL, @"Unknown numeric type");

    return (struct numericTypeAttributes){ 0, NO, NO };
}

static NSNumber *performOperationWithWidth(char op, unsigned short requiredWidth, BOOL requiresSign, BOOL integral, NSNumber *v1, NSNumber *v2)
{
    
#define COMPUTE(into, arg1, arg2) \
    switch(op) { \
        case OFArithmeticOperation_Add:      into = arg1 + arg2; break; \
        case OFArithmeticOperation_Subtract: into = arg1 - arg2; break; \
        case OFArithmeticOperation_Multiply: into = arg1 * arg2; break; \
        case OFArithmeticOperation_Divide:   into = arg1 / arg2; break; \
        default: return nil; \
    }
#define BLAH(type, getsel, mksel) { type result; COMPUTE(result, [v1 getsel], [v2 getsel]); return [NSNumber mksel:result]; }
    
    if (!integral) {
        // All our non-integer types are signed
        if (requiredWidth <= CHAR_BIT * sizeof(float)) {
            BLAH(float, floatValue, numberWithFloat);
        } else {
            BLAH(double, doubleValue, numberWithDouble);
        }
    } else {
        if (requiresSign) {
            if (requiredWidth < CHAR_BIT * sizeof(short)) {
                BLAH(short, shortValue, numberWithShort);
            } else if (requiredWidth < CHAR_BIT * sizeof(int)) {
                BLAH(int, intValue, numberWithInt);
            } else if (requiredWidth < CHAR_BIT * sizeof(long)) {
                BLAH(long, longValue, numberWithLong);
            } else {
                BLAH(long long, longLongValue, numberWithLongLong);
            }
        } else {
            if (requiredWidth <= CHAR_BIT * sizeof(unsigned short)) {
                BLAH(unsigned short, unsignedShortValue, numberWithUnsignedShort);
            } else if (requiredWidth <= CHAR_BIT * sizeof(unsigned int)) {
                BLAH(unsigned int, unsignedIntValue, numberWithUnsignedInt);
            } else if (requiredWidth <= CHAR_BIT * sizeof(unsigned long)) {
                BLAH(unsigned long, unsignedLongValue, numberWithUnsignedLong);
            } else {
                BLAH(unsigned long long, unsignedLongLongValue, numberWithUnsignedLongLong);
            }
        }
    }
}

