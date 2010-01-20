// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/OBObject.h>
#import <OmniBase/assertions.h>

@class ODOEntity, ODOObject;

#define ODO_PROPERTY_SNAPSHOT_INDEX_WIDTH (27)
struct _ODOPropertyFlags {
    unsigned int optional : 1;
    unsigned int transient : 1;
    unsigned int calculated : 1;
    unsigned int relationship : 1;
    unsigned int toMany : 1;
    unsigned int snapshotIndex : ODO_PROPERTY_SNAPSHOT_INDEX_WIDTH;
};

typedef id (*ODOPropertyGetter)(ODOObject *self, SEL _cmd);
typedef void (*ODOPropertySetter)(ODOObject *self, SEL _cmd, id value);

@interface ODOProperty : OBObject <NSCopying>
{
@package
    ODOEntity *_nonretained_entity;
    NSString *_name;
    
    // Getter/setter selectors are defined no matter what.
    struct {
        SEL get;
        SEL set;
    } _sel;
    
    // IMPs are cached when needed.  Setter might be NULL (someday) if the property is @dynamic and read-only.
    struct {
        ODOPropertyGetter get;
        ODOPropertySetter set;
    } _imp;
    
    struct _ODOPropertyFlags _flags;
}

@property(readonly) ODOEntity *entity;
@property(readonly) NSString *name;

@property(readonly) BOOL isOptional;
@property(readonly) BOOL isTransient;
@property(readonly) BOOL isCalculated;

- (NSComparisonResult)compareByName:(ODOProperty *)prop;

@end
