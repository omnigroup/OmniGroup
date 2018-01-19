// Copyright 2008-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$


// Using a CFArray is slower than it needs to be since it bridges back to NSArray. Using a NSArray directly won't work since we store nils.

NS_ASSUME_NONNULL_BEGIN

@interface ODOObjectSnapshot : NSObject
@end

extern ODOObjectSnapshot *ODOObjectSnapshotCreate(NSUInteger propertyCount) OB_HIDDEN;
extern NSUInteger ODOObjectSnapshotValueCount(ODOObjectSnapshot *snapshot) OB_HIDDEN;

extern void ODOObjectSnapshotSetValueAtIndex(ODOObjectSnapshot *snapshot, NSUInteger propertyIndex, id _Nullable value) OB_HIDDEN;
extern id _Nullable ODOObjectSnapshotGetValueAtIndex(ODOObjectSnapshot *snapshot, NSUInteger propertyIndex) OB_HIDDEN;

NS_ASSUME_NONNULL_END

