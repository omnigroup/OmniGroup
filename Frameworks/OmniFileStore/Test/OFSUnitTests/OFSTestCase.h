// Copyright 2008-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFTestCase.h"

@interface OFSTestCase : OFTestCase

@property(nonatomic,readonly) NSURL *accountRemoteBaseURL;
- (NSURLCredential *)accountCredentialWithPersistence:(NSURLCredentialPersistence)persistence;

@end
