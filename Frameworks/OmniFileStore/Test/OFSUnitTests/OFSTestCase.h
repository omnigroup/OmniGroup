// Copyright 2008-2012 The Omni Group. All rights reserved.
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
@property(nonatomic,readonly) NSURLCredential *accountCredential;

- (void)closeSocketsConnectedToURL:(NSURL *)url;

@end
