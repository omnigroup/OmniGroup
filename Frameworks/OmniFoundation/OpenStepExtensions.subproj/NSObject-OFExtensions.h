// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h> // NSTimeInterval

@class NSArray, NSBundle, NSMutableDictionary;

NS_ASSUME_NONNULL_BEGIN

@interface NSObject (OFExtensions)

+ (nullable Class)classImplementingSelector:(SEL)aSelector;

+ (NSBundle *)bundle;

- (BOOL)satisfiesCondition:(SEL)sel withObject:(nullable id)object;

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

typedef BOOL (^OFRunLoopRunPredicate)(void);
extern BOOL OFRunLoopRunUntil(NSTimeInterval timeout, OFRunLoopRunType runType, OFRunLoopRunPredicate NS_NOESCAPE _Nullable predicate);

extern NSString * _Nullable OFInstanceMethodReturnTypeEncoding(Class cls, SEL sel);

@protocol OFInvokeMethodSignature <NSObject>
@property (readonly) NSUInteger numberOfArguments;
- (const char *)getArgumentTypeAtIndex:(NSUInteger)idx;
@property (readonly) const char *methodReturnType;
@end
@protocol OFInvokeMethodInvocation <NSObject>
@property(nonatomic,readonly) id <OFInvokeMethodSignature> methodSignature;
- (void)retainArguments;
- (void)setArgument:(void *)argumentLocation atIndex:(NSInteger)idx;
- (void)getReturnValue:(void *)retLoc;
@end

typedef BOOL (^OFInvokeMethodHandler)(id <OFInvokeMethodSignature> _Nonnull methodSignature, id <OFInvokeMethodInvocation> _Nonnull invocation);

extern BOOL OFInvokeMethod(id _Nonnull object, SEL _Nonnull selector, OFInvokeMethodHandler _Nonnull provideArguments, OFInvokeMethodHandler _Nonnull collectResults);

NS_ASSUME_NONNULL_END
