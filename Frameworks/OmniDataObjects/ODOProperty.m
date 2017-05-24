// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/ODOProperty.h>

#import <OmniDataObjects/ODOModel.h>
#import <OmniDataObjects/ODOAttribute.h>
#import <OmniDataObjects/ODOModel-Creation.h>

#import "ODOEntity-Internal.h"
#import "ODOObject-Accessors.h"
#import "ODOProperty-Internal.h"

RCS_ID("$Id$")

@implementation ODOProperty

+ (void)initialize;
{
    OBINITIALIZE;
    
}

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

- (BOOL)isCalculated;
{
    return _flags.calculated;
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

void ODOPropertyInit(ODOProperty *self, NSString *name, struct _ODOPropertyFlags flags, BOOL optional, BOOL transient, SEL get, SEL set)
{
    OBPRECONDITION([self isKindOfClass:[ODOProperty class]]);
    OBPRECONDITION([name length] > 0);
    OBPRECONDITION(get);
    
    self->_nonretained_entity = (ODOEntity *)0xdeadbeef;
    self->_name = [name copy];
    self->_flags = flags; // We'll override the property-specific bits of this.
    self->_flags.optional = optional;
    self->_flags.transient = transient;
    self->_flags.calculated = (set == NULL);
    self->_sel.get = get;
    self->_sel.set = set;
}

void ODOPropertyBind(ODOProperty *self, ODOEntity *entity)
{
    OBPRECONDITION([self isKindOfClass:[ODOProperty class]]);
    self->_nonretained_entity = entity;
}

// Since we install method implementations if they don't exist, this can provoke +[ODOObject resolveInstanceMethod:] to fire and install methods.  We should bail on installing methods if properties are read-only, though, so the getter IMP should always get cached, but the setter might not.
static void _ODOPropertyCacheImplementations(ODOProperty *self)
{
    OBPRECONDITION(self->_imp.get == NULL);
    OBPRECONDITION(self->_imp.set == NULL);

    Class instanceClass = [self->_nonretained_entity instanceClass];
    Method method = NULL;

    // This query should cause dynamic method creation via +[ODOObject resolveInstanceMethod:].
    [instanceClass instancesRespondToSelector:self->_sel.get];

    IMP getter = NULL;
    method = class_getInstanceMethod(instanceClass, self->_sel.get);
    if (method != NULL) {
        OBASSERT(strcmp(method_getTypeEncoding(method), ODOGetterSignatureForProperty(self)) == 0); // Only support id-returning getters for now.
        getter = (typeof(self->_imp.get))method_getImplementation(method);
    } else {
        getter = ODOGetterForProperty(self);
    }
    
    // TODO: if "self->_flags.relationship && self->_flags.toMany" and there is a @property, make sure the result type is NSSet, not NSMutableSet.  If the user implements the method themselves, then they are taking their fate into their own hands.
    self->_imp.get = getter;
    
    // Again, provoke the method installation if it is going to be installed
    [instanceClass instancesRespondToSelector:self->_sel.set];

    IMP setter = NULL;
    method = class_getInstanceMethod(instanceClass, self->_sel.set);
    if (method != NULL) {
        // Only support id-taking setters for now
        OBASSERT(strcmp(method_getTypeEncoding(method), ODOSetterSignatureForProperty(self)) == 0);
        setter = (typeof(self->_imp.set))method_getImplementation(method);
    } else {
        // TODO: Don't do this for read-only properties.  Only catching the primary key right now
        if (self->_flags.relationship == NO && [(ODOAttribute *)self isPrimaryKey]) {
            setter = NULL;
        } else {
            setter = ODOSetterForProperty(self);
        }
    }
    
    if (setter != NULL) {
        if (self->_flags.relationship && self->_flags.toMany) {
            // TODO: Should allow setting to-many sets by setting the inverse on elements of the set, if nothing else.
            self->_imp.set = NULL;
        } else {
            self->_imp.set = setter;
        }
    }
    
    OBPOSTCONDITION(self->_imp.get != NULL); // Setter might be NULL, though.
}

SEL ODOPropertyGetterSelector(ODOProperty *property)
{
    return property->_sel.get;
}

SEL ODOPropertySetterSelector(ODOProperty *property)
{
    return property->_sel.set;
}

IMP ODOPropertyGetterImpl(ODOProperty *property)
{
    if (property->_imp.get == NULL) {
        _ODOPropertyCacheImplementations(property);
    }
    
    return property->_imp.get;
}

IMP ODOPropertySetterImpl(ODOProperty *property)
{
    if (property->_imp.get == NULL) {
        _ODOPropertyCacheImplementations(property);
    }
    
    return property->_imp.set;
}

BOOL ODOPropertyHasIdenticalName(ODOProperty *property, NSString *name)
{
    OBPRECONDITION([property isKindOfClass:[ODOProperty class]]);
    return property->_name == name;
}

void ODOPropertySnapshotAssignSnapshotIndex(ODOProperty *property, NSUInteger snapshotIndex)
{
    OBPRECONDITION(property->_flags.snapshotIndex == ODO_NON_SNAPSHOT_PROPERTY_INDEX); // shouldn't have been assigned yet.
    property->_flags.snapshotIndex = (unsigned)snapshotIndex;
    OBASSERT(property->_flags.snapshotIndex == snapshotIndex); // make sure it didn't get truncated.
}

@end

