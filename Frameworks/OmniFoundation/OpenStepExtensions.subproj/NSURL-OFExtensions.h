// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSURL.h>

// A utility function which returns the range of the path portion of an RFC1808-style URL.
extern NSRange OFURLRangeOfPath(NSString *rfc1808URL);

// Appends a slash to the path of the given URL if it doesn't already end in one.
extern NSURL *OFURLWithTrailingSlash(NSURL *baseURL);

// -[NSURL isEqual:] ignores the http://tools.ietf.org/html/rfc3986#section-2.1 which says that percent-encoded octets should be compared case-insentively (%5b should be the same as %5B).
extern BOOL OFURLEqualsURL(NSURL *URL1, NSURL *URL2);

extern BOOL OFURLEqualToURLIgnoringTrailingSlash(NSURL *URL1, NSURL *URL2);

extern BOOL OFURLContainsURL(NSURL *containerURL, NSURL *url);
extern NSString *OFFileURLRelativePath(NSURL *baseURL, NSURL *fileURL);

