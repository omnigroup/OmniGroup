// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>

RCS_ID("$Id$")

@implementation NSMutableDictionary (OFExtensions)

- (void)setObject:(id)anObject forKeys:(NSArray *)keys;
{
    unsigned int keyCount;

    keyCount = [keys count];
    while (keyCount--)
	[self setObject:anObject forKey:[keys objectAtIndex:keyCount]];
}


- (void)setFloatValue:(float)value forKey:(NSString *)key;
{
    NSNumber *number;

    number = [[NSNumber alloc] initWithFloat:value];
    [self setObject:number forKey:key];
    [number release];
}

- (void)setDoubleValue:(double)value forKey:(NSString *)key;
{
    NSNumber *number;

    number = [[NSNumber alloc] initWithDouble:value];
    [self setObject:number forKey:key];
    [number release];
}

- (void)setIntValue:(int)value forKey:(NSString *)key;
{
    NSNumber *number;

    number = [[NSNumber alloc] initWithInt:value];
    [self setObject:number forKey:key];
    [number release];
}

- (void)setUnsignedIntValue:(unsigned int)value forKey:(NSString *)key;
{
    NSNumber *number;

    number = [[NSNumber alloc] initWithUnsignedInt:value];
    [self setObject:number forKey:key];
    [number release];
}

- (void)setBoolValue:(BOOL)value forKey:(NSString *)key;
{
    NSNumber *number;
    
    number = [[NSNumber alloc] initWithBool:value];
    [self setObject:number forKey:key];
    [number release];
}

// We don't use NSValueGeometryExtensions because we use these methods to create property lists (which don't support those geometry types as of 10.3).
// #define USE_NSValueGeometryExtensions

#ifdef OmniFoundation_NSDictionary_NSGeometry_Extensions
- (void)setPointValue:(NSPoint)value forKey:(NSString *)key;
{
#ifdef USE_NSValueGeometryExtensions
    [self setObject:[NSValue valueWithPoint:value] forKey:key];
#else
    [self setObject:NSStringFromPoint(value) forKey:key];
#endif
}

- (void)setSizeValue:(NSSize)value forKey:(NSString *)key;
{
#ifdef USE_NSValueGeometryExtensions
    [self setObject:[NSValue valueWithSize:value] forKey:key];
#else
    [self setObject:NSStringFromSize(value) forKey:key];
#endif
}

- (void)setRectValue:(NSRect)value forKey:(NSString *)key;
{
#ifdef USE_NSValueGeometryExtensions
    [self setObject:[NSValue valueWithRect:value] forKey:key];
#else
    [self setObject:NSStringFromRect(value) forKey:key];
#endif
}
#endif

// Set values with defaults

- (void)setObject:(id)object forKey:(NSString *)key defaultObject:(id)defaultObject;
{
    if (!object || [object isEqual:defaultObject]) {
        [self removeObjectForKey:key];
        return;
    }

    [self setObject:object forKey:key];
}

- (void)setFloatValue:(float)value forKey:(NSString *)key defaultValue:(float)defaultValue;
{
    if (value == defaultValue) {
        [self removeObjectForKey:key];
        return;
    }

    [self setFloatValue:value forKey:key];
}

- (void)setDoubleValue:(double)value forKey:(NSString *)key defaultValue:(double)defaultValue;
{
    if (value == defaultValue) {
        [self removeObjectForKey:key];
        return;
    }

    [self setDoubleValue:value forKey:key];
}

- (void)setIntValue:(int)value forKey:(NSString *)key defaultValue:(int)defaultValue;
{
    if (value == defaultValue) {
        [self removeObjectForKey:key];
        return;
    }

    [self setIntValue:value forKey:key];
}

- (void)setUnsignedIntValue:(unsigned int)value forKey:(NSString *)key defaultValue:(unsigned int)defaultValue;
{
    if (value == defaultValue) {
        [self removeObjectForKey:key];
        return;
    }

    [self setUnsignedIntValue:value forKey:key];
}

- (void)setBoolValue:(BOOL)value forKey:(NSString *)key defaultValue:(BOOL)defaultValue;
{
    if (value == defaultValue) {
        [self removeObjectForKey:key];
        return;
    }

    [self setBoolValue:value forKey:key];
}

#ifdef OmniFoundation_NSDictionary_NSGeometry_Extensions
- (void)setPointValue:(NSPoint)value forKey:(NSString *)key defaultValue:(NSPoint)defaultValue;
{
    if (NSEqualPoints(value, defaultValue)) {
        [self removeObjectForKey:key];
        return;
    }
    
    [self setPointValue:value forKey:key];
}

- (void)setSizeValue:(NSSize)value forKey:(NSString *)key defaultValue:(NSSize)defaultValue;
{
    if (NSEqualSizes(value, defaultValue)) {
        [self removeObjectForKey:key];
        return;
    }
    
    [self setSizeValue:value forKey:key];
}

- (void)setRectValue:(NSRect)value forKey:(NSString *)key defaultValue:(NSRect)defaultValue;
{
    if (NSEqualRects(value, defaultValue)) {
        [self removeObjectForKey:key];
        return;
    }
    
    [self setRectValue:value forKey:key];
}
#endif

@end
