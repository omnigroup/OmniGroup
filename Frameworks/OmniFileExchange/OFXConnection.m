// Copyright 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXConnection.h"

#import <OmniDAV/ODAVOperation.h>

RCS_ID("$Id$")

@implementation OFXConnection
{
    NSArray *_redirects;
    NSURL *_redirectedBaseURL;
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithSessionConfiguration:(ODAV_NSURLSESSIONCONFIGURATION_CLASS *)configuration;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- initWithSessionConfiguration:(ODAV_NSURLSESSIONCONFIGURATION_CLASS *)configuration baseURL:(NSURL *)baseURL;
{
    OBPRECONDITION(baseURL);
    
    if (!(self = [super initWithSessionConfiguration:configuration]))
        return nil;
    
    _originalBaseURL = [baseURL copy];
    
    return self;
}

- (NSURL *)baseURL;
{
    if (_redirectedBaseURL)
        return _redirectedBaseURL;
    return _originalBaseURL;
}

- (void)updateBaseURLWithRedirects:(NSArray *)redirects;
{
    if (_redirects) {
        _redirects = [_redirects arrayByAddingObjectsFromArray:redirects];
    } else {
        _redirects = [redirects copy];
    }
    
    // We could maybe keep the previous redirected URL if we had one, but presumably that led to getting another redirection.
    _redirectedBaseURL = [self suggestRedirectedURLForURL:self.baseURL];
}

- (NSURL *)suggestRedirectedURLForURL:(NSURL *)url;
{
    NSURL *redirectedURL = [ODAVRedirect suggestAlternateURLForURL:url withRedirects:_redirects];
    if (redirectedURL)
        return redirectedURL;
    return url;
}

@end
