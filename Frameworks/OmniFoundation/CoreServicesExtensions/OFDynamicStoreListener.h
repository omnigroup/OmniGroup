// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

#import <CoreFoundation/CFRunLoop.h>
#import <SystemConfiguration/SCDynamicStore.h>

@interface OFDynamicStoreListener : NSObject {
  @private
    SCDynamicStoreRef _dynamicStore;
    CFRunLoopSourceRef _runLoopSource;
    NSMutableDictionary *_observerInfoByKey;
    NSMutableSet *_observedKeys;
    NSMutableSet *_observedKeyPatterns;
}

+ (OFDynamicStoreListener *)defaultDynamicStoreListener;

- (id)init;

// Use this reference to get/set values on the dynamic store; Don't alter the notification keys
- (SCDynamicStoreRef)dynamicStore;

// Target/action should be of the form:
// - (void)dynamicStore<Key>DidChange;
// - (void)dynamicStore<Key>DidChange:(id)sender;
// - (void)dynamicStore:(id)sender <key>DidChange:(NSString *)key;

- (void)addObserver:(id)observer selector:(SEL)selector forKey:(NSString *)key;
- (void)addObserver:(id)observer selector:(SEL)selector forKeyPattern:(NSString *)keyPattern;

- (void)removeObserver:(id)observer selector:(SEL)selector forKey:(NSString *)key;
- (void)removeObserver:(id)observer selector:(SEL)selector forKeyPattern:(NSString *)keyPattern;

- (void)removeObserver:(id)observer;

@end

#endif // !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
