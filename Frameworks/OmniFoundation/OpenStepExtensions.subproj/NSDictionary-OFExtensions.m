// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSDictionary-OFExtensions.h>

RCS_ID("$Id$")

NSString * const OmniDictionaryElementNameKey = @"__omniDictionaryElementNameKey";

#define SAFE_ALLOCA_SIZE (8 * 8192)

@implementation NSDictionary (OFExtensions)

- (id)anyObject;
{
    return [[self allValues] anyObject];
}

/*" Returns an object which is a shallow copy of the receiver except that the given key now maps to anObj. anObj may be nil in order to remove the given key from the dictionary. "*/
- (NSDictionary *)dictionaryWithObject:(id)anObj forKey:(NSString *)key;
{
    unsigned int keyCount;
    NSMutableArray *newKeys, *newValues;
    NSEnumerator *keyEnumerator;
    NSDictionary *result;
    id aKey;

    keyCount = [self count];
    
    if (keyCount == 0 || (keyCount == 1 && [self objectForKey:key] != nil))
        return anObj ? [NSDictionary dictionaryWithObject:anObj forKey:key] : [NSDictionary dictionary];

    if ([self objectForKey:key] == anObj)
        return [NSDictionary dictionaryWithDictionary:self];

    newKeys = [[NSMutableArray alloc] initWithCapacity:keyCount+1];
    newValues = [[NSMutableArray alloc] initWithCapacity:keyCount+1];
    keyEnumerator = [self keyEnumerator];
    while ( (aKey = [keyEnumerator nextObject]) != nil ) {
        if (![aKey isEqual:key]) {
            [newKeys addObject:aKey];
            [newValues addObject:[self objectForKey:aKey]];
        }
    }

    if (anObj != nil) {
        [newKeys addObject:key];
        [newValues addObject:anObj];
    }

    result = [NSDictionary dictionaryWithObjects:newValues forKeys:newKeys];
    [newKeys release];
    [newValues release];
    
    return result;
}

/*" Returns an object which is a shallow copy of the receiver except that the key-value pairs from aDictionary are included (overriding existing key-value associations if they existed). "*/

struct dictByAddingContext {
    id *keys;
    id *values;
    unsigned kvPairsUsed;
    BOOL differs;
    CFDictionaryRef older, newer;
};

static void copyWithOverride(const void *aKey, const void *aValue, void *_context)
{
    struct dictByAddingContext *context = _context;
    unsigned used = context->kvPairsUsed;
    
    const void *otherValue = CFDictionaryGetValue(context->newer, aKey);
    if (otherValue && otherValue != aValue) {
        context->values[used] = (id)otherValue;
        context->differs = YES;
    } else {
        context->values[used] = (id)aValue;
    }
    context->keys[used] = (id)aKey;
    context->kvPairsUsed = used+1;
}

static void copyNewItems(const void *aKey, const void *aValue, void *_context)
{
    struct dictByAddingContext *context = _context;
    
    if(CFDictionaryContainsKey(context->older, aKey)) {
        // Value will already have been chaecked by copyWithOverride().
    } else {
        unsigned used = context->kvPairsUsed;
        context->keys[used] = (id)aKey;
        context->values[used] = (id)aValue;
        context->differs = YES;
        context->kvPairsUsed = used+1;
    }
}

- (NSDictionary *)dictionaryByAddingObjectsFromDictionary:(NSDictionary *)otherDictionary;
{
    unsigned int myKeyCount, otherKeyCount;
    struct dictByAddingContext context;

    if (!otherDictionary)
        goto nochange_noalloc;
    
    myKeyCount = [self count];
    otherKeyCount = [otherDictionary count];
    
    if (!otherKeyCount)
        goto nochange_noalloc;
    
    context.keys = calloc(myKeyCount+otherKeyCount, sizeof(*(context.keys)));
    context.values = calloc(myKeyCount+otherKeyCount, sizeof(*(context.values)));
    context.kvPairsUsed = 0;
    context.differs = NO;
    context.older = (CFDictionaryRef)self;
    context.newer = (CFDictionaryRef)otherDictionary;
    
    CFDictionaryApplyFunction((CFDictionaryRef)self, copyWithOverride, &context);
    CFDictionaryApplyFunction((CFDictionaryRef)otherDictionary, copyNewItems, &context);
    if (!context.differs)
        goto nochange;
    
    NSDictionary *newDictionary = [NSDictionary dictionaryWithObjects:context.values forKeys:context.keys count:context.kvPairsUsed];
    free(context.keys);
    free(context.values);
    return newDictionary;
    
nochange:
    free(context.keys);
    free(context.values);
nochange_noalloc:
    return [NSDictionary dictionaryWithDictionary:self];
}

- (NSString *)keyForObjectEqualTo:(id)anObject;
{
    NSEnumerator *keyEnumerator;
    NSString *aKey;

    keyEnumerator = [self keyEnumerator];
    while ((aKey = [keyEnumerator nextObject]))
        if ([[self objectForKey:aKey] isEqual:anObject])
	    return aKey;
    return nil;
}

- (float)floatForKey:(NSString *)key defaultValue:(float)defaultValue;
{
    id value;

    value = [self objectForKey:key];
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
    id value;

    value = [self objectForKey:key];
    if (value)
        return [value doubleValue];
    return defaultValue;
}

- (double)doubleForKey:(NSString *)key;
{
    return [self doubleForKey:key defaultValue:0.0];
}

// If we end up needing these, we could use the CG types.
#ifdef OmniFoundation_NSDictionary_NSGeometry_Extensions
- (NSPoint)pointForKey:(NSString *)key defaultValue:(NSPoint)defaultValue;
{
    id value = [self objectForKey:key];
    if ([value isKindOfClass:[NSString class]] && ![NSString isEmptyString:value])
        return NSPointFromString(value);
    else if ([value isKindOfClass:[NSValue class]])
        return [value pointValue];
    else
        return defaultValue;
}

- (NSPoint)pointForKey:(NSString *)key;
{
    return [self pointForKey:key defaultValue:NSZeroPoint];
}

- (NSSize)sizeForKey:(NSString *)key defaultValue:(NSSize)defaultValue;
{
    id value = [self objectForKey:key];
    if ([value isKindOfClass:[NSString class]] && ![NSString isEmptyString:value])
        return NSSizeFromString(value);
    else if ([value isKindOfClass:[NSValue class]])
        return [value sizeValue];
    else
        return defaultValue;
}

- (NSSize)sizeForKey:(NSString *)key;
{
    return [self sizeForKey:key defaultValue:NSZeroSize];
}

- (NSRect)rectForKey:(NSString *)key defaultValue:(NSRect)defaultValue;
{
    id value = [self objectForKey:key];
    if ([value isKindOfClass:[NSString class]] && ![NSString isEmptyString:value])
        return NSRectFromString(value);
    else if ([value isKindOfClass:[NSValue class]])
        return [value rectValue];
    else
        return defaultValue;
}

- (NSRect)rectForKey:(NSString *)key;
{
    return [self rectForKey:key defaultValue:NSZeroRect];
}
#endif

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
    id value;

    value = [self objectForKey:key];
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
    id value;

    value = [self objectForKey:key];
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
    id value;

    value = [self objectForKey:key];
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
    id value;
    
    value = [self objectForKey:key];
    if (!value)
        return defaultValue;
    return [value integerValue];
}

- (NSInteger)integerForKey:(NSString *)key;
{
    return [self integerForKey:key defaultValue:0];
}

struct _makeValuesPerformSelectorContext {
    SEL sel;
    id object;
};

static void _makeValuesPerformSelectorApplier(const void *key, const void *value, void *context)
{
    struct _makeValuesPerformSelectorContext *ctx = context;
    [(id)value performSelector:ctx->sel withObject:ctx->object];
}

- (void)makeValuesPerformSelector:(SEL)sel withObject:(id)object;
{
    struct _makeValuesPerformSelectorContext ctx = {sel, object};
    CFDictionaryApplyFunction((CFDictionaryRef)self, _makeValuesPerformSelectorApplier, &ctx);
}

- (void)makeValuesPerformSelector:(SEL)sel;
{
    [self makeValuesPerformSelector:sel withObject:nil];
}

- (id)objectForKey:(NSString *)key defaultObject:(id)defaultObject;
{
    id value;

    value = [self objectForKey:key];
    if (value)
        return value;
    return defaultObject;
}

- (id)deepMutableCopy;
{
    NSMutableDictionary *newDictionary;
    id anObject;
    id aKey;

    newDictionary = [self mutableCopy];
    // Run through the new dictionary and replace any objects that respond to -deepMutableCopy or -mutableCopy with copies.
    for (aKey in self) {
	anObject = [newDictionary objectForKey:aKey];
        if ([anObject respondsToSelector:@selector(deepMutableCopy)]) {
            anObject = [anObject deepMutableCopy];
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
    const void   **keys;
    unsigned int   keyCount, byteCount;
    BOOL           useMalloc;
    
    keyCount = CFDictionaryGetCount(self);
    
    byteCount = sizeof(*keys) * keyCount;
    useMalloc = byteCount >= SAFE_ALLOCA_SIZE;
    keys = useMalloc ? malloc(byteCount) : alloca(byteCount);
    
    CFDictionaryGetKeysAndValues((CFDictionaryRef)self, keys, NULL);
    
    id keyArray;
    keyArray = [[resultClass alloc] initWithObjects:(id *)keys count:keyCount];
    
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

@end


@implementation NSDictionary (OFDeprecatedExtensions)

- (id)valueForKey:(NSString *)key defaultValue:(id)defaultValue;
{
    return [self objectForKey:key defaultObject:defaultValue];
}

@end
