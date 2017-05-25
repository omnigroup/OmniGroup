// Copyright 2004-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLIdentifierRegistry.h>

#import <Foundation/Foundation.h>

#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/CFDictionary-OFExtensions.h>
#import <OmniFoundation/NSData-OFEncoding.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define DEBUG_IDREG(format, ...) NSLog(@"IDREG: " format, ## __VA_ARGS__)
#else
    #define DEBUG_IDREG(format, ...)
#endif

/*" Creates a valid XML ID string from the input string under the constraints that (a) if the input is already valid, it is returned exactly (b) two identical inputs will produce two identical outputs and (c) two different inputs will produce two different outputs.  We probably don't conform to (c) exactly since we conform to (a).  That is, since (a) requres that valid inputs are returned, no matter what function we chose to encode invalid inputs into valid ones, someone could pass in a 'pre-fixed' invalid output and get a duplicate.  This shouldn't happen give our current caller.
 "*/
NSString *OFXMLIDFromString(NSString *str)
{
    OBPRECONDITION(str);
    
    if (OFXMLIsValidID(str))
        return str;
    
    // Try prepending a value XML identifier character (perhaps str is just an encoded oid with a leading number)
    NSString *try = [@"_" stringByAppendingString:str];
    if (OFXMLIsValidID(try))
        return try;
    
    return [@"_" stringByAppendingString:[[str dataUsingEncoding:NSUTF8StringEncoding] unadornedLowercaseHexString]];
}

@implementation OFXMLIdentifierRegistry
{
    CFMutableDictionaryRef _idToObject;
    CFMutableDictionaryRef _objectToID;
}

- (id)initWithRegistry:(OFXMLIdentifierRegistry *)registry;
{
    if (!(self = [super init]))
        return nil;

    [self _setup:registry];
    OBINVARIANT([self checkInvariants]);
    return self;
}

- (id)init;
{
    return [self initWithRegistry:nil];
}

- (void)dealloc;
{
    OBINVARIANT([self checkInvariants]);

    if (_idToObject && _objectToID) {
        [self _clear];
    } else {
        // Can happen if we are deallocated w/o init being called. For example, if our OFXMLDocument subclass encounters an error in an init method and returns nil.
    }
    
    [super dealloc];
}

#pragma mark - NSObject (OBDebugging)

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    
    if (_idToObject)
        [dict setObject:((__bridge NSMutableDictionary *)_idToObject) forKey:@"_idToObject"];
    if (_objectToID)
        [dict setObject:((__bridge NSMutableDictionary *)_objectToID) forKey:@"_objectToID"];
    
    return dict;
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale indent:(NSUInteger)level
{
    if (level < 3)
        return [[self debugDictionary] descriptionWithLocale:locale indent:level];
    return [self shortDescription];
}

/*" Returns [self descriptionWithLocale:nil indent:0]. This often provides more meaningful information than the default implementation of description, and is (normally) automatically used by the debugger, gdb, when asked to print an object.
 
 See also: - description (NSObject), - shortDescription
 "*/
- (NSString *)description;
{
    return [self descriptionWithLocale:nil indent:0];
}

- (NSString *)shortDescription;
{
    return [super description];
}

#pragma mark - Public API

/*" Manages the identifier/object relationship.  If object is nil, then identifier is required and any mapping for the identifier is cleared and nil is returned.  If object is non-nil, then the object is registered.  In this case, the identifier can be nil, signalling that the caller doesn't care what identifier is registered.  If the identifier is non-nil, then it is the preferred value to use for the identifier.  If some other object already has that identifier registered, though, a new unique identifier will be created.  In the registration case, this method returns a new retained unique identifier for the object.  Note that registration does not retain the object -- thus if the object is deallocated, it must be deregistered.  The identifier actually used is returned autoreleased.  The object is notified when it is added and removed from the registry via the OFXMLIdentifierRegistryObject protocol. "*/
- (NSString *)registerIdentifier:(NSString *)identifier forObject:(id <OFXMLIdentifierRegistryObject>)object;
{
    OBINVARIANT_EXPENSIVE([self checkInvariants]);
    OBPRECONDITION(object || identifier);
    OBPRECONDITION(!object || ![self identifierForObject:object]); // Don't allow duplicate adds
    
    if (!object) {
        OBASSERT(OFXMLIsValidID(identifier) || ![self objectForIdentifier:identifier]); // Shouldn't be registered yet if the identifier is invalid
        object = [self objectForIdentifier:identifier];
        if (object) {
            // Was previously registered -- remove the mappings.
            CFDictionaryRemoveValue(_idToObject, (__bridge CFStringRef)identifier);
            CFDictionaryRemoveValue(_objectToID, (__bridge CFTypeRef)object);
            DEBUG_IDREG(@"In registry %p, de-registering object <%@-%p> with identifier %@", self, [(NSObject *)object class], object, identifier);
            [object removedFromIdentifierRegistry:self];
        }
        OBINVARIANT_EXPENSIVE([self checkInvariants]);
        return nil;
    } else {
        if (identifier)
            identifier = OFXMLIDFromString(identifier);

        [identifier retain]; // Loop should end with a retained string
        while (!identifier || CFDictionaryGetValue(_idToObject, (__bridge CFStringRef)identifier)) {
            [identifier release];
            identifier = OFXMLCreateID();
        }

        CFDictionarySetValue(_objectToID, (__bridge CFTypeRef)object, (__bridge CFStringRef)identifier);
        CFDictionarySetValue(_idToObject, (__bridge CFStringRef)identifier, (__bridge CFTypeRef)object);
        [object addedToIdentifierRegistry:self withIdentifier:identifier];
        OBINVARIANT_EXPENSIVE([self checkInvariants]);

        // _idToObject retains the identifier, so we can -release instead of -autorelease here
        [identifier release];
        DEBUG_IDREG(@"In registry %p, registering object <%@-%p> with identifier %@", self, [(NSObject *)object class], object, identifier);
        return identifier;
    }
}

- (id <OFXMLIdentifierRegistryObject>)objectForIdentifier:(NSString *)identifier;
{
    OBINVARIANT_EXPENSIVE([self checkInvariants]);
    return (id)CFDictionaryGetValue(_idToObject, (__bridge CFStringRef)identifier);
}

- (NSString *)identifierForObject:(id <OFXMLIdentifierRegistryObject>)object;
{
    OBINVARIANT_EXPENSIVE([self checkInvariants]);
    return (__bridge NSString *)CFDictionaryGetValue(_objectToID, (__bridge CFTypeRef)object);
}

- (void)applyBlock:(void (^)(NSString *identifier, id <OFXMLIdentifierRegistryObject> object))block;
{
    OBINVARIANT([self checkInvariants]);
    
    // The applier could be modifying the registrations directly or indirectly.  For example, when one object gets unregistered, it may unregister some of its sub-objects.
    NSDictionary *mapping = [self copyIdentifierToObjectMapping];
    
    @try {
        [mapping enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, id object, BOOL *stop) {
            block(identifier, object);
        }];
    } @finally {
	[mapping release];
    }
    
    OBINVARIANT([self checkInvariants]);
}

- (void)clearRegistrations;
{
    [self _clear];
    [self _setup:nil];
}

- (NSUInteger)registrationCount;
{
    OBPRECONDITION(CFDictionaryGetCount(_idToObject) == CFDictionaryGetCount(_objectToID));
    
    return CFDictionaryGetCount(_idToObject);
}

- (NSMutableDictionary *)copyIdentifierToObjectMapping;
{
    return (OB_BRIDGE_TRANSFER NSMutableDictionary *)CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, _idToObject);
}

#ifdef OMNI_ASSERTIONS_ON

- (BOOL)checkInvariants;
{
    OBINVARIANT(CFDictionaryGetCount(_idToObject) == CFDictionaryGetCount(_objectToID));
    
    [(__bridge NSDictionary *)_idToObject enumerateKeysAndObjectsUsingBlock:^(NSString *identifier, id object, BOOL *stop) {
        OBINVARIANT([identifier isKindOfClass:[NSString class]]);
        OBINVARIANT(OFXMLIsValidID(identifier));
        OBINVARIANT([object class]); // just make sure it isn't zombied
        
        if (CFDictionaryGetValue(_objectToID, (__bridge CFTypeRef)object) != (__bridge CFStringRef)identifier) {
            NSLog(@"_objectToID[%@] -> '%@'", identifier, OBShortObjectDescription(object));
            NSLog(@"_idToObject['%@'] -> %@", OBShortObjectDescription(object), CFDictionaryGetValue(_objectToID, (__bridge CFTypeRef)object));
            OBINVARIANT(CFDictionaryGetValue(_objectToID, (__bridge CFTypeRef)object) == (__bridge CFStringRef)identifier);
        }
    }];
    
    return YES;
}

- (BOOL)isSubsetOfRegistry:(OFXMLIdentifierRegistry *)otherRegistry;
{
    OBINVARIANT([self checkInvariants]);
    OBINVARIANT([otherRegistry checkInvariants]);
    __block BOOL mismatchFound = NO;
    [(__bridge NSDictionary *)_idToObject enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *identifier = key;
        id otherRegistryObject = [otherRegistry objectForIdentifier:identifier];
        if (otherRegistryObject != obj) {
            mismatchFound = YES;
            *stop = YES;
        }
    }];
    return !mismatchFound;
}
#endif

#pragma mark - Private

- (void)_setup:(OFXMLIdentifierRegistry *)registry;
{
    OBPRECONDITION(_idToObject == NULL);
    OBPRECONDITION(_objectToID == NULL);

    if (registry) {
        DEBUG_IDREG(@"Initializing new registry %p from old registry %p", self, registry);
        _idToObject = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, registry->_idToObject);
        _objectToID = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, registry->_objectToID);
    } else {
        // The id->object dictionary uses object equality comparison and does NOT retain the objects
        _idToObject = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectDictionaryKeyCallbacks, &OFNonOwnedPointerDictionaryValueCallbacks);

        // The object->id dictionary uses pointer equality comparison and does NOT retain the objects OR the identifiers (the identifiers are retained by _idToObject already)
        _objectToID = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNonOwnedPointerDictionaryKeyCallbacks, &OFNonOwnedPointerDictionaryValueCallbacks);
    }

}

- (void)_clear;
{
    [self applyBlock:^(NSString *identifier, id <OFXMLIdentifierRegistryObject> object) {
        [object removedFromIdentifierRegistry:self];
    }];

    if (_idToObject) {
        CFRelease(_idToObject);
        _idToObject = NULL;
    }
    if  (_objectToID) {
        CFRelease(_objectToID);
        _objectToID = NULL;
    }
}

@end
