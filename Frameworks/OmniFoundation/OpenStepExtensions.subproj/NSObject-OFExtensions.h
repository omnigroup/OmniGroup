// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h> // NSTimeInterval

@class NSArray, NSBundle, NSMutableDictionary;

@interface NSObject (OFExtensions)

+ (Class)classImplementingSelector:(SEL)aSelector;

+ (NSBundle *)bundle;

- (BOOL)satisfiesCondition:(SEL)sel withObject:(id)object;

- (NSMutableDictionary *)dictionaryWithNonNilValuesForKeys:(NSArray<NSString *> *)keys;

@end

extern void OFAfterDelayPerformBlock(NSTimeInterval delay, void (^block)(void));

// Makes a one-shot NSOperationQueue to run the specified block. Use this instead of performSelectorInBackground:withObject:.
extern void OFPerformInBackground(void (^block)(void));

extern void OFMainThreadPerformBlock(void (^block)(void));
extern void OFMainThreadPerformBlockSynchronously(void (^block)(void));

typedef NS_ENUM(NSUInteger, OFRunLoopRunType) {
    OFRunLoopRunTypeBlocking,
    OFRunLoopRunTypePolling,
};

extern BOOL OFRunLoopRunUntil(NSTimeInterval timeout, OFRunLoopRunType runType, BOOL(^predicate)(void));

@protocol OFInvokeMethodSignature <NSObject>
@property (readonly) NSUInteger numberOfArguments;
- (const char *)getArgumentTypeAtIndex:(NSUInteger)idx;
@property (readonly) const char *methodReturnType;
@end
@protocol OFInvokeMethodInvocation <NSObject>
- (void)setArgument:(void *)argumentLocation atIndex:(NSInteger)idx;
- (void)getReturnValue:(void *)retLoc;
@end

typedef BOOL (^OFInvokeMethodHandler)(id <OFInvokeMethodSignature> methodSignature, id <OFInvokeMethodInvocation> invocation);

extern BOOL OFInvokeMethod(id object, SEL selector, OFInvokeMethodHandler provideArguments, OFInvokeMethodHandler collectResults);
