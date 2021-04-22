// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

#import <OmniDAV/ODAVAsynchronousOperation.h>

@class NSMutableArray;
@class ODAVRedirect;

NS_ASSUME_NONNULL_BEGIN

@interface ODAVOperation : NSObject <ODAVAsynchronousOperation>

- (NSError *)prettyErrorForDAVError:(NSError *)davError;

@property(nonatomic,readonly,nullable) NSError *error;

@property(nonatomic,readonly) NSInteger statusCode;
- (NSString * __nullable)valueForResponseHeader:(NSString *)header;

@property(nonatomic,readonly) NSArray <ODAVRedirect *> *redirects; /* see below */

// These only related to retries based on network connection loss.
@property(nonatomic,readonly) BOOL retryable;
@property(nonatomic,assign) NSUInteger retryIndex;

@end

/* The array returned by -redirects holds a sequence of ODAVRedirect objects, each corresponding to one redirection or URL rewrite. */
@interface ODAVRedirect : NSObject

+ (NSURL * __nullable)suggestAlternateURLForURL:(NSURL *)url withRedirects:(NSArray <ODAVRedirect *> *)redirects;

@property(nonatomic,readonly,copy) NSURL *from;
@property(nonatomic,readonly,copy) NSURL *to;
@property(nonatomic,readonly,copy) NSString *type;
@end

extern NSString * const ODAVContentTypeHeader;

/* Non-3xx redirect types here */
#define    kODAVRedirectPROPFIND    (@"PROPFIND")  /* Redirected ourselves because PROPFIND returned a URL other than the one we did a PROPFIND on; see for example the last paragraph of RFC4918 [5.2] */
#define    kODAVRedirectContentLocation  (@"Content-Location")  /* "Redirect" because a response included a Content-Location: header; see e.g. RFC4918 [5.2] para 8 */

void ODAVAddRedirectEntry(NSMutableArray <ODAVRedirect *> *entries, NSString *type, NSURL *from, NSURL *to, NSDictionary * __nullable responseHeaders) OB_HIDDEN;

/* Returns YES if the string matches the 'byte-content-range' production from rfc7233. Fills in any out parameters which apply; unspecified values are left alone. Returns YES iff the header is successfully parsed (but may touch some output values even on failure). */
BOOL ODAVParseContentRangeBytes(NSString * __nullable contentRange, unsigned long long * __nullable outFirstByte, unsigned long long * __nullable outLastByte, unsigned long long * __nullable outTotalLength);


NS_ASSUME_NONNULL_END
