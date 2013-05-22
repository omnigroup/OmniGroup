// Copyright 1997-2005, 2007-2008, 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFMultiValueDictionary.h>

#import <OmniFoundation/CFDictionary-OFExtensions.h>
#import <OmniFoundation/NSDictionary-OFExtensions.h>

RCS_ID("$Id$")

@implementation OFMultiValueDictionary
{
    CFMutableDictionaryRef dictionary;
    short dictionaryFlags;
}

#define DictKeysStandard  0   // dictionary is an NSMutableDictionary
#define DictKeysOFCaseInsensitiveStrings  1  // dictionary uses OFCaseInsensitiveStringKeyDictionaryCallbacks
#define DictKeysCustom  2  // dictionary uses some caller-supplied key callbacks

- init;
{
    return [self initWithKeyCallBacks:NULL];
}

- initWithCaseInsensitiveKeys:(BOOL)caseInsensitivity;
{
    if (caseInsensitivity)
        return [self initWithKeyCallBacks:&OFCaseInsensitiveStringKeyDictionaryCallbacks];
    else
        return [self initWithKeyCallBacks:&OFNSObjectCopyDictionaryKeyCallbacks];
}

// The designated initializer
- initWithKeyCallBacks:(const CFDictionaryKeyCallBacks *)keyBehavior;
{
    if (!(self = [super init]))
        return nil;

    if (keyBehavior == NULL)
        keyBehavior = &OFNSObjectCopyDictionaryKeyCallbacks;

    if (keyBehavior == &OFNSObjectCopyDictionaryKeyCallbacks)
        dictionaryFlags = DictKeysStandard;
    else if (keyBehavior == &OFCaseInsensitiveStringKeyDictionaryCallbacks)
        dictionaryFlags = DictKeysOFCaseInsensitiveStrings;
    else
        dictionaryFlags = DictKeysCustom;

    dictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                           keyBehavior,
                                           &OFNSObjectDictionaryValueCallbacks);

    return self;
}

- (void)dealloc;
{
    CFRelease(dictionary);
    [super dealloc];
}

- (NSMutableArray *)_arrayForKey:(id)aKey alloc:(NSUInteger)allocCapacity;
{
    NSMutableArray *value;

    if (aKey == nil) {
        if (allocCapacity != 0)
            OBRejectInvalidCall(self, _cmd, @"Attempt to insert nil key");
        return nil;
    }
        
    value = (id)CFDictionaryGetValue(dictionary, aKey);
    if (allocCapacity && !value) {
        value = [[NSMutableArray alloc] initWithCapacity:allocCapacity];
        CFDictionaryAddValue(dictionary, aKey, value);
        [value release];
    }

    return value;
}

- (NSArray *)arrayForKey:(id)aKey;
{
    return [self _arrayForKey:aKey alloc:0];
}

- (id)firstObjectForKey:(id)aKey;
{
    return [[self _arrayForKey:aKey alloc:0] objectAtIndex:0];
}

- (id)lastObjectForKey:(id)aKey;
{
    return [[self _arrayForKey:aKey alloc:0] lastObject];
}

- (void)addObject:(id)anObject forKey:(id)aKey;
{
    if (anObject == nil)
        OBRejectInvalidCall(self, _cmd, @"Attempt to insert nil value");
    [[self _arrayForKey:aKey alloc:1] addObject:anObject];
}

- (void)addObjects:(NSArray *)moreObjects forKey:(id)aKey;
{
    NSMutableArray *valueArray;
    NSUInteger objectCount = [moreObjects count];

    if (objectCount == 0)
        return;
    valueArray = [self _arrayForKey:aKey alloc:objectCount];
    [valueArray addObjectsFromArray:moreObjects];
}

- (void)addObjects:(NSArray *)manyObjects keyedByBlock:(OFObjectToObjectBlock)keyBlock;
{
    for (id object in manyObjects) {
        id key = keyBlock(object);
        if (key == nil)
            OBRejectInvalidCall(self, _cmd, @"Attempt to insert value with nil key");
        [[self _arrayForKey:key alloc:1] addObject:object];
    }
}

- (void)setObjects:(NSArray *)replacementObjects forKey:(id)aKey;
{
    if (replacementObjects != nil && [replacementObjects count] > 0) {
        NSMutableArray *valueArray;

        valueArray = [[NSMutableArray alloc] initWithArray:replacementObjects];
        CFDictionaryAddValue(dictionary, aKey, valueArray);
        [valueArray release];
    } else {
        CFDictionaryRemoveValue(dictionary, aKey);
    }
}

- (void)insertObject:(id)anObject forKey:(id)aKey atIndex:(unsigned int)anIndex;
{
    if (anObject == nil)
        OBRejectInvalidCall(self, _cmd, @"Attempt to insert nil value");
    [[self _arrayForKey:aKey alloc:1] insertObject:anObject atIndex:anIndex];
}

- (BOOL)removeObject:(id)anObject forKey:(id)aKey
{
    NSMutableArray *valueArray = [self _arrayForKey:aKey alloc:0];
    NSUInteger objectIndex;

    if (!valueArray)
        return NO;

    objectIndex = [valueArray indexOfObject:anObject];
    if (objectIndex == NSNotFound)
        return NO;

    [valueArray removeObjectAtIndex:objectIndex];

    if ([valueArray count] == 0)
        CFDictionaryRemoveValue(dictionary, aKey);

    return YES;
}

- (BOOL)removeObjectIdenticalTo:(id)anObject forKey:(id)aKey
{
    NSMutableArray *valueArray = [self _arrayForKey:aKey alloc:0];
    NSUInteger objectIndex;

    if (!valueArray)
        return NO;

    objectIndex = [valueArray indexOfObjectIdenticalTo:anObject];
    if (objectIndex == NSNotFound)
        return NO;

    [valueArray removeObjectAtIndex:objectIndex];

    if ([valueArray count] == 0)
        CFDictionaryRemoveValue(dictionary, aKey);

    return YES;
}

- (void)removeAllObjects
{
    CFDictionaryRemoveAllValues(dictionary);
}

- (NSEnumerator *)keyEnumerator;
{
    return [(NSDictionary *)dictionary keyEnumerator];
}

struct copyOutContext {
    NSMutableArray *copyKeys;
    NSMutableArray *copyValues;
};

static void copyFunction(const void *key, const void *value, void *context)
{
    struct copyOutContext *copyOut = context;

    if (copyOut->copyKeys)
        [copyOut->copyKeys addObject:(id)key];
    if (copyOut->copyValues)
        [copyOut->copyValues addObjectsFromArray:(NSArray *)value];
}

- (NSArray *)allKeys;
{
    struct copyOutContext copyOut;
    
    copyOut.copyKeys = [NSMutableArray array];
    copyOut.copyValues = nil;
    CFDictionaryApplyFunction(dictionary, &copyFunction, &copyOut);
    return copyOut.copyKeys;
}

- (NSArray *)allValues;
{
    struct copyOutContext copyOut;

    copyOut.copyKeys = nil;
    copyOut.copyValues = [NSMutableArray array];
    CFDictionaryApplyFunction(dictionary, &copyFunction, &copyOut);
    return copyOut.copyValues;
}

- (NSMutableDictionary *)dictionary;
{
    return (NSMutableDictionary *)dictionary;
}

static void duplicateFunction(const void *key, const void *value, void *context)
{
    OFMultiValueDictionary *other = context;

    [other setObjects:(NSArray *)value forKey:(id)key];
}

- mutableCopyWithZone:(NSZone *)newZone
{
    OFMultiValueDictionary *newSelf;

    newSelf = [[[self class] allocWithZone:newZone] init];
    CFDictionaryApplyFunction(dictionary, &duplicateFunction, (void *)newSelf);
    return newSelf;
}

- (BOOL)isEqual:anotherObject
{
    NSMutableDictionary *otherDictionary;

    if (anotherObject == self)
        return YES;
    if ([anotherObject isKindOfClass:[OFMultiValueDictionary class]])
        otherDictionary = [anotherObject dictionary];
    else
        return NO;

    return CFEqual(dictionary, otherDictionary)? YES : NO;
}

// If we do need to support NSCoding, we'll need to handle 64-bit key counts or at least avoid accidentally updating the archiving to an incompatible format.
#if 0

#pragma mark -
#pragma mark NSCoding

- initWithCoder:(NSCoder *)coder
{
    short flags;
    unsigned int keyCount;
    unsigned *valueCounts;
    unsigned keyIndex, valueIndex;
    
    [coder decodeValuesOfObjCTypes:"si", &flags, &keyCount];
    
    if ((flags & 0xFE) != 0)
        [NSException raise:NSGenericException format:@"Serialized %@ is of unknown kind", [[self class] name]];
    
    if (![self initWithCaseInsensitiveKeys: (flags&1)? YES : NO])
        return nil;
    
    if (keyCount == 0)
        return self;
    
    valueCounts = malloc(sizeof(*valueCounts) * keyCount);
    [coder decodeArrayOfObjCType:@encode(unsigned int) count:keyCount at:valueCounts];
    for (keyIndex = 0; keyIndex < keyCount; keyIndex ++) {
        NSMutableArray *values;
        NSString *key;
        
        key = [coder decodeObject];
        values = [[NSMutableArray alloc] initWithCapacity:valueCounts[keyIndex]];
        for (valueIndex = 0; valueIndex < valueCounts[keyIndex]; valueIndex ++) {
            [values addObject:[coder decodeObject]];
        }
        CFDictionaryAddValue(dictionary, key, values);
        [values release];
    }
    free(valueCounts);
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    short flags;
    int keyIndex, keyCount;
    NSArray *keys;
    NSArray **values;
    unsigned int *valueCounts, valueIndex;

    flags = 0;
    if (dictionaryFlags == DictKeysOFCaseInsensitiveStrings)
        flags |= 1;
    else if (dictionaryFlags != DictKeysStandard) {
        [NSException raise:NSGenericException format:@"Cannot serialize an %@ with custom key callbacks", [[self class] name]];
    }

    keys = [[self allKeys] sortedArrayUsingSelector:@selector(compare:)];
    keyCount = [keys count];

    [coder encodeValuesOfObjCTypes:"si", &flags, &keyCount];

    if (keyCount == 0)
        return;

    valueCounts = malloc(sizeof(*valueCounts) * keyCount);
    values = malloc(sizeof(*values) * keyCount);

    for(keyIndex = 0; keyIndex < keyCount; keyIndex ++) {
        NSArray *valueArray = [self arrayForKey:[keys objectAtIndex:keyIndex]];
        values[keyIndex] = valueArray;
        valueCounts[keyIndex] = [valueArray count];
    }

    [coder encodeArrayOfObjCType:@encode(unsigned int) count:keyCount at:valueCounts];

    for(keyIndex = 0; keyIndex < keyCount; keyIndex ++) {
        [coder encodeObject:[keys objectAtIndex:keyIndex]];
        for(valueIndex = 0; valueIndex < valueCounts[keyIndex]; valueIndex ++) {
            [coder encodeObject:[values[keyIndex] objectAtIndex:valueIndex]];
        }
    }

    free(valueCounts);
    free(values);
}
#endif

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:(id)dictionary forKey:@"dictionary"];
    return debugDictionary;
}

@end

@implementation NSArray (OFMultiValueDictionary)

- (OFMultiValueDictionary *)groupByKeyBlock:(OFObjectToObjectBlock)keyBlock;
{
    OFMultiValueDictionary *dictionary = [[[OFMultiValueDictionary alloc] init] autorelease];
    for (id object in self)
        [dictionary addObject:object forKey:keyBlock(object)];
    return dictionary;
}

- (OFMultiValueDictionary *)groupByKeyBlock:(id (^)(id object, id arg))keyBlock withObject:(id)argument;
{
    OFMultiValueDictionary *dictionary = [[[OFMultiValueDictionary alloc] init] autorelease];
    for (id object in self)
        [dictionary addObject:object forKey:keyBlock(object, argument)];
    return dictionary;
}

@end

#import <OmniFoundation/OFCharacterSet.h>
#import <OmniFoundation/OFStringScanner.h>

@implementation NSString (OFMultiValueDictionary)

static OFCharacterSet *_nameDelimiterOFCharacterSet(void)
{
    static OFCharacterSet *NameDelimiterSet = nil;
    if (NameDelimiterSet == nil) {
        NameDelimiterSet = [[OFCharacterSet alloc] initWithString:@"&="];
    }
    OBPOSTCONDITION(NameDelimiterSet != nil);
    return NameDelimiterSet;
}

static OFCharacterSet *_valueDelimiterOFCharacterSet(void)
{
    static OFCharacterSet *ValueDelimiterSet = nil;
    if (ValueDelimiterSet == nil) {
        ValueDelimiterSet = [[OFCharacterSet alloc] initWithString:@"&"];
    }
    OBPOSTCONDITION(ValueDelimiterSet != nil);
    return ValueDelimiterSet;
}

- (OFMultiValueDictionary *)parametersFromQueryString;
{
    OFCharacterSet *nameDelimiterSet = _nameDelimiterOFCharacterSet();
    OFCharacterSet *valueDelimiterSet = _valueDelimiterOFCharacterSet();
    OFMultiValueDictionary *parameters = [[[OFMultiValueDictionary alloc] init] autorelease];
    OFStringScanner *scanner = [[OFStringScanner alloc] initWithString:self];
    while (scannerHasData(scanner)) {
        NSString *encodedName = [scanner readFullTokenWithDelimiterOFCharacterSet:nameDelimiterSet forceLowercase:NO];
        if (scannerPeekCharacter(scanner) == '=')
            scannerSkipPeekedCharacter(scanner); // Skip '=' between name and value
        NSString *encodedValue = [scanner readFullTokenWithDelimiterOFCharacterSet:valueDelimiterSet forceLowercase:NO];
        if (scannerPeekCharacter(scanner) == '&')
            scannerSkipPeekedCharacter(scanner); // Skip '&' between value pairs
        NSString *decodedName = [NSMakeCollectable(CFURLCreateStringByReplacingPercentEscapes(kCFAllocatorDefault, (CFStringRef)encodedName, CFSTR(""))) autorelease];
        NSString *decodedValue = [NSMakeCollectable(CFURLCreateStringByReplacingPercentEscapes(kCFAllocatorDefault, (CFStringRef)encodedValue, CFSTR(""))) autorelease];
        if (decodedName == nil)
            decodedName = encodedName;
        if (decodedValue == nil)
            decodedValue = encodedValue;
        if (decodedValue == nil)
            decodedValue = (id)[NSNull null];
        [parameters addObject:decodedValue forKey:decodedName];
    }
    [scanner release];
    return parameters;
}

@end
