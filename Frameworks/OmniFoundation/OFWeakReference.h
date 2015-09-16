// Copyright 2012-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <OmniBase/macros.h>

/*
 This allows classes to form collections of weak references. OS X 10.8 adds weak support for NSMapTable, but this class will work on 10.7 and will support other collections. Note that -hash and -isEqual: are not currently bridged to the contained object (and we'd need to cache the hash in case the weak object reference was nullified). For now we just get the default -hash (pointer based) so this is just useful for arrays and dictionary values.
 */
@interface OFWeakReference OB_GENERIC1(ObjectType) : NSObject

- initWithObject:(OB_GENERIC_ARG(ObjectType))object;
- (BOOL)referencesObject:(void *)objectPointer;

#if OB_ARC
@property(nonatomic,weak) OB_GENERIC_ARG(ObjectType) object;
#else
@property(nonatomic,assign) OB_GENERIC_ARG(ObjectType) object;
#endif

@end
