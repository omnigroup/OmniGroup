// Copyright 2008-2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQContentAnimatingLayer.h>

#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniQuartz/CALayer-OQExtensions.h>
#import <objc/runtime.h>

#if 0 && defined(DEBUG)
    #define DEBUG_CONTENT_ANIMATION(format, ...) NSLog((format), ## __VA_ARGS__)
#else
    #define DEBUG_CONTENT_ANIMATION(format, ...)
#endif

RCS_ID("$Id$")

/*
 
 NOTE: If you add ivars to your subclass that are referenced in its drawing methods (configuration stuff like non-animated colors/rects), then you must implement -initWithLayer: in your subclass to copy that state. Otherwise, the presentationLayer made when animations start won't be properly configured and will at best draw incorrectly and at worst crash.
 
 */

@implementation OQContentAnimatingLayer

// Ghetto support for -actionFor<Key>
static CFMutableDictionaryRef ActionNameToSelector = NULL;

static SEL ActionSelectorForKey(NSString *key)
{
    // TODO: Locking, if you need it.
    OBPRECONDITION([NSThread isMainThread]);
    
    SEL sel = (SEL)CFDictionaryGetValue(ActionNameToSelector, key);
    if (sel == NULL) {
        NSString *selName = [NSString stringWithFormat:@"actionFor%@%@", [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]];
        sel = NSSelectorFromString(selName);
        
        CFDictionarySetValue(ActionNameToSelector, (const void *)key, sel);
    }
    return sel;
}

static Boolean _equalStrings(const void *value1, const void *value2)
{
    return [(NSString *)value1 isEqualToString:(NSString *)value2];
}
static CFHashCode _hashString(const void *value)
{
    return CFHash((CFStringRef)value);
}

+ (void)initialize;
{
    if (self == [OQContentAnimatingLayer class]) {
        CFDictionaryKeyCallBacks keyCallbacks;
        memset(&keyCallbacks, 0, sizeof(keyCallbacks));
        keyCallbacks.hash = _hashString;
        keyCallbacks.equal = _equalStrings;
        keyCallbacks.retain = OFNSObjectRetainCopy;
        keyCallbacks.release = OFNSObjectRelease;
        
        CFDictionaryValueCallBacks valueCallbacks;
        memset(&valueCallbacks, 0, sizeof(valueCallbacks));
        ActionNameToSelector = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &keyCallbacks, &valueCallbacks);
    }
}

- init;
{
    if (!(self = [super init]))
        return nil;
    
    // Since we have content, it seems reasonable to assume we'd want to draw it (unlike layers just used for their background color).  Layers don't normally start out needing display.
    [self setNeedsDisplay];
    
    // Our content probably fills our bounds.
    self.needsDisplayOnBoundsChange = YES;
    
    return self;
}

- (void)dealloc;
{
    OBASSERT(_activeContentAnimations == nil);
    [_activeContentAnimations release];
    [super dealloc];
}

#pragma mark NSObject (NSKeyValueObservingCustomization).

// Might want to rename this instead of using the KVO method; or not.
+ (NSSet *)keyPathsForValuesAffectingContent;
{
    return [NSSet set];
}

#pragma mark NSObject subclass

+ (BOOL)resolveInstanceMethod:(SEL)sel;
{
    // Called due to -respondsToSelector: in our -actionForKey:, but only if it doesn't have the method already (in which case we assume it does something reasonble).  Install a method that provides an animation for the property. Right now we are doing a forward lookup of key->sel since this shouldn't get called often, though we could invert the dictionary if needed.

    NSSet *contentAffectingKeys = [self keyPathsForValuesAffectingContent];
    OBASSERT(self == [OQContentAnimatingLayer class] || [contentAffectingKeys count] > 0); // Why are you subclassing and not providing any keys?
    
    for (NSString *key in contentAffectingKeys) {
        if (ActionSelectorForKey(key) == sel) {
            // Clone a default behavior over to this key.
            Method m = class_getInstanceMethod(self, @selector(basicAnimationForKey:));
            class_addMethod(self, sel, method_getImplementation(m), method_getTypeEncoding(m));
            return YES;
        }
    }
    
    return [super resolveInstanceMethod:sel];
}

#pragma mark CALayer subclass

+ (BOOL)needsDisplayForKey:(NSString *)key;
{
    if ([[self keyPathsForValuesAffectingContent] member:key])
        return YES;
    return [super needsDisplayForKey:key];
}

- (id <CAAction>)actionForKey:(NSString *)event;
{
    SEL sel = ActionSelectorForKey(event);
    if ([self respondsToSelector:sel])
        return objc_msgSend(self, sel, event); // NOTE that we pass the event here. This will be an extra hidden argument to -actionFor<Key> but will be used by the default -basicAnimationForKey:.
    return [super actionForKey:event];
}

- (void)addAnimation:(CAAnimation *)anim forKey:(NSString *)key;
{
    if ([self isContentAnimation:anim]) {
        // Sadly, even though we set it, removedOnCompletion seems to do nothing (and we can't really depend on subclasses remembering to do this), so keep track of the active animations here.

        // The current CALayer doesn't set the toValue either.  When we get here, luckily, it has already been set on ourselves (and we've already captured the fromValue in -basicAnimationForKey:).
        if ([anim isKindOfClass:[CABasicAnimation class]]) {
            CABasicAnimation *basic = (CABasicAnimation *)anim;
            OBASSERT(basic.fromValue); // should have been set already by -basicAnimationForKey: or -actionFor<Key>
            
            id value = [self valueForKey:basic.keyPath];
            basic.toValue = value;
        }

        OBASSERT(anim.delegate == nil);
        anim.delegate = self;
    }
        
    [super addAnimation:anim forKey:key];
}

#pragma mark CAAnimation deleate

- (void)animationDidStart:(CAAnimation *)anim;
{
    // Have to do the add here instead of in -addAnimation:forKey: since a copy is started, not the original passed in.
    if ([self isContentAnimation:anim]) {
        if (!_activeContentAnimations) {
            _activeContentAnimations = [[NSMutableArray alloc] init];
        }
        OBASSERT([_activeContentAnimations indexOfObjectIdenticalTo:anim] == NSNotFound);
        [_activeContentAnimations addObject:anim];
        DEBUG_CONTENT_ANIMATION(@"Started content animation %@.%@ %@..%@ to %@, count %d %g", anim, [(CABasicAnimation *)anim keyPath], [(CABasicAnimation *)anim fromValue], [(CABasicAnimation *)anim toValue], self, [_activeContentAnimations count], anim.duration);
    }
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag;
{
    NSUInteger animIndex = [_activeContentAnimations indexOfObjectIdenticalTo:anim];
    if (animIndex == NSNotFound) {
        OBASSERT_NOT_REACHED("Unknown animation");
        return;
    }
    
    [_activeContentAnimations removeObjectAtIndex:animIndex];
    DEBUG_CONTENT_ANIMATION(@"Stopped content animation %@.%@ from %@, count %d", anim, ((CABasicAnimation *)anim).keyPath, self, [_activeContentAnimations count]);

    if ([_activeContentAnimations count] == 0) {
        // One last display now that things are in the final state
        [self setNeedsDisplay];
        
        [_activeContentAnimations release];
        _activeContentAnimations = nil;
        [self finishedAnimatingContent];
    }
}

#pragma mark KVC

// If animation is disabled, our -actionForKey: won't get called on property changes.
// TODO: This will miss @dynamic property setters like "self.prop = value;".  We don't have a great place to catch this w/o doing it in +resolveInstanceMethod: (and then we need to call super to store the value w/o getting into an infinite loop).
- (void)setValue:(id)value forKey:(NSString *)key;
{
    [super setValue:value forKey:key];	
    
    if ([[CATransaction valueForKey:kCATransactionDisableActions] boolValue] &&
        [[[self class] keyPathsForValuesAffectingContent] member:key] != nil)
        [self setNeedsDisplay];
}

#pragma mark API

- (BOOL)hasContentAnimations;
{
    return [_activeContentAnimations count] > 0;
}

- (BOOL)isContentAnimation:(CAAnimation *)anim;
{
    if (![anim isKindOfClass:[CAPropertyAnimation class]])
        return NO;
    
    // Will be fater if subclass +keyPathsForValuesAffectingContent don't autorelease each time we call them.  Better way to do this?
    CAPropertyAnimation *prop = (CAPropertyAnimation *)anim;
    return [[[self class] keyPathsForValuesAffectingContent] member:[prop keyPath]] != nil;
}

- (void)finishedAnimatingContent;
{
    // For subclasses
}

- (CABasicAnimation *)basicAnimationForKey:(NSString *)key;
{
    CABasicAnimation *basic = [CABasicAnimation animationWithKeyPath:key];

    CALayer *presentation = self.presentationLayer;
    
    // without this set, when our timer fires, the presentation layer won't report any changes.  Bug in CA, I hear.
    if (presentation)
        basic.fromValue = [presentation valueForKey:key];
    else
        basic.fromValue = [self valueForKey:key];
    basic.fillMode = kCAFillModeBoth;
    OBASSERT(basic.fromValue);
    
    return basic;
}

@end
