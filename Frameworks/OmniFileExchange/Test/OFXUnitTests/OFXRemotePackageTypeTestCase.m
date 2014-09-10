// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

RCS_ID("$Id$")

@interface OFXRemotePackageTypeTestCase : OFXTestCase

@end

@implementation OFXRemotePackageTypeTestCase

- (NSArray *)extraPackagePathExtensionsForAgentName:(NSString *)agentName;
{
    if ([agentName isEqual:OFXTestFirstAgentName])
        return @[@"package-on-client-a"];
    return nil;
}

- (void)testPackageKnownOnlyOnOneClient;
{
    // Client A should publish what it sees as a package.
    OFXFileMetadata *originalMetadata = [self uploadFixture:@"test.package-on-client-a"];
    
    // B should download this and should also see it as a package, even though it doesn't know that this is a package type.
    BOOL (^predicate)(OFXFileMetadata *metadata) = ^BOOL(OFXFileMetadata *metadata) {
        return [metadata.fileIdentifier isEqual:originalMetadata.fileIdentifier] && metadata.downloaded && [[metadata.fileURL lastPathComponent] isEqual:@"test.package-on-client-a"];
    };
    
    [self waitForFileMetadata:self.agentB where:predicate];
    
    // Wait for a bit and no futher activity should happen
    [self waitForSeconds:2];
    [self waitForFileMetadata:self.agentA where:predicate];
    [self waitForFileMetadata:self.agentB where:predicate];
}

@end
