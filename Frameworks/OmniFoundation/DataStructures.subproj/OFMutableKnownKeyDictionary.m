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
    id           *_conditions;
    id           *_objects;
    unsigned int  _objectCount;
    unsigned int  _nextIndex;
    id            _owner;
}

- initWithConditionList: (id *) conditions
             objectList: (id *) objects
                  count: (unsigned int) count
                  owner: (id) owner;

- (id) nextObject;

@end

@implementation _OFMutableKnownKeyDictionaryEnumerator

- initWithConditionList: (id *) conditions
             objectList: (id *) objects
                  count: (unsigned int) count
                  owner: (id) owner;
{
    _conditions = conditions;
    _objects = objects;
    _objectCount = count;
    [_owner retain]; // this should keep _conditions or _objects from becoming invalid

    return self;
}

- (void) dealloc;
{
    [_owner release];
    [super dealloc];
}

- (id) nextObject;
{
    id object, condition;

    // Return the next object corresponding to a non-nil condition
    while (_nextIndex < _objectCount) {
        condition = _conditions[_nextIndex];
        object    = _objects[_nextIndex];
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


static inline unsigned int _offsetForKeyAllowNotFound(id key, id *keys, unsigned int keyCount)
{
    unsigned int keyIndex;

    for (keyIndex = 0; keyIndex < keyCount; keyIndex++) {
        if (*keys == key)
            return keyIndex;
        keys++;
    }

    // No pointer match.  Back up and try -isEqual:.  Sigh.
    keys -= keyCount;
    for (keyIndex = 0; keyIndex < keyCount; keyIndex++) {
        if ([*keys isEqual: key])
            return keyIndex;
        keys++;
    }

    return ~(unsigned int)0;
}

static inline unsigned int _offsetForKey(id key, id *keys, unsigned int keyCount)
{
    unsigned int keyIndex;

    for (keyIndex = 0; keyIndex < keyCount; keyIndex++) {
        if (*keys == key)
            return keyIndex;
        keys++;
    }

    // No pointer match.  Back up and try -isEqual:.  Sigh.
    keys -= keyCount;
    for (keyIndex = 0; keyIndex < keyCount; keyIndex++) {
        if ([*keys isEqual: key])
            return keyIndex;
        keys++;
    }

    // We don't support unknown keys!
    [NSException raise: NSInvalidArgumentException
                format: @"'%@' is not a known key", key];

    // keep the compiler happy
    return 0;
}

static inline void _nonNilKey(id key)
{
    if (!key) {
        [NSException raise: NSInvalidArgumentException
                    format: @"Attempt to access known-key dictionary with nil key."];
    }
}


@implementation OFMutableKnownKeyDictionary

+ (OFMutableKnownKeyDictionary *) newWithTemplate: (OFKnownKeyDictionaryTemplate *) template zone: (NSZone *) zone;
{
    OFMutableKnownKeyDictionary *dict;

    dict = (OFMutableKnownKeyDictionary *)NSAllocateObject(self, template->_keyCount * sizeof(id), zone);
    return [dict _initWithTemplate: template];
}

+ (OFMutableKnownKeyDictionary *) newWithTemplate: (OFKnownKeyDictionaryTemplate *) template;
{
    return [self newWithTemplate: template zone: NULL];
}

- (void) dealloc;
{
    unsigned int   valueCount;
    NSObject     **values;

    // _template is not retained since it lives forever
    
    valueCount = _template->_keyCount;
    values = &_values[0];
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
    unsigned int objectIndex, fullCount;

    // Count the non-nil slots
    fullCount = 0;
    for (objectIndex = 0; objectIndex < _template->_keyCount; objectIndex++) {
        if (_values[objectIndex])
            fullCount++;
    }

    return fullCount;
}

- (NSEnumerator *)keyEnumerator;
{
    // enumerate over keys with non-nil values
    return [[[_OFMutableKnownKeyDictionaryEnumerator alloc] initWithConditionList: &_values[0]
                                                                       objectList: &_template->_keys[0]
                                                                            count: _template->_keyCount
                                                                            owner: self] autorelease];
}

- (id)objectForKey:(id)aKey;
{
    unsigned int keyIndex;
    
    _nonNilKey(aKey);
    keyIndex = _offsetForKeyAllowNotFound(aKey, &_template->_keys[0], _template->_keyCount);
    if (keyIndex == ~(unsigned int)0)
        return nil;
    return _values[keyIndex];
}

- (NSArray *)allKeys;
{
    return [[self copyKeys] autorelease];
}

- (NSArray *) copyKeys;
{
    // See if we have any nil values.  If we don't, we can just use
    // the keys array from the template.
    unsigned int  objectIndex, fullCount;
    id           *keys;

    // Collect the non-nil keys in here
    keys = alloca(sizeof(id) * _template->_keyCount);

    // Count the non-nil slots
    fullCount = 0;
    for (objectIndex = 0; objectIndex < _template->_keyCount; objectIndex++) {
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
        return [[NSArray alloc] initWithObjects: keys count: fullCount];
}

- (NSArray *)allValues;
{
    unsigned int  objectIndex, fullCount;
    id           *values;

    // Collect the non-nil keys in here
    values = alloca(sizeof(id) * _template->_keyCount);

    // Count the non-nil slots
    fullCount = 0;
    for (objectIndex = 0; objectIndex < _template->_keyCount; objectIndex++) {
        if (_values[objectIndex]) {
            // store the non-nil value
            values[fullCount] = _values[objectIndex];
            fullCount++;
        }
    }

    // return a new array formed from the non-nil values
    return [[[NSArray alloc] initWithObjects: values count: fullCount] autorelease];
}

- (NSEnumerator *)objectEnumerator;
{
    // enumerate over non-nil values (the values themselves are the condition)
    return [[[_OFMutableKnownKeyDictionaryEnumerator alloc] initWithConditionList: &_values[0]
                                                                       objectList: &_values[0]
                                                                            count: _template->_keyCount
                                                                            owner: self] autorelease];
}

//
// NSMutableDictionary methods that we either must implement or should for speed.
//

- (void)removeObjectForKey:(id)aKey;
{
    unsigned int keyIndex;

    _nonNilKey(aKey);
    keyIndex = _offsetForKey(aKey, &_template->_keys[0], _template->_keyCount);
    [_values[keyIndex] release];
    _values[keyIndex] = nil;
}

- (void)setObject:(id)anObject forKey:(id)aKey;
{
    unsigned int keyIndex;

    _nonNilKey(aKey);
    keyIndex = _offsetForKey(aKey, &_template->_keys[0], _template->_keyCount);
    if (_values[keyIndex] != anObject) {
        [_values[keyIndex] release];
        _values[keyIndex] = [anObject retain];
    }
}

//
// Local methods
//

- (OFMutableKnownKeyDictionary *) mutableKnownKeyCopyWithZone: (NSZone *) zone;
{
    OFMutableKnownKeyDictionary  *copy;
    NSObject                    **source, **dest;
    unsigned int                  valueCount;

    copy = (OFMutableKnownKeyDictionary *)NSAllocateObject(isa, _template->_keyCount * sizeof(id), zone);
    copy->_template = _template;
    valueCount      = _template->_keyCount;
    
    source = &_values[0];
    dest   = &copy->_values[0];
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

    unsigned int valueIndex = _template->_keyCount;

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
    unsigned int valueIndex = _template->_keyCount;

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

    unsigned int valueIndex = _template->_keyCount;
    while (valueIndex--) {
        id value1 = _values[valueIndex];
        id value2 = pairDictionary->_values[valueIndex];
        if (value1 || value2)
            function(_template->_keys[valueIndex], value1, value2, context);
    }
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
