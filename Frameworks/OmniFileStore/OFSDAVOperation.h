// Copyright 2008-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import <OmniFileStore/OFSAsynchronousOperation.h>

@interface OFSDAVOperation : NSObject <OFSAsynchronousOperation, NSURLConnectionDelegate, NSURLConnectionDataDelegate>

- initWithRequest:(NSURLRequest *)request;

- (NSError *)prettyErrorForDAVError:(NSError *)davError;

@property(nonatomic,copy) void (^validateCertificateForChallenge)(OFSDAVOperation *op, NSURLAuthenticationChallenge *challenge);
@property(nonatomic,copy) NSURLCredential *(^findCredentialsForChallenge)(OFSDAVOperation *op, NSURLAuthenticationChallenge *challenge);

@property(nonatomic,readonly) NSError *error;
@property(nonatomic,readonly) NSData *resultData; // Only set if didReceiveData is nil, otherwise that block is expected to accumulate data however the caller wants

- (NSString *)valueForResponseHeader:(NSString *)header;

@property(nonatomic,readonly) NSArray *redirects; /* see below */

@end

/* The array returned by -redirects holds a sequence of dictionaries, each corresponding to one redirection or URL rewrite. */

/* Dictionary keys */
#define kOFSRedirectedFrom      (@"from")    /* NSURL from which we were redirected */
#define kOFSRedirectedTo        (@"to")      /* NSURL to which we were redirected */
#define kOFSRedirectionType     (@"type")    /* A string indicating the nature of the redirect: an HTTP status code (presumably 3xx), "PROPFIND", or "Content-Location" */
/* Non-3xx redirect types here */
#define    kOFSRedirectPROPFIND    (@"PROPFIND")  /* Redirected ourselves because PROPFIND returned a URL other than the one we did a PROPFIND on; see for example the last paragraph of RFC4918 [5.2] */
#define    kOFSRedirectContentLocation  (@"Content-Location")  /* "Redirect" because a response included a Content-Location: header; see e.g. RFC4918 [5.2] para 8 */

void OFSAddRedirectEntry(NSMutableArray *entries, NSString *type, NSURL *from, NSURL *to, NSDictionary *responseHeaders) OB_HIDDEN;
