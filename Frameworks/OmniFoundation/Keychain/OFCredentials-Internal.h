// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Security/Security.h>

// IT IS INSECURE TO ENABLE THIS: Your credentials will be logged; use only test accounts.
#if 0 && defined(DEBUG)
    #define DEBUG_CREDENTIALS(format, ...) NSLog(@"CREDENTIALS: " format, ## __VA_ARGS__)
    #define DEBUG_CREDENTIALS_DEFINED 1
#else
    #define DEBUG_CREDENTIALS(format, ...) do {} while (0)
    #define DEBUG_CREDENTIALS_DEFINED 0
#endif

void _OFLogSecError(const char *caller, const char *function, OSStatus err) OB_HIDDEN;
#define OFLogSecError(function, err) _OFLogSecError(__PRETTY_FUNCTION__, function, err)

NSURLCredential *_OFCredentialFromUserAndPassword(NSString *user, NSString *password) OB_HIDDEN;

SecTrustRef _OFTrustForChallenge(NSURLAuthenticationChallenge *challenge) OB_HIDDEN;
NSData *_OFDataForLeafCertificateInChallenge(NSURLAuthenticationChallenge *challenge) OB_HIDDEN;
