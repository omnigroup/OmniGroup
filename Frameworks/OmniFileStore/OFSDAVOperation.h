// Copyright 2008-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OmniFileStore/OFSAsynchronousOperation.h>
#import <OmniFileStore/OFSFileManagerAsynchronousOperationTarget.h>

@class OFSDAVFileManager;

@interface OFSDAVOperation : OFObject <OFSAsynchronousOperation>
{
@private
    OFSDAVFileManager *_nonretained_fileManager;
    id <OFSFileManagerAsynchronousOperationTarget> _target;
    NSURLRequest *_request;
    NSURLConnection *_connection;

    // For PUT operations
    long long _bodyBytesSent;
    long long _expectedBytesToWrite;
    
    // Mostly for GET operations, though _response gets used at the end of a PUT or during an auth challenge.
    NSHTTPURLResponse *_response;
    NSMutableData *_resultData;
    BOOL _targetWantsData;
    long long _bytesReceived;
    
    BOOL _finished;
    NSError *_error;
    NSMutableArray *_redirections;
}

- initWithFileManager:(OFSDAVFileManager *)fileManager request:(NSURLRequest *)request target:(id <OFSFileManagerAsynchronousOperationTarget>)target;
- (NSError *)prettyErrorForDAVError:(NSError *)davError;
- (NSData *)run:(NSError **)outError;
- (NSArray *)redirects; /* see below */

@end

/* The array returned by -redirects holds a sequence of dictionaries, each corresponding to one redirection or URL rewrite. */

/* Dictionary keys */
#define kOFSRedirectedFrom      (@"from")    /* NSURL from which we were redirected */
#define kOFSRedirectedTo        (@"to")      /* NSURL to which we were redirected */
#define kOFSRedirectionType     (@"type")    /* A string indicating the nature of the redirect: an HTTP status code (presumably 3xx), "PROPFIND", or "Content-Location" */
/* Non-3xx redirect types here */
#define    kOFSRedirectPROPFIND    (@"PROPFIND")  /* Redirected ourselves because PROPFIND returned a URL other than the one we did a PROPFIND on; see for example the last paragraph of RFC4918 [5.2] */
#define    kOFSRedirectContentLocation  (@"Content-Location")  /* "Redirect" because a response included a Content-Location: header; see e.g. RFC4918 [5.2] para 8 */

__private_extern__ void OFSAddRedirectEntry(NSMutableArray *entries, NSString *type, NSURL *from, NSURL *to, NSDictionary *responseHeaders);
