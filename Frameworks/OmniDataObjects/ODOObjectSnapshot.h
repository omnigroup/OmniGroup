// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


// Using a CFArray is slower than it needs to be since it bridges back to NSArray. Using a NSArray directly won't work since we store nils.

#import <OmniBase/macros.h>

@class ODOProperty, ODOEntity;

NS_ASSUME_NONNULL_BEGIN

@interface ODOObjectSnapshot : NSObject
- (nullable id)valueForProperty:(ODOProperty *)property;
@end

extern ODOObjectSnapshot *ODOObjectSnapshotCreate(ODOEntity *entity) OB_HIDDEN;
extern void *ODOObjectSnapshotGetStorageBase(ODOObjectSnapshot *snapshot) OB_HIDDEN;

extern ODOEntity *ODOObjectSnapshotGetEntity(ODOObjectSnapshot *snapshot) OB_HIDDEN;

extern id _Nullable ODOObjectSnapshotGetValueForProperty(ODOObjectSnapshot *snapshot, ODOProperty *property) OB_HIDDEN;

NS_ASSUME_NONNULL_END

