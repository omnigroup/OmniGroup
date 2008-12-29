// Copyright 2004-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLIdentifierRegistry.h>

#import <OmniFoundation/CFDictionary-OFExtensions.h>
#import <OmniFoundation/NSData-OFEncoding.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/XML/OFXMLIdentifierRegistry.m 102862 2008-07-15 05:14:37Z bungi $");



/*" These must match the 'NAME' production in <http://www.w3.org/TR/2004/REC-xml-20040204/>:

NameChar ::= Letter | Digit | '.' | '-' | '_' | ':' | CombiningChar | Extender
Name     ::= (Letter | '_' | ':') (NameChar)*

NameChar is a production that allows a whole bunch of Unicode crud and I'm not going to type that in!
"*/

static NSCharacterSet *_InvalidNameChar(void)
{
    static NSCharacterSet *InvalidNC = nil;

    if (!InvalidNC) {
        NSMutableCharacterSet *set = [[NSCharacterSet characterSetWithCharactersInString:@".-_:"] mutableCopy];
        [set formUnionWithCharacterSet:[NSCharacterSet alphanumericCharacterSet]];
        InvalidNC = [[set invertedSet] copy];
        [set release];
    }
    return InvalidNC;
}

static BOOL _OFIsValidXMLID(NSString *identifier)
{
    unsigned int length = [identifier length];
    if (length == 0)
        return NO;
    
    // The first character can has a more limited set of options than the rest.  No numbers, no '.' and no '-'.
    unichar c = [identifier characterAtIndex:0];
    if (c != '_' && c != ':' && ![[NSCharacterSet letterCharacterSet] characterIsMember:c])
        return NO;
    
    
    NSRange r = [identifier rangeOfCharacterFromSet:_InvalidNameChar() options:0 range:(NSRange){1, length-1}];
    if (r.length > 0)
        return NO;
    return YES;
}

/*" Creates a valid XML 'ID' attribute.  These must match the 'NAME' production in <http://www.w3.org/TR/2004/REC-xml-20040204/>.  We want these to be short but still typically unique.  For example, we don't want two users editing the same file in CVS to create duplicate identifiers.  We can't satisfy both of these goals all the time, but we can make it extremely unlikely.  We'll make our IDs be 64-bits of data out of /dev/random encoded via a simple packing.  If opening /dev/urandom fails for some reason, we'll use CFUUID.
"*/

#define RANDOM_FILE "/dev/urandom"

NSString *OFXMLCreateID(void)
{
    static BOOL  initialized = NO;
    static FILE *device = NULL; // Use stdio so that we get some buffering rather than a kernel trap on every ID creation
    if (!initialized) {
        initialized = YES;
        device = fopen(RANDOM_FILE, "r");
        if (!device)
            perror(RANDOM_FILE);
    }

    if (device) {
        uint64_t value;
        if (fread(&value, 1, sizeof(value), device) == sizeof(value)) {
            // ':' is allowed in all positions, and '.' after the first position.  But as these have meaning on some filesystems, let's not use it in case our ids are used in file names.  This, also means our choice of characters is 64 options.
            static const char chars[64] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_";

            // Encoding 64 bits 6 bits at a time yields 11 characters (64/6 == 10 + rem 4).
            char encode[11];

            // We'll actually encode 4 of the bits in the first character to ensure that it is a letter (which is required in the XML 'NAME' production).
            encode[0] = chars[value & ((1<<4) - 1)];
            value >>= 4;

            unsigned int encodeIndex;
            for (encodeIndex = 1; encodeIndex < 11; encodeIndex++) {
                unsigned char i = value & ((1<<6) - 1);
                encode[encodeIndex] = chars[i];
                value >>= 6;
            }

            OBASSERT(value == 0); // should have consumed the whole value at this point

            return [[NSString alloc] initWithBytes:encode length:sizeof(encode) encoding:NSASCIIStringEncoding];
        }
    }

    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    NSString *uuidString = (NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuid);
    CFRelease(uuid);

    NSString *ident = [[NSString alloc] initWithFormat:@":%@", uuidString]; // Prefix with '_' to make sure it is a valid XML ID
    [uuidString release];

    return ident;
}

/*" Creates a valid XML ID string from the input string under the constraints that (a) if the input is already valid, it is returned exactly (b) two identical inputs will produce two identical outputs and (c) two different inputs will produce two different outputs.  We probably don't conform to (c) exactly since we conform to (a).  That is, since (a) requres that valid inputs are returned, no matter what function we chose to encode invalid inputs into valid ones, someone could pass in a 'pre-fixed' invalid output and get a duplicate.  This shouldn't happen give our current caller.
"*/
NSString *OFXMLIDFromString(NSString *str)
{
    OBPRECONDITION(str);

    if (_OFIsValidXMLID(str))
        return str;

    // Try prepending a ':' (ie, assume that str is just an encoded oid with a leading number)
    NSString *try = [@"_" stringByAppendingString:str];
    if (_OFIsValidXMLID(try))
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
        OBASSERT(_OFIsValidXMLID(identifier) || ![self objectForIdentifier:identifier]); // Shouldn't be registered yet if the identifier is invalid
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
    OBINVARIANT(_OFIsValidXMLID(identifier));
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
