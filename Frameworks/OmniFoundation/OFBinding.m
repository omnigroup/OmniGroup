// Copyright 2004-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFBinding.h>

#import <OmniFoundation/OFNull.h> // For OFISEQUAL()

//#define DEBUG_KVO 1

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OFBinding.m 102862 2008-07-15 05:14:37Z bungi $");

@interface OFBinding (Private)
- (void)_register;
- (void)_deregister;
@end

@implementation OFBinding

+ (id)allocWithZone:(NSZone *)zone;
{
    OBPRECONDITION((self == [OFBinding class]) || (self == [OFObjectBinding class]) || (self == [OFArrayBinding class]) || (self == [OFSetBinding class]));
    if (self == [OFBinding class])
	return [OFObjectBinding allocWithZone:zone];
    return [super allocWithZone:zone];
}

- initWithSourceObject:(id)sourceObject sourceKey:(NSString *)sourceKey
     destinationObject:(id)destinationObject destinationKey:(NSString *)destinationKey;
{
    OBPRECONDITION(sourceObject);
    OBPRECONDITION(sourceKey);
    OBPRECONDITION(destinationObject);
    OBPRECONDITION(destinationKey);
    
    _sourceObject = [sourceObject retain];
    _sourceKey = [sourceKey copy];
    _nonretained_destinationObject = destinationObject;
    _destinationKey = [destinationKey copy];
    
    [self enable];
    
    // Caller is responsible for setting up the initial value
    
    OBPOSTCONDITION([self isEnabled]);
    return self;
}

- initWithSourcePoint:(OFBindingPoint)sourcePoint destinationPoint:(OFBindingPoint)destinationPoint;
{
    return [self initWithSourceObject:sourcePoint.object sourceKey:sourcePoint.key destinationObject:destinationPoint.object destinationKey:destinationPoint.key];
}

- (void)dealloc;
{
    [self invalidate];
    [super dealloc];
}

- (void)invalidate;
{
#if DEBUG_KVO
    NSLog(@"binding %p invalidated:%p %@.%@", self, _sourceObject, [_sourceObject shortDescription], [self sourceKey]);
#endif
    
    if (_registered)
        [self _deregister];
    
    if ([_sourceObject respondsToSelector:@selector(bindingWillInvalidate:)])
	[_sourceObject bindingWillInvalidate:self];
    [_sourceObject release];
    _sourceObject = nil;
    
    [_sourceKey release];
    _sourceKey = nil;
    
    [_destinationKey release];
    _destinationKey = nil;
    
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

- (id)sourceObject;
{
    return _sourceObject;
}

- (NSString *)sourceKey;
{
    return _sourceKey;
}

- (id)destinationObject;
{
    return _nonretained_destinationObject;
}

- (NSString *)destinationKey;
{
    return _destinationKey;
}

- (id)currentValue;
{
    return [_sourceObject valueForKey:_sourceKey];
}

- (void)propagateCurrentValue;
{
    [_nonretained_destinationObject setValue:[_sourceObject valueForKey:_sourceKey] forKeyPath:_destinationKey];
}

- (NSString *)humanReadableDescription;
{
    return [_sourceObject humanReadableDescriptionForKey:_sourceKey];
}

- (NSString *)shortHumanReadableDescription;
{
    return [_sourceObject shortHumanReadableDescriptionForKey:_sourceKey];
}

- (BOOL)isEqualConsideringSourceAndKey:(OFBinding *)otherBinding;
{
    return [_sourceObject isEqual:[otherBinding sourceObject]] && [_sourceKey isEqual:[otherBinding sourceKey]];
}

// Use the hash of the key.  This will provide less dispersal of values, but then the source don't need to implement hash.
- (unsigned)hash;
{
    return [_sourceKey hash];
}

#pragma mark -
#pragma mark NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    OBRequestConcreteImplementation(self, _cmd);
}

#pragma mark -
#pragma mark Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    [dict setValue:_sourceObject forKey:@"sourceObject"];
    [dict setValue:_sourceKey forKey:@"sourceKey"];
    [dict setValue:_nonretained_destinationObject forKey:@"destinationObject"];
    [dict setValue:_destinationKey forKey:@"destinationKey"];
    return dict;
}

@end


@implementation OFBinding (Private)

- (NSKeyValueObservingOptions)_options;
{
    // Most need only the new.
    return NSKeyValueObservingOptionNew;
}

- (void)_register;
{
    OBPRECONDITION(_sourceObject);
    OBPRECONDITION(_sourceKey);
    OBPRECONDITION(_destinationKey);
    OBPRECONDITION(_nonretained_destinationObject);
    
    OBPRECONDITION(!_registered);
    if (_registered) // don't double-register if there is a programming error
	return;
    
    
    NSKeyValueObservingOptions options = [self _options];
    [_sourceObject addObserver:self forKeyPath:_sourceKey options:options context:NULL];
    
    _registered = YES;
#if DEBUG_KVO
    NSLog(@"binding %p observing:%@.%@", self, [_sourceObject shortDescription], _sourceKey);
#endif
}

- (void)_deregister;
{
    OBPRECONDITION(_registered);
    if (!_registered) // don't null-deregister if there is a programming error
	return;

    [_sourceObject removeObserver:self forKeyPath:_sourceKey];
    _registered = NO;

#if DEBUG_KVO
    NSLog(@"binding %p ignoring:%p.%@", self, [_sourceObject shortDescription], _sourceKey);
#endif
}

@end

static void _handleSetValue(id sourceObject, NSString *sourceKey, id destinationObject, NSString *destinationKey, NSDictionary *change)
{
    // Possibly faster than looking it up via a key path
    id value = [change objectForKey:NSKeyValueChangeNewKey];

    // Value is NSNull if it is getting set to nil.
    if (OFISNULL(value))
	value = nil;
    
    OBASSERT(OFISEQUAL(value, [sourceObject valueForKeyPath:sourceKey]));
    
    [destinationObject setValue:value forKeyPath:destinationKey];
}

@implementation OFObjectBinding

#pragma mark -
#pragma mark NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    OBPRECONDITION([keyPath isEqualToString:_sourceKey]);
    OBPRECONDITION(object == _sourceObject);
    
#if DEBUG_KVO
    //if (![_sourceObject isKindOfClass:[ODEventPlaybackEventSource class]] && ![_sourceObject isKindOfClass:[ODTimeParametricEventSource class]])
    NSLog(@"binding %p observe %@.%@ -- propagating to %@.%@, change %@", self, [_sourceObject shortDescription], _sourceKey, [_nonretained_destinationObject shortDescription], _destinationKey, change);
#endif
    
    // The destination may cause us to get freed when we notify it.  Our caller doesn't like it when we are dead when we return.
    [[self retain] autorelease];
    
    NSNumber *kind = [change objectForKey:NSKeyValueChangeKindKey];
    switch ((NSKeyValueChange)[kind intValue]) {
	case NSKeyValueChangeSetting: {
	    _handleSetValue(_sourceObject, _sourceKey, _nonretained_destinationObject, _destinationKey, change);
	    break;
	}
	default: {
	    [NSException raise:NSInvalidArgumentException format:@"Don't know how to handle change %@", change];
	}
    }
}

@end

// Ordered to-many properties
@implementation OFArrayBinding

- (NSMutableArray *)mutableValue;
{
    return [_sourceObject mutableArrayValueForKey:_sourceKey];
}

#pragma mark -
#pragma mark NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    OBPRECONDITION([keyPath isEqualToString:_sourceKey]);
    OBPRECONDITION(object == _sourceObject);
    
#if DEBUG_KVO
    //if (![_sourceObject isKindOfClass:[ODEventPlaybackEventSource class]] && ![_sourceObject isKindOfClass:[ODTimeParametricEventSource class]])
    NSLog(@"binding %p observe %@.%@ -- propagating to %@.%@, change %@", self, [_sourceObject shortDescription], _sourceKey, [_nonretained_destinationObject shortDescription], _destinationKey, change);
#endif
    
    // The destination may cause us to get freed when we notify it.  Our caller doesn't like it when we are dead when we return.
    [[self retain] autorelease];
    
    NSNumber *kind = [change objectForKey:NSKeyValueChangeKindKey];
    switch ((NSKeyValueChange)[kind intValue]) {
	case NSKeyValueChangeSetting: {
	    _handleSetValue(_sourceObject, _sourceKey, _nonretained_destinationObject, _destinationKey, change);
	    break;
	}
	case NSKeyValueChangeInsertion: {
	    NSArray *inserted = [change objectForKey:NSKeyValueChangeNewKey];
	    NSIndexSet *indexes = [change objectForKey:NSKeyValueChangeIndexesKey];
	    OBASSERT(inserted);
	    OBASSERT(indexes);
	    OBASSERT([inserted count] == [indexes count]);
	    
            [[_nonretained_destinationObject mutableArrayValueForKey:_destinationKey] insertObjects:inserted atIndexes:indexes];
	    break;
	}
	case NSKeyValueChangeRemoval: {
	    NSIndexSet *indexes = [change objectForKey:NSKeyValueChangeIndexesKey];
	    OBASSERT(indexes);
	    
            [[_nonretained_destinationObject mutableArrayValueForKey:_destinationKey] removeObjectsAtIndexes:indexes];
	    break;
	}
	default: {
	    [NSException raise:NSInvalidArgumentException format:@"Don't know how to handle change %@", change];
	}
    }
}

@end

// Unordered to-many properties
@implementation OFSetBinding

- (NSMutableSet *)mutableValue;
{
    return [_sourceObject mutableSetValueForKey:_sourceKey];
}

- (NSKeyValueObservingOptions)_options;
{
    // We need the 'Old' for the remove case.  Since it doesn't contain indexes, like the array case, we need to know what actuall got removed.
    return NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    OBPRECONDITION([keyPath isEqualToString:_sourceKey]);
    OBPRECONDITION(object == _sourceObject);
    
#if DEBUG_KVO
    //if (![_sourceObject isKindOfClass:[ODEventPlaybackEventSource class]] && ![_sourceObject isKindOfClass:[ODTimeParametricEventSource class]])
    NSLog(@"binding %p observe %@.%@ -- propagating to %@.%@, change %@", self, [_sourceObject shortDescription], _sourceKey, [_nonretained_destinationObject shortDescription], _destinationKey, change);
#endif
    
    // The destination may cause us to get freed when we notify it.  Our caller doesn't like it when we are dead when we return.
    [[self retain] autorelease];
    
    NSNumber *kind = [change objectForKey:NSKeyValueChangeKindKey];
    switch ((NSKeyValueChange)[kind intValue]) {
	case NSKeyValueChangeSetting: {
	    _handleSetValue(_sourceObject, _sourceKey, _nonretained_destinationObject, _destinationKey, change);
	    break;
	}
	case NSKeyValueChangeInsertion: {
	    NSSet *inserted = [change objectForKey:NSKeyValueChangeNewKey];
	    OBASSERT(inserted);
	    OBASSERT([inserted count] > 0);
	    
	    [[_nonretained_destinationObject mutableSetValueForKey:_destinationKey] unionSet:inserted];
	    break;
	}
	case NSKeyValueChangeRemoval: {
	    NSSet *removed = [change objectForKey:NSKeyValueChangeOldKey];
	    OBASSERT(removed);
	    OBASSERT([removed count] > 0);
	    
	    [[_nonretained_destinationObject mutableSetValueForKey:_destinationKey] minusSet:removed];
	    break;
	}
        case NSKeyValueChangeReplacement: {
            // See test case at <svn+ssh://source.omnigroup.com/Source/svn/Omni/trunk/Staff/bungi/Radar/SetSetBindingTest>.
            // The meaning of this enum isn't totally clear from the documentation.  Empirically this test shows that this change means to remove the old set and add the new; doing a subset replacement, but the documenation is vague enough that in the past I've had differing interpretations.
	    NSSet *removed = [change objectForKey:NSKeyValueChangeOldKey];
	    NSSet *inserted = [change objectForKey:NSKeyValueChangeNewKey];

            OBASSERT(![removed intersectsSet:inserted]); // If these intersect, then we'll publish a remove of some objects followed by an add; better for the object to not be in the sets at all.
            
            NSMutableSet *proxy = [_nonretained_destinationObject mutableSetValueForKey:_destinationKey];
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
}

@end

// Directly modifies the set, publishing KVO changes
// Computes the delta operations necessary to transition to the new set.  NSController has a bug where whole-property replacement doesn't send the right KVO, so this can be a workaround for that problem, as well as possibly being more efficient.
void OFSetMutableSet(id self, NSString *key, NSMutableSet *ivar, NSSet *set)
{
    OBPRECONDITION(self);
    OBPRECONDITION(key);
    OBPRECONDITION(ivar);
    OBPRECONDITION(set);
    
    // Add everything in the new set that we don't already have
    NSMutableSet *toAdd = [NSMutableSet setWithSet:set];
    [toAdd minusSet:ivar];
    
    // Remove everything in the existing set that isn't in the new one
    NSMutableSet *toRemove = [NSMutableSet setWithSet:ivar];
    [toRemove minusSet:set];
    
    // Do the add first; this will prevent the target set from being empty temporarily, which is important for cases where that has special meaning.  If we need the opposite, an argument must be added to this function or a new function added to allow the caller to specify what they want.
    if ([toAdd count] > 0) {
        [self willChangeValueForKey:key withSetMutation:NSKeyValueUnionSetMutation usingObjects:toAdd];
        [ivar unionSet:toAdd];
        [self didChangeValueForKey:key withSetMutation:NSKeyValueUnionSetMutation usingObjects:toAdd];
    }
    
    if ([toRemove count] > 0) {
        [self willChangeValueForKey:key withSetMutation:NSKeyValueMinusSetMutation usingObjects:toRemove];
        [ivar minusSet:toRemove];
        [self didChangeValueForKey:key withSetMutation:NSKeyValueMinusSetMutation usingObjects:toRemove];
    }
}

// Modifies the set by calling the KVO proxy methods, depending on those to send KVO.  Useful if you've implemented -{add,remove}Foos:
void OFSetMutableSetByProxy(id self, NSString *key, NSSet *ivar, NSSet *set)
{
    OBPRECONDITION(self);
    OBPRECONDITION(key);
    OBPRECONDITION(ivar);
    //OBPRECONDITION(set);
    
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
