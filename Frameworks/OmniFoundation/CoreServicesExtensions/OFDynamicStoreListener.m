// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDynamicStoreListener.h>

#import "OFDynamicStoreListenerPrivate.h"

RCS_ID("$Id$");

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

static void _SCDynamicStoreCallBack(SCDynamicStoreRef store, CFArrayRef changedKeys, void *info);

@implementation OFDynamicStoreListener

+ (OFDynamicStoreListener *)defaultDynamicStoreListener;
{
    static OFDynamicStoreListener *defaultDynamicStoreListener = nil;
    if (!defaultDynamicStoreListener)
        defaultDynamicStoreListener = [[OFDynamicStoreListener alloc] init];
        
    return defaultDynamicStoreListener;
}

- (id)init;
{
    self = [super init];
    if (!self)
        return nil;

    SCDynamicStoreContext context = {
        .version = 0,
        .info = self,
        .retain = NULL,
        .release = NULL,
        .copyDescription = NULL
    };
        
    CFStringRef name = (CFStringRef)[[NSBundle mainBundle] bundleIdentifier];
    _dynamicStore = SCDynamicStoreCreate(kCFAllocatorDefault, name, _SCDynamicStoreCallBack, &context);
    if (!_dynamicStore) {
        [self release];
        return nil;
    }
    
    _runLoopSource = SCDynamicStoreCreateRunLoopSource(kCFAllocatorDefault, _dynamicStore, 0);
    if (!_runLoopSource) {
        [self release];
        return nil;
    }
    
    CFRunLoopAddSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);

    return self;
}

- (void)dealloc;
{
    if (_dynamicStore) CFRelease(_dynamicStore);

    if (_runLoopSource){
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
        CFRelease(_runLoopSource);
    }
    
    [_observerInfoByKey release];
    [_observedKeys release];
    [_observedKeyPatterns release];

    [super dealloc];
}

- (SCDynamicStoreRef)dynamicStore;
{
    return _dynamicStore;
}

- (void)addObserver:(id)observer selector:(SEL)selector forKey:(NSString *)key;
{
    OBPRECONDITION(observer);
    OBPRECONDITION(selector);
    OBPRECONDITION(key);

    NSMutableDictionary *observerInfoByKey = [self _observerInfoByKey];
    NSMutableSet *observers = [observerInfoByKey objectForKey:key];

    if (!observers) {
        observers = [NSMutableSet set];
        [observerInfoByKey setObject:observers forKey:key];
    }

    _OFDynamicStoreListenerObserverInfo *observerInfo = [[_OFDynamicStoreListenerObserverInfo alloc] initWithObserver:observer selector:selector key:key];
    [observers addObject:observerInfo];
    [observerInfo release];
    
    [self _startObservingDynamicStoreKey:key];
}

- (void)addObserver:(id)observer selector:(SEL)selector forKeyPattern:(NSString *)keyPattern;
{
    OBPRECONDITION(keyPattern);

    NSArray *keyList = CFBridgingRelease(SCDynamicStoreCopyKeyList(_dynamicStore, (__bridge CFStringRef)keyPattern));

    if (keyList) {
        for (NSString *key in keyList) {
            [self addObserver:observer selector:selector forKey:key];
        }
    }

    [self _startObservingDynamicStoreKeyPattern:keyPattern];
}

- (void)removeObserver:(id)observer selector:(SEL)selector forKey:(NSString *)key;
{
    NSMutableDictionary *observerInfoByKey = [self _observerInfoByKey];

    if (key) {
        NSMutableSet *observers = [observerInfoByKey objectForKey:key];
        OBASSERT(observers);
        
        NSEnumerator *observerEnumerator = [observers objectEnumerator];
        _OFDynamicStoreListenerObserverInfo *observerInfo = nil;
        NSMutableSet *observersToRemove = [NSMutableSet set];
        
        while (nil != (observerInfo = [observerEnumerator nextObject])) {
            if ([observerInfo observer] == observer && [[observerInfo key] isEqualToString:key] && (selector == NULL || [observerInfo selector] == selector)) {
                [observersToRemove addObject:observerInfo];
            }
        }
        
        [observers minusSet:observersToRemove];
    } else {
        NSEnumerator *valueEnumerator = [observerInfoByKey objectEnumerator];
        NSMutableSet *observers = nil;
        
        while (nil != (observers = [valueEnumerator nextObject])) {
            NSEnumerator *observerEnumerator = [observers objectEnumerator];
            _OFDynamicStoreListenerObserverInfo *observerInfo = nil;
            NSMutableSet *observersToRemove = [NSMutableSet set];
            
            while (nil != (observerInfo = [observerEnumerator nextObject])) {
                if ([observerInfo observer] == observer && (selector == NULL || [observerInfo selector] == selector)) {
                    [observersToRemove addObject:observerInfo];
                }
            }
            
            [observers minusSet:observersToRemove];
        }
    }
}

- (void)removeObserver:(id)observer selector:(SEL)selector forKeyPattern:(NSString *)keyPattern;
{
    OBPRECONDITION(keyPattern);

    NSArray *keyList = CFBridgingRelease(SCDynamicStoreCopyKeyList(_dynamicStore, (__bridge CFStringRef)keyPattern));
    if (keyList) {
        for (NSString *key in keyList) {
            [self removeObserver:observer selector:selector forKey:key];
        }
    }

    [self _stopObservingDynamicStoreKey:keyPattern];
}

- (void)removeObserver:(id)observer;
{
    [self removeObserver:observer selector:NULL forKey:nil];
}

#pragma mark -
#pragma mark Private

static void _SCDynamicStoreCallBack(SCDynamicStoreRef store, CFArrayRef changedKeys, void *info)
{
    OFDynamicStoreListener *self = (__bridge OFDynamicStoreListener *)info;
    [self _didChangeValuesForKeys:(__bridge NSArray *)changedKeys];
}

- (void)_didChangeValuesForKeys:(NSArray *)changedKeys;
{
    NSEnumerator *keyEnumerator = [changedKeys objectEnumerator];
    NSString *key = nil;
    
    while (nil != (key = [keyEnumerator nextObject])){
        NSMutableDictionary *observerInfoByKey = [self _observerInfoByKey];
        NSMutableSet *observers = [observerInfoByKey objectForKey:key];
        NSEnumerator *observerEnumerator = [observers objectEnumerator];
        _OFDynamicStoreListenerObserverInfo *observerInfo = nil;
        
        while (nil != (observerInfo = [observerEnumerator nextObject])) {
            if ([[observerInfo key] isEqualToString:key]) {
                id observer = [observerInfo observer];
                SEL selector = [observerInfo selector];
                NSMethodSignature *signature = [observer methodSignatureForSelector:selector];
                OBASSERT(signature);
                if ([signature numberOfArguments] == 4) {
                    typedef void (*IMP_callback_4)(id self, SEL _cmd, id sender, NSString *key);
                    IMP_callback_4 callback = (IMP_callback_4)[observer methodForSelector:selector];
                    callback(observer, selector, self, key);
                } else if ([signature numberOfArguments] == 3) {
                    typedef void (*IMP_callback_3)(id self, SEL _cmd, id sender);
                    IMP_callback_3 callback = (IMP_callback_3)[observer methodForSelector:selector];
                    callback(observer, selector, self);
                } else {
                    typedef void (*IMP_callback_2)(id self, SEL _cmd);
                    IMP_callback_2 callback = (IMP_callback_2)[observer methodForSelector:selector];
                    callback(observer, selector);
                }
            }
        }    
    }
}

- (NSMutableDictionary *)_observerInfoByKey;
{
    if (!_observerInfoByKey)
        _observerInfoByKey = [[NSMutableDictionary alloc] initWithCapacity:0];
        
    return _observerInfoByKey;
}

- (BOOL)_isObservingDynamicStoreKey:(NSString *)key;
{
    return [_observedKeys containsObject:key];
}

- (void)_startObservingDynamicStoreKey:(NSString *)key;
{
    if ([self _isObservingDynamicStoreKey:key])
        return;
        
    if (!_observedKeys)
        _observedKeys = [[NSMutableSet alloc] initWithCapacity:0];
       
    [_observedKeys addObject:key];
    SCDynamicStoreSetNotificationKeys(_dynamicStore, (CFArrayRef)[_observedKeys allObjects], NULL);
}

- (void)_stopObservingDynamicStoreKey:(NSString *)key;
{
    if (![self _isObservingDynamicStoreKey:key])
        return;

    [_observedKeys removeObject:key];
    SCDynamicStoreSetNotificationKeys(_dynamicStore, (CFArrayRef)[_observedKeys allObjects], NULL);
}

- (BOOL)_isObservingDynamicStoreKeyPattern:(NSString *)keyPattern;
{
    return [_observedKeyPatterns containsObject:keyPattern];
}

- (void)_startObservingDynamicStoreKeyPattern:(NSString *)keyPattern;
{
    if (!_observedKeyPatterns)
        _observedKeyPatterns = [[NSMutableSet alloc] initWithCapacity:0];
       
    [_observedKeyPatterns addObject:keyPattern];
    // N.B. don't add the key pattern to the dynamic store - we explode the pattern at -addobserver:... time
}

- (void)_stopObservingDynamicStoreKeyPattern:(NSString *)keyPattern;
{
    [_observedKeyPatterns removeObject:keyPattern];
}

@end

#endif // !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
