// Copyright 1998-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSNotificationCenter-OFExtensions.h>

#import <OmniFoundation/OFObject-Queue.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")

@implementation NSNotificationCenter (OFExtensions)

#if 0 && defined(DEBUG_bungi) && defined(OMNI_ASSERTIONS_ON)
// Warn when performing notification registration changes or posting on background threads. While you could, for a certain subgraph of objects, make this work, its usually a bug.

static void (*original_addObserverSelectorNameObject)(id self, SEL _cmd, id observer, SEL aSelector, NSString *name, id anObject) = NULL;

// These may or may not all funnel to -postNotification:, but we won't assume so (downside being multiple assertions).
static void (*original_postNotification)(id self, SEL _cmd, NSNotification *note) = NULL;
static void (*original_postNotificationNameObject)(id self, SEL _cmd, NSString *name, id object) = NULL;
static void (*original_postNotificationNameObjectUserInfo)(id self, SEL _cmd, NSString *name, id object, NSDictionary *userInfo) = NULL;

static void (*original_removeObserver)(id self, SEL _cmd, id observer) = NULL;
static void (*original_removeObserverNameObject)(id self, SEL _cmd, id observer, NSString *name, id object) = NULL;

// Not currently asserting on the block-based observations since those _can_ have an explicit queue, but if they don't it might be good to assert. But, the -removeObserver: gets called for block-based notification unsubscription, so maybe should do both anyway.

OBPerformPosing(^{
    Class self = objc_getClass("NSNotificationCenter");
    
    original_addObserverSelectorNameObject = (typeof(original_addObserverSelectorNameObject))OBReplaceMethodImplementationWithSelector(self, @selector(addObserver:selector:name:object:), @selector(replacement_addObserver:selector:name:object:));
    OBASSERT(original_addObserverSelectorNameObject);
    
    original_postNotification = (typeof(original_postNotification))OBReplaceMethodImplementationWithSelector(self, @selector(postNotification:), @selector(replacement_postNotification:));
    OBASSERT(original_postNotification);

    original_postNotificationNameObject = (typeof(original_postNotificationNameObject))OBReplaceMethodImplementationWithSelector(self, @selector(postNotificationName:object:), @selector(replacement_postNotificationName:object:));
    OBASSERT(original_postNotificationNameObject);

    original_postNotificationNameObjectUserInfo = (typeof(original_postNotificationNameObjectUserInfo))OBReplaceMethodImplementationWithSelector(self, @selector(postNotificationName:object:userInfo:), @selector(replacement_postNotificationName:object:userInfo:));
    OBASSERT(original_postNotificationNameObjectUserInfo);

    original_removeObserver = (typeof(original_removeObserver))OBReplaceMethodImplementationWithSelector(self, @selector(removeObserver:), @selector(replacement_removeObserver:));
    OBASSERT(original_removeObserver);

    original_removeObserverNameObject = (typeof(original_removeObserverNameObject))OBReplaceMethodImplementationWithSelector(self, @selector(removeObserver:name:object:), @selector(replacement_removeObserver:name:object:));
    OBASSERT(original_removeObserverNameObject);
});

- (void)replacement_addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName object:(id)anObject;
{
    OBPRECONDITION([NSThread isMainThread], "Adding notification registrations on background threads is generally not a good idea, observer:%@ selector:%@ name:%@ object:%@", OBShortObjectDescription(observer), NSStringFromSelector(aSelector), aName, OBShortObjectDescription(anObject));
    original_addObserverSelectorNameObject(self, _cmd, observer, aSelector, aName, anObject);
}

- (void)replacement_postNotification:(NSNotification *)note;
{
    OBPRECONDITION([NSThread isMainThread], "Posting notification registrations on background threads is generally not a good idea, note:%@", note);
    original_postNotification(self, _cmd, note);
}

- (void)replacement_postNotificationName:(NSString *)aName object:(id)anObject;
{
    OBPRECONDITION([NSThread isMainThread], "Posting notifications on background threads is generally not a good idea, name:%@ object:%@", aName, OBShortObjectDescription(anObject));
    original_postNotificationNameObject(self, _cmd, aName, anObject);
}

- (void)replacement_postNotificationName:(NSString *)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo;
{
    OBPRECONDITION([NSThread isMainThread], "Posting notifications on background threads is generally not a good idea, name:%@ object:%@ userInfo:%@", aName, OBShortObjectDescription(anObject), aUserInfo);
    original_postNotificationNameObjectUserInfo(self, _cmd, aName, anObject, aUserInfo);
}

- (void)replacement_removeObserver:(id)observer;
{
    OBPRECONDITION([NSThread isMainThread], "Removing notification registrations on background threads is generally not a good idea, object:%@", OBShortObjectDescription(observer));
    original_removeObserver(self, _cmd, observer);
}

- (void)replacement_removeObserver:(id)observer name:(NSString *)aName object:(id)anObject;
{
    OBPRECONDITION([NSThread isMainThread], "Removing notification registrations on background threads is generally not a good idea, observer:%@ name:%@ object:%@", OBShortObjectDescription(observer), aName, OBShortObjectDescription(anObject));
    original_removeObserverNameObject(self, _cmd, observer, aName, anObject);
}

#endif

- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName objects:(NSArray *)objects;
{
    for (id object in objects)
        [self addObserver:observer selector:aSelector name:aName object:object];
}

- (void)removeObserver:(id)observer name:(NSString *)aName objects:(NSArray *)objects;
{
    for (id object in objects)
        [self removeObserver:observer name:aName object:object];
}

- (void)mainThreadPostNotificationName:(NSString *)aName object:(id)anObject;
    // Asynchronously post a notification in the main thread
{
    [self mainThreadPerformSelector:@selector(postNotificationName:object:) withObject:aName withObject:anObject];
}

- (void)mainThreadPostNotificationName:(NSString *)aName object:(id)anObject userInfo:(NSDictionary *)aUserInfo;
    // Asynchronously post a notification in the main thread
{
    [self mainThreadPerformSelector:@selector(postNotificationName:object:userInfo:) withObject:aName withObject:anObject withObject:aUserInfo];
}

@end
