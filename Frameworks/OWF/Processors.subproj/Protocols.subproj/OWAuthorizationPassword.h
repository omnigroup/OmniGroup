// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWAuthorizationCredential.h>

@interface OWAuthorizationPassword : OWAuthorizationCredential
{
    NSString *username;
    NSString *password;
}

- initForRequest:(OWAuthorizationRequest *)req realm:(NSString *)authRealm username:(NSString *)user password:(NSString *)pass;

@end
