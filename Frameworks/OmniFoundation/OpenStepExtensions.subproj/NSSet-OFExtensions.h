// Copyright 2005-2008, 2010-2011, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSSet.h>

#import <CoreFoundation/CFSet.h>
#import <OmniFoundation/OFUtilities.h>
#import <Foundation/NSObjCRuntime.h> // for NSComparator

@interface NSSet (OFExtensions)

- (NSSet *)setByPerformingSelector:(SEL)aSelector;
- (NSSet *)setByPerformingBlock:(OFObjectToObjectBlock)block;

- (NSSet *)setByRemovingObject:(id)anObject;

- (NSArray *)sortedArrayUsingSelector:(SEL)comparator;
- (NSArray *)sortedArrayUsingComparator:(NSComparator)comparator;

- (void)applyFunction:(CFSetApplierFunction)applier context:(void *)context;

- (id)any:(OFPredicateBlock)predicate;
- (BOOL)all:(OFPredicateBlock)predicate;

- (NSSet *)select:(OFPredicateBlock)predicate;

@end

#define OFSetByGettingProperty(set, cls, prop) [(set) setByPerformingBlock:^id(cls *item){ return item.prop; }]
