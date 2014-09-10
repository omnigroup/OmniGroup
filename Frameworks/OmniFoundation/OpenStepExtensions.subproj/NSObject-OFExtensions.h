// Copyright 1997-2005, 2007-2008, 2010, 2012, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h> // NSTimeInterval

@class NSArray, NSBundle, NSMutableDictionary, NSSet;

@interface NSObject (OFExtensions)

+ (Class)classImplementingSelector:(SEL)aSelector;

+ (NSBundle *)bundle;

- (BOOL)satisfiesCondition:(SEL)sel withObject:(id)object;

- (NSMutableDictionary *)dictionaryWithNonNilValuesForKeys:(NSArray *)keys;

@end

extern void OFAfterDelayPerformBlock(NSTimeInterval delay, void (^block)(void));

// Makes a one-shot NSOperationQueue to run the specified block. Use this instead of performSelectorInBackground:withObject:.
extern void OFPerformInBackground(void (^block)(void));

extern void OFMainThreadPerformBlock(void (^block)(void));
