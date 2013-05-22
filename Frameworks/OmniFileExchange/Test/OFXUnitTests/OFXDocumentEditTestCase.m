// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

#import "OFXTrace.h"

#import <OmniFoundation/OFNull.h>
#import <OmniFileStore/Errors.h>

RCS_ID("$Id$")

@interface OFXDocumentEditTestCase : OFXTestCase
@end


@implementation OFXDocumentEditTestCase

- (BOOL)automaticallyDownloadFileContents
{
    return NO;
}

- (void)testAddDocument;
{
    OFXAgent *agent = self.agentA;
    OFXServerAccount *account = [agent.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(account);
    
    [self copyFixtureNamed:@"test.package" ofAccount:account];

    __block NSSet *metadataItems;
    [self waitUntil:^BOOL{
        metadataItems = [agent metadataItemsForAccount:account];
        if ([metadataItems count] == 0)
            return NO;

        OFXFileMetadata *metadata = [metadataItems anyObject];
        if (!metadata.uploaded)
            return NO;
        
        return YES;
    }];

    STAssertEquals(1ULL, [metadataItems count], nil);
    
    OFXFileMetadata *metadata = [metadataItems anyObject];
    STAssertEqualObjects([metadata.fileURL lastPathComponent], @"test.package", nil);
    STAssertEquals(34ULL, metadata.fileSize, nil);
    STAssertEqualObjects(metadata.creationDate, metadata.modificationDate, nil);
    // ... more assertions
}

- (void)testEditDocument;
{
    OFXAgent *agent = self.agentA;
    OFXServerAccount *account = [agent.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(account);
    
    [self copyFixtureNamed:@"test.package" ofAccount:account];
    
    // Wait for this version of the file to register so that we don't replace it before the agent has grabbed this one (otherwise our file size check at the end could spuriously succeed).
    [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded;
    }];
    
    // This other pacakge adds a sub-file, removes one, edits another, moves yet another, and leaves one alone.
    [self copyFixtureNamed:@"test2.package" toPath:@"test.package" ofAccount:account];
    
    [self waitForFileMetadataItems:agent where:^BOOL(NSSet *metadataItems) {
        STAssertEquals([metadataItems count], 1ULL, @"the old metadata should replace the new one");

        OFXFileMetadata *metadata = [metadataItems anyObject];
        return [[metadata.fileURL lastPathComponent] isEqualToString:@"test.package"] && (metadata.fileSize == 45ULL);
    }];
}

- (void)testDownloadDocument;
{
    [self uploadFixture:@"test.package"];

    // Sync on B and wait for the file's metadata to appear (it might not automatically download the contents).
    {
        [self.agentB sync:nil];
        [self waitForFileMetadata:self.agentB where:nil];
        
        OFXServerAccount *account = [self.agentB.accountRegistry.validCloudSyncAccounts lastObject];

        STAssertEquals([[self.agentB metadataItemsForAccount:account] count], 1ULL, nil);
    }
    
    // Download the item
    {
        OFXServerAccount *account = [self.agentB.accountRegistry.validCloudSyncAccounts lastObject];

        OFXFileMetadata *placeholderMetadata = [[self.agentB metadataItemsForAccount:account] anyObject];
        STAssertFalse(placeholderMetadata.downloaded, nil);

        [self.agentB requestDownloadOfItemAtURL:placeholderMetadata.fileURL completionHandler:^(NSError *errorOrNil) {
            STAssertNil(errorOrNil, nil);
        }];

        OFXFileMetadata *downloadedMetadata = [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata){
            return metadata.downloaded;
        }];
        STAssertTrue(downloadedMetadata.downloaded, nil);
        STAssertEqualObjects(placeholderMetadata.creationDate, downloadedMetadata.creationDate, nil);
        STAssertEqualObjects(downloadedMetadata.creationDate, downloadedMetadata.modificationDate, nil);

        // Make sure we got the right contents
        OFDiffFiles(self, [[self fixtureNamed:@"test.package"] path], [downloadedMetadata.fileURL path], nil);
    }
}

- (void)testDownloadUpdatedDocumentWithoutDownloadingFirstVersion;
{
    OFXFileMetadata *firstMetadata = [self uploadFixture:@"test.package"];
 
    // Wait until we see the first version
    OFXFileMetadata *bFirstSeenMetadata = [self waitForFileMetadata:self.agentB where:nil];
    STAssertTrue(bFirstSeenMetadata.downloaded == NO, nil);
    STAssertEqualObjects(bFirstSeenMetadata.creationDate, bFirstSeenMetadata.modificationDate, nil);
    
    [self waitForSeconds:1]; // make sure the modification will differ ... the filesystem only stores second resolution
    
    // Update it. We should not have to explicitly tell the agent to upload -- this should happen eagerly when connected to the network (based on autosave or explicit save).
    OFXFileMetadata *secondMetadata = [self uploadFixture:@"test2.package" as:@"test.package" replacingMetadata:firstMetadata];

    // Wait for the upload to finish (or we could call -sync: in the wait block below
    OFXFileMetadata *uploadedEditMetadata = [self waitForFileMetadata:self.agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded && OFNOTEQUAL(bFirstSeenMetadata.editIdentifier, metadata.editIdentifier);
    }];
    STAssertTrue(OFISEQUAL(bFirstSeenMetadata.creationDate, uploadedEditMetadata.creationDate), nil);
    STAssertTrue(OFNOTEQUAL(bFirstSeenMetadata.modificationDate, uploadedEditMetadata.modificationDate), nil);
    
    // Wait until we see an updated copy
    OFXFileMetadata *bSecondSeenMetadata = [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return OFISEQUAL(secondMetadata.editIdentifier, metadata.editIdentifier);
    }];
    STAssertTrue(bFirstSeenMetadata.downloaded == NO, nil);
    STAssertTrue(OFISEQUAL(bFirstSeenMetadata.creationDate, bSecondSeenMetadata.creationDate), nil);
    STAssertTrue(OFNOTEQUAL(bFirstSeenMetadata.modificationDate, bSecondSeenMetadata.modificationDate), nil);
    STAssertTrue(OFISEQUAL(uploadedEditMetadata.modificationDate, bSecondSeenMetadata.modificationDate), nil);

    // Download the updated copy
    OFXFileMetadata *contentDownloadedMetadata = [self downloadWithMetadata:bFirstSeenMetadata agent:self.agentB];
    
    STAssertEqualObjects(contentDownloadedMetadata.editIdentifier, bSecondSeenMetadata.editIdentifier, nil);
    STAssertEqualObjects(contentDownloadedMetadata.creationDate, bSecondSeenMetadata.creationDate, nil);
    STAssertEqualObjects(contentDownloadedMetadata.modificationDate, bSecondSeenMetadata.modificationDate, nil);

    // Make sure we got the right contents
    OFDiffFiles(self, [[self fixtureNamed:@"test2.package"] path], [contentDownloadedMetadata.fileURL path], nil);
}

- (void)testDownloadUpdatedDocumentAfterDownloadingFirstVersion;
{
    OFXFileMetadata *firstMetadata = [self uploadFixture:@"test.package"];
    
    // Wait until we see the first version
    OFXFileMetadata *bFirstSeenMetadata = [self waitForFileMetadata:self.agentB where:nil];
    STAssertTrue(bFirstSeenMetadata.downloaded == NO, nil);
    STAssertTrue(OFISEQUAL(bFirstSeenMetadata.creationDate, bFirstSeenMetadata.creationDate), nil);
    STAssertTrue(OFISEQUAL(bFirstSeenMetadata.creationDate, bFirstSeenMetadata.modificationDate), nil);
    
    // Download the first version
    OFXFileMetadata *contentDownloadedMetadata = [self downloadWithMetadata:bFirstSeenMetadata agent:self.agentB];
    STAssertEqualObjects(contentDownloadedMetadata.creationDate, contentDownloadedMetadata.modificationDate, nil);
    
    // Update it. We should not have to explicitly tell the agent to upload -- this should happen eagerly when connected to the network (based on autosave or explicit save).
    [self uploadFixture:@"test2.package" as:@"test.package" replacingMetadata:firstMetadata];
    
    // Wait for the upload to finish (or we could call -sync: in the wait block below
    OFXFileMetadata *uploadedEditMetadata = [self waitForFileMetadata:self.agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded && OFNOTEQUAL(bFirstSeenMetadata.editIdentifier, metadata.editIdentifier);
    }];
    STAssertTrue(OFISEQUAL(bFirstSeenMetadata.creationDate, uploadedEditMetadata.creationDate), nil);
    STAssertTrue(OFNOTEQUAL(bFirstSeenMetadata.modificationDate, uploadedEditMetadata.modificationDate), nil);
    
    // Wait until we see an updated copy; since we downloaded the first copy, the sync system should automatically download the edit
    OFXFileMetadata *secondContentDownloadedMetadata = [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded && OFNOTEQUAL(bFirstSeenMetadata.editIdentifier, metadata.editIdentifier);
    }];
    STAssertTrue(secondContentDownloadedMetadata.downloaded, nil);
    STAssertEqualObjects(uploadedEditMetadata.creationDate, secondContentDownloadedMetadata.creationDate, nil);
    STAssertEqualObjects(uploadedEditMetadata.modificationDate, secondContentDownloadedMetadata.modificationDate, nil);
    STAssertEqualObjects(uploadedEditMetadata.editIdentifier, secondContentDownloadedMetadata.editIdentifier, nil);
    
    // Make sure we got the right contents
    OFDiffFiles(self, [[self fixtureNamed:@"test2.package"] path], [contentDownloadedMetadata.fileURL path], nil);
}

- (void)testDownloadUpdatedDocumentAfterDownloadingFirstVersionAndThenMissingSomeVersions;
{
    OFXFileMetadata *currentMetadataA = [self uploadFixture:@"test.package"];
    
    // Download the first version and then go offline
    OFXFileMetadata *currentMetadataB = [self waitForFileMetadata:self.agentB where:nil];
    [self downloadWithMetadata:currentMetadataB agent:self.agentB];
    self.agentB.syncingEnabled = NO;

    // Update the file a couple times to step the version counter past what agentB knows about.
    for (NSUInteger uploadIndex = 0; uploadIndex < 3; uploadIndex++) {
        OFXFileMetadata *uploadedMetadataA = [self makeRandomPackageNamed:@"test.package" memberCount:2 memberSize:64];
        STAssertEqualObjects(uploadedMetadataA.fileIdentifier, currentMetadataA.fileIdentifier, nil);
        STAssertFalse([uploadedMetadataA.editIdentifier isEqual:currentMetadataA.editIdentifier], nil);
        currentMetadataA = uploadedMetadataA;
    }
    
    // Go back online and wait for the download to update to the latest version
    self.agentB.syncingEnabled = YES;
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded && [metadata.editIdentifier isEqual:currentMetadataA.editIdentifier];
    }];
    
    // Make sure we got the same contents
    OFDiffFiles(self, [currentMetadataA.fileURL path], [currentMetadataB.fileURL path], NULL/*pathFilter*/);
}

// This is intended to race vs. updates so that we sometimes have a file in local=normal/remote=edited state. Sometimes it will also hit the updated-while-downloading path.
- (void)testDownloadUpdatedDocumentWhileMakingLotsOfQuickUpdates;
{
    OFXFileMetadata *currentMetadataA = [self uploadFixture:@"test.package"];
    
    // Download the first version
    OFXFileMetadata *currentMetadataB = [self waitForFileMetadata:self.agentB where:nil];
    [self downloadWithMetadata:currentMetadataB agent:self.agentB];
    
    // Make a bunch of quick updates
    for (NSUInteger uploadIndex = 0; uploadIndex < 50; uploadIndex++) {
        OFXFileMetadata *uploadedMetadataA = [self makeRandomPackageNamed:@"test.package" memberCount:2 memberSize:64];
        STAssertEqualObjects(uploadedMetadataA.fileIdentifier, currentMetadataA.fileIdentifier, nil);
        STAssertFalse([uploadedMetadataA.editIdentifier isEqual:currentMetadataA.editIdentifier], nil);
        currentMetadataA = uploadedMetadataA;
    }
    
    // Eventually we should settle down to the final state on B.
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded && [metadata.editIdentifier isEqual:currentMetadataA.editIdentifier];
    }];
    
    // Make sure we got the same contents
    OFDiffFiles(self, [currentMetadataA.fileURL path], [currentMetadataB.fileURL path], NULL/*pathFilter*/);
}

- (void)testDownloadWithStaleMetadata;
{
    OFXFileMetadata *firstMetadata = [self uploadFixture:@"test.package"];
    
    // Wait until we see the first version
    [self.agentB sync:nil];
    OFXFileMetadata *bFirstSeenMetadata = [self waitForFileMetadata:self.agentB where:nil];
    STAssertTrue(bFirstSeenMetadata.downloaded == NO, nil);
    STAssertEqualObjects(bFirstSeenMetadata.creationDate, bFirstSeenMetadata.creationDate, nil);
    STAssertEqualObjects(bFirstSeenMetadata.creationDate, bFirstSeenMetadata.modificationDate, nil);
    
    // Update it. We should not have to explicitly tell the agent to upload -- this should happen eagerly when connected to the network (based on autosave or explicit save).
    OFXFileMetadata *uploadedEditMetadata = [self uploadFixture:@"test2.package" as:@"test.package" replacingMetadata:firstMetadata];
    STAssertEqualObjects(bFirstSeenMetadata.creationDate, uploadedEditMetadata.creationDate, nil);
    STAssertTrue(OFNOTEQUAL(bFirstSeenMetadata.modificationDate, uploadedEditMetadata.modificationDate), nil);
    
    // Attempt downloading with agentB *maybe* having old metadata. There is a race here with the net state notification. Our request might come back immediately (since we've already downloaded the old file contents).
    OFXFileMetadata *contentDownloadedMetadata = [self downloadWithMetadata:bFirstSeenMetadata agent:self.agentB];
    STAssertTrue(contentDownloadedMetadata.downloaded, nil);
    
    OFXFileMetadata *expectedDownloadMetadata;
    NSString *expectedDocumentContents;
    if ([contentDownloadedMetadata.editIdentifier isEqual:bFirstSeenMetadata.editIdentifier]) {
        // Didn't see the net state notification yet.
        expectedDownloadMetadata = bFirstSeenMetadata;
        expectedDocumentContents = @"test.package";
    } else {
        expectedDownloadMetadata = uploadedEditMetadata;
        expectedDocumentContents = @"test2.package";
    }
    
    STAssertEqualObjects(expectedDownloadMetadata.creationDate, contentDownloadedMetadata.creationDate, nil);
    STAssertEqualObjects(expectedDownloadMetadata.modificationDate, contentDownloadedMetadata.modificationDate, nil);
    STAssertEqualObjects(expectedDownloadMetadata.editIdentifier, contentDownloadedMetadata.editIdentifier, nil);
    
    // TODO: There is *still* a race here since we will start downloading the update if we didn't see it at first.
    // Make sure we got the right contents
    OFDiffFiles(self, [[self fixtureNamed:expectedDocumentContents] path], [contentDownloadedMetadata.fileURL path], nil);
}

- (void)testTransferProgress;
{
    // Make a large random file, upload it, and record the percentages we see as the file is uploading.
    {
        OFXAgent *agent = self.agentA;
        OFXServerAccount *account = [agent.accountRegistry.validCloudSyncAccounts lastObject];
        OBASSERT(account);
        
        [self copyLargeRandomTextFileToPath:@"random.txt" ofAccount:account];
        
        NSMutableArray *percentages = [NSMutableArray array];
        [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
            float percentUploaded = metadata.percentUploaded;
            STAssertTrue(percentUploaded >= 0, @"Percent should be non-negative");
            STAssertTrue(percentUploaded <= 1, @"Percent should not go over 100%");
            
            float previousPercentUploaded = -1;
            if ([percentages count] > 0)
                previousPercentUploaded = [[percentages lastObject] floatValue];
            
            if (previousPercentUploaded != percentUploaded) {
                STAssertTrue(previousPercentUploaded <= percentUploaded, @"Percent should never decrease");
                if (percentUploaded != 0 && percentUploaded != 1)
                    [percentages addObject:@(percentUploaded)]; // Record partial percentages
            }
            
            if (metadata.uploaded) {
                STAssertEquals(percentUploaded, 1.0f, @"Fully uploaded files should end at 100%");
                return YES;
            }
            return NO;
        }];
        
        //NSLog(@"percentages = %@", percentages);
        STAssertTrue([percentages count] > 0, @"Should see some partial percentages");
    }
    
    // Then, download the file and make sure we see some partial percentages.
    {
        OFXAgent *agent = self.agentB;
        [agent sync:nil];
        OFXFileMetadata *metadata = [self waitForFileMetadata:self.agentB where:nil];
        
        STAssertFalse(metadata.downloaded, nil);
        STAssertFalse(metadata.downloading, nil);
        
        [self.agentB requestDownloadOfItemAtURL:metadata.fileURL completionHandler:^(NSError *errorOrNil) {
            STAssertNil(errorOrNil, nil);
        }];
        
        NSMutableArray *percentages = [NSMutableArray array];
        [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
            float percentDownloaded = metadata.percentDownloaded;
            STAssertTrue(percentDownloaded >= 0, @"Percent should be non-negative");
            STAssertTrue(percentDownloaded <= 1, @"Percent should not go over 100%");
            
            float previousPercentDownloaded = -1;
            if ([percentages count] > 0)
                previousPercentDownloaded = [[percentages lastObject] floatValue];
            
            if (previousPercentDownloaded != percentDownloaded) {
                STAssertTrue(previousPercentDownloaded <= percentDownloaded, @"Percent should never decrease");
                if (percentDownloaded != 0 && percentDownloaded != 1)
                    [percentages addObject:@(percentDownloaded)]; // Record partial percentages
            }
            
            if (metadata.downloaded) {
                STAssertFalse(metadata.downloading, @"Should stop being downloaded once fully downloaded");
                STAssertEquals(percentDownloaded, 1.0f, @"Fully downloaded files should end at 100%");
                return YES;
            } else if (percentDownloaded > 0) // might not have started yet
                STAssertTrue(metadata.downloading, @"Should stay downloading until fully downloaded");
            return NO;
        }];
        //NSLog(@"percentages = %@", percentages);
        STAssertTrue([percentages count] > 0, @"Should see some partial percentages");
    }
}

- (void)testIncomingUpdateWhileDownloading;
{
    // Make a large file on agentA
    OFXFileMetadata *originalMetadata = [self makeRandomLargePackage:@"random.package"];

    // Start downloading the large file
    OFXAgent *agentB = self.agentB;
    [self downloadFileWithIdentifier:originalMetadata.fileIdentifier untilPercentage:0.1 agent:agentB];

    [NSError suppressingLogsWithUnderlyingDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_NOT_FOUND action:^{
        // Replace the file that is downloading
        OFXAgent *agentA = self.agentA;
        OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
        [self copyFixtureNamed:@"test.package" toPath:@"random.package" ofAccount:accountA];
        OFXFileMetadata *smallFileA = [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
            return metadata.fileSize < 1000 && metadata.uploaded; // Make sure the small file is uploaded
        }];
        
        // Eventually, the other agent should get the small file
        OFXFileMetadata *smallFileB = [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
            return [metadata.editIdentifier isEqual:smallFileA.editIdentifier] && metadata.downloaded;
        }];
        
        STAssertTrue(ITEM_MATCHES_FIXTURE(smallFileB, @"test.package"), nil);
    }];
}

- (void)testIncomingUpdateOfPreviouslyDownloadedFileWhileDownloading;
{
    // Start out with the same package everywhere
    [self uploadFixture:@"test.package"];
    
    // Make a large replacement; this should start downloading on B since it downloaded the first version. Wait for it to get to a certain percentage though.
    OFXFileMetadata *randomMetadata = [self makeRandomLargePackage:@"test.package"];
    [self downloadFileWithIdentifier:randomMetadata.fileIdentifier untilPercentage:0.1 agent:self.agentB];
    
    // Replace the file yet again
    OFXServerAccount *accountA = [self.agentA.accountRegistry.validCloudSyncAccounts lastObject];
    [self copyFixtureNamed:@"test2.package" toPath:@"test.package" ofAccount:accountA];
    
    // We should settle down on the third version of the file
    OFXFileMetadata *finalMetadata = [self waitForFileMetadata:self.agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.fileSize < 1000 && metadata.uploaded; // Make sure the small file is uploaded
    }];
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded && OFISEQUAL(finalMetadata.editIdentifier, metadata.editIdentifier);
    }];
}

- (void)testLocalUpdateWhileDownloading;
{
    self.agentA.automaticallyDownloadFileContents = YES; // So the conflict downloads
    self.agentB.automaticallyDownloadFileContents = YES; // So the first version downloads

    // Start out with the same package everywhere
    [self copyFixtureNamed:@"test.package"];
    
    // Make a large replacement; this should start downloading on B since it downloaded the first version. Wait for it to get to a certain percentage though.
    OFXFileMetadata *randomMetadata = [self makeRandomPackageNamed:@"test.package" memberCount:32 memberSize:4*1024*1024]; // Too low and we can randomly finish the download before B can clobber the file.

    [self downloadFileWithIdentifier:randomMetadata.fileIdentifier untilPercentage:0.1 agent:self.agentB];
    
    // Replace the file on B.
    OFXServerAccount *accountB = [self.agentB.accountRegistry.validCloudSyncAccounts lastObject];
    [self copyFixtureNamed:@"test2.package" toPath:@"test.package" ofAccount:accountB];
    
    // Should end up with two files due to the conflict
    BOOL (^predicate)(NSSet *metadataItems) = ^(NSSet *metadataItems){
        if ([metadataItems count] != 2)
            return NO;
        
        // Since the random package made it to the server first, it should be the conflict winner.
        OFXFileMetadata *nonConflict = [metadataItems any:^BOOL(OFXFileMetadata *metadata) {
            return [[metadata.fileURL lastPathComponent] isEqual:@"test.package"];
        }];
        if (!nonConflict)
            return NO;
        if (!nonConflict.downloaded || OFNOTEQUAL(nonConflict.editIdentifier, randomMetadata.editIdentifier))
            return NO;
        
        // There should also be a conflict with the appropriate contents
        OFXFileMetadata *conflict = [metadataItems any:^BOOL(OFXFileMetadata *metadata) {
            return [[[metadata.fileURL lastPathComponent] stringByDeletingPathExtension] containsString:@"Conflict" options:NSCaseInsensitiveSearch];
        }];
        if (!conflict.downloaded || !ITEM_MATCHES_FIXTURE(conflict, @"test2.package"))
            return NO;
        
        return YES;
    };
    
    [self waitForFileMetadataItems:self.agentA where:predicate];
    [self waitForFileMetadataItems:self.agentB where:predicate];
}

// Write version of -testLocalUpdateWhileDownloading where we simulate local unsaved changes when there is an incoming download update of a file
// Test uploading a new document w/o automatically downloading a different large document
// Replace a file with different contents but the same mtime while syncing is off. Turn on syncing. Dropbox doesn't notice the change.
// Test creating a folder with a path extension that is marked as being a package on the server but for a file type the local app doesn't support. For example, if OmniGraffle/iPad made a document called "foo.oo3/bar.graffle". We wouldn't want it to get eaten and look like a .oo3 file (without a contents.xml for that matter).
// write tests for case insensitivity of path extensions
// write tests for case insensitivity of file names
// write tests for case insensitivity of containing directories
// write tests for in-place edits of members of file packages (maybe while our agent isn't running). That is, we should check for timestamp changes inside file packages, not just of the package itself.
// test creating "foo/doc.ext" with one agent, "Foo/doc2.ext" on another and various similar case craziness.
// test that the agent refuses to start accounts on case sensitive filesystems (or handle it)
// test that the agent refuses to start accounts on non-local filesystems (NFS won't send us file presenter/FSEvent notifications)


@end

