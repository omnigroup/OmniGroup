// Copyright 2013-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVFeatures.h>

@interface OFXConnection : ODAVConnection

- initWithSessionConfiguration:(ODAV_NSURLSESSIONCONFIGURATION_CLASS *)configuration baseURL:(NSURL *)baseURL;

// Convenience for passing around the top-level directory on the account.
@property(nonatomic,readonly) NSURL *originalBaseURL;
@property(nonatomic,readonly) NSURL *baseURL; // Possibly redirected

- (void)updateBaseURLWithRedirects:(NSArray *)redirects;
- (NSURL *)suggestRedirectedURLForURL:(NSURL *)url;

@end
