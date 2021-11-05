// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOAttribute.h>

#import <OmniFoundation/OFEnumNameTable.h>

#import <OmniDataObjects/ODOObject.h>
#import <OmniDataObjects/ODOModel-Creation.h>
#import "ODOProperty-Internal.h"

@implementation ODOAttribute

- (void)dealloc;
{
    [_defaultValue release];
    [super dealloc];
}

- (ODOAttributeType)type;
{
    return _type;
}

- (NSObject <NSCopying> *)defaultValue;
{
    OBPRECONDITION(!_defaultValue || [_defaultValue isKindOfClass:_valueClass]);
    return _defaultValue;
}

- (Class)valueClass;
{
    OBPRECONDITION(_valueClass);
    return _valueClass;
}

@synthesize primaryKey = _isPrimaryKey;

#pragma mark -
#pragma mark Debugging

#ifdef DEBUG
- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setObject:@(_type) forKey:@"type"];
    if (_defaultValue)
        [dict setObject:_defaultValue forKey:@"defaultValue"];
    return dict;
}
#endif

#pragma mark ODOModel creation

// No validation is done for non-DEBUG builds.  The Ruby generator is expected to have done it.
ODOAttribute *ODOAttributeCreate(NSString *name, BOOL optional, BOOL transient, SEL get, SEL set,
                                 ODOAttributeType type, Class valueClass, NSObject <NSCopying> *defaultValue, BOOL isPrimaryKey)
{
    OBPRECONDITION(type > ODOAttributeTypeInvalid);
    OBPRECONDITION(type < ODOAttributeTypeCount);
    OBPRECONDITION(valueClass);
    OBPRECONDITION([valueClass conformsToProtocol:@protocol(NSCopying)] || (type == ODOAttributeTypeUndefined && transient)); // Can use NSObject/transient w/o having the class itself require NSCopying.  The values will require it, though.
    
    ODOAttribute *attr = [[ODOAttribute alloc] init];
    attr->_isPrimaryKey = isPrimaryKey;

    struct _ODOPropertyFlags baseFlags;
    memset(&baseFlags, 0, sizeof(baseFlags));

    if (transient) {
        baseFlags.transientIsODOObject = OBClassIsSubclassOfClass(valueClass, [ODOObject class]);
    }

    ODOPropertyInit(attr, name, baseFlags, optional, transient, get, set);

    if (attr->_isPrimaryKey) {
        // The primary key isn't in the snapshot, but has a special marker for that.
        attr->_storageKey.snapshotIndex = ODO_STORAGE_KEY_PRIMARY_KEY_SNAPSHOT_INDEX;
        OBASSERT(optional == NO);
    }
    
    attr->_type = type;
    attr->_valueClass = valueClass;
    attr->_defaultValue = [defaultValue copy];
    
    {
        BOOL wantsScalarAccessors = NO;
        
        switch (attr->_type) {
            case ODOAttributeTypeInvalid: {
                OBASSERT_NOT_REACHED("Unused attribute type.");
                break;
            }
                
            case ODOAttributeTypeUndefined: {
                wantsScalarAccessors = NO;
                break;
            }
                
            case ODOAttributeTypeInt16:
            case ODOAttributeTypeInt32:
            case ODOAttributeTypeInt64:
            case ODOAttributeTypeFloat32:
            case ODOAttributeTypeFloat64: {
                wantsScalarAccessors = !attr->_flags.optional;
                break;
            }
                
            case ODOAttributeTypeString: {
                wantsScalarAccessors = NO;
                break;
            }
                
            case ODOAttributeTypeBoolean: {
                wantsScalarAccessors = !attr->_flags.optional;
                break;
            }
                
            case ODOAttributeTypeDate:
            case ODOAttributeTypeXMLDateTime:
            case ODOAttributeTypeData: {
                wantsScalarAccessors = NO;
                break;
            }
        }
        
        attr->_flags.scalarAccessors = wantsScalarAccessors;
    }

    if (type == ODOAttributeTypeUndefined) {
        if (valueClass == [NSObject class]) {
            attr->_setterBehavior = ODOAttributeSetterBehaviorDetermineAtRuntime;
        } else {
            attr->_setterBehavior = [valueClass conformsToProtocol:@protocol(NSCopying)] ? ODOAttributeSetterBehaviorCopy : ODOAttributeSetterBehaviorRetain;
        }
    } else {
        [valueClass conformsToProtocol:@protocol(NSCopying)];
        attr->_setterBehavior = ODOAttributeSetterBehaviorCopy;
    }
    
    return attr;
}

@end
