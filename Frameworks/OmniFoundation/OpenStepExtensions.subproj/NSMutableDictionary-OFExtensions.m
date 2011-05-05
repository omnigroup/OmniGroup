// Copyright 1997-2005, 2007-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>

#import <Foundation/Foundation.h>

RCS_ID("$Id$")

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    #define CGPointValue pointValue
    #define CGRectValue rectValue
    #define CGSizeValue sizeValue

//    #define CGPointEqualToPoint NSEqualPoints
//    #define CGSizeEqualToSize NSEqualSizes
    #define CGRectEqualToRect NSEqualRects
#else
    #define NSStringFromPoint NSStringFromCGPoint
    #define NSStringFromRect NSStringFromCGRect
    #define NSStringFromSize NSStringFromCGSize
    #import <UIKit/UIGeometry.h>
#endif

@implementation NSMutableDictionary (OFExtensions)

- (void)setObject:(id)anObject forKeys:(NSArray *)keys;
{
    for (NSString *key in keys)
	[self setObject:anObject forKey:key];
}

- (void)setFloatValue:(float)value forKey:(id)key;
{
    NSNumber *number = [[NSNumber alloc] initWithFloat:value];
    [self setObject:number forKey:key];
    [number release];
}

- (void)setDoubleValue:(double)value forKey:(id)key;
{
    NSNumber *number = [[NSNumber alloc] initWithDouble:value];
    [self setObject:number forKey:key];
    [number release];
}

- (void)setIntValue:(int)value forKey:(id)key;
{
    NSNumber *number = [[NSNumber alloc] initWithInt:value];
    [self setObject:number forKey:key];
    [number release];
}

- (void)setUnsignedIntValue:(unsigned int)value forKey:(id)key;
{
    NSNumber *number = [[NSNumber alloc] initWithUnsignedInt:value];
    [self setObject:number forKey:key];
    [number release];
}

- (void)setIntegerValue:(NSInteger)value forKey:(id)key;
{
    NSNumber *number = [[NSNumber alloc] initWithInteger:value];
    [self setObject:number forKey:key];
    [number release];
}

- (void)setUnsignedIntegerValue:(NSUInteger)value forKey:(id)key;
{
    NSNumber *number = [[NSNumber alloc] initWithUnsignedInteger:value];
    [self setObject:number forKey:key];
    [number release];
}

- (void)setUnsignedLongLongValue:(unsigned long long)value forKey:(id)key;
{
    NSNumber *number = [[NSNumber alloc] initWithUnsignedLongLong:value];
    [self setObject:number forKey:key];
    [number release];
}

- (void)setBoolValue:(BOOL)value forKey:(id)key;
{
    NSNumber *number = [[NSNumber alloc] initWithBool:value];
    [self setObject:number forKey:key];
    [number release];
}

- (void)setPointValue:(CGPoint)value forKey:(id)key;
{
    [self setObject:NSStringFromPoint(value) forKey:key];
}

- (void)setSizeValue:(CGSize)value forKey:(id)key;
{
    [self setObject:NSStringFromSize(value) forKey:key];
}

- (void)setRectValue:(CGRect)value forKey:(id)key;
{
    [self setObject:NSStringFromRect(value) forKey:key];
}

// Set values with defaults

- (void)setObject:(id)object forKey:(id)key defaultObject:(id)defaultObject;
{
    if (!object || [object isEqual:defaultObject]) {
        [self removeObjectForKey:key];
        return;
    }

    [self setObject:object forKey:key];
}

- (void)setFloatValue:(float)value forKey:(id)key defaultValue:(float)defaultValue;
{
    if (value == defaultValue) {
        [self removeObjectForKey:key];
        return;
    }

    [self setFloatValue:value forKey:key];
}

- (void)setDoubleValue:(double)value forKey:(id)key defaultValue:(double)defaultValue;
{
    if (value == defaultValue) {
        [self removeObjectForKey:key];
        return;
    }

    [self setDoubleValue:value forKey:key];
}

- (void)setIntValue:(int)value forKey:(id)key defaultValue:(int)defaultValue;
{
    if (value == defaultValue) {
        [self removeObjectForKey:key];
        return;
    }

    [self setIntValue:value forKey:key];
}

- (void)setUnsignedIntValue:(unsigned int)value forKey:(id)key defaultValue:(unsigned int)defaultValue;
{
    if (value == defaultValue) {
        [self removeObjectForKey:key];
        return;
    }

    [self setUnsignedIntValue:value forKey:key];
}

- (void)setIntegerValue:(NSInteger)value forKey:(id)key defaultValue:(NSInteger)defaultValue;
{
    if (value == defaultValue) {
        [self removeObjectForKey:key];
        return;
    }
    
    [self setIntegerValue:value forKey:key];
}

- (void)setUnsignedIntegerValue:(NSUInteger)value forKey:(id)key defaultValue:(NSUInteger)defaultValue;
{
    if (value == defaultValue) {
        [self removeObjectForKey:key];
        return;
    }
    
    [self setUnsignedIntegerValue:value forKey:key];
}

- (void)setUnsignedLongLongValue:(unsigned long long)value forKey:(id)key defaultValue:(unsigned long long)defaultValue;
{
    if (value == defaultValue) {
        [self removeObjectForKey:key];
        return;
    }
    
    [self setUnsignedLongLongValue:value forKey:key];
}

- (void)setBoolValue:(BOOL)value forKey:(id)key defaultValue:(BOOL)defaultValue;
{
    if (value == defaultValue) {
        [self removeObjectForKey:key];
        return;
    }

    [self setBoolValue:value forKey:key];
}

- (void)setPointValue:(CGPoint)value forKey:(id)key defaultValue:(CGPoint)defaultValue;
{
    if (CGPointEqualToPoint(value, defaultValue)) {
        [self removeObjectForKey:key];
        return;
    }
    
    [self setPointValue:value forKey:key];
}

- (void)setSizeValue:(CGSize)value forKey:(id)key defaultValue:(CGSize)defaultValue;
{
    if (CGSizeEqualToSize(value, defaultValue)) {
        [self removeObjectForKey:key];
        return;
    }
    
    [self setSizeValue:value forKey:key];
}

- (void)setRectValue:(CGRect)value forKey:(id)key defaultValue:(CGRect)defaultValue;
{
    if (CGRectEqualToRect(value, defaultValue)) {
        [self removeObjectForKey:key];
        return;
    }
    
    [self setRectValue:value forKey:key];
}

@end
