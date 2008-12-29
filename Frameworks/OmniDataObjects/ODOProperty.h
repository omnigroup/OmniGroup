// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/OBObject.h>

@class ODOEntity;

#define ODO_PROPERTY_SNAPSHOT_INDEX_WIDTH (28)
struct _ODOPropertyFlags {
    unsigned int optional : 1;
    unsigned int transient : 1;
    unsigned int relationship : 1;
    unsigned int toMany : 1;
    unsigned int snapshotIndex : ODO_PROPERTY_SNAPSHOT_INDEX_WIDTH;
};

@interface ODOProperty : OBObject <NSCopying>
{
@private
    ODOEntity *_nonretained_entity;
    NSString *_name;
    SEL _getterSelector;
    SEL _setterSelector;
    struct _ODOPropertyFlags _flags;
}

- (ODOEntity *)entity;
- (NSString *)name;

- (BOOL)isOptional;
- (BOOL)isTransient;

- (NSComparisonResult)compareByName:(ODOProperty *)prop;

@end

extern struct _ODOPropertyFlags ODOPropertyFlags(ODOProperty *property);
