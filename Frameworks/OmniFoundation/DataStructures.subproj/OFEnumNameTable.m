// Copyright 2002-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFEnumNameTable.h>

#import <OmniFoundation/OFXMLCursor.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/CFArray-OFExtensions.h>
#import <OmniFoundation/CFDictionary-OFExtensions.h>


RCS_ID("$Id$");

/*"
This class is intended for use in a bi-directional mapping between an integer enumeration and string representations for the elements of the enumeration.  This is useful, for example, when converting data structures to and from an external representation.  Instead of encoding internal enumeration values as integers, they can be encoded as string names.  This makes it easier to interpret the external representation and easier to rearrange the private enumeration values without impact to existing external representations in files, defaults property lists, databases, etc.

The implementation does not currently assume anything about the range of the enumeration values.  It would simplify the implementation if we could assume that there was a small set of values, starting at zero and all contiguous.  This is the default for enumerations in C, but certainly isn't required.
"*/
@implementation OFEnumNameTable

// Init and dealloc

- init;
{
    OBRequestConcreteImplementation(isa, _cmd);
    [self release];
    return nil;
}

- initWithDefaultEnumValue:(NSInteger)defaultEnumValue;
{
    _defaultEnumValue = defaultEnumValue;

    // Typically the default value will be first, but not always, so we don't set its order here.
    _enumOrder = CFArrayCreateMutable(kCFAllocatorDefault, 0, &OFIntegerArrayCallbacks);

    _enumToName = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFIntegerDictionaryKeyCallbacks, &OFNSObjectDictionaryValueCallbacks);
    _enumToDisplayName = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFIntegerDictionaryKeyCallbacks, &OFNSObjectDictionaryValueCallbacks);
    _nameToEnum = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectDictionaryKeyCallbacks, &OFIntegerDictionaryValueCallbacks);
    
    return self;
}

- (void)dealloc;
{
    CFRelease(_enumOrder);
    CFRelease(_enumToName);
    CFRelease(_enumToDisplayName);
    CFRelease(_nameToEnum);
    [super dealloc];
}


// API

- (NSInteger)defaultEnumValue;
{
    return _defaultEnumValue;
}

// For cases where we don't care about the localized values.
- (void)setName:(NSString *)enumName forEnumValue:(NSInteger)enumValue;
{
    [self setName:enumName displayName:enumName forEnumValue:enumValue];
}

/*" Registers a string name and its corresponding integer enumeration value with the receiver. There must be a one-to-one correspondence between names and values; it is an error for either a name or a value to be duplicated. The order in which name-value pairs are registered determines the ordering used by -nextEnum:. "*/
- (void)setName:(NSString *)enumName displayName:(NSString *)displayName forEnumValue:(NSInteger)enumValue;
{
    OBPRECONDITION(enumName);
    OBPRECONDITION(displayName);
    
    // Note that we aren't enforcing uniqueness of display names... I'm not sure if that is a bug or feature yet
    OBPRECONDITION(!OFCFDictionaryContainsIntegerKey(_enumToDisplayName, enumValue));
    OBPRECONDITION(!OFCFDictionaryContainsIntegerKey(_enumToName, enumValue));
    OBPRECONDITION(!CFDictionaryContainsKey(_nameToEnum, (const void *)enumName));

    OFCFArrayAppendIntegerValue(_enumOrder, enumValue);

    OFCFDictionarySetValueForInteger(_enumToName, enumValue, (const void *)enumName);
    OFCFDictionarySetValueForInteger(_enumToDisplayName, enumValue, (const void *)displayName);
    OFCFDictionarySetIntegerValue(_nameToEnum, (const void *)enumName, enumValue);
}

/*" Returns the string name corresponding to the given integer enumeration value. "*/
- (NSString *)nameForEnum:(NSInteger)enumValue_;
{
    NSString *name = nil;
    intptr_t enumValue = enumValue_;
    
    if (!CFDictionaryGetValueIfPresent(_enumToName, (const void *)enumValue, (const void **)&name)) {
        // Since the enumeration values are internal, we expect that we know all of them and all are registered.
        [NSException raise: NSInvalidArgumentException format: @"Attempted to get name for unregistered enum value %d", enumValue];
    }
    OBASSERT(name);
    return name;
}

/*" Returns the display name corresponding to the given integer enumeration value. "*/
- (NSString *)displayNameForEnum:(NSInteger)enumValue_;
{
    NSString *name = nil;
    intptr_t enumValue = enumValue_;

    if (!CFDictionaryGetValueIfPresent(_enumToDisplayName, (const void *)enumValue, (const void **)&name)) {
        // Since the enumeration values are internal, we expect that we know all of them and all are registered.
        [NSException raise: NSInvalidArgumentException format: @"Attempted to get display name for unregistered enum value %d", enumValue];
    }
    OBASSERT(name);
    return name;
}

/*" Returns the integer enumeration value corresponding to the given string. "*/
- (NSInteger)enumForName:(NSString *)name;
{
    intptr_t enumValue;

    if (!name)
        // Don't require the name -- the external representation might not encode default values
        return _defaultEnumValue;
    
    if (!CFDictionaryGetValueIfPresent(_nameToEnum, (const void *)name, (const void **)&enumValue)) {
        // some unknown name -- the external representation might have been mucked up somehow
        return _defaultEnumValue;
    }
    
    return enumValue;
}

/*" Tests whether the specified enumeration value has been registered with the receiver.  "*/
- (BOOL)isEnumValue:(NSInteger)enumValue;
{
    return OFCFDictionaryContainsIntegerKey(_enumToName, enumValue)? YES : NO;
}

/*" Tests whether the specified enumeration name has been registered with the receiver.  "*/
- (BOOL)isEnumName:(NSString *)name;
{
    return name != nil && CFDictionaryContainsKey(_nameToEnum, (const void *)name)? YES : NO;
}

- (NSUInteger)count;
{
    OBINVARIANT(CFArrayGetCount(_enumOrder) == CFDictionaryGetCount(_enumToName));
    OBINVARIANT(CFArrayGetCount(_enumOrder) == CFDictionaryGetCount(_nameToEnum));
    return CFArrayGetCount(_enumOrder);
}

- (NSInteger)enumForIndex:(NSUInteger)enumIndex;
{
    OBASSERT(enumIndex >= 0 && (NSInteger)enumIndex < CFArrayGetCount(_enumOrder));
    intptr_t value = OFCFArrayGetIntegerValueAtIndex(_enumOrder, enumIndex);
    
    return value;
}

/*" Returns the 'next' enum value based on the cyclical order defined by the order of name/value definition. "*/
- (NSInteger)nextEnum:(NSInteger)enumValue;
{
    NSInteger count = CFArrayGetCount(_enumOrder);
    
    NSInteger enumIndex = OFCFArrayGetFirstIndexOfIntegerValue(_enumOrder, (CFRange){0, count}, enumValue);

    OBASSERT(enumIndex != kCFNotFound);
    
    if (enumIndex == kCFNotFound || (enumIndex+1) >= count) {
        enumIndex = 0;
    } else {
        enumIndex = enumIndex + 1;
    }
    
    return OFCFArrayGetIntegerValueAtIndex(_enumOrder, enumIndex);
}

/*" Returns the 'next' enum name based on the cyclical order defined by the order of name/value definition. "*/
- (NSString *)nextName:(NSString *)name;
{
    return [self nameForEnum:[self nextEnum:[self enumForName:name]]];
}

// Comparison

/*" Compares the receiver's name/value pairs against another instance of OFEnumNameTable. This implementation does not require that the cyclical ordering of the two enumerations be the same for them to compare equal, but callers should probably not rely on this behavior.  This also doesn't require that the display names are equal -- this is intentional. "*/
- (BOOL)isEqual:(id)anotherEnumeration_
{
    NSUInteger associationCount, associationIndex;
    
    if (anotherEnumeration_ == self)
        return YES;
    
    if (![anotherEnumeration_ isMemberOfClass:isa])
        return NO;
    
    OFEnumNameTable *anotherEnumeration = anotherEnumeration_;

    associationCount = [anotherEnumeration count];
    if (associationCount != [self count])
        return NO;
    
    if ([anotherEnumeration defaultEnumValue] != [self defaultEnumValue])
        return NO;

    for (associationIndex = 0; associationIndex < associationCount; associationIndex ++) {
        NSInteger anEnumValue = [self enumForIndex:associationIndex];
        if ([anotherEnumeration enumForName:[self nameForEnum:anEnumValue]] != anEnumValue)
            return NO;
    }

    return YES;
}

// Archiving (primarily for OAEnumStyleAttribute)
+ (NSString *)xmlElementName;
{
    return @"enum-name-table";
}

static int _compareIntptrs(const void *arg1, const void *arg2) {
    void *ptr1 = *(void * const *)arg1;
    void *ptr2 = *(void * const *)arg2;
    intptr_t int1 = (intptr_t)ptr1;
    intptr_t int2 = (intptr_t)ptr2;

    return ( int1 > int2 )? 1 : ( (int1 == int2)? 0 : -1 );
}

static inline int _writableEnumValue(NSInteger value)
{
    // Foundation has started doing enum {...}; typedef NSUInteger FooEnum and the like.  We don't expect to get large values; let's assert that.
    OBASSERT(value >= INT_MIN && value <= INT_MAX);
    return (int)value;
}

- (void)appendXML:(OFXMLDocument *)doc;
{
    [doc pushElement:[isa xmlElementName]];
    {
        [doc setAttribute:@"default-value" integer:_writableEnumValue(_defaultEnumValue)];

        // Store elements sorted by enum value
        NSInteger enumIndex, enumCount = CFDictionaryGetCount(_enumToName);
        OBASSERT(enumCount == CFDictionaryGetCount(_nameToEnum));

        intptr_t *values = malloc(sizeof(intptr_t) * enumCount);
        CFDictionaryGetKeysAndValues(_nameToEnum, NULL, (const void **)values);

        qsort(values, enumCount, sizeof(intptr_t), _compareIntptrs);

        for (enumIndex = 0; enumIndex < enumCount; enumIndex++) {
            [doc pushElement:@"enum-name-table-element"];
            {
                intptr_t value = values[enumIndex];
                
                [doc setAttribute:@"value" integer:_writableEnumValue(value)];

                NSString *name = [self nameForEnum:value];
                NSString *displayName = [self displayNameForEnum:value];
                
                [doc setAttribute:@"name" string:name];

                if (![name isEqualToString:displayName])
                    [doc setAttribute:@"display-name" string:displayName];
            }
            [doc popElement];
        }
        free(values);
    }
    [doc popElement];
}

- initFromXML:(OFXMLCursor *)cursor;
{
    OBPRECONDITION([[cursor name] isEqualToString:[isa xmlElementName]]);

    _defaultEnumValue = [[cursor attributeNamed:@"default-value"] intValue];

    if (!(self = [self initWithDefaultEnumValue:_defaultEnumValue]))
        return nil;
    
    id child;
    while ((child = [cursor nextChild])) {
        if (![child isKindOfClass:[OFXMLElement class]])
            continue;
        OFXMLElement *element = child;

        if (![[element name] isEqualToString:@"enum-name-table-element"])
            continue;

        int value = [[element attributeNamed:@"value"] intValue];
        NSString *name  = [element attributeNamed:@"name"];
        NSString *displayName = [element attributeNamed:@"display-name"];
        
        if (OFCFDictionaryContainsIntegerKey(_enumToName, value)) {
            [self release];
            [NSException raise:NSInvalidArgumentException
                        format:@"Unable to unarchive OFEnumNameTable: %@", @"Duplicate enum value"];
        }

        if (CFDictionaryContainsKey(_nameToEnum, (const void *)name)) {
            [self release];
            [NSException raise:NSInvalidArgumentException
                        format:@"Unable to unarchive OFEnumNameTable: %@", @"Duplicate enum name"];
        }

        if (!displayName)
            displayName = name;
        
        [self setName:name displayName:displayName forEnumValue:value];
    }

    if (!OFCFDictionaryContainsIntegerKey(_enumToName, _defaultEnumValue)) {
        [self release];
        [NSException raise:NSInvalidArgumentException
                    format:@"Unable to unarchive OFEnumNameTable: %@", @"Missing definition for default enum value"];
    }

    return self;
}

@end
