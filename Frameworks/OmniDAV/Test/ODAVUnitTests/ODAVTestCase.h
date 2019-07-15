// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

@interface ODAVTestCase : OFTestCase

@property(nonatomic,readonly) BOOL shouldUseRedirectingRemoteBaseURL;
@property(nonatomic,readonly) NSURL *accountRemoteBaseURL;

- (NSURLCredential *)accountCredentialWithPersistence:(NSURLCredentialPersistence)persistence;
- (BOOL)shouldAddTrustForCertificateChallenge:(NSURLAuthenticationChallenge *)challenge;

@end

extern NSString * const ODAVTestCaseRedirectSourceDirectoryName;
extern NSString * const ODAVTestCaseRedirectDestinationDirectoryName;

// Synchronous wrappers for these tests
#import <OmniDAV/ODAVConnection.h>
