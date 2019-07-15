// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWAuthorizationPassword.h>

@interface OWAuthSchemeHTTPDigest : OWAuthorizationPassword
{
    NSString *nonce;
    NSString *opaque;

    // The quality-of-protection we've chosen to supply
    enum {
        htdigest_no_qop,	// Server specified no QOP (rfc2069)
        htdigest_qop_auth,	// Authentication (implies rfc2617)
        htdigest_qop_auth_int,	// Auth. & integrity (ditto rfc2617) [not supp]
        htdigest_no_qop_supported  // server doesn't want any qops we support
    } qop;
    
    // The message digest algorithm the server requested
    enum {
        htdigest_alg_MD5,		// normal
        htdigest_alg_MD5_sess,		// new in rfc2617; not supported by us yet
        htdigest_alg_unknown		// unknown; we can't handle it
    } digest_algorithm;

    NSString *client_nonce;
    unsigned int client_nonce_count, client_nonce_use_count;
    NSTimeInterval client_nonce_created;
}

- (void)setParameters:(NSDictionary *)digestAuthParams;

@end
