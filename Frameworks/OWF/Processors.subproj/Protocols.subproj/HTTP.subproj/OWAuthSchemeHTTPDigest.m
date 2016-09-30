// Copyright 2001-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


// Note: There are two specifications of Digest authentication, RFC2069 and RFC2617. This was originally written to conform to 2069. Any modifications to the behavior of this class need to be able to work with servers supporting either RFC2069 Digest authentication *or* RFC2617 Digest authentication. In general, 2617 is a superset of 2069, but the implementation must properly handle the omission of the optional parameters.

#import "OWAuthSchemeHTTPDigest.h"

#import <OWF/OWHTTPProcessor.h>
#import <OWF/OWHTTPSession.h>
#import <OWF/OWAddress.h>
#import <OWF/OWURL.h>
#import <OWF/OWPipeline.h>

#import <OmniFoundation/OmniFoundation.h>
#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OWAuthSchemeHTTPDigest

// Discard any given client nonce if we've used it more than 30 times or if it's more than 15 minutes old.
#define MAX_CLIENT_NONCE_USES 30
#define MAX_CLIENT_NONCE_AGE (15 * 60)

// Init and dealloc

- init;
{
    if (!(self = [super init]))
        return nil;

    return self;
}

- initAsCopyOf:otherInstance
{
    
    if (!(self = [super initAsCopyOf:otherInstance]))
        return nil;
        
    if ([otherInstance isKindOfClass:[OWAuthSchemeHTTPDigest class]]) {
        OWAuthSchemeHTTPDigest *other = otherInstance;
        nonce = [other->nonce copy];
        opaque = [other->opaque copy];
        qop = other->qop;
        digest_algorithm = other->digest_algorithm;
        client_nonce = [other->client_nonce copy];
        client_nonce_count = other->client_nonce_count;
        client_nonce_use_count = other->client_nonce_use_count;
        client_nonce_created = other->client_nonce_created;
    } else {
        nonce = nil;
        opaque = nil;
        qop = htdigest_no_qop;
        digest_algorithm = htdigest_alg_MD5;
        client_nonce = nil;
        client_nonce_count = 0;
    }

    return self;
}

- (void)setParameters:(NSDictionary *)digestAuthParams
{
    nonce = [digestAuthParams objectForKey:@"nonce"];
    opaque = [digestAuthParams objectForKey:@"opaque"];

    NSString *qopString = [digestAuthParams objectForKey:@"qop"];
    if (qopString != nil) {
        // Must parse the QoP header. According to rfc2617, this is a list of tokens indicating different QoP levels the server is willing to accept.
        // rfc2617 defines two QoP levels: 'auth' (basically the same as 2069) and 'auth-int' (which includes request body integrity checking), and allows for the possibility that more will be defined in the future. Right now we only support 'auth', and not 'auth-int'.
        
        // unclear whether whitespace is allowed to separate tokens in the qop value. here we replace all whitespace with commas (sheesh) and later we ignore 0-length tokens. we're also trying to avoid creating ephemeral character sets (e.g. whitespace-and-comma-character-set) here.
        NSMutableString *qopBuffer = [qopString mutableCopy];
        [qopBuffer collapseAllOccurrencesOfCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] toString:@","];
        NSArray *qops = [[qopBuffer componentsSeparatedByString:@","] arrayByPerformingSelector:@selector(lowercaseString)];
        qopBuffer = nil;

        if ([qops containsObject:@"auth"]) {
            qop = htdigest_qop_auth;
        } else {
            // eventually, test for auth-int here, but right now we don't support that...
            qop = htdigest_no_qop_supported;
        }
    } else {
        qop = htdigest_no_qop;  // rfc2069 compatibility support
    }

    NSString *algString = [digestAuthParams objectForKey:@"algorithm"];
    if (algString == nil || ([algString caseInsensitiveCompare:@"MD5"] == NSOrderedSame))
        digest_algorithm = htdigest_alg_MD5;
    else if ([algString caseInsensitiveCompare:@"MD5-sess"] == NSOrderedSame)
        digest_algorithm = htdigest_alg_MD5_sess;
    else
        digest_algorithm = htdigest_alg_unknown;
}

- (int)compareToNewCredential:(OWAuthorizationCredential *)other
{
    int compare = [super compareToNewCredential:other];
    // NB: super will also check that 'other' is of the same class we are, which ensures that the casts (below) are valid
    
    if (compare == OWCredentialIsEquivalent) {
        NSString *otherOpaque;
        OWAuthSchemeHTTPDigest *otherDigest = ((OWAuthSchemeHTTPDigest *)other);
        if (![nonce isEqual:(otherDigest->nonce)])
            compare = OWCredentialWouldReplace;
        otherOpaque = (otherDigest->opaque);
        if ((opaque == nil && otherOpaque != nil) ||
            (opaque != nil && otherOpaque == nil) ||
            (opaque != otherOpaque && ![opaque isEqual:otherOpaque]))
            compare = OWCredentialWouldReplace;
        if (qop != otherDigest->qop || digest_algorithm != otherDigest->digest_algorithm)
            compare = OWCredentialWouldReplace;
    }
    
    return compare;
}

// Computes the digest used for rfc2069, or rfc2617 with no QoP parameter
static NSString *computeDigest_2069(NSString *username,
                               NSString *password,
                               NSString *nonce,
                               NSString *realmname,
                               NSString *method,
                               NSString *fetchPath)
{
    NSString *response;

    @autoreleasepool {
        // buffer for string manipulation
        NSMutableString *Ax = [[NSMutableString alloc] init];
        
        // compute A1 and its MD5-hash
        [Ax appendStrings:username, @":", realmname, @":", password, nil];
        NSString *A1hash = [[[Ax dataUsingEncoding:NSISOLatin1StringEncoding] md5Signature] unadornedLowercaseHexString];
        [Ax deleteCharactersInRange:NSMakeRange(0, [Ax length])];
        
        // compute A2 and its MD5-hash
        [Ax appendStrings:method, @":", fetchPath, nil];
        NSString *A2hash = [[[Ax dataUsingEncoding:NSISOLatin1StringEncoding] md5Signature] unadornedLowercaseHexString];
        [Ax deleteCharactersInRange:NSMakeRange(0, [Ax length])];
        
        // compute the final digest
        [Ax appendStrings:A1hash, @":", nonce, @":", A2hash, nil];
        response = [[[Ax dataUsingEncoding:NSISOLatin1StringEncoding] md5Signature] unadornedLowercaseHexString];
    }
    
    return response;
}

// compute the digest for ( qop=auth | qop=auth-int ) & ( algorithm=MD5 )
static NSString *computeDigest_2617(NSString *username,
                                    NSString *password,
                                    NSString *nonce,
                                    NSString *realmname,
                                    NSString *method,
                                    NSString *fetchPath,

                                    NSString *cnonce_count,
                                    NSString *cnonce,
                                    NSString *qop)
{
    NSString *response;

    @autoreleasepool {
        // buffer for string manipulation
        NSMutableString *Ax = [[NSMutableString alloc] init];
        
        // compute A1 and its MD5-hash
        [Ax appendStrings:username, @":", realmname, @":", password, nil];
        NSString *A1hash = [[[Ax dataUsingEncoding:NSISOLatin1StringEncoding] md5Signature] unadornedLowercaseHexString];
        [Ax deleteCharactersInRange:NSMakeRange(0, [Ax length])];
        
        // compute A2 and its MD5-hash
        [Ax appendStrings:method, @":", fetchPath, nil];
        NSString *A2hash = [[[Ax dataUsingEncoding:NSISOLatin1StringEncoding] md5Signature] unadornedLowercaseHexString];
        [Ax deleteCharactersInRange:NSMakeRange(0, [Ax length])];
        
        // compute the final digest
        [Ax appendStrings:A1hash, @":", nonce, @":", cnonce_count, @":", cnonce, @":", qop, @":", A2hash, nil];
        response = [[[Ax dataUsingEncoding:NSISOLatin1StringEncoding] md5Signature] unadornedLowercaseHexString];
    }

    return response;
}


- (void)_freshenNonce
{
    NSTimeInterval now = [[NSDate date] timeIntervalSinceReferenceDate];
    
    // Decide whether we need to create a new client nonce.
    if (client_nonce != nil && client_nonce_count > 0 &&
        client_nonce_use_count < MAX_CLIENT_NONCE_USES &&
        (now - client_nonce_created) < MAX_CLIENT_NONCE_AGE)
        return;

    struct {
        void *p1, *p2, *p3;
        NSTimeInterval tv;
    } cheap_entropy;
    
    cheap_entropy.p1 = &cheap_entropy;
    cheap_entropy.p2 = (__bridge void *)(client_nonce);
    cheap_entropy.p3 = &client_nonce;
    cheap_entropy.tv = now;

    NSMutableData *entropy_buf = [[NSMutableData alloc] init];
    [entropy_buf appendBytes:&cheap_entropy length:sizeof(cheap_entropy)];
    [entropy_buf appendData:[client_nonce dataUsingEncoding:NSUTF8StringEncoding]];
    [entropy_buf appendData:[OWAuthorizationRequest entropy]];

    client_nonce = [[[entropy_buf sha1Signature] base64EncodedStringWithOptions:0] substringToIndex:20];
    client_nonce_count++;
    client_nonce_use_count = 0;
    client_nonce_created = now;
    
    // It's not clear to me that the client_nonce_count has any use, since the user might quit & restart the client, or be running several clients behind one nat or proxy setup. However, the rfc requires it ...
}

static void appendAuthParameter0(NSMutableString *buf, NSString *name, NSString *value)
{
    NSCharacterSet *nonToken = [OWHTTPSession nonTokenCharacterSet];
    
    [buf appendLongCharacter:' '];
    [buf appendString:name];
    [buf appendLongCharacter:'='];

    if ([value containsCharacterInSet:nonToken]) {
        NSMutableString *quotedValue = [value mutableCopy];
        [quotedValue replaceAllOccurrencesOfString:@"\\" withString:@"\\\\"];
        [quotedValue replaceAllOccurrencesOfString:@"\"" withString:@"\\\""];
        // TODO: Check for totally bogus characters in value (non-ASCII, or controls).

        [buf appendLongCharacter:'"'];
        [buf appendString:quotedValue];
        [buf appendLongCharacter:'"'];
    } else
        [buf appendString:value];
}

static void appendAuthParameter(NSMutableString *buf, NSString *name, NSString *value)
{
    [buf appendLongCharacter:','];
    appendAuthParameter0(buf, name, value);
}

- (NSString *)httpHeaderStringForProcessor:(OWHTTPProcessor *)aProcessor
{
    NSMutableString *response;
    OWAddress *uri;
    NSString *fetchPath, *fetchMethod;
    NSString *headerName;

    // TODO: How should we handle proxies who use Digest authentication?
    if (aProcessor == nil)
        return nil;

    uri = [aProcessor sourceAddress];
    OBASSERT(uri != nil);
    fetchPath = [[uri url] fetchPath];
    fetchMethod = [uri methodString];
    OBASSERT(fetchPath != nil);
    OBASSERT(fetchMethod != nil);

    if (type == OWAuth_HTTP)
        headerName = @"Authorization";
    else if (type == OWAuth_HTTP_Proxy)
        headerName = @"Proxy-Authorization";
    else
        headerName = @"X-Bogus-Header"; // TODO        

    response = [NSMutableString stringWithString:headerName];
    [response appendString:@": Digest"];

    appendAuthParameter0(response,  @"username",  username);
    appendAuthParameter(response,  @"realm",     realm);
    appendAuthParameter(response,  @"nonce",     nonce);
    appendAuthParameter(response,  @"uri",       fetchPath);
    switch(qop) {
        default:  // TODO: Server won't accept this unless it's broken, but we might as well try
        case htdigest_qop_auth:
            {
                NSString *noncecount, *qop_string;

                [self _freshenNonce];

                qop_string = @"auth";
                noncecount = [NSString stringWithFormat:@"%08x", client_nonce_count];
                
                appendAuthParameter(response, @"qop", qop_string);
                appendAuthParameter(response, @"nc", noncecount);
                appendAuthParameter(response, @"cnonce", client_nonce);
                appendAuthParameter(response,  @"response",  computeDigest_2617(username, password, nonce, realm, fetchMethod, fetchPath, noncecount, client_nonce, qop_string));
                client_nonce_use_count ++;
            }
            break;
        case htdigest_no_qop:
            appendAuthParameter(response,  @"response",  computeDigest_2069(username, password, nonce, realm, fetchMethod, fetchPath));
            break;
    }
    
    appendAuthParameter(response,  @"algorithm", @"MD5");  // TODO: other algs (e.g. MD5-sess)
    
    if (opaque)
        appendAuthParameter(response,  @"opaque", opaque);

    /* TODO: entity-digest headers for qop=auth-int */
    
    return response;
}

- (BOOL)appliesToHTTPChallenge:(NSDictionary *)challenge
{
    // Correct scheme?
    if ([[challenge objectForKey:@"scheme"] caseInsensitiveCompare:@"digest"] != NSOrderedSame)
        return NO;
    
    // Correct realm?
    if (realm && [realm caseInsensitiveCompare:[challenge objectForKey:@"realm"]] != NSOrderedSame)
        return NO;
    
    // It's OK to use an old nonce. The server will tell us if the nonce is too old and give us a chance to try again.
    
    return YES;
}

- (void)authorizationSucceeded:(BOOL)success response:(OWHeaderDictionary *)response;
{
    /* If we've failed, but we succeeded some time in the past, check to see if we can just try again with a new nonce instead of prompting the user again. */
    if (!success && lastSucceededTimeInterval > OWAuthDistantPast) {
        NSArray *challenges = [OWAuthorizationRequest findParametersOfType:type headers:response];
        for (NSDictionary *challenge in challenges) {
            if ([self appliesToHTTPChallenge:challenge]) {
                NSString *stale = [challenge objectForKey:@"stale"];
                NSString *newNonce = [challenge objectForKey:@"nonce"];
                if (stale != nil && newNonce != nil && ![nonce isEqual:newNonce] &&
                    [stale caseInsensitiveCompare:@"true"] == NSOrderedSame) {
                    OWAuthSchemeHTTPDigest *newCred = [[OWAuthSchemeHTTPDigest alloc] initAsCopyOf:self];
                    [newCred setParameters:challenge];
                    [OWAuthorizationRequest cacheCredentialIfAbsent:newCred];
                }
            }
        }
    }

    // TODO: Parse the Authentication-Info header for greater efficiency & protection
    
    [super authorizationSucceeded:success response:response];
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary = [super debugDictionary];
    NSString *str;

    [debugDictionary setObject:nonce forKey:@"nonce"];
    if (opaque)
        [debugDictionary setObject:opaque forKey:@"opaque"];

    switch (qop) {
        case htdigest_no_qop: str = nil; break;
        case htdigest_qop_auth: str = @"auth"; break;
        case htdigest_qop_auth_int: str = @"auth-int"; break;
        case htdigest_no_qop_supported: default: str = @"(unsupported)"; break;
    }
    if (str)
        [debugDictionary setObject:str forKey:@"qop"];

    switch (digest_algorithm) {
        case htdigest_alg_MD5: str = @"MD5"; break;
        case htdigest_alg_MD5_sess: str = @"MD5-sess"; break;
        case htdigest_alg_unknown: str = @"(unknown)"; break;
    }
    [debugDictionary setObject:str forKey:@"algorithm"];

    if (client_nonce) {
        [debugDictionary setObject:client_nonce forKey:@"cnonce"];
        [debugDictionary setIntValue:client_nonce_count forKey:@"nc"];
    }

    return debugDictionary;
}


@end

