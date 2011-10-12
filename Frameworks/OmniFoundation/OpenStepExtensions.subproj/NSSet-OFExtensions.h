// Copyright 2005-2008, 2010-2011 Omni Development, Inc. All rights reserved.
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

@interface NSSet (OFExtensions)

- (NSSet *)setByPerformingSelector:(SEL)aSelector;
- (NSArray *)sortedArrayUsingSelector:(SEL)comparator;

- (void)applyFunction:(CFSetApplierFunction)applier context:(void *)context;

- (id)any:(OFPredicateBlock)predicate;
- (NSSet *)select:(OFPredicateBlock)predicate;

@end

