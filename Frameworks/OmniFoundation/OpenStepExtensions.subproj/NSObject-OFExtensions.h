// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSArray, NSSet, NSBundle;

@interface NSObject (OFExtensions)

+ (Class)classImplementingSelector:(SEL)aSelector;

+ (NSBundle *)bundle;
- (NSBundle *)bundle;

- (void)performSelector:(SEL)sel withEachObjectInArray:(NSArray *)array;
- (void)performSelector:(SEL)sel withEachObjectInSet:(NSSet *)set;
- (NSArray *)arrayByPerformingSelector:(SEL)sel withEachObjectInArray:(NSArray *)array;

- (BOOL)satisfiesCondition:(SEL)sel withObject:(id)object;

- (NSMutableDictionary *)dictionaryWithNonNilValuesForKeys:(NSArray *)keys;

@end
