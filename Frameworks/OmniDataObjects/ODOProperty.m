// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOProperty.h>

#import <OmniDataObjects/ODOObject.h>
#import <OmniDataObjects/ODOModel.h>

#import "ODOEntity-Internal.h"

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/ODOProperty.m 104581 2008-09-06 21:18:23Z kc $")

#ifdef OMNI_ASSERTIONS_ON
@interface ODOProperty (Signatures)
// Used for getting type signatures
- (id)_getter_signature;
- (void)_setter_signature:(id)arg;
@end
@implementation ODOProperty (Signatures)
// Used for getting type signatures
- (id)_getter_signature;
{
    return nil;
}
- (void)_setter_signature:(id)arg;
{
}
@end
#endif

#ifdef OMNI_ASSERTIONS_ON
const char *ODOPropertyGetterSignature = NULL;
const char *ODOPropertySetterSignature = NULL;
#endif

@implementation ODOProperty

#ifdef OMNI_ASSERTIONS_ON
+ (void)initialize;
{
    OBINITIALIZE;
    
    Method getter = class_getInstanceMethod(self, @selector(_getter_signature));
    ODOPropertyGetterSignature = method_getTypeEncoding(getter);
    Method setter = class_getInstanceMethod(self, @selector(_setter_signature:));
    ODOPropertySetterSignature = method_getTypeEncoding(setter);
}
#endif

- (void)dealloc;
{
    [_name release];
    [super dealloc];
}

- (ODOEntity *)entity;
{
    return _nonretained_entity;
}

- (NSString *)name;
{
    return _name;
}

- (BOOL)isOptional;
{
    return _flags.optional;
}

- (BOOL)isTransient;
{
    return _flags.transient;
}

- (NSComparisonResult)compareByName:(ODOProperty *)prop;
{
    return [_name compare:prop->_name];
}

#pragma mark -
#pragma mark NSCopying

// All properties are immutable.  Don't need schema changes or dynamic building.  This allows us to be dictionary keys.
- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
}

#pragma mark -
#pragma mark Debugging

#ifdef DEBUG
- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setObject:_name forKey:@"name"];
    [dict setObject:[_nonretained_entity name] forKey:@"entity"];
    return dict;
}
#endif

@end

#import "ODOProperty-Internal.h"

NSString * const ODOPropertyNameAttributeName = @"name";
NSString * const ODOPropertyOptionalAttributeName = @"optional";
NSString * const ODOPropertyTransientAttributeName = @"transient";

@implementation ODOProperty (Internal)

- (id)initWithCursor:(OFXMLCursor *)cursor entity:(ODOEntity *)entity baseFlags:(struct _ODOPropertyFlags)flags error:(NSError **)outError;
{
    OBPRECONDITION(entity);
    
    _nonretained_entity = entity;
    _flags = flags; // We'll override the property-specific bits of this.
    
    NSString *name = [cursor attributeNamed:ODOPropertyNameAttributeName];
    NSString *intern = [ODOModel internName:name];

#ifdef OMNI_ASSERTIONS_ON
    if (name == intern) {
        NSLog(@"Property name '%@' is not interned!", name);
        OBASSERT(name != intern); // Your model should intern constant strings before reading the model so that we can pick them up.
    }
#endif
    
    _name = [intern retain];
    
    if ([NSString isEmptyString:_name]) {
        NSString *reason = NSLocalizedStringFromTableInBundle(@"Property has no name.", nil, OMNI_BUNDLE, @"error reason");
        NSString *description = NSLocalizedStringFromTableInBundle(@"Unable to load model.", nil, OMNI_BUNDLE, @"error description");
        ODOError(outError, ODOUnableToLoadModel, description, reason, nil);
        [self release];
        return nil;
    }
    
    NSString *str;
    
    str = [cursor attributeNamed:ODOPropertyOptionalAttributeName];
    if (str) {
        OBASSERT([str isEqualToString:@"true"] || [str isEqualToString:@"false"]);
        _flags.optional = [str isEqualToString:@"true"] ? 1 : 0;
    }
    
    str = [cursor attributeNamed:ODOPropertyTransientAttributeName];
    if (str) {
        OBASSERT([str isEqualToString:@"true"] || [str isEqualToString:@"false"]);
        _flags.transient = [str isEqualToString:@"true"] ? 1 : 0;
    }
    
    SEL getterSelector = NSSelectorFromString(_name);
    if ([[entity instanceClass] instancesRespondToSelector:getterSelector]) {
        // Only support id-returning getters for now
#ifdef OMNI_ASSERTIONS_ON
        Method method = class_getInstanceMethod([entity instanceClass], getterSelector);
        const char *types = method_getTypeEncoding(method);
        OBASSERT(strcmp(types, ODOPropertyGetterSignature) == 0);
#endif
        
        if (_flags.relationship && _flags.toMany) {
            OBASSERT_NOT_REACHED("We don't want getters for to-many relationships for now."); // What could possibly happen there that is valid?  If we do allow it, we need to consider how it would work in terms of mutability of the result, primativeValueForKey:, faulting, etc.
            getterSelector = NULL;
        }
        
        _getterSelector = getterSelector;
    }

    SEL setterSelector;
    {
        NSMutableString *setterName = [[NSMutableString alloc] initWithFormat:@"set%@:", _name];
        [setterName replaceCharactersInRange:NSMakeRange(3,1) withString:[[_name substringToIndex:1] uppercaseString]];
        setterSelector = NSSelectorFromString(setterName);
        [setterName release];
    }
    
    if ([[entity instanceClass] instancesRespondToSelector:setterSelector]) {
#ifdef OMNI_ASSERTIONS_ON
        // Only support id-taking setters for now
        Method method = class_getInstanceMethod([entity instanceClass], setterSelector);
        const char *types = method_getTypeEncoding(method);
        OBASSERT(strcmp(types, ODOPropertySetterSignature) == 0);
#endif

        if (_flags.relationship && _flags.toMany) {
            OBASSERT_NOT_REACHED("We don't want setters for to-many relationships for now."); // What could possibly happen there that is valid?  If we do allow it, we need to consider how it would work in terms of mutability of the result, primativeValueForKey:, faulting, relational integrity, etc.
            setterSelector = NULL;
        }

        _setterSelector = setterSelector;
    }
    
    return self;
}

#ifdef OMNI_ASSERTIONS_ON
- (SEL)_setterSelector;
{
    return _setterSelector;
}
#endif

BOOL ODOPropertyHasIdenticalName(ODOProperty *property, NSString *name)
{
    OBPRECONDITION([property isKindOfClass:[ODOProperty class]]);
    return property->_name == name;
}

struct _ODOPropertyFlags ODOPropertyFlags(ODOProperty *property)
{
    OBPRECONDITION([property isKindOfClass:[ODOProperty class]]);
    return property->_flags;
}

void ODOPropertySnapshotAssignSnapshotIndex(ODOProperty *property, unsigned int snapshotIndex)
{
    OBPRECONDITION(property->_flags.snapshotIndex == ODO_NON_SNAPSHOT_PROPERTY_INDEX); // shouldn't have been assigned yet.
    property->_flags.snapshotIndex = snapshotIndex;
}

id ODOPropertyGetValue(ODOObject *object, ODOProperty *property)
{
    OBPRECONDITION([property isKindOfClass:[ODOProperty class]]);

    SEL getter = property->_getterSelector;
    if (getter)
        return objc_msgSend(object, getter);
    else {
        NSString *key = property->_name;
        [object willAccessValueForKey:key];
        id value = [object primitiveValueForProperty:property];
        [object didAccessValueForKey:key];
        return value;
    }
}

void ODOPropertySetValue(ODOObject *object, ODOProperty *property, id value)
{
    OBPRECONDITION([property isKindOfClass:[ODOProperty class]]);

    SEL setter = property->_setterSelector;
    if (setter)
        objc_msgSend(object, setter, value);
    else {
        NSString *key = property->_name;
        [object willChangeValueForKey:key];
        [object setPrimitiveValue:value forProperty:property];
        [object didChangeValueForKey:key];
    }
}

@end

