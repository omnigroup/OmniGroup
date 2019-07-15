// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

/*
 The intended use of this is to detect retain cycles that tend to creep into an app and prevent "large" objects from being deallocated (taking tons of memory with them).
 
 To use this, simply invoke `OBExpectDeallocation(object);` for any objects that are known to be at their end of live. If they aren't deallocated within a few seconds, an assertion will be logged with the pointer, class.
 
 For example, when your NSDocument or NSWindowController subclass closes, it might invoke this on itself and some key views, controllers, and model objects. The intention is not to invoke this on every single object that might be deallocated, but just the central hubs that tend to hold onto the majority of other things. This aids in quickly detecting a regression in memory management due to retain cycles (block capture, backpointers that should be __weak, explicit retain cycles that need to be manually broken, etc).
 
 By default, this is enabled in debug builds and disabled in release builds.
 */

NS_ASSUME_NONNULL_BEGIN

extern void OBEnableExpectedDeallocations(void);

// Can be used to bracket more expensive calls that would traverse data structures calling OBExpectDeallocation() on multiple elements, but it is not necessary to check before calling OBExpectDeallocation() or OBExpectDeallocationWithPossibleFailureReason(); they will return with no action if OBEnableExpectedDeallocations() has not been called.
extern BOOL OBExpectedDeallocationsIsEnabled(void);

// Return a possible reason the object it wasn't deallocated. The object will still be logged, but more briefly.
typedef NSString * _Nullable (^OBExpectedDeallocationPossibleFailureReason)(id object);

// Internal functions that shouldn't be called directly.
extern void _OBExpectDeallocation(id _Nullable object);
extern void _OBExpectDeallocationWithPossibleFailureReason(id object, OBExpectedDeallocationPossibleFailureReason _Nullable possibleFailureReason);

// Wrapper macros to avoid evaluating the argument unless we are enabled
#define OBExpectDeallocation(object) do { \
    if (OBExpectedDeallocationsIsEnabled()) { \
        _OBExpectDeallocation(object); \
    } \
} while(0)

#define OBExpectDeallocationWithPossibleFailureReason(object, possibleFailureReason) do { \
    if (OBExpectedDeallocationsIsEnabled()) { \
        _OBExpectDeallocationWithPossibleFailureReason((object), (possibleFailureReason)); \
    } \
} while(0)

@class OBMissedDeallocation;

@protocol OBMissedDeallocationObserver
- (void)missedDeallocationsUpdated:(NSSet <OBMissedDeallocation *> *)missedDeallocations;
@end

@interface OBMissedDeallocation : NSObject

@property(class,nullable,weak,nonatomic) id <OBMissedDeallocationObserver> observer;

@property(nonatomic,readonly) const void *pointer;
@property(nonatomic,readonly) Class originalClass;
@property(nonatomic,readonly) NSTimeInterval timeInterval;
@property(nonatomic,nullable,readonly) OBExpectedDeallocationPossibleFailureReason possibleFailureReason;

- (nullable NSString *)failureReason;

@end

NS_ASSUME_NONNULL_END
