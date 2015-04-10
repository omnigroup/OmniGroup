// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

RCS_ID("$Id$")

@interface OFXRedirectTestCase : OFXTestCase
@end

@implementation OFXRedirectTestCase

- (BOOL)shouldUseRedirectingRemoteBaseURL;
{
    return YES;
}

- (void)testBasicOperations;
{
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [self singleAccountInAgent:agentA];
    OFXAgent *agentB = self.agentB;
    OFXServerAccount *accountB = [self singleAccountInAgent:agentB];
    
    // Add a file and wait for B to download
    OFXFileMetadata *originalMetadata = [self uploadFixture:@"test.package"];
    
    // Rename it, wait for B to see
    [self movePath:@"test.package" toPath:@"moved.package" ofAccount:accountA];
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return [metadata.fileIdentifier isEqual:originalMetadata.fileIdentifier] && metadata.downloaded && [[metadata.fileURL lastPathComponent] isEqual:@"moved.package"];
    }];
    [self requireAgentsToHaveSameFilesByName];
    
    // Edit it on B, wait for A to see
    OFXFileMetadata *renamedMetadata = [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        // just getting the current metadata on A
        return YES;
    }];
    [self copyFixtureNamed:@"test2.package" toPath:@"moved.package" ofAccount:accountB];
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return [metadata.fileIdentifier isEqual:renamedMetadata.fileIdentifier] && metadata.downloaded && ![metadata.editIdentifier isEqual:renamedMetadata.editIdentifier];
    }];
    [self requireAgentsToHaveSameFilesByName];
    
    // Delete it on A, wait for B to see
    [self deletePath:@"moved.package" inAgent:agentA];
    [self waitForFileMetadataItems:agentB where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
}

@end
