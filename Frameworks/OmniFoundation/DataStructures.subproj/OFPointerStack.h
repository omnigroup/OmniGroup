// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface OFPointerStack<T> : NSObject

// O(1)
- (void)push:(T)object;

/*
 If unique is YES, this is O(n). This ensures that the only instance of your object in the stack is the one at the top.
 */

- (void)push:(T)object uniquing:(BOOL)unique;

/*
If compactFirst is YES, this is O(n). We prune nil entries, and then perform the operation. If compactFirst is NO, this is O(1), but you might receive a nil object when there are valid objects in the stack
*/
- (nullable T)peekAfterCompacting:(BOOL)compactFirst;
- (nullable T)popAfterCompacting:(BOOL)compactFirst;

// O(n)
@property (nonatomic, readonly) NSArray<T> *allObjects;
@property (nonatomic, readonly) NSInteger count; // We compact before calculating the count
@property (nonatomic, readonly) BOOL isEmpty; // Convenience for count == 0
- (BOOL)contains:(T)object; // Could be made O(1) if we add an additional NSMapTable storage that has weakly held keys that hold the stack members, and has some arbitrary object value. If table[object] is non-nil, then object is in the stack. We'd also need to remove keys upon calling the remove: and pop: methods, and upon removing object that satisfy an additional compaction condition.
- (nullable T)firstElementSatisfyingCondition:(BOOL (^)(T))condition;
- (NSArray<T> *)allElementsSatisfyingCondition:(BOOL (^)(T))condition;
- (void)remove:(T)object;

// API
// Normally, the only compaction condition is that nil objects and NULL pointers are pruned. This happens upon calling each O(n) operation. Your condition block can be called up to N times, so if your condition takes higher than constant time to evaluate (or you introduce N conditions) you could introduce performance issues. Also, be sure to be careful if you use objects that may be in the pointer stack as a basis for comparison in this block, as that will strongly retain the object and sidestep the weak behavior that is expected with this structure.
- (void)addAdditionalCompactionCondition:(BOOL (^)(T))isIncludedCondition;

@end

NS_ASSUME_NONNULL_END
