// Copyright 2001-2008, 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFPreference.h>

#import <OmniBase/OBObject.h> // For -shortDescription
#import <OmniFoundation/OFEnumNameTable.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/NSDate-OFExtensions.h> // For -initWithXMLString:

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniFoundation/NSUserDefaults-OFExtensions.h>
#import <Foundation/NSScriptCommand.h>
#import <Foundation/NSScriptObjectSpecifiers.h>
#endif

#import <Foundation/Foundation.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

//#define DEBUG_PREFERENCES

static NSUserDefaults *standardUserDefaults;
static NSMutableDictionary *preferencesByKey;
static NSLock *preferencesLock;
static NSSet *registeredKeysCache;
static NSObject *unset = nil;
static volatile unsigned registrationGeneration = 1;
static NSNotificationCenter *preferenceNotificationCenter = nil;

NSString * const OFPreferenceObjectValueBinding = @"objectValue";
NSString * const OFPreferenceDidChangeNotification = @"OFPreferenceDidChangeNotification";

@interface OFPreference ()
{
@protected
    // OFEnumeratedPreference references these
    NSString *_key;
    id _value;
}
@end

@interface OFEnumeratedPreference : OFPreference
{
    OFEnumNameTable *names;
}

- (id)_initWithKey:(NSString * )key enumeration:(OFEnumNameTable *)enumeration;

@end

@implementation OFPreference
{
    unsigned _generation;
    id _defaultValue;
    
    id _controller;
    NSString *_controllerKey;
    BOOL _updatingController;
}

static id _retainedObjectValue(OFPreference *self, id const *_value, NSString *key)
{
    id result = nil;

    @synchronized(self) {
        if (self->_generation != registrationGeneration)
            result = [unset retain];
        else
            result = [*_value retain];
    }
    
    if (result == unset) {
        [result release];
        [self _refresh];
        return _retainedObjectValue(self, _value, key); // gcc does tail-call optimization
    }

#ifdef DEBUG_PREFERENCES
    NSLog(@"OFPreference(0x%08x:%@) -> %@", self, key, result);
#endif

    return result;
}

static inline id _objectValue(OFPreference *self, id const *_value, NSString *key, NSString *className)
{
    id result = [_retainedObjectValue(self, _value, key) autorelease];

    // We use a class name rather than a class to avoid calling +class when assertions are off
    OBASSERT(!result || [result isKindOfClass: NSClassFromString(className)]);

    return result;
}

static void _setValueUnderlyingValue(OFPreference *self, id controller, NSString *keyPath, NSString *key, id value)
{
    if (self->_updatingController)
        controller = nil;
    
    BOOL setUpdating = (controller && !self->_updatingController);
    if (setUpdating)
        self->_updatingController = YES;
    
    [self willChangeValueForKey:OFPreferenceObjectValueBinding];
    
    @try {
        if (value) {
            [standardUserDefaults setObject:value forKey:key];
            if (controller)
                [controller setValue:value forKeyPath:keyPath];
        } else {
            [standardUserDefaults removeObjectForKey:key];
            if (controller)
                [controller setValue:nil forKeyPath:keyPath];
        }
    } @finally {
        [self didChangeValueForKey:OFPreferenceObjectValueBinding];

        if (setUpdating)
            self->_updatingController = NO;
    }
}

static void _setValue(OFPreference *self, OB_STRONG id *_value, NSString *key, id value)
{
    @synchronized(self) {
        // If this preference is created & used by a OAPreferenceClient, or other NSController, use KVC on the controller to set the preference so that other observers of the controller will get notified via KVO.
        // This introduces an(other?) ugly bit, though.  Our OAPreferenceClient instances each use a OFPreferenceWrapper.  This creates a feedback loop on setting in some cases (particularly clearing to a default value).  So, we have _updatingController to record whether we are getting called recursively.
        NSString *keyPath;
        id controller = self->_controller;
        NSString *controllerKey = self->_controllerKey;
        
        if (controller) {
            if (controllerKey)
                keyPath = [NSString stringWithFormat:@"%@.%@", controllerKey, key];
            else
                keyPath = key;
        } else {
            // Won't be used anyway
            keyPath = nil;
        }

        if (value) {
            [value retain];
            [*_value release];
            *_value = value;
            
            _setValueUnderlyingValue(self, controller, keyPath, key, value);
#ifdef DEBUG_PREFERENCES
            NSLog(@"OFPreference(0x%08x:%@) <- %@", self, key, *_value);
#endif
        } else {
            _setValueUnderlyingValue(self, controller, keyPath, key, value);
            
            // Get the new value exposed by removing this from the user default domain
            [*_value release];
            *_value = [unset retain];

#ifdef DEBUG_PREFERENCES
            NSLog(@"OFPreference(0x%08x:%@) <- nil (is now %@)", self, key, *_value);
#endif
        }
    }
    
    // Tell anyone who is interested that this default changed
    [preferenceNotificationCenter postNotificationName:OFPreferenceDidChangeNotification object:self];
}

+ (void) initialize;
{
    OBINITIALIZE;
    
    standardUserDefaults = [[NSUserDefaults standardUserDefaults] retain];
    [standardUserDefaults volatileDomainForName:NSRegistrationDomain]; // avoid a race condition
    preferencesByKey = [[NSMutableDictionary alloc] init];
    preferencesLock = [[NSLock alloc] init];
    unset = [[NSObject alloc] init];  // just getting a guaranteed-unique, retainable/releasable object
    
    preferenceNotificationCenter = [[NSNotificationCenter alloc] init];
}

+ (NSSet *)registeredKeys
{
    NSSet *result;

    [preferencesLock lock];

    if (registeredKeysCache == nil) {
        NSMutableSet *keys = [[NSMutableSet alloc] init];
        [keys addObjectsFromArray:[preferencesByKey allKeys]];
        [keys addObjectsFromArray:[[standardUserDefaults volatileDomainForName:NSRegistrationDomain] allKeys]];
        registeredKeysCache = [keys copy];
        [keys release];
    }

    result = [registeredKeysCache retain];

    [preferencesLock unlock];

    return [result autorelease];
}

+ (void)recacheRegisteredKeys
{
    [preferencesLock lock];
    [registeredKeysCache release];
    registeredKeysCache = nil;
    registrationGeneration ++;
    [preferencesLock unlock];
}

+ (void)addObserver:(id)anObserver selector:(SEL)aSelector forPreference:(OFPreference *)aPreference;
{
    [preferenceNotificationCenter addObserver:anObserver selector:aSelector name:OFPreferenceDidChangeNotification object:aPreference];
}

+ (void)removeObserver:(id)anObserver forPreference:(OFPreference *)aPreference;
{
    [preferenceNotificationCenter removeObserver:anObserver name:OFPreferenceDidChangeNotification object:aPreference];
}

+ (id)coerceStringValue:(NSString *)stringValue toTypeOfPropertyListValue:(id)propertyListValue;
{
    if (stringValue == nil || [stringValue isNull]) { // null
        return [NSNull null];
    } else if ([propertyListValue isKindOfClass:[NSString class]]) { // <string>
        return stringValue;
    } else if ([propertyListValue isKindOfClass:[NSNumber class]]) { // <real> or <integer> or <true/> or <false/>
        const char *objCType = [(NSNumber *)propertyListValue objCType];
        if (strcmp(objCType, @encode(int)) == 0) // <integer>
            return [NSNumber numberWithInt:[stringValue intValue]];
        else if (strcmp(objCType, @encode(double)) == 0) // <real>
            return [NSNumber numberWithDouble:[stringValue doubleValue]];
        else if (strcmp(objCType, @encode(char)) == 0) // <true/> or <false/>
            return [NSNumber numberWithBool:[stringValue boolValue]];
        else {
            OBASSERT((strcmp(objCType, @encode(double)) == 0)); // ??? What is this new property list type?
            return [NSNumber numberWithDouble:[stringValue doubleValue]];
        }
    } else if ([propertyListValue isKindOfClass:[NSDate class]]) { // <date>
        return [[[NSDate alloc] initWithXMLString:stringValue] autorelease];
    } else if ([propertyListValue isKindOfClass:[NSData class]]) { // <data> (not yet implemented)
        OBASSERT(![propertyListValue isKindOfClass:[NSData class]]);
        NSLog(@"+[OFPreference coerceStringValue:toTypeOfPropertyListValue: unimplemented conversion to NSData");
        return nil;
    } else if ([propertyListValue isKindOfClass:[NSArray class]] || [propertyListValue isKindOfClass:[NSDictionary class]]) { // <array> or <dict>
        return [stringValue propertyList];
    }
    return nil;
}

// OFPreference instances must be uniqued, so you should always go through +preferenceForKey:
- init;
{
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
    NSScriptCommand *command = [NSScriptCommand currentCommand];
    if (command) {
        // Some one doing 'make new' in a script; don't crash but log an error
        [command setScriptErrorNumber:NSReceiversCantHandleCommandScriptError];
        [command setScriptErrorString:@"Preferences cannot be defined by scripts."];
        
        [self release];
        return nil;
    }
#endif

    OBRejectUnusedImplementation(self, _cmd);
}

- (void)dealloc;
{
    // Instances are currently held onto forever, so we shouldn't hit this.
    OBPRECONDITION(NO);
    
    [_key release];
    [_value release];
    [_defaultValue release];
    [_controller release];
    [_controllerKey release];
    [super dealloc];
}

// Subclass methods

- (NSUInteger) hash;
{
    return [_key hash];
}

- (BOOL) isEqual: (id) otherPreference;
{
    return [_key isEqual: [otherPreference key]];
}

#pragma mark API

+ (OFPreference *) preferenceForKey: (NSString *) key;
{
    return [self preferenceForKey:key enumeration:nil];
}

+ (OFPreference *) preferenceForKey: (NSString *) key enumeration: (OFEnumNameTable *)enumeration;
{
    OFPreference *preference;
    
    OBPRECONDITION(key);
    
    [preferencesLock lock];
    preference = [[preferencesByKey objectForKey: key] retain];
    if (!preference) {
        if (enumeration == nil) {
            preference = [[self alloc] _initWithKey: key];
        } else {
            preference = [[OFEnumeratedPreference alloc] _initWithKey: key enumeration: enumeration];
        }
        [preferencesByKey setObject: preference forKey: key];
    }
    [preferencesLock unlock];

    if (enumeration != nil) {
        // It's OK to pass in a nil value for the enumeration, if you know that the enumeration has already been set up
        assert([[preference enumeration] isEqual: enumeration]);
    }
    
    return [preference autorelease];
}

- (NSString *) key;
{
    return _key;
}

- (OFEnumNameTable *) enumeration
{
    return nil;
}

- (id)controller;
{
    return _controller;
}

- (NSString *)controllerKey;
{
    return _controllerKey;
}

- (void)setController:(id)controller key:(NSString *)controllerKey;
{
    // Should be set once when setting up a preference controller.
    OBPRECONDITION(_controller == nil);
    OBPRECONDITION(_controllerKey == nil);
    
    _controller = [controller retain];
    _controllerKey = [controllerKey copy];
}

- (id) defaultObjectValue;
{
    NSDictionary *registrationDictionary;
    id defaultValue;

    @synchronized(self) {
	if (_defaultValue != nil && _generation != registrationGeneration) {
	    [_defaultValue release];
	    _defaultValue = nil;
	}
	defaultValue = _defaultValue;
    }

    if (defaultValue != nil)
        return _defaultValue;

    registrationDictionary = [standardUserDefaults volatileDomainForName:NSRegistrationDomain];
    defaultValue = [registrationDictionary objectForKey:_key];

    @synchronized(self) {
	if (_defaultValue == nil)
	    _defaultValue = [defaultValue retain];
    }

    return defaultValue;
}

- (BOOL) hasNonDefaultValue;
{
    id value, defaultValue;

    value = [self objectValue];
    defaultValue = [self defaultObjectValue];
    
    return !OFISEQUAL(value, defaultValue);
}


- (void) restoreDefaultValue;
{
    _setValue(self, &_value, _key, nil);
}

- (id) objectValue;
{
    return _objectValue(self, &_value, _key, @"NSObject");
}

- (NSString *) stringValue;
{
    return [[self objectValue] description];
}

- (NSArray *) arrayValue;
{
    return _objectValue(self, &_value, _key, @"NSArray");
}

- (NSDictionary *) dictionaryValue;
{
    return _objectValue(self, &_value, _key, @"NSDictionary");
}

- (NSData *) dataValue;
{
    return _objectValue(self, &_value, _key, @"NSData");
}

- (int) intValue;
{
    id number;
    int result;

    number = _retainedObjectValue(self, &_value, _key);
    OBASSERT(!number || [number isKindOfClass: [NSNumber class]] || [number isKindOfClass: [NSString class]]);
    if (number)
        result = [number intValue];
    else
        result = 0;
    [number release];
#ifdef DEBUG_PREFERENCES
    NSLog(@"OFPreference(0x%08x:%@) %s -> %d", self, _key, _cmd, result);
#endif
    
    return result;
}

- (NSInteger) integerValue;
{
    id number;
    NSInteger result;
    
    number = _retainedObjectValue(self, &_value, _key);
    OBASSERT(!number || [number isKindOfClass: [NSNumber class]] || [number isKindOfClass: [NSString class]]);
    if (number)
        result = [number integerValue];
    else
        result = 0;
    [number release];
#ifdef DEBUG_PREFERENCES
    NSLog(@"OFPreference(0x%08x:%@) %s -> %d", self, _key, _cmd, result);
#endif
    
    return result;
}

- (unsigned int) unsignedIntValue;
{
    id number;
    unsigned int result;

    number = _retainedObjectValue(self, &_value, _key);
    OBASSERT(!number || [number isKindOfClass: [NSNumber class]] || [number isKindOfClass: [NSString class]]);
    if (number)
        result = [number unsignedIntValue];
    else
        result = 0;
    [number release];
#ifdef DEBUG_PREFERENCES
    NSLog(@"OFPreference(0x%08x:%@) %s -> %d", self, _key, _cmd, result);
#endif

    return result;
}

- (NSUInteger) unsignedIntegerValue;
{
    id number;
    NSUInteger result;
    
    number = _retainedObjectValue(self, &_value, _key);
    OBASSERT(!number || [number isKindOfClass: [NSNumber class]] || [number isKindOfClass: [NSString class]]);
    if (number)
        result = [number unsignedIntegerValue];
    else
        result = 0;
    [number release];
#ifdef DEBUG_PREFERENCES
    NSLog(@"OFPreference(0x%08x:%@) %s -> %d", self, _key, _cmd, result);
#endif
    
    return result;
}

- (float) floatValue;
{
    id number;
    float result;

    number = _retainedObjectValue(self, &_value, _key);
    OBASSERT(!number || [number isKindOfClass: [NSNumber class]] || [number isKindOfClass: [NSString class]]);
    if (number)
        result = [number floatValue];
    else
        result = 0.0f;
    [number release];
#ifdef DEBUG_PREFERENCES
    NSLog(@"OFPreference(0x%08x:%@) %s -> %f", self, _key, _cmd, result);
#endif

    return result;
}

- (double) doubleValue;
{
    id number;
    double result;
    
    number = _retainedObjectValue(self, &_value, _key);
    OBASSERT(!number || [number isKindOfClass: [NSNumber class]] || [number isKindOfClass: [NSString class]]);
    if (number)
        result = [number doubleValue];
    else
        result = 0.0f;
    [number release];
#ifdef DEBUG_PREFERENCES
    NSLog(@"OFPreference(0x%08x:%@) %s -> %f", self, _key, _cmd, result);
#endif
    
    return result;
}

- (BOOL) boolValue;
{
    id number;
    BOOL result;

    number = _retainedObjectValue(self, &_value, _key);
    OBASSERT(!number || [number isKindOfClass: [NSNumber class]] || [number isKindOfClass: [NSString class]]);
    if (number)
        result = [number boolValue];
    else
        result = NO;
    [number release];
#ifdef DEBUG_PREFERENCES
    NSLog(@"OFPreference(0x%08x:%@) %s -> %s", self, _key, _cmd, result ? "YES" : "NO");
#endif

    return result;
}

- (NSArray *) stringArrayValue;
{
    return [self arrayValue];
}

- (NSInteger) enumeratedValue
{
    [NSException raise:NSInvalidArgumentException format:@"-%@ called on non-enumerated %@ (%@)", NSStringFromSelector(_cmd), [self shortDescription], _key];
    return INT_MIN; // unreached; and unlikely to be a valid enumeration value
}

- (void) setObjectValue: (id) value;
{
    _setValue(self, &_value, _key, value);
}

- (void) setStringValue: (NSString *) value;
{
    OBPRECONDITION(!value || [value isKindOfClass: [NSString class]]);
    _setValue(self, &_value, _key, value);
}

- (void) setArrayValue: (NSArray *) value;
{
    OBPRECONDITION(!value || [value isKindOfClass: [NSArray class]]);
    _setValue(self, &_value, _key, value);
}

- (void) setDictionaryValue: (NSDictionary *) value;
{
    OBPRECONDITION(!value || [value isKindOfClass: [NSDictionary class]]);
    _setValue(self, &_value, _key, value);
}

- (void) setDataValue: (NSData *) value;
{
    OBPRECONDITION(!value || [value isKindOfClass: [NSData class]]);
    _setValue(self, &_value, _key, value);
}

- (void) setIntValue: (int) value;
{
    NSNumber *number = [[NSNumber alloc] initWithInt: value];
    _setValue(self, &_value, _key, number);
    [number release];
}

- (void) setIntegerValue: (NSInteger) value;
{
    NSNumber *number = [[NSNumber alloc] initWithInteger: value];
    _setValue(self, &_value, _key, number);
    [number release];
}

- (void) setUnsignedIntValue: (unsigned int) value;
{
    NSNumber *number = [[NSNumber alloc] initWithUnsignedInt: value];
    _setValue(self, &_value, _key, number);
    [number release];
}

- (void) setUnsignedIntegerValue: (NSUInteger) value;
{
    NSNumber *number = [[NSNumber alloc] initWithUnsignedInteger: value];
    _setValue(self, &_value, _key, number);
    [number release];
}

- (void) setFloatValue: (float) value;
{
    NSNumber *number = [[NSNumber alloc] initWithFloat: value];
    _setValue(self, &_value, _key, number);
    [number release];
}

- (void) setDoubleValue: (double) value;
{
    NSNumber *number = [[NSNumber alloc] initWithDouble: value];
    _setValue(self, &_value, _key, number);
    [number release];
}


- (void) setBoolValue: (BOOL) value;
{
    NSNumber *number = [[NSNumber alloc] initWithBool: value];
    _setValue(self, &_value, _key, number);
    [number release];
}

- (void)setEnumeratedValue:(NSInteger)value;
{
    [NSException raise:NSInvalidArgumentException format:@"-%@ called on non-enumerated %@ (%@)", NSStringFromSelector(_cmd), [self shortDescription], _key];
}

#pragma mark AppleScript Support

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE

- (NSScriptObjectSpecifier *)objectSpecifier;
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    // We assume that preferences will be owned by the application with an element of @"scriptPreferences".  This is what OAApplication does.
    id application = [NSClassFromString(@"NSApplication") performSelector:@selector(sharedApplication)];
    return [[[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:(NSScriptClassDescription *)[application classDescription] containerSpecifier:[application objectSpecifier] key:@"scriptPreferences" uniqueID:_key] autorelease];
#pragma clang diagnostic pop
}

- (NSString *)scriptIdentifier;
{
    return _key;
}

- (id)scriptValue;
{
    id value = [self objectValue];
    if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSData class]])
        return [value description];
    else
        return value;
}

- (void)setScriptValue:(id)value;
{
    // TODO: Make sure this is a plist type?
    // Cocoa Scripting should do this for us, or reject the apple event, before we are ever called.

    if ([value isKindOfClass:[NSString class]])
        value = [[self class] coerceStringValue:value toTypeOfPropertyListValue:[self defaultObjectValue]];

    [self setObjectValue:value];
}

- (id)scriptDefaultValue;
{
    id value = [self defaultObjectValue];
    if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSData class]])
        return [value description];
    else
        return value;
}

#endif

#pragma mark - Private

- (id) _initWithKey: (NSString * ) key;
{
    OBPRECONDITION(key != nil);

    _key = [key copy];
    _generation = 0;
    _value = [unset retain];
    
    return self;
}

- (void)_refresh
{
    unsigned newGeneration;
    id newValue;

    [preferencesLock lock];

#ifdef DEBUG
    if (![_key hasPrefix:@"SiteSpecific:"] && ![[standardUserDefaults volatileDomainForName:NSRegistrationDomain] objectForKey:_key]) {
        NSLog(@"OFPreference: No default value is registered for '%@'", _key);
        OBPRECONDITION([[standardUserDefaults volatileDomainForName:NSRegistrationDomain] objectForKey:_key]);
    }
#endif

    newGeneration = registrationGeneration;
    newValue = [[standardUserDefaults objectForKey: _key] retain];
    [preferencesLock unlock];

#ifdef DEBUG_PREFERENCES
    NSLog(@"OFPreference(0x%08x:%@) faulting in value %@ generation %u", self, _key, newValue, newGeneration);
#endif

    @synchronized(self) {
        [_value release];
        _value = newValue;
	if (_generation != newGeneration) {
	    [_defaultValue release];
	    _defaultValue = nil;
	    _generation = newGeneration;
	}
    }
}

@end

@implementation OFEnumeratedPreference

- (id)_initWithKey:(NSString * )key enumeration:(OFEnumNameTable *)enumeration;
{
    if (!(self = [super _initWithKey:key]))
        return nil;
    names = [enumeration retain];
    return self;
}

// no -dealloc: we are never deallocated

- (OFEnumNameTable *) enumeration
{
    return names;
}

- (id)defaultObjectValue
{
    id defaultValue = [super defaultObjectValue];
    if (defaultValue == nil)
        return [names nameForEnum:[names defaultEnumValue]];
    else
        return defaultValue;
}

#define BAD_TYPE_IMPL(x) { [NSException raise:NSInvalidArgumentException format:@"-%@ called on enumerated %@ (%@)", NSStringFromSelector(_cmd), [self shortDescription], _key]; x; }

- (NSString *)stringValue;            BAD_TYPE_IMPL(return nil)
- (NSArray *)arrayValue;              BAD_TYPE_IMPL(return nil)
- (NSDictionary *)dictionaryValue;    BAD_TYPE_IMPL(return nil)
- (NSData *)dataValue;                BAD_TYPE_IMPL(return nil)
- (int)intValue;                      BAD_TYPE_IMPL(return 0)
- (NSInteger)integerValue             BAD_TYPE_IMPL(return 0)
- (unsigned int)unsignedIntValue;     BAD_TYPE_IMPL(return 0)
- (NSUInteger)unsignedIntegerValue    BAD_TYPE_IMPL(return 0)
- (float)floatValue;                  BAD_TYPE_IMPL(return 0)
- (double)doubleValue;                BAD_TYPE_IMPL(return 0)
- (BOOL)boolValue;                    BAD_TYPE_IMPL(return NO)

- (NSInteger)enumeratedValue;
{
    id value = _retainedObjectValue(self, &_value, _key);
    
    NSInteger result;
    if ([value isKindOfClass:[NSNumber class]]) {
        result = [(NSNumber *)value integerValue];
        [value release];
    } else if ([value isKindOfClass:[NSString class]]) {
        result = [names enumForName:value];
        [value release];
    } else {
        OBASSERT_NOT_REACHED("Enumerated preference not a string or a number");
        [value release];
        result = [names defaultEnumValue];
    }
    
    return result;
}

- (void)setStringValue:(NSString *)value;            BAD_TYPE_IMPL(;)
- (void)setArrayValue:(NSArray *)value;              BAD_TYPE_IMPL(;)
- (void)setDictionaryValue:(NSDictionary *)value;    BAD_TYPE_IMPL(;)
- (void)setDataValue:(NSData *)value;                BAD_TYPE_IMPL(;)
- (void)setIntValue:(int)value;                      BAD_TYPE_IMPL(;)
- (void)setIntegerValue:(NSInteger)value;            BAD_TYPE_IMPL(;)
- (void)setFloatValue:(float)value;                  BAD_TYPE_IMPL(;)
- (void)setDoubleValue:(double)value;                BAD_TYPE_IMPL(;)
- (void)setBoolValue:(BOOL)value;                    BAD_TYPE_IMPL(;)

- (void)setEnumeratedValue:(NSInteger)value;
{
    [self setObjectValue:[names nameForEnum:value]];
}

@end

@implementation OFPreferenceWrapper : NSObject

+ (OFPreferenceWrapper *) sharedPreferenceWrapper;
{
    static OFPreferenceWrapper *sharedPreferenceWrapper = nil;
    
    if (!sharedPreferenceWrapper)
        sharedPreferenceWrapper = [[self alloc] init];
    return sharedPreferenceWrapper;
}

- (OFPreference *)preferenceForKey:(NSString *)key;
{
    return [OFPreference preferenceForKey:key];
}

- (void) dealloc;
{
    OBRejectUnusedImplementation(self, _cmd); // OFPreferenceWrapper instance should never be deallocated
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
    [super dealloc]; // We know this won't be reached, but w/o this we get a warning about a missing call to super -dealloc
#pragma clang diagnostic pop
}

- (id)objectForKey:(NSString *)defaultName;
{
    return [[OFPreference preferenceForKey: defaultName] objectValue];
}

- (void)setObject:(id)value forKey:(NSString *)defaultName;
{
    [[OFPreference preferenceForKey: defaultName] setObjectValue: value];
}

- (id)valueForKey:(NSString *)aKey;
{
    return [[OFPreference preferenceForKey: aKey] objectValue];
}

- (void)setValue:(id)value forKey:(NSString *)aKey;
{
    [[OFPreference preferenceForKey: aKey] setObjectValue: value];
}

- (void)removeObjectForKey:(NSString *)defaultName;
{
    [[OFPreference preferenceForKey: defaultName] restoreDefaultValue];
}

- (NSString *)stringForKey:(NSString *)defaultName;
{
    return [[OFPreference preferenceForKey: defaultName] stringValue];
}

- (NSArray *)arrayForKey:(NSString *)defaultName;
{
    return [[OFPreference preferenceForKey: defaultName] arrayValue];
}

- (NSDictionary *)dictionaryForKey:(NSString *)defaultName;
{
    return [[OFPreference preferenceForKey: defaultName] dictionaryValue];
}

- (NSData *)dataForKey:(NSString *)defaultName;
{
    return [[OFPreference preferenceForKey: defaultName] dataValue];
}

- (NSArray *)stringArrayForKey:(NSString *)defaultName;
{
    return [[OFPreference preferenceForKey: defaultName] stringArrayValue];
}

- (int)intForKey:(NSString *)defaultName;
{
    return [[OFPreference preferenceForKey: defaultName] intValue];
}

- (NSInteger)integerForKey:(NSString *)defaultName;
{
    return [[OFPreference preferenceForKey: defaultName] intValue];
}

- (float)floatForKey:(NSString *)defaultName; 
{
    return [[OFPreference preferenceForKey: defaultName] floatValue];
}

- (double)doubleForKey:(NSString *)defaultName; 
{
    return [[OFPreference preferenceForKey: defaultName] floatValue];
}

- (BOOL)boolForKey:(NSString *)defaultName;  
{
    return [[OFPreference preferenceForKey: defaultName] boolValue];
}

- (void)setInt:(int)value forKey:(NSString *)defaultName;
{
    [[OFPreference preferenceForKey: defaultName] setIntValue: value];
}

- (void)setInteger:(NSInteger)value forKey:(NSString *)defaultName;
{
    [[OFPreference preferenceForKey: defaultName] setIntegerValue: value];
}

- (void)setFloat:(float)value forKey:(NSString *)defaultName;
{
    [[OFPreference preferenceForKey: defaultName] setFloatValue: value];
}

- (void)setDouble:(double)value forKey:(NSString *)defaultName;
{
    [[OFPreference preferenceForKey: defaultName] setDoubleValue: value];
}

- (void)setBool:(BOOL)value forKey:(NSString *)defaultName;
{
    [[OFPreference preferenceForKey: defaultName] setBoolValue: value];
}

- (BOOL)synchronize;
{
    return [standardUserDefaults synchronize];
}

- (NSDictionary *)volatileDomainForName:(NSString *)name;
{
    return [[NSUserDefaults standardUserDefaults] volatileDomainForName:name];
}

@end

void _OFInitializeDebugLogLevel(NSInteger *outLevel, NSString *name)
{
    NSInteger level;
    
    const char *env = getenv([name UTF8String]); /* easier for command line tools */
    if (env)
        level = strtoul(env, NULL, 0);
    else
        level = [[NSUserDefaults standardUserDefaults] integerForKey:name];
    
    if (level)
        NSLog(@"DEBUG LEVEL %@ = %ld", name, level);
    *outLevel = level;
}

void _OFInitializeTimeInterval(NSTimeInterval *outInterval, NSString *name, NSTimeInterval default_value, NSTimeInterval min_value, NSTimeInterval max_value)
{
    NSTimeInterval value = default_value;
    
    const char *env = getenv([name UTF8String]); /* easier for command line tools */
    if (env)
        value = strtod(env, NULL);
    else if ([[NSUserDefaults standardUserDefaults] objectForKey:name])
        value = [[NSUserDefaults standardUserDefaults] doubleForKey:name];
    
    value = CLAMP(value, min_value, max_value);
    if (value != default_value)
        NSLog(@"TIME INTERVAL %@ = %lf", name, value);
    *outInterval = value;
}

