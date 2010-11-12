// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class NSURLCredential, NSURLProtectionSpace, NSURLAuthenticationChallenge;

__private_extern__ NSURLCredential *OUIReadCredentialsForProtectionSpace(NSURLProtectionSpace *protectionSpace);
__private_extern__ NSURLCredential *OUIReadCredentialsForChallenge(NSURLAuthenticationChallenge *challenge);
__private_extern__ void OUIWriteCredentialsForProtectionSpace(NSString *userName, NSString *password, NSURLProtectionSpace *protectionSpace);
__private_extern__ void OUIDeleteAllCredentials(void);
__private_extern__ void OUIDeleteCredentialsForProtectionSpace(NSURLProtectionSpace *protectionSpace);
