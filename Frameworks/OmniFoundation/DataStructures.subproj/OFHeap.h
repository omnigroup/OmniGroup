// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

#import <Foundation/NSObjCRuntime.h> // for NSComparator
#import <OmniBase/macros.h>

@interface OFHeap : OFObject

- initWithComparator:(NSComparator)comparator;

- (NSUInteger)count;

- (void)addObject:(id)anObject;

- (id)removeObject;
- (id)removeObjectLessThanObject:(id)object;

- (void)removeAllObjects;

- (id)peekObject;

@end
