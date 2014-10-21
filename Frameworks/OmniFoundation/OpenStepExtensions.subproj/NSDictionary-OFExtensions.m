// Copyright 1997-2008, 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSDictionary-OFExtensions.h>

#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/assertions.h>
#import <OmniBase/objc.h>
#import <OmniBase/OBUtilities.h>

#include <stdlib.h>

RCS_ID("$Id$")

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    #define CGPointValue pointValue
    #define CGRectValue rectValue
    #define CGSizeValue sizeValue
#else
    #import <UIKit/UIGeometry.h>
    #define NSPointFromString CGPointFromString
    #define NSRectFromString CGRectFromString
    #define NSSizeFromString CGSizeFromString
    #define NSZeroPoint CGPointZero
    #define NSZeroSize CGSizeZero
    #define NSZeroRect CGRectZero
#endif

#define SAFE_ALLOCA_SIZE (8 * 8192)

@implementation NSDictionary (OFExtensions)

- (id)anyObject;
{
    for (NSString *key in self)
        return [self objectForKey:key];
    return nil;
}

/*" Returns an object which is a shallow copy of the receiver except that the given key now maps to anObj. anObj may be nil in order to remove the given key from the dictionary. "*/
- (NSDictionary *)dictionaryWithPossiblyRemovedObject:(id)anObj forKey:(NSString *)key;
{
    NSUInteger keyCount = [self count];
    
    if (keyCount == 0 || (keyCount == 1 && [self objectForKey:key] != nil))
        return anObj ? [NSDictionary dictionaryWithObject:anObj forKey:key] : [NSDictionary dictionary];

    if ([self objectForKey:key] == anObj)
        return [NSDictionary dictionaryWithDictionary:self];

    NSMutableArray *newKeys = [[NSMutableArray alloc] initWithCapacity:keyCount+1];
    NSMutableArray *newValues = [[NSMutableArray alloc] initWithCapacity:keyCount+1];
    
    for (NSString *aKey in self) {
        if (![aKey isEqual:key]) {
            [newKeys addObject:aKey];
            [newValues addObject:[self objectForKey:aKey]];
        }
    }

    if (anObj != nil) {
        [newKeys addObject:key];
        [newValues addObject:anObj];
    }

    NSDictionary *result = [NSDictionary dictionaryWithObjects:newValues forKeys:newKeys];
    [newKeys release];
    [newValues release];
    
    return result;
}

- (NSDictionary *)dictionaryWithObject:(id)anObj forKey:(NSString *)key;
{
    OBASSERT_NOTNULL(anObj);
    return [self dictionaryWithPossiblyRemovedObject:anObj forKey:key];
}

- (NSDictionary *)dictionaryWithObjectRemovedForKey:(NSString *)key;
{
    return [self dictionaryWithPossiblyRemovedObject:nil forKey:key];
}

/*" Returns an object which is a shallow copy of the receiver except that the key-value pairs from otherDictionary are included (overriding existing key-value associations if they existed). "*/

- (NSDictionary *)dictionaryByAddingObjectsFromDictionary:(NSDictionary *)otherDictionary;
{
    __block NSMutableDictionary *mutatedDictionary = nil;
    
    [otherDictionary enumerateKeysAndObjectsUsingBlock:^(id key, id otherValue, BOOL *stop) {
        id value = self[key];
        if (value != otherValue) {
            if (!mutatedDictionary)
                mutatedDictionary = [self mutableCopy];
            mutatedDictionary[key] = otherValue;
        }
    }];

    if (mutatedDictionary) {
        [mutatedDictionary autorelease];
        return [[mutatedDictionary copy] autorelease];
    }
    return [[self copy] autorelease];
}

- (NSString *)keyForObjectEqualTo:(id)anObject;
{
    for (NSString *key in self)
        if ([[self objectForKey:key] isEqual:anObject])
	    return key;
    return nil;
}

- (NSString *)stringForKey:(NSString *)key defaultValue:(NSString *)defaultValue;
{
    id object = [self objectForKey:key];
    if (![object isKindOfClass:[NSString class]])
        return defaultValue;
    return object;
}

- (NSString *)stringForKey:(NSString *)key;
{
    return [self stringForKey:key defaultValue:nil];
}

- (NSArray *)stringArrayForKey:(NSString *)key defaultValue:(NSArray *)defaultValue;
{
#ifdef OMNI_ASSERTIONS_ON
    for (id value in defaultValue)
        OBPRECONDITION([value isKindOfClass:[NSString class]]);
#endif
    NSArray *array = [self objectForKey:key];
    if (![array isKindOfClass:[NSArray class]])
        return defaultValue;
    for (id value in array) {
        if (![value isKindOfClass:[NSString class]])
            return defaultValue;
    }
    return array;
}

- (NSArray *)stringArrayForKey:(NSString *)key;
{
    return [self stringArrayForKey:key defaultValue:nil];
}

- (float)floatForKey:(NSString *)key defaultValue:(float)defaultValue;
{
    id value = [self objectForKey:key];
    if (value)
        return [value floatValue];
    return defaultValue;
}

- (float)floatForKey:(NSString *)key;
{
    return [self floatForKey:key defaultValue:0.0f];
}

- (double)doubleForKey:(NSString *)key defaultValue:(double)defaultValue;
{
    id value = [self objectForKey:key];
    if (value)
        return [value doubleValue];
    return defaultValue;
}

- (double)doubleForKey:(NSString *)key;
{
    return [self doubleForKey:key defaultValue:0.0];
}

- (CGPoint)pointForKey:(NSString *)key defaultValue:(CGPoint)defaultValue;
{
    id value = [self objectForKey:key];
    if ([value isKindOfClass:[NSString class]] && ![NSString isEmptyString:value])
        return NSPointFromString(value);
    else if ([value isKindOfClass:[NSValue class]])
        return [value CGPointValue];
    else
        return defaultValue;
}

- (CGPoint)pointForKey:(NSString *)key;
{
    return [self pointForKey:key defaultValue:NSZeroPoint];
}

- (CGSize)sizeForKey:(NSString *)key defaultValue:(CGSize)defaultValue;
{
    id value = [self objectForKey:key];
    if ([value isKindOfClass:[NSString class]] && ![NSString isEmptyString:value])
        return NSSizeFromString(value);
    else if ([value isKindOfClass:[NSValue class]])
        return [value CGSizeValue];
    else
        return defaultValue;
}

- (CGSize)sizeForKey:(NSString *)key;
{
    return [self sizeForKey:key defaultValue:NSZeroSize];
}

- (CGRect)rectForKey:(NSString *)key defaultValue:(CGRect)defaultValue;
{
    id value = [self objectForKey:key];
    if ([value isKindOfClass:[NSString class]] && ![NSString isEmptyString:value])
        return NSRectFromString(value);
    else if ([value isKindOfClass:[NSValue class]])
        return [value CGRectValue];
    else
        return defaultValue;
}

- (CGRect)rectForKey:(NSString *)key;
{
    return [self rectForKey:key defaultValue:NSZeroRect];
}

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue;
{
    id value = [self objectForKey:key];

    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]])
        return [value boolValue];

    return defaultValue;
}

- (BOOL)boolForKey:(NSString *)key;
{
    return [self boolForKey:key defaultValue:NO];
}

- (int)intForKey:(NSString *)key defaultValue:(int)defaultValue;
{
    id value = [self objectForKey:key];
    if (!value)
        return defaultValue;
    return [value intValue];
}

- (int)intForKey:(NSString *)key;
{
    return [self intForKey:key defaultValue:0];
}

- (unsigned int)unsignedIntForKey:(NSString *)key defaultValue:(unsigned int)defaultValue;
{
    id value = [self objectForKey:key];
    if (value == nil)
        return defaultValue;
    return [value unsignedIntValue];
}

- (unsigned int)unsignedIntForKey:(NSString *)key;
{
    return [self unsignedIntForKey:key defaultValue:0];
}

- (unsigned long long int)unsignedLongLongForKey:(NSString *)key defaultValue:(unsigned long long int)defaultValue;
{
    id value = [self objectForKey:key];
    if (value == nil)
        return defaultValue;
    return [value unsignedLongLongValue];
}

- (unsigned long long int)unsignedLongLongForKey:(NSString *)key;
{
    return [self unsignedLongLongForKey:key defaultValue:0ULL];
}

- (NSInteger)integerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue;
{
    id value = [self objectForKey:key];
    if (!value)
        return defaultValue;
    return [value integerValue];
}

- (NSInteger)integerForKey:(NSString *)key;
{
    return [self integerForKey:key defaultValue:0];
}

- (NSUInteger)unsignedIntegerForKey:(NSString *)key defaultValue:(NSInteger)defaultValue;
{
    id value = [self objectForKey:key];
    if (!value)
        return defaultValue;
    return [value unsignedIntegerValue];
}

- (NSUInteger)unsignedIntegerForKey:(NSString *)key;
{
    return [self unsignedIntegerForKey:key defaultValue:0];
}

- (void)makeValuesPerformSelector:(SEL)sel withObject:(id)object;
{
    [self enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        OBSendVoidMessageWithObject(value, sel, object);
    }];
}

- (void)makeValuesPerformSelector:(SEL)sel;
{
    [self enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        OBSendVoidMessage(value, sel);
    }];
}

- (id)objectForKey:(NSString *)key defaultObject:(id)defaultObject;
{
    id value = [self objectForKey:key];
    if (value)
        return value;
    return defaultObject;
}

- (id)deepMutableCopy;
{
    NSMutableDictionary *newDictionary = [self mutableCopy];
    // Run through the new dictionary and replace any objects that respond to -deepMutableCopy or -mutableCopy with copies.
    for (id aKey in self) {
	id anObject = [newDictionary objectForKey:aKey];
        if ([anObject respondsToSelector:@selector(deepMutableCopy)]) {
            anObject = [(NSDictionary *)anObject deepMutableCopy];
            [newDictionary setObject:anObject forKey:aKey];
            [anObject release];
        } else if ([anObject conformsToProtocol:@protocol(NSMutableCopying)]) {
            anObject = [anObject mutableCopy];
            [newDictionary setObject:anObject forKey:aKey];
            [anObject release];
        } else
            [newDictionary setObject:anObject forKey:aKey];
    }

    return newDictionary;
}

static id copyDictionaryKeys(CFDictionaryRef self, Class resultClass)
{
    NSUInteger keyCount = CFDictionaryGetCount(self);
    
    void **keys;
    size_t byteCount = sizeof(*keys) * keyCount;
    BOOL useMalloc = byteCount >= SAFE_ALLOCA_SIZE;
    keys = (void **)(useMalloc ? malloc(byteCount) : alloca(byteCount));
    
    CFDictionaryGetKeysAndValues((CFDictionaryRef)self, (const void **)keys, NULL);
    
    id keyArray;
    keyArray = [[resultClass alloc] initWithObjects:OBCastMemoryBufferToUnsafeObjectArray(keys) count:keyCount];
    
    if (useMalloc)
        free(keys);
    
    return keyArray;
}

- (NSArray *) copyKeys;
/*.doc. Just like -allKeys on NSDictionary, except that it doesn't autorelease the result but returns a retained array. */
{
    return copyDictionaryKeys((CFDictionaryRef)self, [NSArray class]);
}

- (NSMutableArray *) mutableCopyKeys;
/*.doc. Just like -allKeys on NSDictionary, except that it doesn't autorelease the result but returns a newly created mutable array. */
{
    return copyDictionaryKeys((CFDictionaryRef)self, [NSMutableArray class]);
}

- (NSSet *) copyKeySet;
{
    return copyDictionaryKeys((CFDictionaryRef)self, [NSSet class]);
}

- (NSMutableSet *) mutableCopyKeySet;
{
    return copyDictionaryKeys((CFDictionaryRef)self, [NSMutableSet class]);
}

@end


@implementation NSDictionary (OFDeprecatedExtensions)

- (id)valueForKey:(NSString *)key defaultValue:(id)defaultValue;
{
    return [self objectForKey:key defaultObject:defaultValue];
}

@end
