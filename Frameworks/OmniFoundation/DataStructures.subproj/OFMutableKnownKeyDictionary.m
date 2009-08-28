// Copyright 1998-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFMutableKnownKeyDictionary.h>

#import <OmniFoundation/OFKnownKeyDictionaryTemplate.h>

RCS_ID("$Id$")

@interface OFMutableKnownKeyDictionary (PrivateAPI)
- _initWithTemplate: (OFKnownKeyDictionaryTemplate *) template;
@end

@interface _OFMutableKnownKeyDictionaryEnumerator : NSEnumerator
{
    id *_conditions;
    id *_objects;
    NSUInteger _objectCount;
    NSUInteger _nextIndex;
    id _owner;
}

- initWithConditionList:(id *)conditions
             objectList:(id *)objects
                  count:(NSUInteger)count
                  owner:(id)owner;

- (id)nextObject;

@end

@implementation _OFMutableKnownKeyDictionaryEnumerator

- initWithConditionList:(id *)conditions
             objectList:(id *)objects
                  count:(NSUInteger)count
                  owner:(id)owner;
{
    _conditions = conditions;
    _objects = objects;
    _objectCount = count;
    
    [_owner retain]; // this should keep _conditions or _objects from becoming invalid

    return self;
}

- (void)dealloc;
{
    [_owner release];
    [super dealloc];
}

- (id)nextObject;
{
    // Return the next object corresponding to a non-nil condition
    while (_nextIndex < _objectCount) {
        id condition = _conditions[_nextIndex];
        id object = _objects[_nextIndex];
        _nextIndex++;
        if (condition) {
            OBASSERT(object);
            return object;
        }
    }

    // out of objects
    return nil;
}

@end


static inline NSUInteger _offsetForKeyAllowNotFound(id key, id *keys, NSUInteger keyCount)
{
    for (NSUInteger keyIndex = 0; keyIndex < keyCount; keyIndex++) {
        if (*keys == key)
            return keyIndex;
        keys++;
    }

    // No pointer match.  Back up and try -isEqual:.  Sigh.
    keys -= keyCount;
    for (NSUInteger keyIndex = 0; keyIndex < keyCount; keyIndex++) {
        if ([*keys isEqual: key])
            return keyIndex;
        keys++;
    }

    return ~(NSUInteger)0;
}

static inline NSUInteger _offsetForKey(id key, id *keys, NSUInteger keyCount)
{
    for (NSUInteger keyIndex = 0; keyIndex < keyCount; keyIndex++) {
        if (*keys == key)
            return keyIndex;
        keys++;
    }

    // No pointer match.  Back up and try -isEqual:.  Sigh.
    keys -= keyCount;
    for (NSUInteger keyIndex = 0; keyIndex < keyCount; keyIndex++) {
        if ([*keys isEqual: key])
            return keyIndex;
        keys++;
    }

    // We don't support unknown keys!
    [NSException raise:NSInvalidArgumentException format:@"'%@' is not a known key", key];

    // keep the compiler happy
    return 0;
}

static inline void _nonNilKey(id key)
{
    if (!key)
        [NSException raise:NSInvalidArgumentException format:@"Attempt to access known-key dictionary with nil key."];
}


@implementation OFMutableKnownKeyDictionary

+ (OFMutableKnownKeyDictionary *)newWithTemplate:(OFKnownKeyDictionaryTemplate *)template zone:(NSZone *)zone;
{
    OFMutableKnownKeyDictionary *dict = NSAllocateObject(self, template->_keyCount * sizeof(id), zone);
    return [dict _initWithTemplate: template];
}

+ (OFMutableKnownKeyDictionary *)newWithTemplate:(OFKnownKeyDictionaryTemplate *)template;
{
    return [self newWithTemplate:template zone:NULL];
}

- (void)dealloc;
{
    // _template is not retained since it lives forever
    
    NSUInteger valueCount = _template->_keyCount;
    NSObject **values = &_values[0];
    while (valueCount--) {
        [*values release];
        values++;
    }

    [super dealloc];
}

//
// NSDictionary methods that we either must implement or should for speed.
//

- (NSUInteger)count;
{
    // Count the non-nil slots
    NSUInteger fullCount = 0;
    for (NSUInteger objectIndex = 0; objectIndex < _template->_keyCount; objectIndex++) {
        if (_values[objectIndex])
            fullCount++;
    }

    return fullCount;
}

- (NSEnumerator *)keyEnumerator;
{
    // enumerate over keys with non-nil values
    return [[[_OFMutableKnownKeyDictionaryEnumerator alloc] initWithConditionList:&_values[0]
                                                                       objectList:&_template->_keys[0]
                                                                            count:_template->_keyCount
                                                                            owner:self] autorelease];
}

- (id)objectForKey:(id)aKey;
{    
    _nonNilKey(aKey);
    NSUInteger keyIndex = _offsetForKeyAllowNotFound(aKey, &_template->_keys[0], _template->_keyCount);
    if (keyIndex == ~(NSUInteger)0)
        return nil;
    return _values[keyIndex];
}

- (NSArray *)allKeys;
{
    return [[self copyKeys] autorelease];
}

- (NSArray *)copyKeys;
{
    // See if we have any nil values.  If we don't, we can just use
    // the keys array from the template.

    // Collect the non-nil keys in here
    id *keys = alloca(sizeof(id) * _template->_keyCount);

    // Count the non-nil slots
    NSUInteger fullCount = 0;
    for (NSUInteger objectIndex = 0; objectIndex < _template->_keyCount; objectIndex++) {
        if (_values[objectIndex]) {
            // store the *key* for this non-nil value
            keys[fullCount] = _template->_keys[objectIndex];
            fullCount++;
        }
    }

    if (fullCount == _template->_keyCount)
        // all keys present
        return [_template->_keyArray retain];
    else
        // return a new array formed from the keys with non-nil values
        return [[NSArray alloc] initWithObjects:keys count:fullCount];
}

- (NSArray *)allValues;
{
    // Collect the non-nil keys in here
    id *values = alloca(sizeof(id) * _template->_keyCount);

    // Count the non-nil slots
    NSUInteger fullCount = 0;
    for (NSUInteger objectIndex = 0; objectIndex < _template->_keyCount; objectIndex++) {
        if (_values[objectIndex]) {
            // store the non-nil value
            values[fullCount] = _values[objectIndex];
            fullCount++;
        }
    }

    // return a new array formed from the non-nil values
    return [[[NSArray alloc] initWithObjects:values count:fullCount] autorelease];
}

- (NSEnumerator *)objectEnumerator;
{
    // enumerate over non-nil values (the values themselves are the condition)
    return [[[_OFMutableKnownKeyDictionaryEnumerator alloc] initWithConditionList:&_values[0]
                                                                       objectList:&_values[0]
                                                                            count:_template->_keyCount
                                                                            owner:self] autorelease];
}

//
// NSMutableDictionary methods that we either must implement or should for speed.
//

- (void)removeObjectForKey:(id)aKey;
{
    _nonNilKey(aKey);
    NSUInteger keyIndex = _offsetForKey(aKey, &_template->_keys[0], _template->_keyCount);
    [_values[keyIndex] release];
    _values[keyIndex] = nil;
}

- (void)setObject:(id)anObject forKey:(id)aKey;
{
    _nonNilKey(aKey);
    NSUInteger keyIndex = _offsetForKey(aKey, &_template->_keys[0], _template->_keyCount);
    if (_values[keyIndex] != anObject) {
        [_values[keyIndex] release];
        _values[keyIndex] = [anObject retain];
    }
}

//
// Local methods
//

- (OFMutableKnownKeyDictionary *)mutableKnownKeyCopyWithZone:(NSZone *)zone;
{
    OFMutableKnownKeyDictionary *copy = NSAllocateObject(isa, _template->_keyCount * sizeof(id), zone);
    copy->_template = _template;
    NSUInteger valueCount = _template->_keyCount;
    
    NSObject **source = &_values[0];
    NSObject **dest = &copy->_values[0];
    while (valueCount--) {
        *dest = [*source retain];
        dest++;
        source++;
    }

    return copy;
}

- (void)addLocallyAbsentValuesFromDictionary:(OFMutableKnownKeyDictionary *)fromDictionary;
/*" Modifies the receiver by adding any values from fromDictionary that are present there but not present in the receiver.  The two dictionaries must share the same template. "*/
{
    OBPRECONDITION(_template == fromDictionary->_template);

    NSUInteger valueIndex = _template->_keyCount;

    while (valueIndex--) {
        if (_values[valueIndex])
            continue;
        id value = fromDictionary->_values[valueIndex];
        if (value)
            _values[valueIndex] = [value retain];
    }
}

- (void)applyFunction:(OFMutableKnownKeyDictionaryApplier)function context:(void *)context;
/*" Calls the function for each key/value pair with non-nil value.  Much faster than using a keyEnumerator.  The function may modify the value for the key being processed, but should not modify values for other keys. "*/
{
    NSUInteger valueIndex = _template->_keyCount;

    while (valueIndex--) {
        id value = _values[valueIndex];
        if (value)
            function(_template->_keys[valueIndex], value, context);
    }
}

- (void)applyPairFunction:(OFMutableKnownKeyDictionaryPairApplier)function pairDictionary:(OFMutableKnownKeyDictionary *)pairDictionary context:(void *)context;
/*" Calls the function for key in the receiver and another dictionary.  The key and the two objects are passed to the function.  Since two dictionaries are consulted for key/value pairs, the function may get one value that is nil and another that isn't, but it should never get two nil values (i.e., the key isn't in either dictionary).  The two dictionaries must share the same template. "*/
{
    OBPRECONDITION(_template == pairDictionary->_template);

    NSUInteger valueIndex = _template->_keyCount;
    while (valueIndex--) {
        id value1 = _values[valueIndex];
        id value2 = pairDictionary->_values[valueIndex];
        if (value1 || value2)
            function(_template->_keys[valueIndex], value1, value2, context);
    }
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    // Not as fast as it could be; but we can optimize later if this gets called a lot.
    return [[NSDictionary alloc] initWithDictionary:self];
}
- (id)mutableCopyWithZone:(NSZone *)zone;
{
    // Not as fast as it could be; but we can optimize later if this gets called a lot.
    return [[NSMutableDictionary alloc] initWithDictionary:self];
}

@end

@implementation OFMutableKnownKeyDictionary (PrivateAPI)
- _initWithTemplate: (OFKnownKeyDictionaryTemplate *) template
{
    // Don't retain.  Templates are uniqued and live forever.
    _template = template;
    return self;
}

@end
