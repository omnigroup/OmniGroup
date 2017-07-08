// Copyright 2004-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBinding.h>

#import <OmniFoundation/OFBindingPoint.h>
#import <OmniFoundation/OFNull.h> // For OFISEQUAL()
#import <OmniBase/OBObject.h>
#import <OmniBase/macros.h>

//#define DEBUG_KVO 1

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

OBDEPRECATED_METHOD(-humanReadableDescriptionForKey:); // Use the key path variant
OBDEPRECATED_METHOD(-shortHumanReadableDescriptionForKey:);

static unsigned int _OFBindingObservationContext; 

@interface OFBinding () {
  @protected
    unsigned int _enabledCount;
    BOOL _registered;
    id        _sourceObject;
    NSString *_sourceKeyPath;
    id        _nonretained_destinationObject; // We assume the destantion owns us
    NSString *_destinationKeyPath;
}

- (void)_register;
- (void)_deregister;

@end

#pragma mark -

@implementation OFBinding

+ (id)allocWithZone:(NSZone *)zone;
{
    if (self == [OFBinding class])
	return [OFObjectBinding allocWithZone:zone];
    return [super allocWithZone:zone];
}

- (instancetype)init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (instancetype)initWithSourceObject:(id)sourceObject sourceKeyPath:(NSString *)sourceKeyPath
                   destinationObject:(id)destinationObject destinationKeyPath:(NSString *)destinationKeyPath;
{
    OBPRECONDITION(sourceObject);
    OBPRECONDITION(sourceKeyPath);
    OBPRECONDITION(destinationObject);
    OBPRECONDITION(destinationKeyPath);

    if (!(self = [super init]))
        return nil;

    _sourceObject = [sourceObject retain];
    _sourceKeyPath = [sourceKeyPath copy];
    _nonretained_destinationObject = destinationObject;
    _destinationKeyPath = [destinationKeyPath copy];
    
    [self enable];
    
    // Caller is responsible for setting up the initial value
    
    OBPOSTCONDITION([self isEnabled]);
    return self;
}

- (instancetype)initWithSourcePoint:(OFBindingPoint *)sourcePoint destinationPoint:(OFBindingPoint *)destinationPoint;
{
    return [self initWithSourceObject:sourcePoint.object sourceKeyPath:sourcePoint.keyPath destinationObject:destinationPoint.object destinationKeyPath:destinationPoint.keyPath];
}

- (void)dealloc;
{
    [self invalidate];
    [super dealloc];
}

- (void)invalidate;
{
#if DEBUG_KVO
    NSLog(@"binding %p invalidated:%p %@.%@", self, _sourceObject, [_sourceObject shortDescription], [self sourceKeyPath]);
#endif
    
    if (_registered)
        [self _deregister];
    
    if ([_sourceObject respondsToSelector:@selector(bindingWillInvalidate:)])
	[_sourceObject bindingWillInvalidate:self];
    [_sourceObject release];
    _sourceObject = nil;
    
    [_sourceKeyPath release];
    _sourceKeyPath = nil;
    
    [_destinationKeyPath release];
    _destinationKeyPath = nil;
    
    _nonretained_destinationObject = nil;
}

- (BOOL)isEnabled;
{
    return _enabledCount > 0;
}

- (void)enable;
{
    BOOL wasEnabled = [self isEnabled];
    _enabledCount++;
    BOOL newEnabled = [self isEnabled];
    if (!wasEnabled && newEnabled)
	[self _register];
}

- (void)disable;
{
    OBPRECONDITION(_enabledCount > 0);

    BOOL wasEnabled = [self isEnabled];
    _enabledCount--;
    BOOL newEnabled = [self isEnabled];
    if (wasEnabled && !newEnabled)
	[self _deregister];
}

- (void)reset;
{
    [_sourceObject reset];
}

- (OFBindingPoint *)sourcePoint;
{
    return OFBindingPointMake(_sourceObject, _sourceKeyPath);
}

- (id)sourceObject;
{
    return _sourceObject;
}

- (NSString *)sourceKeyPath;
{
    return _sourceKeyPath;
}

- (OFBindingPoint *)destinationPoint;
{
    return OFBindingPointMake(_nonretained_destinationObject, _destinationKeyPath);
}

- (id)destinationObject;
{
    return _nonretained_destinationObject;
}

- (NSString *)destinationKeyPath;
{
    return _destinationKeyPath;
}

- (id)currentValue;
{
    return [_sourceObject valueForKeyPath:_sourceKeyPath];
}

- (void)propagateCurrentValue;
{
    [_nonretained_destinationObject setValue:[_sourceObject valueForKeyPath:_sourceKeyPath] forKeyPath:_destinationKeyPath];
}

- (NSString *)humanReadableDescription;
{
    return [_sourceObject humanReadableDescriptionForKeyPath:_sourceKeyPath];
}

- (NSString *)shortHumanReadableDescription;
{
    return [_sourceObject shortHumanReadableDescriptionForKeyPath:_sourceKeyPath];
}

- (BOOL)isEqualConsideringSourceAndKeyPath:(OFBinding *)otherBinding;
{
    return [_sourceObject isEqual:[otherBinding sourceObject]] && [_sourceKeyPath isEqual:[otherBinding sourceKeyPath]];
}

// Use the hash of the key.  This will provide less dispersal of values, but then the source don't need to implement hash.
- (NSUInteger)hash;
{
    return [_sourceKeyPath hash];
}

#pragma mark -
#pragma mark NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change context:(nullable void *)context;
{
    if (context == &_OFBindingObservationContext) {
        OBRequestConcreteImplementation(self, _cmd);
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark -
#pragma mark Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setValue:_sourceObject forKey:@"sourceObject"];
    [dict setValue:_sourceKeyPath forKey:@"sourceKeyPath"];
    [dict setValue:_nonretained_destinationObject forKey:@"destinationObject"];
    [dict setValue:_destinationKeyPath forKey:@"destinationKeyPath"];
    return dict;
}

#pragma mark -
#pragma mark Private

- (NSKeyValueObservingOptions)_options;
{
    // Most need only the new.
    return NSKeyValueObservingOptionNew;
}

- (void)_register;
{
    OBPRECONDITION(_sourceObject);
    OBPRECONDITION(_sourceKeyPath);
    OBPRECONDITION(_destinationKeyPath);
    OBPRECONDITION(_nonretained_destinationObject);
    
    OBPRECONDITION(!_registered);
    if (_registered) // don't double-register if there is a programming error
	return;
    
    
    NSKeyValueObservingOptions options = [self _options];
    [_sourceObject addObserver:self forKeyPath:_sourceKeyPath options:options context:&_OFBindingObservationContext];
    
    _registered = YES;
#if DEBUG_KVO
    NSLog(@"binding %p observing:%@.%@ options:0x%x", self, [_sourceObject shortDescription], _sourceKeyPath, options);
#endif
}

- (void)_deregister;
{
    OBPRECONDITION(_registered);
    if (!_registered) // don't null-deregister if there is a programming error
	return;

    [_sourceObject removeObserver:self forKeyPath:_sourceKeyPath context:&_OFBindingObservationContext];
    _registered = NO;

#if DEBUG_KVO
    NSLog(@"binding %p ignoring:%p.%@", self, [_sourceObject shortDescription], _sourceKeyPath);
#endif
}

@end

static void _handleSetValue(id sourceObject, NSString *sourceKeyPath, id destinationObject, NSString *destinationKeyPath, NSDictionary *change)
{
    // Possibly faster than looking it up via a key path
    id value = [change objectForKey:NSKeyValueChangeNewKey];

    // Value is NSNull if it is getting set to nil.
    if (OFISNULL(value))
	value = nil;
    
    OBASSERT(OFISEQUAL(value, [sourceObject valueForKeyPath:sourceKeyPath]));
    
    [destinationObject setValue:value forKeyPath:destinationKeyPath];
}

@implementation OFObjectBinding

#pragma mark -
#pragma mark NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change context:(nullable void *)context;
{
    if (context == &_OFBindingObservationContext) {
        OBPRECONDITION([keyPath isEqualToString:_sourceKeyPath]);
        OBPRECONDITION(object == _sourceObject);
        
#if DEBUG_KVO
        //if (![_sourceObject isKindOfClass:[ODEventPlaybackEventSource class]] && ![_sourceObject isKindOfClass:[ODTimeParametricEventSource class]])
        NSLog(@"binding %p observe %@.%@ -- propagating to %@.%@, change %@", self, [_sourceObject shortDescription], _sourceKeyPath, [_nonretained_destinationObject shortDescription], _destinationKeyPath, change);
#endif
        
        // The destination may cause us to get freed when we notify it.  Our caller doesn't like it when we are dead when we return.
        OBRetainAutorelease(self);
        
        NSNumber *kind = [change objectForKey:NSKeyValueChangeKindKey];
        switch ((NSKeyValueChange)[kind intValue]) {
            case NSKeyValueChangeSetting: {
                _handleSetValue(_sourceObject, _sourceKeyPath, _nonretained_destinationObject, _destinationKeyPath, change);
                break;
            }
            default: {
                [NSException raise:NSInvalidArgumentException format:@"Don't know how to handle change %@", change];
            }
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end

// Ordered to-many properties
@implementation OFArrayBinding

- (NSMutableArray *)mutableValue;
{
    return [_sourceObject mutableArrayValueForKeyPath:_sourceKeyPath];
}

#pragma mark -
#pragma mark NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change context:(nullable void *)context;
{
    if (context == &_OFBindingObservationContext) {
        OBPRECONDITION([keyPath isEqualToString:_sourceKeyPath]);
        OBPRECONDITION(object == _sourceObject);
        
#if DEBUG_KVO
        //if (![_sourceObject isKindOfClass:[ODEventPlaybackEventSource class]] && ![_sourceObject isKindOfClass:[ODTimeParametricEventSource class]])
        NSLog(@"binding %p observe %@.%@ -- propagating to %@.%@, change %@", self, [_sourceObject shortDescription], _sourceKey, [_nonretained_destinationObject shortDescription], _destinationKeyPath, change);
#endif
        
        // The destination may cause us to get freed when we notify it.  Our caller doesn't like it when we are dead when we return.
        OBRetainAutorelease(self);
        
        NSNumber *kind = [change objectForKey:NSKeyValueChangeKindKey];
        switch ((NSKeyValueChange)[kind intValue]) {
            case NSKeyValueChangeSetting: {
                _handleSetValue(_sourceObject, _sourceKeyPath, _nonretained_destinationObject, _destinationKeyPath, change);
                break;
            }
            case NSKeyValueChangeInsertion: {
                NSArray *inserted = [change objectForKey:NSKeyValueChangeNewKey];
                NSIndexSet *indexes = [change objectForKey:NSKeyValueChangeIndexesKey];
                OBASSERT(inserted);
                OBASSERT(indexes);
                OBASSERT([inserted count] == [indexes count]);
                
                [[_nonretained_destinationObject mutableArrayValueForKeyPath:_destinationKeyPath] insertObjects:inserted atIndexes:indexes];
                break;
            }
            case NSKeyValueChangeRemoval: {
                NSIndexSet *indexes = [change objectForKey:NSKeyValueChangeIndexesKey];
                OBASSERT(indexes);
                
                [[_nonretained_destinationObject mutableArrayValueForKeyPath:_destinationKeyPath] removeObjectsAtIndexes:indexes];
                break;
            }
            default: {
                [NSException raise:NSInvalidArgumentException format:@"Don't know how to handle change %@", change];
            }
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end

// Unordered to-many properties
@implementation OFSetBinding

- (NSMutableSet *)mutableValue;
{
    return [_sourceObject mutableSetValueForKeyPath:_sourceKeyPath];
}

- (NSKeyValueObservingOptions)_options;
{
    // We need the 'Old' for the remove case.  Since it doesn't contain indexes, like the array case, we need to know what actuall got removed.
    return NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld;
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey, id> *)change context:(nullable void *)context;
{
    if (context == &_OFBindingObservationContext) {
        OBPRECONDITION([keyPath isEqualToString:_sourceKeyPath]);
        OBPRECONDITION(object == _sourceObject);
        
#if DEBUG_KVO
        //if (![_sourceObject isKindOfClass:[ODEventPlaybackEventSource class]] && ![_sourceObject isKindOfClass:[ODTimeParametricEventSource class]])
        NSLog(@"binding %p observe %@.%@ -- propagating to %@.%@, change %@", self, [_sourceObject shortDescription], _sourceKey, [_nonretained_destinationObject shortDescription], _destinationKeyPath, change);
#endif
        
        // The destination may cause us to get freed when we notify it.  Our caller doesn't like it when we are dead when we return.
        OBRetainAutorelease(self);
        
        NSNumber *kind = [change objectForKey:NSKeyValueChangeKindKey];
        switch ((NSKeyValueChange)[kind intValue]) {
            case NSKeyValueChangeSetting: {
                _handleSetValue(_sourceObject, _sourceKeyPath, _nonretained_destinationObject, _destinationKeyPath, change);
                break;
            }
            case NSKeyValueChangeInsertion: {
                NSSet *inserted = [change objectForKey:NSKeyValueChangeNewKey];
                OBASSERT(inserted);
                OBASSERT([inserted count] > 0);
                
                [[_nonretained_destinationObject mutableSetValueForKeyPath:_destinationKeyPath] unionSet:inserted];
                break;
            }
            case NSKeyValueChangeRemoval: {
                NSSet *removed = [change objectForKey:NSKeyValueChangeOldKey];
                OBASSERT(removed);
                OBASSERT([removed count] > 0);
                
                [[_nonretained_destinationObject mutableSetValueForKeyPath:_destinationKeyPath] minusSet:removed];
                break;
            }
            case NSKeyValueChangeReplacement: {
                // See test case at <svn+ssh://source.omnigroup.com/Source/svn/Omni/trunk/Staff/bungi/Radar/SetSetBindingTest>.
                // The meaning of this enum isn't totally clear from the documentation.  Empirically this test shows that this change means to remove the old set and add the new; doing a subset replacement, but the documenation is vague enough that in the past I've had differing interpretations.
                NSSet *removed = [change objectForKey:NSKeyValueChangeOldKey];
                NSSet *inserted = [change objectForKey:NSKeyValueChangeNewKey];
                
                OBASSERT(![removed intersectsSet:inserted]); // If these intersect, then we'll publish a remove of some objects followed by an add; better for the object to not be in the sets at all.
                
                NSMutableSet *proxy = [_nonretained_destinationObject mutableSetValueForKeyPath:_destinationKeyPath];
                if ([removed count] > 0)
                    [proxy minusSet:removed];
                if ([inserted count] > 0)
                    [proxy unionSet:inserted];
                break;
            }
                
            default: {
                [NSException raise:NSInvalidArgumentException format:@"Don't know how to handle change %@", change];
            }
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end

NSString *OFKeyPathForKeys(NSString *firstKey, ...)
{
    OBPRECONDITION(firstKey != nil);
    
    if (firstKey == nil)
        return (NSString * _Nonnull)nil;
    
    NSMutableString *keyPath = [NSMutableString stringWithString:firstKey];
    
    NSString *nextKey;
    va_list argList;
    
    va_start(argList, firstKey);
    while ((nextKey = va_arg(argList, id)) != nil) {
        [keyPath appendString:@"."];
        [keyPath appendString:nextKey];
    }
    va_end(argList);
    
    return keyPath;
}

NSArray *OFKeysForKeyPath(NSString *keyPath)
{
    return [keyPath componentsSeparatedByString:@"."];
}

NSArray *OFPrefixedKeyPaths(NSString *prefixKey, NSArray *keyPaths)
{
    OBPRECONDITION(prefixKey != nil);
    
    if (prefixKey == nil)
        return [[keyPaths copy] autorelease];
    
    NSArray *result = [keyPaths arrayByPerformingBlock:^id(id obj) {
        NSString *keyPath = OB_CHECKED_CAST(NSString, obj);
        NSMutableString *prefixedKeyPath = [prefixKey mutableCopy];
        [prefixedKeyPath appendString:@"."];
        [prefixedKeyPath appendString:keyPath];
        return [prefixedKeyPath autorelease];
    }];
    
    return result;
}

// Directly modifies the set, publishing KVO changes
// Computes the delta operations necessary to transition to the new set.  NSController has a bug where whole-property replacement doesn't send the right KVO, so this can be a workaround for that problem, as well as possibly being more efficient.

static void _OFSetMutableSet(id self, NSString *key, OB_STRONG NSMutableSet * _Nonnull * _Nonnull ivar, NSSet *set, BOOL processRemovalsFirst) {

    OBPRECONDITION(self);
    OBPRECONDITION(key);
    OBPRECONDITION(ivar); // Allow it to point to nil since we can fill in the set.
    OBPRECONDITION(set);
    OBPRECONDITION(key && [key rangeOfString:@"."].length == 0); // Not a path

    if (!ivar)
        [NSException raise:NSInvalidArgumentException format:@"Must pass a non-NULL ivar pointer to %s.", __PRETTY_FUNCTION__];

    // If the two sets are disjoint, it'll be just as fast and maybe faster to do a single set.
    // A NSKeyValueSetSetMutation change would send a NSKeyValueChangeReplacement change, with the old and new values but without any way of knowing it was a complete replacement (we don't want to read the destination in OFSetBinding).  So, we take a pointer to a set and do NSKeyValueChangeSetting.
    if (![*ivar intersectsSet:set]) {
        [self willChangeValueForKey:key];
#if OB_ARC
        *ivar = [[NSMutableSet alloc] initWithSet:set];
#else
        [*ivar release];
        *ivar = [[NSMutableSet alloc] initWithSet:set];
#endif
        [self didChangeValueForKey:key];
        return;
    }

    NSMutableSet *ivarValue = *ivar;

    // Add everything in the new set that we don't already have
    NSMutableSet *toAdd = [NSMutableSet setWithSet:set];
    [toAdd minusSet:ivarValue];

    // Remove everything in the existing set that isn't in the new one
    NSMutableSet *toRemove = [NSMutableSet setWithSet:ivarValue];
    [toRemove minusSet:set];

    void(^processAdds)(void) = ^(void) {

        if ([toAdd count] > 0) {
            [self willChangeValueForKey:key withSetMutation:NSKeyValueUnionSetMutation usingObjects:toAdd];
            [ivarValue unionSet:toAdd];
            [self didChangeValueForKey:key withSetMutation:NSKeyValueUnionSetMutation usingObjects:toAdd];
        }
    };

    void(^processRemovals)(void) = ^(void) {

        if ([toRemove count] > 0) {
            [self willChangeValueForKey:key withSetMutation:NSKeyValueMinusSetMutation usingObjects:toRemove];
            [ivarValue minusSet:toRemove];
            [self didChangeValueForKey:key withSetMutation:NSKeyValueMinusSetMutation usingObjects:toRemove];
        }
    };

    // Most of the time, processRemovalsFirst will be NO -- processing insertions first will prevent the target set from being empty temporarily, which is important for cases where that has special meaning.

    if (processRemovalsFirst) {
        processRemovals();
        processAdds();
    } else {
        processAdds();
        processRemovals();
    }
}

void OFSetMutableSet(id self, NSString *key, OB_STRONG NSMutableSet * _Nonnull * _Nonnull ivar, NSSet *set)
{
    _OFSetMutableSet(self, key, ivar, set, NO);
}

void OFSetMutableSetProcessingRemovalsFirst(id self, NSString *key, OB_STRONG NSMutableSet * _Nonnull * _Nonnull ivar, NSSet *set)
{
    _OFSetMutableSet(self, key, ivar, set, YES);
}


// Modifies the set by calling the KVO proxy methods, depending on those to send KVO.  Useful if you've implemented -{add,remove}Foos:
void OFSetMutableSetByProxy(id self, NSString *key, NSSet *ivar, NSSet *set)
{
    OBPRECONDITION(self);
    OBPRECONDITION(key);
    OBPRECONDITION(ivar);
    //OBPRECONDITION(set);
    OBPRECONDITION(key && [key rangeOfString:@"."].length == 0); // Not a path, though we could support it here.
    
    // Add everything in the new set that we don't already have
    NSMutableSet *toAdd = [NSMutableSet setWithSet:set];
    [toAdd minusSet:ivar];
    
    // Remove everything in the existing set that isn't in the new one
    NSMutableSet *toRemove = [NSMutableSet setWithSet:ivar];
    [toRemove minusSet:set];
    
    // Do the add first; this will prevent the target set from being empty temporarily, which is important for cases where that has special meaning.  If we need the opposite, an argument must be added to this function or a new function added to allow the caller to specify what they want.
    if ([toAdd count] > 0)
        [[self mutableSetValueForKey:key] unionSet:toAdd];
    
    if ([toRemove count] > 0)
        [[self mutableSetValueForKey:key] minusSet:toRemove];
}

NS_ASSUME_NONNULL_END
