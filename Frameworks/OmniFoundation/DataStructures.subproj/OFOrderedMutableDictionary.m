// Copyright 2013-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFOrderedMutableDictionary.h>

RCS_ID("$Id$");

@interface OFOrderedMutableDictionary ()

@property (nonatomic, strong) NSMutableDictionary *dictionary;
@property (nonatomic, strong) NSMutableArray *orderedKeys;

@end

@implementation OFOrderedMutableDictionary

#pragma mark - API

- (id<NSCopying>)keyAtIndex:(NSUInteger)index;
{
    return self.orderedKeys[index];
}

- (NSUInteger)indexOfKey:(id<NSCopying>)aKey;
{
    return [self.orderedKeys indexOfObject:aKey];
}

- (id)objectAtIndex:(NSUInteger)index;
{
    id<NSCopying> key = [self keyAtIndex:index];
    return [self objectForKey:key];
}

- (void)setIndex:(NSUInteger)index forKey:(id<NSCopying>)aKey;
{
    OBPRECONDITION([self.orderedKeys containsObject:aKey]);
    if (![self.orderedKeys containsObject:aKey])
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"Dictionary does not an object for key '%@'", aKey] userInfo:nil];
    
    [self setObject:self[aKey] index:index forKey:aKey];
}

- (void)setObject:(id)anObject index:(NSUInteger)index forKey:(id<NSCopying>)aKey;
{
    // In an NSArray you can insertAtIndex:array.count to add to the end of the array. We want to let you do the same here, hence a strictly greater-than check:
    if (index > self.orderedKeys.count)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Index out of bounds" userInfo:nil];
    
    [self setObject:anObject forKey:aKey];
    
    [self.orderedKeys removeObject:aKey];
    [self.orderedKeys insertObject:aKey atIndex:index];
}

- (void)sortUsingComparator:(NSComparator)cmptr;
{
    [self.orderedKeys sortUsingComparator:cmptr];
}

- (void)enumerateEntriesUsingBlock:(void (^)(NSUInteger index, id key, id obj, BOOL *stop))blk;
{
    [self.orderedKeys enumerateObjectsUsingBlock:^(id orderedKeysObject, NSUInteger orderedKeysIndex, BOOL *stop) {
        blk(orderedKeysIndex, orderedKeysObject, self[orderedKeysIndex], stop);
    }];
}

- (void)enumerateEntriesWithOptions:(NSEnumerationOptions)opts usingBlock:(void (^)(NSUInteger index, id key, id obj, BOOL *stop))blk;
{
    [self.orderedKeys enumerateObjectsWithOptions:opts usingBlock:^(id orderedKeysObject, NSUInteger orderedKeysIndex, BOOL *stop) {
        blk(orderedKeysIndex, orderedKeysObject, self[orderedKeysIndex], stop);
    }];
}

#pragma mark - NSMutableDictionary subclass

- (id)init;
{
    return [self initWithCapacity:0];
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    OBRejectInvalidCall(self, _cmd, @"%@ instances don't support NS(Secure)Coding", NSStringFromClass([self class]));
    return [self init];
}

- (id)initWithCapacity:(NSUInteger)numItems;
{
    // Calling [super initWithCapacity:numItems] here will throw an exception, since -initWithCapacity: is only defined on the abstract superclass in this cluster.
    // Instead, we blithely discard the capacity for the super call and just use a default -init. See rdar://problem/14294287
    // This is fine because we're not actually using the superclass's storage anyway – we set up our own dictionary and array right away, using the capacity we're passed.
    
    if (!(self = [super init]))
        return nil;
    
    _dictionary = [[NSMutableDictionary alloc] initWithCapacity:numItems];
    _orderedKeys = [[NSMutableArray alloc] initWithCapacity:numItems];
    
    return self;
}

- (void)setObject:(id)anObject forKey:(id<NSCopying>)aKey;
{
    [self.dictionary setObject:anObject forKey:aKey];
    if (![self.orderedKeys containsObject:aKey]) {
        [self.orderedKeys addObject:aKey];
    }
}

- (void)removeObjectForKey:(id)aKey;
{
    [self.dictionary removeObjectForKey:aKey];
    [self.orderedKeys removeObject:aKey];
}

#pragma mark - NSDictionary subclass

- (id)initWithObjects:(NSArray *)objects forKeys:(NSArray *)keys;
{
    if (!(self = [self initWithCapacity:0]))
        return nil;

    [_dictionary release];
    [_orderedKeys release];
    
    _dictionary = [[NSMutableDictionary alloc] initWithObjects:objects forKeys:keys];
    _orderedKeys = OFISNULL(keys) ? [[NSMutableArray alloc] init] : [keys mutableCopy];
    
    return self;
}

- (NSUInteger)count;
{
    return self.dictionary.count;
}

- (id)objectForKey:(id)aKey;
{
    return [self.dictionary objectForKey:aKey];
}

- (NSEnumerator *)keyEnumerator;
{
    // -[NSArray objectEnumerator] is documented to start at index 0 and work forwards
    return [self.orderedKeys objectEnumerator];
}

- (NSArray *)allKeys;
{
    return [[self.orderedKeys copy] autorelease];
}

#pragma mark - NSObject subclass

- (NSString *)description;
{
    // Emulate NSDictionary's description, but sort the objects by index and include the index on each line
    NSMutableString *desc = [[@"{\n" mutableCopy] autorelease];
    
    for (NSUInteger idx = 0; idx < self.count; idx++) {
        id<NSCopying> key = self.orderedKeys[idx];
        id object = self.dictionary[key];
        [desc appendFormat:@"    (%lu) %@ = \"%@\";\n", idx, key, object];
    }
    
    [desc appendString:@"}"];
    return desc;
}

- (void)dealloc;
{
    [_dictionary release];
    [_orderedKeys release];
    
    [super dealloc];
}

#pragma mark - Subscripting

- (id)objectAtIndexedSubscript:(NSUInteger)index;
{
    return [self objectAtIndex:index];
}

@end
