// Copyright 2008-2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "ODAVConcreteTestCase.h"

#import <OmniFoundation/OFRandom.h>
#import <OmniDAV/ODAVErrors.h>

#import "OBTestCase.h"

@interface ODAVRedirectTestCase : ODAVConcreteTestCase
@end

@implementation ODAVRedirectTestCase

- (BOOL)shouldUseRedirectingRemoteBaseURL;
{
    return YES;
}

- (void)testMoveWithDestinationRedirected;
{
    // In Apache 2.4, a MOVE with a Destination that needs redirection returns a 301/302 without actually do any MOVE, or including a Location header.
    
    __autoreleasing NSError *error;
    
    NSURL *file = [self.remoteBaseURL URLByAppendingPathComponent:@"file"];
    NSData *data = OFRandomCreateDataOfLength(16);
    
    NSURL *putFileURL;
    OBShouldNotError(putFileURL = [self.connection synchronousPutData:data toURL:file error:&error]);
    XCTAssert([[putFileURL pathComponents] containsObject:ODAVTestCaseRedirectDestinationDirectoryName]);
    
    NSURL *targetURL = [self.remoteBaseURL URLByAppendingPathComponent:@"file-moved"];
    NSURL *resultURL = [self.connection synchronousMoveURL:putFileURL toMissingURL:targetURL error:&error];
    XCTAssertNil(resultURL);
    XCTAssert([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_MOVED_PERMANENTLY] ||
              [error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_MOVED_TEMPORARILY]);
}

- (void)testCopyWithDestinationRedirected;
{
    // In Apache 2.4, a COPY with a Destination that needs redirection returns a 301/302 without actually do any COPY, or including a Location header.
    
    __autoreleasing NSError *error;
    
    NSURL *file = [self.remoteBaseURL URLByAppendingPathComponent:@"file"];
    NSData *data = OFRandomCreateDataOfLength(16);
    
    NSURL *putFileURL;
    OBShouldNotError(putFileURL = [self.connection synchronousPutData:data toURL:file error:&error]);
    XCTAssert([[putFileURL pathComponents] containsObject:ODAVTestCaseRedirectDestinationDirectoryName]);
    
    NSURL *targetURL = [self.remoteBaseURL URLByAppendingPathComponent:@"file-copy"];
    NSURL *resultURL = [self.connection synchronousCopyURL:putFileURL toURL:targetURL withSourceETag:nil overwrite:NO error:&error];
    XCTAssertNil(resultURL);
    XCTAssert([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_MOVED_PERMANENTLY] ||
              [error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_MOVED_TEMPORARILY]);
}

@end
