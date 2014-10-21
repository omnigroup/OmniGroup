// Copyright 2008-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import <OmniDAV/ODAVAsynchronousOperation.h>

@interface ODAVOperation : NSObject <ODAVAsynchronousOperation>

- (NSError *)prettyErrorForDAVError:(NSError *)davError;

@property(nonatomic,readonly) NSError *error;
@property(nonatomic,readonly) NSData *resultData; // Only set if didReceiveData is nil, otherwise that block is expected to accumulate data however the caller wants

- (NSString *)valueForResponseHeader:(NSString *)header;

@property(nonatomic,readonly) NSArray *redirects; /* see below */

@property(nonatomic,assign) NSUInteger retryIndex;

@end

/* The array returned by -redirects holds a sequence of dictionaries, each corresponding to one redirection or URL rewrite. */
@interface ODAVRedirect : NSObject
@property(nonatomic,readonly,copy) NSURL *from;
@property(nonatomic,readonly,copy) NSURL *to;
@property(nonatomic,readonly,copy) NSString *type;
@end

/* Non-3xx redirect types here */
#define    kODAVRedirectPROPFIND    (@"PROPFIND")  /* Redirected ourselves because PROPFIND returned a URL other than the one we did a PROPFIND on; see for example the last paragraph of RFC4918 [5.2] */
#define    kODAVRedirectContentLocation  (@"Content-Location")  /* "Redirect" because a response included a Content-Location: header; see e.g. RFC4918 [5.2] para 8 */

void ODAVAddRedirectEntry(NSMutableArray *entries, NSString *type, NSURL *from, NSURL *to, NSDictionary *responseHeaders) OB_HIDDEN;
