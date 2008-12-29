// Copyright 2004-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLIdentifierRegistry.h>

#import <OmniFoundation/OFXMLIdentifier.h>
#import <OmniFoundation/CFDictionary-OFExtensions.h>
#import <OmniFoundation/NSData-OFEncoding.h>

RCS_ID("$Id$");

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
@interface OFXMLIdentifierRegistry (PrivateAPI)
- (void)_setup:(OFXMLIdentifierRegistry *)registry;
- (void)_clear;
@end

@implementation OFXMLIdentifierRegistry

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

    [self _clear];
    [super dealloc];
}

/*" Manages the identifier/object relationship.  If object is nil, then identifier is required and any mapping for the identifier is cleared and nil is returned.  If object is non-nil, then the object is registered.  In this case, the identifier can be nil, signalling that the caller doesn't care what identifier is registered.  If the identifier is non-nil, then it is the preferred value to use for the identifier.  If some other object already has that identifier registered, though, a new unique identifier will be created.  In the registration case, this method returns a new retained unique identifier for the object.  Note that registration does not retain the object -- thus if the object is deallocated, it must be deregistered.  The identifer actually used is returned autoreleased.  The object is notified when it is added and removed from the registry via the OFXMLIdentifierRegistryObject protocol. "*/
- (NSString *)registerIdentifier:(NSString *)identifier forObject:(id <OFXMLIdentifierRegistryObject>)object;
{
    OBINVARIANT([self checkInvariants]);
    OBPRECONDITION(object || identifier);
    OBPRECONDITION(!object || ![self identifierForObject:object]); // Don't allow duplicate adds

    if (!object) {
        OBASSERT(OFXMLIsValidID(identifier) || ![self objectForIdentifier:identifier]); // Shouldn't be registered yet if the identifier is invalid
        object = [self objectForIdentifier:identifier];
        if (object) {
            // Was previously registered -- remove the mappings.
            CFDictionaryRemoveValue(_idToObject, identifier);
            CFDictionaryRemoveValue(_objectToID, object);
            [object removedFromIdentifierRegistry:self];
        }
        OBINVARIANT([self checkInvariants]);
        return nil;
    } else {
        if (identifier)
            identifier = OFXMLIDFromString(identifier);

        [identifier retain]; // Loop should end with a retained string
        while (!identifier || CFDictionaryGetValue(_idToObject, identifier)) {
            [identifier release];
            identifier = OFXMLCreateID();
        }

        CFDictionarySetValue(_objectToID, object, identifier);
        CFDictionarySetValue(_idToObject, identifier, object);
        [object addedToIdentifierRegistry:self withIdentifier:identifier];
        OBINVARIANT([self checkInvariants]);

        // _idToObject retains the identifier, so we can -release instead of -autorelease here
        [identifier release];
        return identifier;
    }
}

- (id <OFXMLIdentifierRegistryObject>)objectForIdentifier:(NSString *)identifier;
{
    OBINVARIANT([self checkInvariants]);
    return (id)CFDictionaryGetValue(_idToObject, identifier);
}

- (NSString *)identifierForObject:(id <OFXMLIdentifierRegistryObject>)object;
{
    OBINVARIANT([self checkInvariants]);
    return (NSString *)CFDictionaryGetValue(_objectToID, object);
}

- (void)applyFunction:(CFDictionaryApplierFunction)function context:(void *)context;
{
    OBINVARIANT([self checkInvariants]);
    
    // The applier could be modifying the registrations directly or indirectly.  For example, when one object gets unregistered, it may unregister some of its sub-objects.
    NSDictionary *mapping = [self copyIdentifierToObjectMapping];
    
    @try {
	CFDictionaryApplyFunction((CFDictionaryRef)mapping, function, context);
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

- (unsigned)registrationCount;
{
    OBPRECONDITION(CFDictionaryGetCount(_idToObject) == CFDictionaryGetCount(_objectToID));
    return CFDictionaryGetCount(_idToObject);
}

- (NSMutableDictionary *)copyIdentifierToObjectMapping;
{
    return [[NSMutableDictionary alloc] initWithDictionary:(NSDictionary *)_idToObject];
}

#ifdef OMNI_ASSERTIONS_ON

static void _checkEntry(const void *key, const void *value, void *context)
{
    NSString *identifier = (NSString *)key;
    id object = (id)value;

    OBINVARIANT([identifier isKindOfClass:[NSString class]]);
    OBINVARIANT(OFXMLIsValidID(identifier));
    OBINVARIANT([object class]); // just make sure it isn't zombied

    if (CFDictionaryGetValue((CFDictionaryRef)context, object) != identifier) {
        NSLog(@"_objectToID[%@] -> '%@'", identifier, OBShortObjectDescription(object));
        NSLog(@"_idToObject['%@'] -> %@", OBShortObjectDescription(object), CFDictionaryGetValue((CFDictionaryRef)context, object));
        OBINVARIANT(CFDictionaryGetValue((CFDictionaryRef)context, object) == identifier);
    }
}

- (BOOL)checkInvariants;
{
    OBINVARIANT(CFDictionaryGetCount(_idToObject) == CFDictionaryGetCount(_objectToID));
    CFDictionaryApplyFunction(_idToObject, _checkEntry, _objectToID);
    return YES;
}
#endif

//
// Debugging
//
- (NSMutableDictionary *) debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];
    
    [dict setObject:(id)_idToObject forKey:@"_idToObject"];
    [dict setObject:(id)_objectToID forKey:@"_objectToID"];

    return dict;
}

@end


@implementation OFXMLIdentifierRegistry (PrivateAPI)

- (void)_setup:(OFXMLIdentifierRegistry *)registry;
{
    OBPRECONDITION(_idToObject == NULL);
    OBPRECONDITION(_objectToID == NULL);

    if (registry) {
        _idToObject = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, registry->_idToObject);
        _objectToID = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, registry->_objectToID);
    } else {
        // The id->object dictionary uses object equality comparison and does NOT retain the objects
        _idToObject = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectDictionaryKeyCallbacks, &OFNonOwnedPointerDictionaryValueCallbacks);

        // The object->id dictionary uses pointer equality comparison and does NOT retain the objects OR the identifiers (the identifiers are retained by _idToObject already)
        _objectToID = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &OFNonOwnedPointerDictionaryKeyCallbacks, &OFNonOwnedPointerDictionaryValueCallbacks);
    }

}

static void _objectRemoved(const void *key, const void *value, void *context)
{
    [(id <OFXMLIdentifierRegistryObject>)value removedFromIdentifierRegistry:(OFXMLIdentifierRegistry *)context];
}

- (void)_clear;
{
    [self applyFunction:_objectRemoved context:self];
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
