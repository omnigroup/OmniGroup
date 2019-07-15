// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBObject.h>
#import <OmniBase/assertions.h>

@class ODOEntity, ODOObject;

@interface ODOProperty : OBObject <NSCopying>

@property (nonatomic, readonly) ODOEntity *entity;
@property (nonatomic, readonly) NSString *name;

@property (nonatomic, readonly, getter=isOptional) BOOL optional;
@property (nonatomic, readonly, getter=isTransient) BOOL transient;
@property (nonatomic, readonly, getter=isCalculated) BOOL calculated;

- (NSComparisonResult)compareByName:(ODOProperty *)prop;

@end
