// Copyright 2001-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWAuthorizationCredential.h>

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@interface OWAuthorizationCredential (Private)
@end

@implementation OWAuthorizationCredential

NSTimeInterval OWAuthDistantPast;

+ (void)initialize
{
    OWAuthDistantPast = [[NSDate distantPast] timeIntervalSinceReferenceDate];
}

+ (OWAuthorizationCredential *)nullCredential; // a placeholder for no credential at all
{
    static OWAuthorizationCredential *nullCredential = nil;
    
    if (!nullCredential)
        nullCredential = [[self alloc] init];
    return nullCredential;
}

- initForRequest:(OWAuthorizationRequest *)req realm:(NSString *)authRealm
{
    self = [super init];
    if (self == nil)
        return nil;
    
    if (req == nil) {
        self = nil;
        return nil;
    }
    
    realm = authRealm;
    port = 0;
    hostname = [req hostname];
    port = [req port];
    type = [req type];
    lastSucceededTimeInterval = OWAuthDistantPast;
    lastFailedTimeInterval = OWAuthDistantPast;
    
    return self;
}

- (instancetype)initAsCopyOf:(id)otherInstance;
{
    OWAuthorizationCredential *other;
    
    if (!(self = [super init]))
        return nil;
        
    if (![otherInstance isKindOfClass:[OWAuthorizationCredential class]]) {
        self = nil;
        return nil;
    }
    
    other = otherInstance;
    realm = [other->realm copy];
    port = other->port;
    hostname = [other->hostname copy];
    type = other->type;
    
    lastSucceededTimeInterval = OWAuthDistantPast;
    lastFailedTimeInterval = OWAuthDistantPast;
    
    return self;
}

- (NSString *)hostname
{
    return hostname;
}

- (enum OWAuthorizationType)type
{
    return type;
}

- (unsigned int)port
{
    return port;
}

- (NSString *)realm
{
    return realm;
}

// Default implementation
- (NSString *)httpHeaderStringForProcessor:(OWHTTPProcessor *)aProcessor
{
    return nil;
}

- (BOOL)appliesToHTTPChallenge:(NSDictionary *)challenge
{
    return NO;
}

- keychainTag
{
    return keychainTag;
}

- (void)setKeychainTag:newTag
{
    keychainTag = newTag;
}

- (int)compareToNewCredential:(OWAuthorizationCredential *)other
{
    if (![other isKindOfClass:[self class]])
        return OWCredentialIsUnrelated;
    
    if ([other type] != type)
        return OWCredentialIsUnrelated;
    
    if (![hostname isEqual:(other->hostname)])
        return OWCredentialIsUnrelated;
    
    if (realm) {
        if (![other realm] || ![[other realm] isEqual:realm])
            return OWCredentialIsUnrelated;
    } else {
        if ([other realm])
            return OWCredentialIsUnrelated;
    }
    
    // TODO: handle default port numbers correctly
    if (port != other->port)
        return OWCredentialIsUnrelated;
    
    return OWCredentialIsEquivalent;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
    NSString *typeStr;

    [debugDictionary setObject:hostname forKey:@"hostname"];
    switch(type) {
        case OWAuth_HTTP: typeStr = @"HTTP"; break;
        case OWAuth_HTTP_Proxy: typeStr = @"HTTP_Proxy"; break;
        case OWAuth_FTP: typeStr = @"FTP"; break;
        case OWAuth_NNTP: typeStr = @"NNTP"; break;
        default: typeStr = nil;
    }
    if (typeStr)
        [debugDictionary setObject:typeStr forKey:@"type"];
    if (port > 0)
        [debugDictionary setObject:[NSNumber numberWithUnsignedInt:port] forKey:@"port"];
    if (realm)
        [debugDictionary setObject:realm forKey:@"realm"];
    if (lastSucceededTimeInterval > OWAuthDistantPast)
        [debugDictionary setObject:[NSDate dateWithTimeIntervalSinceReferenceDate:lastSucceededTimeInterval] forKey:@"lastSucceededTimeInterval"];
    if (lastFailedTimeInterval > OWAuthDistantPast)
        [debugDictionary setObject:[NSDate dateWithTimeIntervalSinceReferenceDate:lastFailedTimeInterval] forKey:@"lastFailedTimeInterval"];
        
    return debugDictionary;
}

- (void)authorizationSucceeded:(BOOL)success response:(OWHeaderDictionary *)response;
{
    // used by subclasses
    // TODO: if we fail, mark ourselves so we aren't used again, or so that we are only used as a last resort. We don't want to remove ourselves from the cache, because we don't want OWAuthReq. to re-request us from the keychain (possibly popping up another dialogue box).
    
    if (success) 
        lastSucceededTimeInterval = [[NSDate date] timeIntervalSinceReferenceDate];
    else
        lastFailedTimeInterval = [[NSDate date] timeIntervalSinceReferenceDate];
}

@end

@implementation OWAuthorizationCredential (Private)
@end
