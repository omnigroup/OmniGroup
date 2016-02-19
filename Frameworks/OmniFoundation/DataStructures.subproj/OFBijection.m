// Copyright 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFBijection-Internal.h"

#import <Foundation/NSMapTable.h>

RCS_ID("$Id$");

@implementation OFBijection

#pragma mark - Public API

#pragma mark Class constructors

+ (instancetype)bijection;
{
    return [[[self alloc] init] autorelease];
}

+ (instancetype)bijectionWithObject:(id)anObject forKey:(id)aKey;
{
    return [[[self alloc] initWithObject:anObject forKey:aKey] autorelease];
}

+ (instancetype)bijectionWithObjects:(NSArray *)objects forKeys:(NSArray *)keys;
{
    return [[[self alloc] initWithObjects:objects forKeys:keys] autorelease];
}

+ (instancetype)bijectionWithObjectsAndKeys:(id)anObject, ... NS_REQUIRES_NIL_TERMINATION;
{
    va_list args;
    va_start(args, anObject);
    OFBijection *bijection = [[[self alloc] _initWithFirstObject:anObject rest:args] autorelease];
    va_end(args);
    
    return bijection;
}

+ (instancetype)bijectionWithDictionary:(NSDictionary *)dictionary;
{
    return [[[self alloc] initWithDictionary:dictionary] autorelease];
}

#pragma mark Instance initializers

- (id)init;
{
    return [self initWithObjects:@[] forKeys:@[]];
}

- (id)initWithObject:(id)anObject forKey:(id)aKey;
{
    return [self initWithObjects:@[ anObject ] forKeys:@[ aKey ]];
}

- (id)initWithObjects:(NSArray *)objects forKeys:(NSArray *)keys;
{
    OBPRECONDITION(OFNOTNULL(keys));
    if (OFISNULL(keys))
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Bijection requires keys" userInfo:nil];
    
    OBPRECONDITION(objects);
    if (OFISNULL(objects))
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Bijection requires objects" userInfo:nil];
    
    OBPRECONDITION(keys.count == objects.count);
    if (keys.count != objects.count)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Bijection requires same number of keys and objects" userInfo:nil];
    
    OBPRECONDITION([[NSSet setWithArray:keys] count] == keys.count);
    if ([[NSSet setWithArray:keys] count] != keys.count)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Bijection requires unique keys" userInfo:nil];
    
    OBPRECONDITION([[NSSet setWithArray:objects] count] == objects.count);
    if ([[NSSet setWithArray:objects] count] != objects.count)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Bijection requires unique objects" userInfo:nil];
    
    if (!(self = [super init]))
        return nil;
    
    _keysToObjects = [[NSMapTable alloc] initWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory capacity:keys.count];
    _objectsToKeys = [[NSMapTable alloc] initWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory capacity:objects.count];
    
    for (NSUInteger i = 0; i < keys.count; i++) {
        id key = keys[i];
        id object = objects[i];
        
        [_keysToObjects setObject:object forKey:key];
        [_objectsToKeys setObject:key forKey:object];
    }
    
    OBPOSTCONDITION(self.count == keys.count); // and therefore == objects.count
    OBINVARIANT([self checkInvariants]);
    return self;
}

- (id)initWithObjectsAndKeys:(id)anObject, ... NS_REQUIRES_NIL_TERMINATION;
{
    va_list args;
    va_start(args, anObject);
    self = [self _initWithFirstObject:anObject rest:args];
    va_end(args);
    return self;
}

- (id)_initWithFirstObject:(id)firstObject rest:(va_list)items;
{
    NSMutableArray *keys = [NSMutableArray array];
    NSMutableArray *objects = [NSMutableArray array];
    
    id object = firstObject;
    id key = va_arg(items, id);
    
    while (OFNOTNULL(object)) {
        
        OBASSERT(OFNOTNULL(key));
        if (OFISNULL(key))
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Bijection requires equal number of keys and objects" userInfo:nil];
        
        [keys addObject:key];
        [objects addObject:object];
        
        object = va_arg(items, id);
        key = va_arg(items, id);
    }
    
    return [self initWithObjects:objects forKeys:keys];
}

- (id)initWithDictionary:(NSDictionary *)dictionary; // designated initializer
{
    NSMutableArray *orderedKeys = [NSMutableArray array];
    NSMutableArray *orderedValues = [NSMutableArray array];
    for (id key in dictionary) {
        [orderedKeys addObject:key];
        [orderedValues addObject:dictionary[key]];
    }
    return [self initWithObjects:orderedValues forKeys:orderedKeys];
}

- (void)dealloc;
{
    [_keysToObjects release];
    [_objectsToKeys release];
    [super dealloc];
}

#pragma mark Core functions

- (NSUInteger)count;
{
    return self.keysToObjects.count;
}

- (id)objectForKey:(id)aKey;
{
    return [self.keysToObjects objectForKey:aKey];
}

- (id)keyForObject:(id)anObject;
{
    return [self.objectsToKeys objectForKey:anObject];
}

- (id)objectForKeyedSubscript:(id)aKey;
{
    // Documentation: "This method behaves the same as objectForKey:."
    return [self objectForKey:aKey];
}

- (NSArray *)allKeys;
{
    return [[self.keysToObjects keyEnumerator] allObjects];
}

- (NSArray *)allObjects;
{
    return [[self.objectsToKeys keyEnumerator] allObjects];
}

#pragma mark Derived bijections

- (OFBijection *)invertedBijection;
{
    NSMutableArray *keys = [NSMutableArray arrayWithCapacity:self.count];
    NSMutableArray *objects = [NSMutableArray arrayWithCapacity:self.count];
    
    for (id key in self) {
        id object = [self objectForKey:key];
        
        [keys addObject:key];
        [objects addObject:object];
    }
    
    return [OFBijection bijectionWithObjects:keys forKeys:objects];
}

#pragma mark Comparison

- (BOOL)isEqualToBijection:(OFBijection *)bijection;
{
    if (self.count != bijection.count)
        return NO;
    
    for (id key in self.keysToObjects) {
        id object = [self objectForKey:key];
        id otherObject = [bijection objectForKey:key];
        
        if (![object isEqual:otherObject])
            return NO;
    }
    
    return YES;
}

#pragma mark - NSFastEnumeration protocol

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained [])buffer count:(NSUInteger)len;
{
    return [self.keysToObjects countByEnumeratingWithState:state objects:buffer count:len];
}

#pragma mark - NSObject subclass/protocol

- (BOOL)isEqual:(id)object;
{
    if (![object isKindOfClass:[OFBijection class]])
        return NO;
    
    return [self isEqualToBijection:(OFBijection *)object];
}

- (NSUInteger)hash;
{
    return [self.keysToObjects hash] ^ [self.objectsToKeys hash];
}

- (NSString *)description;
{
    NSMutableString *description = [NSMutableString string];
    
    [description appendFormat:@"%@ <%p> {\n", NSStringFromClass([self class]), self];
    
    for (id key in self.keysToObjects.keyEnumerator) {
        NSString *objectDescription = [[self.keysToObjects objectForKey:key] description];
        if ([objectDescription rangeOfString:@"\n"].location != NSNotFound) {
            objectDescription = [objectDescription stringByReplacingOccurrencesOfString:@"\n" withString:@"\n    "];
        }
        [description appendFormat:@"    %@ -> %@\n", key, objectDescription];
    }
    
    [description appendString:@"}"];
     
    return description;
}

#pragma mark - Debugging & assertions

#if defined(OMNI_ASSERTIONS_ON)
- (BOOL)checkInvariants;
{
    // Have objects?
    OBINVARIANT(OFNOTNULL(self.keysToObjects));
    OBINVARIANT(OFNOTNULL(self.objectsToKeys));
    
    // Have same number of objects?
    OBINVARIANT(self.keysToObjects.count == self.objectsToKeys.count);
    
    // Have same object sets?
    NSSet *forwardKeys = [NSSet setWithArray:[[self.keysToObjects keyEnumerator] allObjects]];
    NSSet *forwardObjects = [NSSet setWithArray:[[self.keysToObjects objectEnumerator] allObjects]];
    
    NSSet *reverseKeys = [NSSet setWithArray:[[self.objectsToKeys objectEnumerator] allObjects]];
    NSSet *reverseObjects = [NSSet setWithArray:[[self.objectsToKeys keyEnumerator] allObjects]];
    
    OBINVARIANT([forwardKeys isEqualToSet:reverseKeys]);
    OBINVARIANT([forwardObjects isEqualToSet:reverseObjects]);
    
    // Mapping is injective & surjective?
    for (id key in self.keysToObjects) {
        id object = [self.keysToObjects objectForKey:key];
        id keyAgain = [self.objectsToKeys objectForKey:object];
        
        OBINVARIANT([key isEqual:keyAgain]);
    }
    
    // This method returns a BOOL so we can wrap it in OBINVARIANT() at call sites
    return YES;
}
#endif

@end
