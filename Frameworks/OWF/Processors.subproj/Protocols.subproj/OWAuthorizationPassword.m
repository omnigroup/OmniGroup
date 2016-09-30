// Copyright 2001-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWAuthorizationPassword.h>

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@implementation OWAuthorizationPassword

- initForRequest:(OWAuthorizationRequest *)req realm:(NSString *)authRealm username:(NSString *)user password:(NSString *)pass
{
    self = [super initForRequest:req realm:authRealm];
    
    if (self == nil)
        return nil;
    
    if (user == nil || pass == nil) {
        self = nil;
        return nil;
    }
    
    username = user;
    password = pass;
    
    return self;
}

- initAsCopyOf:otherInstance
{
    self = [super initAsCopyOf:otherInstance];
    if (self == nil)
        return nil;
        
    if (![otherInstance isKindOfClass:[OWAuthorizationPassword class]]) {
        self = nil;
        return nil;
    }
    
    OWAuthorizationPassword *other = otherInstance;
    username = [other->username copy];
    password = [other->password copy];
        
    return self;
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
