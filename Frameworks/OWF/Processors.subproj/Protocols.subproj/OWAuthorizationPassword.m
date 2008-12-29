// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWAuthorizationPassword.h"

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@interface OWAuthorizationPassword (Private)
@end

@implementation OWAuthorizationPassword

- initForRequest:(OWAuthorizationRequest *)req realm:(NSString *)authRealm username:(NSString *)user password:(NSString *)pass
{
    self = [super initForRequest:req realm:authRealm];
    
    if (!self)
        return nil;
    
    if (!user || !pass) {
        [super dealloc];
        return nil;
    }
    
    username = [user retain];
    password = [pass retain];
    
    return self;
}

- initAsCopyOf:otherInstance
{
    OWAuthorizationPassword *other;
    
    if (!(self = [super initAsCopyOf:otherInstance]))
        return nil;
        
    if (![otherInstance isKindOfClass:[OWAuthorizationPassword class]]) {
        [super dealloc];
        return nil;
    }
    
    other = otherInstance;
    username = [other->username copy];
    password = [other->password copy];
        
    return self;
}


- (void)dealloc
{
    [username release];
    [password release];
    [super dealloc];
}

- (int)compareToNewCredential:(OWAuthorizationCredential *)other
{
    int compare = [super compareToNewCredential:other];
    // NB: super will also check that 'other' is of the same class we are, which ensures that the casts (below) are valid
    
    if (compare == OWCredentialIsEquivalent) {
        // TODO: this makes it impossible to have passwords for two different accounts in the same realm. should it be possible? how would we manage the ui?
        if (![username isEqual:(((OWAuthorizationPassword *)other)->username)])
            compare = OWCredentialWouldReplace;
        if (![password isEqual:(((OWAuthorizationPassword *)other)->password)])
            compare = OWCredentialWouldReplace;
    }
    
    return compare;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];

    [debugDictionary setObject:username forKey:@"username"];
    [debugDictionary setObject:password forKey:@"password"];

    return debugDictionary;
}

@end

@implementation OWAuthorizationPassword (Private)
@end
