// Copyright 2008-2017 Omni Development, Inc. All rights reserved.
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

#define ODO_PROPERTY_SNAPSHOT_INDEX_WIDTH (26)
struct _ODOPropertyFlags {
    unsigned int optional : 1;
    unsigned int transient : 1;
    unsigned int calculated : 1;
    unsigned int relationship : 1;
    unsigned int toMany : 1;
    unsigned int scalarAccessors : 1;
    unsigned int snapshotIndex : ODO_PROPERTY_SNAPSHOT_INDEX_WIDTH;
};

@interface ODOProperty : OBObject <NSCopying> {
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
        IMP get;
        IMP set;
    } _imp;
    
    struct _ODOPropertyFlags _flags;
}

@property (nonatomic, readonly) ODOEntity *entity;
@property (nonatomic, readonly) NSString *name;

@property (nonatomic, readonly, getter=isOptional) BOOL optional;
@property (nonatomic, readonly, getter=isTransient) BOOL transient;
@property (nonatomic, readonly, getter=isCalculated) BOOL calculated;

- (NSComparisonResult)compareByName:(ODOProperty *)prop;

@end
