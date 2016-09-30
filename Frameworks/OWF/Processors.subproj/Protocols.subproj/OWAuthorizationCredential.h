// Copyright 2001-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSString, NSDate;
@class OWProcessor, OWHTTPProcessor;

#import <Foundation/NSDate.h> // For NSTimeInterval
#import <OWF/OWAuthorizationRequest.h> // For OWAuthorizationType
#import <OmniBase/macros.h>

OB_HIDDEN extern NSTimeInterval OWAuthDistantPast;

@interface OWAuthorizationCredential : OFObject
{
    // An authorization realm is limited to one server (host, protocol, and port), and one "realm" string (for HTTP authorization).
    // For FTP authorization, the realm string is nil.
    
    NSString *hostname;      // the hostname, textual or numeric
    enum OWAuthorizationType type;      // the protocol: http, http-proxy, ftp, etc.
    unsigned port;          // the port, or 0 for the default port for this protocol
    
    NSString *realm;
    
    NSTimeInterval lastSucceededTimeInterval, lastFailedTimeInterval;
    
    id keychainTag;
}

+ (OWAuthorizationCredential *)nullCredential; // a placeholder for no credential at all

- initForRequest:(OWAuthorizationRequest *)req realm:(NSString *)authRealm;
- (instancetype)initAsCopyOf:(id)otherInstance;

- (NSString *)hostname;
- (enum OWAuthorizationType)type;
- (unsigned int)port;
- (NSString *)realm;  // for FTP, etc., the realm is the username

// May return nil, if there's a problem (or if this credential isn't applicable to HTTP)
- (NSString *)httpHeaderStringForProcessor:(OWHTTPProcessor *)aProcessor;
- (BOOL)appliesToHTTPChallenge:(NSDictionary *)challenge;

// The keychain tag is an attempt to identify individual keychain items so that we can avoid asking the user to allow us access to an item we already have cached. At the moment it's an NSDictionary, but it should be opaque to preactically everyone.
- keychainTag;
- (void)setKeychainTag:newTag;

// Returns an integer describing the new credential's equivalence to the receiver (see #defines, below)
- (int)compareToNewCredential:(OWAuthorizationCredential *)other;
#define OWCredentialIsEquivalent 1  // the new credential is equivalent
#define OWCredentialWouldReplace 2  // the new credential is different, but would replace this one (eg. a new password for the same account)
#define OWCredentialIsUnrelated 3  // the new credential is unrelated to the receiver (eg. a different account)

// feedback to tell the credential how well it worked
- (void)authorizationSucceeded:(BOOL)success response:(OWHeaderDictionary *)response;

@end
