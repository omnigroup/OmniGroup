// Copyright 2008-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOProperty.h>
#import <OmniDataObjects/ODOAttribute.h>
#import <OmniDataObjects/ODOChangeActions.h>

#import "ODOStorageType.h"

struct _ODOPropertyFlags {
    unsigned int optional : 1;
    unsigned int transient : 1;
    unsigned int transientIsODOObject : 1;
    unsigned int calculated : 1;
    unsigned int relationship : 1;
    unsigned int toMany : 1;
    unsigned int scalarAccessors : 1;
};

@interface ODOProperty ()
{
@package
    ODOEntity *_nonretained_entity;
    NSString *_name;
    
    // Getter/setter selectors are defined no matter what.
    struct {
        SEL get;
        SEL set;
        
        SEL calculate; // For transient/calculated properties
    } _sel;
    
    // IMPs are cached when needed.  Setter might be NULL (someday) if the property is @dynamic and read-only.
    struct {
        IMP get;
        IMP set;
        
        IMP calculate;
    } _imp;
    
    struct _ODOPropertyFlags _flags;
    ODOStorageKey _storageKey;
}
@end

extern void ODOPropertyInit(ODOProperty *self, NSString *name, struct _ODOPropertyFlags flags, BOOL optional, BOOL transient, SEL get, SEL set);

@class ODOObject;
BOOL ODOPropertyHasIdenticalName(ODOProperty *property, NSString *name) OB_HIDDEN;


static inline struct _ODOPropertyFlags ODOPropertyFlags(ODOProperty *property)
{
    OBPRECONDITION([property isKindOfClass:[ODOProperty class]]);
    return property->_flags;
}


static inline NSString *ODOPropertyName(ODOProperty *prop)
{
    OBPRECONDITION([prop isKindOfClass:[ODOProperty class]]);
    return prop->_name;
}


void ODOPropertySnapshotAssignStorageKey(ODOProperty *property, ODOStorageKey storageKey) OB_HIDDEN;

static inline ODOStorageType ODOPropertyGetStorageType(ODOProperty *property) {
    // _flags.scalarAccessors determines the external interface to the property, not how we store them.
    
    if (property->_flags.relationship) {
        return ODOStorageTypeObject;
    }
    
    ODOAttribute *attribute = OB_CHECKED_CAST(ODOAttribute, property);
    ODOAttributeType type = attribute.type;
    
    switch (type) {
        case ODOAttributeTypeUndefined: // Transient objects
        case ODOAttributeTypeString:
        case ODOAttributeTypeDate:
        case ODOAttributeTypeXMLDateTime:
        case ODOAttributeTypeData:
            return ODOStorageTypeObject;
            
        case ODOAttributeTypeBoolean:
            return ODOStorageTypeBoolean;
            
        case ODOAttributeTypeInt16:
            return ODOStorageTypeInt16;
            
        case ODOAttributeTypeInt32:
            return ODOStorageTypeInt32;
            
        case ODOAttributeTypeInt64:
            return ODOStorageTypeInt64;
            
        case ODOAttributeTypeFloat32:
            return ODOStorageTypeFloat32;
            
        case ODOAttributeTypeFloat64:
            return ODOStorageTypeFloat64;
            
        default:
            NSLog(@"Unknown property type %ld", type);
            abort();
    }
}

static inline BOOL ODOPropertyUseScalarStorage(ODOProperty *property)
{
    return ODOPropertyGetStorageType(property) != ODOStorageTypeObject;
}


SEL ODOPropertyGetterSelector(ODOProperty *property) OB_HIDDEN;
SEL ODOPropertySetterSelector(ODOProperty *property) OB_HIDDEN;
IMP ODOPropertyGetterImpl(ODOProperty *property) OB_HIDDEN;
IMP ODOPropertySetterImpl(ODOProperty *property) OB_HIDDEN;
IMP ODOPropertyCalculateImpl(ODOProperty *property) OB_HIDDEN;

NSArray <ODOObjectPropertyChangeAction> *ODOPropertyWillChangeActions(ODOProperty *property) OB_HIDDEN;
NSArray <ODOObjectPropertyChangeAction> *ODOPropertyDidChangeActions(ODOProperty *property) OB_HIDDEN;

