// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
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

- (id)objectAtIndex:(NSUInteger)index;
{
    NSString *key = self.orderedKeys[index];
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
    if (index >= self.orderedKeys.count)
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Index out of bounds" userInfo:nil];
    
    [self setObject:anObject forKey:aKey];
    
    [self.orderedKeys removeObject:aKey];
    [self.orderedKeys insertObject:aKey atIndex:index];
}

- (void)sortUsingComparator:(NSComparator)cmptr;
{
    [self.orderedKeys sortUsingComparator:cmptr];
}

- (void)enumerateEntriesUsingBlock:(void (^)(NSUInteger index, id<NSCopying> key, id obj, BOOL *stop))blk;
{
    [self.orderedKeys enumerateObjectsUsingBlock:^(id orderedKeysObject, NSUInteger orderedKeysIndex, BOOL *stop) {
        blk(orderedKeysIndex, orderedKeysObject, self[orderedKeysIndex], stop);
    }];
}

#pragma mark - NSMutableDictionary subclass

- (id)init;
{
    return [self initWithCapacity:0];
}

- (id)initWithCapacity:(NSUInteger)numItems;
{
    // Calling [super initWithCapacity:numItems] here will throw an exception, since -initWithCapacity: is only defined on the abstract superclass in this cluster.
    // Instead, we blithely discard the capacity and just use a default -init. See rdar://problem/14294287
    
    if (!(self = [super init]))
        return nil;
    
    _dictionary = [[NSMutableDictionary dictionaryWithCapacity:numItems] retain];
    _orderedKeys = [[NSMutableArray arrayWithCapacity:numItems] retain];
    
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
    if (!(self = [super initWithObjects:objects forKeys:keys]))
        return nil;
    
    _dictionary = [[NSMutableDictionary alloc] initWithObjects:objects forKeys:keys];
    _orderedKeys = OFISNULL(keys) ? [[NSMutableArray array] retain] : [keys mutableCopy];
    
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
