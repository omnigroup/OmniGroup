// Copyright 1997-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSObject-OFAppleScriptExtensions.h>

@import ApplicationServices;
@import Foundation;
@import Carbon; // For 'keyASUserRecordFields'

#import <OmniFoundation/OFErrors.h>

RCS_ID("$Id$")

@implementation NSObject (OFAppleScriptExtensions) 

+ (void)registerConversionFromRecord;
{
    NSScriptCoercionHandler *handler = [NSScriptCoercionHandler sharedCoercionHandler];
    [handler registerCoercer:self selector:@selector(coerceObject:toRecordClass:) toConvertFromClass:self toClass:[NSDictionary class]];
    [handler registerCoercer:self selector:@selector(coerceRecord:toClass:) toConvertFromClass:[NSDictionary class] toClass:self];
}

+ (id)coerceRecord:(NSDictionary *)dictionary toClass:(Class)aClass;
{
    id result = [[[aClass alloc] init] autorelease];
    
    [result appleScriptTakeAttributesFromRecord:dictionary];
    return result;
}

+ (id)coerceObject:(id)object toRecordClass:(Class)aClass;
{
    return [object appleScriptAsRecord];
}

- (BOOL)ignoreAppleScriptValueForClassID;
{
    return YES;
}

- (BOOL)ignoreAppleScriptValueForScriptingProperties;
{
    return YES;
}

- (BOOL)ignoreAppleScriptValueForKey:(NSString *)key;
{
    static NSMutableDictionary *keyToIgnoreSelectorMapping = nil;
    NSString *selectorName;
    NSValue *selectorValue;
    SEL selector;
    
    selectorValue = [keyToIgnoreSelectorMapping objectForKey:key];
    if (selectorValue) {
        OBASSERT(strcmp([selectorValue objCType], @encode(typeof(selector))) == 0);
        [selectorValue getValue:&selector];
    } else {
        if (!keyToIgnoreSelectorMapping)
            keyToIgnoreSelectorMapping = [[NSMutableDictionary alloc] init];
        
        selectorName = [NSString stringWithFormat:@"ignoreAppleScriptValueFor%@%@", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
        selector = NSSelectorFromString(selectorName);
        selectorValue = [NSValue value:&selector withObjCType:@encode(typeof(selector))];
        [keyToIgnoreSelectorMapping setObject:selectorValue forKey:key];
    }
    
    OBASSERT(([NSStringFromSelector(selector) isEqual:[NSString stringWithFormat:@"ignoreAppleScriptValueFor%@%@", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]]]));
    
    if ([self respondsToSelector:selector])
        return ((BOOL (*)(id, SEL))[self methodForSelector:selector])(self, selector);
    else
        return NO;
}

- (NSScriptClassDescription *)getApplicableClassDescription;
{
    NSScriptClassDescription *classDescription = nil;
    Class nsObject = [NSObject class], aClass = [self class];
    while (aClass != nil && aClass != nsObject && classDescription == nil) {
        classDescription = (NSScriptClassDescription *)[NSClassDescription classDescriptionForClass:aClass];
        aClass = [aClass superclass];
    }
    return classDescription;
}

- (NSDictionary *)appleScriptAsRecord;
{
    NSMutableDictionary *record;
    NSEnumerator *enumerator;
    NSScriptClassDescription *classDescription;
    NSString *key;
    id value;
    
    record = [NSMutableDictionary dictionary];
    classDescription = [self getApplicableClassDescription];
    enumerator = [[classDescription attributeKeys] objectEnumerator];
    while ((key = [enumerator nextObject])) {
        if ([self ignoreAppleScriptValueForKey:key])
            continue;
        
        @try {
            value = [self valueForKey:key];
        } @catch (NSException *exc) {
            OB_UNUSED_VALUE(exc);
            value = nil;
        }
        [record setObject:value forKey:[NSNumber numberWithUnsignedLong:[classDescription appleEventCodeForKey:key]]];        
    }
    return record;
}

- (void)appleScriptTakeAttributesFromRecord:(NSDictionary *)record;
{
    NSEnumerator *enumerator;
    NSNumber *eventCode;
    NSScriptClassDescription *classDescription;
    NSString *key;
    
    classDescription = [self getApplicableClassDescription];
    enumerator = [record keyEnumerator];
    while ((eventCode = [enumerator nextObject])) {
        key = [classDescription keyWithAppleEventCode:[eventCode unsignedIntValue]];
        if (!key || ![classDescription hasWritablePropertyForKey:key])
            continue;
        
        [self setValue:[self coerceValue:[record objectForKey:eventCode] forKey:key] forKey:key];
    }
}


- (NSDictionary *)_appleScriptTerminologyForSuite:(NSString *)suiteName;
{
    static NSMutableDictionary *cachedTerminology = nil;
    NSDictionary *result;
    
    if (!cachedTerminology)
        cachedTerminology = [[NSMutableDictionary alloc] init];
    
    if (!(result = [cachedTerminology objectForKey:suiteName])) {
        NSString *path;
        NSBundle *bundle;
        
        bundle = [[NSScriptSuiteRegistry sharedScriptSuiteRegistry] bundleForSuite:suiteName];
        path = [bundle pathForResource:suiteName ofType:@"scriptTerminology"];
        if (!path)
            return nil;
        result = [[NSDictionary alloc] initWithContentsOfFile:path];
        [cachedTerminology setObject:result forKey:suiteName];
        [result release];
    }
    return result;
}


- (NSDictionary *)_mappingForEnumeration:(NSString *)typeName;
{
    static NSMutableDictionary *cachedEnumerations = nil;
    NSMutableDictionary *mapping;
    NSScriptClassDescription *classDescription;
    NSString *path;
    NSBundle *bundle;
    NSDictionary *suiteInfo, *typeInfo, *terminologyInfo;
    NSString *type;
    NSEnumerator *enumerator, *codeEnumerator;
    
    if (!cachedEnumerations)
        cachedEnumerations = [[NSMutableDictionary alloc] init];
    if ((mapping = [cachedEnumerations objectForKey:typeName]))
        return mapping;
    
    classDescription = [self getApplicableClassDescription];
    bundle = [[NSScriptSuiteRegistry sharedScriptSuiteRegistry] bundleForSuite:[classDescription suiteName]];
    path = [bundle pathForResource:[classDescription suiteName] ofType:@"scriptSuite"];
    if (!path)
        return nil;
    suiteInfo = [NSDictionary dictionaryWithContentsOfFile:path];
    suiteInfo = [suiteInfo objectForKey:@"Enumerations"];
    terminologyInfo = [[self _appleScriptTerminologyForSuite:[classDescription suiteName]] objectForKey:@"Enumerations"];
    enumerator = [suiteInfo keyEnumerator];
    while ((type = [enumerator nextObject])) {
        NSString *code, *value;
        NSDictionary *terminology;
        
        typeInfo = [[suiteInfo objectForKey:type] objectForKey:@"Enumerators"];
        terminology = [terminologyInfo objectForKey:type];
        mapping = [[NSMutableDictionary alloc] init];
        codeEnumerator = [typeInfo keyEnumerator];
        while ((value = [codeEnumerator nextObject])) {
            code = [typeInfo objectForKey:value];
            NSString *nameForCode = [[terminology objectForKey:value] objectForKey:@"Name"];
            NSNumber *numberForCode = [NSNumber numberWithLong:[code fourCharCodeValue]];
            if (nameForCode == nil || numberForCode == nil) {
                NSLog(@"warning: name is '%@' for code '%@' (%@) in enumeration %@ of %@", nameForCode, code, value, type, path);
                continue;
            }
            [mapping setObject:nameForCode forKey:numberForCode];
        }
        [cachedEnumerations setObject:mapping forKey:type];
        [mapping release];
    }
    return [cachedEnumerations objectForKey:typeName];
}

- (NSString *)_attributeNameForKey:(NSString *)key;
{
    NSScriptClassDescription *classDescription = [self getApplicableClassDescription];
    while (classDescription) {
        NSDictionary *terminology = [[self _appleScriptTerminologyForSuite:[classDescription suiteName]] objectForKey:@"Classes"];
        NSString *attributeName = [[[[terminology objectForKey:[classDescription className]] objectForKey:@"Attributes"] objectForKey:key] objectForKey:@"Name"];
        if (![NSString isEmptyString:attributeName])
            return attributeName;
        
        classDescription = [classDescription superclassDescription];
        if (![classDescription appleEventCodeForKey:key])
            break;
    }
    
    // If we reach this point, we haven't found a scriptTerminology file that names this attribute.
    OBASSERT_NOT_REACHED("No attribute for this key");
    return nil;
}

- (id)appleScriptBlankInit;
{
    return [self init];
}

- (NSDictionary *)_defaultValuesDictionary;
{
    static NSMutableDictionary *cachedDefaultValues = nil;
    NSMutableDictionary *result;
    NSScriptClassDescription *classDescription;
    
    classDescription = [self getApplicableClassDescription];
    
    if (!(result = [cachedDefaultValues objectForKey:[classDescription className]])) {
        NSEnumerator *enumerator;
        id blankObject, value;
        NSString *key;
        
        blankObject = [[NSClassFromString([classDescription className]) alloc] appleScriptBlankInit];
        result = [[NSMutableDictionary alloc] init];
        enumerator = [[classDescription attributeKeys] objectEnumerator];
        while ((key = [enumerator nextObject])) {
            if (![classDescription hasWritablePropertyForKey:key])
                continue;
            
            @try {
                value = [blankObject valueForKey:key];
            } @catch (NSException *exc) {
                OB_UNUSED_VALUE(exc);
                value = nil; // in case the script suite is inaccurate and we don't actually respond to that key 
                // This is needed because the Outliner guys put 'scriptStyle' on NSTextStorage into OmniAppKit, but it is defined in OmniStyle,
                // so any app which uses scripting but doesn't include the OmniStyle framework breaks here.
            }
            if (value)
                [result setObject:value forKey:key];
        }
        if (!cachedDefaultValues)
            cachedDefaultValues = [[NSMutableDictionary alloc] init];
        [cachedDefaultValues setObject:result forKey:[classDescription className]];
        [result release];
        [blankObject release];
    }
    return result;
}

- (NSString *)stringValueForValue:(id)value ofKey:(NSString *)key;
{
    NSString *type, *enumerationValue;
    
    if ([value isKindOfClass:[NSString class]]) {
        NSString *escapeBackslash = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
        NSString *escapeQuotes = [escapeBackslash stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        return [NSString stringWithFormat:@"\"%@\"", escapeQuotes];
    }
    
    if ([value isKindOfClass:[NSNumber class]]) {
        type = [(NSScriptClassDescription *)[self getApplicableClassDescription] typeForKey:key];
        if ([type hasPrefix:@"NSNumber<"]) {
            type = [type substringFromIndex:9];
            type = [type substringToIndex:[type length] - 1];
            if ([type isEqualToString:@"Bool"]) {
                return [value boolValue] ? @"true" : @"false";
            } else if ((enumerationValue = [[self _mappingForEnumeration:type] objectForKey:value])) {
                return enumerationValue;
            }
        }
        return value;
    }
    
    if ([value isKindOfClass:[NSArray class]]) {
        NSArray *arrayValue = value;
        NSMutableArray *parts = [NSMutableArray arrayWithCapacity:[arrayValue count]];
        for (id iteratedObject in arrayValue) {
            [parts addObject:[self stringValueForValue:iteratedObject ofKey:key]];
        }
        return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@", "]];
    }
    
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionaryValue = value;
        NSMutableArray *parts = [NSMutableArray arrayWithCapacity:[dictionaryValue count]];
        for (NSString *partKey in dictionaryValue) {
            id partValue = [dictionaryValue objectForKey:partKey];
            NSString *stringValue = [self stringValueForValue:partValue ofKey:key];
            if (stringValue != nil) {
                [parts addObject:[NSString stringWithFormat:@"%@: %@", partKey, stringValue]];
            }
        }
        return [NSString stringWithFormat:@"{%@}", [parts componentsJoinedByString:@", "]];
    }
    
    return [value appleScriptMakeProperties];
}

- (NSArray *)appleScriptExtraAttributeKeys;
{
    return nil;
}

- (NSString *)appleScriptMakeProperties;
{
    NSScriptClassDescription *classDescription = [self getApplicableClassDescription];
    if (classDescription == nil) // this isn't one of our data-bearing objects, it's a junk object like "scriptingProperties", which is an extra CFDictionary added to every object's list of keys on 10.2
        return nil;
    
    NSDictionary *defaultValues = [self _defaultValuesDictionary];
    NSArray *attributeKeys = [classDescription attributeKeys];
    NSArray *extraKeys = [self appleScriptExtraAttributeKeys];
    if (extraKeys != nil) {
        NSMutableSet *mergedKeys = [NSMutableSet set];
        [mergedKeys addObjectsFromArray:extraKeys];
        [mergedKeys addObjectsFromArray:attributeKeys];
        attributeKeys = [mergedKeys allObjects];
    }
    
    NSMutableString *result = [NSMutableString string];
    BOOL noComma = YES;
    NSEnumerator *enumerator = [attributeKeys objectEnumerator];
    NSString *key;
    while ((key = [enumerator nextObject])) {
        BOOL isExtraKey = [extraKeys containsObject:key];
        if (!isExtraKey && (![classDescription hasWritablePropertyForKey:key] || [self ignoreAppleScriptValueForKey:key]))
            continue;
        
        id value;
        @try {
            value = [self valueForKey:key];
        } @catch (NSException *exc) {
            OB_UNUSED_VALUE(exc);
            value = nil;
        }
        if (!value || [[defaultValues objectForKey:key] isEqual:value])
            continue;
        value = [self stringValueForValue:value ofKey:key];            
        if (!value)
            continue;
        
        if (noComma)
            noComma = NO;
        else
            [result appendString:@", "];
        NSString *attributeName = isExtraKey ? key : [self _attributeNameForKey:key];
        if (attributeName == nil)
            continue;

        [result appendFormat:@"%@: %@", attributeName, value];
    }
    return [NSString stringWithFormat:@"{%@}", result];
}

- (NSString *)appleScriptMakeCommandAt:(NSString *)aLocationSpecifier;
{
    NSScriptClassDescription *classDescription;
    NSDictionary *terminology;
    NSString *properties;
    
    properties = [self appleScriptMakeProperties];
    if (properties == nil)
        return @"";
    
    classDescription = (NSScriptClassDescription *)[self getApplicableClassDescription];
    OBASSERT_NOTNULL(classDescription, @"No class description found for %@.", [self shortDescription]);
    
    terminology = [[[self _appleScriptTerminologyForSuite:[classDescription suiteName]] objectForKey:@"Classes"] objectForKey:[classDescription className]];
    if ([properties isEqualToString:@"{}"])
        return [NSString stringWithFormat:@"make new %@ at %@\r", [terminology objectForKey:@"Name"], aLocationSpecifier];
    else
        return [NSString stringWithFormat:@"make new %@ at %@ with properties %@\r", [terminology objectForKey:@"Name"], aLocationSpecifier, properties];
}

- (NSString *)appleScriptMakeCommandAt:(NSString *)aLocationSpecifier withIndent:(NSInteger)indent;
{
    if (!indent)
        return [self appleScriptMakeCommandAt:aLocationSpecifier];
    else
        return [NSString stringWithFormat:@"%@%@", [@"\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t" substringToIndex:indent], [self appleScriptMakeCommandAt:aLocationSpecifier]];
}

- (NSScriptObjectSpecifier *)objectSpecifierByProperty:(NSString *)propertyKey inRelation:(NSString *)myLocation toContainer:(NSObject *)myContainer
{
    NSScriptClassDescription *myClassDescription = (id)[NSScriptClassDescription classDescriptionForClass:[self class]];
    NSScriptClassDescription *containerClassDescription = (id)[NSScriptClassDescription classDescriptionForClass:[myContainer class]];
    NSScriptObjectSpecifier *containerSpecifier = [myContainer objectSpecifier];
    id myUniqueID = [self valueForKey:propertyKey];
    NSScriptObjectSpecifier *specifier = nil;
    
    FourCharCode propertyKeyCode = [myClassDescription appleEventCodeForKey:propertyKey];
    
    if (propertyKeyCode == pID) { // don't have to look these up
        specifier = [[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:containerClassDescription containerSpecifier:containerSpecifier key:myLocation uniqueID:myUniqueID];
        [specifier autorelease];
    } else if (propertyKeyCode == pName) {
        // We're on OS 10.2.x or greater, so we can use the special unique-ID reference form
        specifier = [[NSNameSpecifier alloc] initWithContainerClassDescription:containerClassDescription containerSpecifier:containerSpecifier key:myLocation name:myUniqueID];
        [specifier autorelease];
    }
    // We need to use a specifier of the form "the first object whose attr is foo" even if attr is the name or id attribute; we'll fall through to the general case for that.
    
    if (specifier == nil) {
        NSScriptObjectSpecifier *idOf = [[NSPropertySpecifier alloc] initWithContainerClassDescription:myClassDescription containerSpecifier:nil key:propertyKey];
        NSScriptWhoseTest *whoseIdIsMe = [[NSSpecifierTest alloc] initWithObjectSpecifier:idOf comparisonOperator:NSEqualToComparison testObject:myUniqueID];
        NSWhoseSpecifier *whose = [[NSWhoseSpecifier alloc] initWithContainerClassDescription:containerClassDescription containerSpecifier:containerSpecifier key:myLocation test:whoseIdIsMe];
        [whose setStartSubelementIdentifier:NSRandomSubelement];
        [idOf release];
        [whoseIdIsMe release];
        
        specifier = [whose autorelease];
    }
    
    // NSLog(@"uniqueIDSpecifier(id=[%@] prop=[%@] container=[%@]) --> %@", myUniqueID, myLocation, myContainer, specifier);
    
    return specifier;
}

#pragma mark -

// Minimal conversion routines for what we need.

- (NSAppleEventDescriptor *)convertToAppleEventDescriptor:(NSError **)outError;
{
    NSScriptObjectSpecifier *specifier = [self objectSpecifier];
    if (specifier == nil) {
        // RT #429341 -- 10.6 began adding non-plist values to -[NSWorkspace currentApplication]. We'll be lossy here in the conversion of NSObjects to event descriptors instead of halting everything for no particularly good reason. We'll return a null descriptor so that we have a non-nil (no error) result and so that if we are getting wrapped in a dictionary, we'll get an missing value entry for this key.
        return [NSAppleEventDescriptor descriptorWithTypeCode:cMissingValue];
    }

    NSAppleEventDescriptor *desc = [specifier descriptor];
    if (desc == nil) {
        NSString *reason = [NSString stringWithFormat:@"Cannot convert \"%@\" to an NSAppleEventDescriptor.", [self shortDescription]];
        OFError(outError, OFUnableToConvertScriptHandlerArgumentToAppleEventDescriptor, reason, @"-descriptor returned nil");
    }

    return desc;
}

@end

@implementation NSNull (OFAppleScriptExtensions)

- (NSAppleEventDescriptor *)convertToAppleEventDescriptor:(NSError **)outError;
{
    return [NSAppleEventDescriptor descriptorWithTypeCode:cMissingValue];
}

@end

@implementation NSString (OFAppleScriptExtensions)

- (NSAppleEventDescriptor *)convertToAppleEventDescriptor:(NSError **)outError;
{
    return [NSAppleEventDescriptor descriptorWithString:self];
}

@end

@implementation NSNumber (OFAppleScriptExtensions)

- (NSAppleEventDescriptor *)convertToAppleEventDescriptor:(NSError **)outError;
{
    CFNumberType type = CFNumberGetType((CFNumberRef)self);

    switch (type) {
        case kCFNumberSInt64Type: {
            SInt64 int64Value = 0;
            CFNumberGetValue((CFNumberRef)self, kCFNumberSInt64Type, &int64Value);
            return [NSAppleEventDescriptor descriptorWithDescriptorType:typeSInt64 bytes:&int64Value length:sizeof(int64Value)];
        }
        case kCFNumberSInt32Type:
            return [NSAppleEventDescriptor descriptorWithInt32:self.intValue];
        case kCFNumberCharType:
            return [NSAppleEventDescriptor descriptorWithBoolean:self.boolValue];
        case kCFNumberFloat64Type:
        case kCFNumberDoubleType:
            return [NSAppleEventDescriptor descriptorWithDouble:self.doubleValue];
        default: {
            NSString *reason = [NSString stringWithFormat:@"Cannot convert \"%@\", type %" PRIdNS " to an NSAppleEventDescriptor.", [self shortDescription], type];
            OFError(outError, OFUnableToConvertScriptHandlerArgumentToAppleEventDescriptor, reason, @"Unknown number type");
            return nil;
        }
    }
}

@end

@implementation NSArray (OFAppleScriptExtensions)

- (NSAppleEventDescriptor *)convertToAppleEventDescriptor:(NSError **)outError;
{
    NSAppleEventDescriptor *result = [NSAppleEventDescriptor listDescriptor];

    NSUInteger objectIndex, objectCount = [self count];
    for (objectIndex = 0; objectIndex < objectCount; objectIndex++) {
        NSAppleEventDescriptor *desc = [[self objectAtIndex:objectIndex] convertToAppleEventDescriptor:outError];
        if (desc == nil)
            return nil;
        [result insertDescriptor:desc atIndex:1+objectIndex]; // 1-based
    }

    return result;
}

@end

@implementation NSDictionary (OFAppleScriptExtensions)

// We send a 'user field' record for arbitrary keys instead of 4CC keys.
- (NSAppleEventDescriptor *)convertToAppleEventDescriptor:(NSError **)outError;
{
    NSAppleEventDescriptor *keysAndValues = [NSAppleEventDescriptor listDescriptor];

    NSArray *keys = [[self allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger descriptorIndex = 1;
    for (NSString *key in keys) {
        id value = [self valueForKey:key];

        NSAppleEventDescriptor *keyDesc = [key convertToAppleEventDescriptor:outError];
        if (keyDesc == nil)
            return nil;

        NSAppleEventDescriptor *valueDesc = [value convertToAppleEventDescriptor:outError];
        if (valueDesc == nil)
            return nil;

        // 1-based
        [keysAndValues insertDescriptor:keyDesc atIndex:descriptorIndex++];
        [keysAndValues insertDescriptor:valueDesc atIndex:descriptorIndex++];
    }

    NSAppleEventDescriptor *result = [NSAppleEventDescriptor recordDescriptor];
    [result setParamDescriptor:keysAndValues forKeyword:keyASUserRecordFields];

    return result;
}

@end


