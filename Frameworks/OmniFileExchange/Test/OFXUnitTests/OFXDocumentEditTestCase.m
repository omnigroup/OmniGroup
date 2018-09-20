// Copyright 2013-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

#import "OFXTrace.h"
#import <OmniFileExchange/OFXAccountClientParameters.h>

#import <OmniFoundation/OFNull.h>
#import <OmniDAV/ODAVErrors.h>

RCS_ID("$Id$")

@interface OFXDocumentEditTestCase : OFXTestCase
@end


@implementation OFXDocumentEditTestCase

- (OFXAccountClientParameters *)accountClientParametersForAgentName:(NSString *)agentName;
{
    OFXAccountClientParameters *clientParameters = [super accountClientParametersForAgentName:agentName];

    // Speed up metadata updates in a copule casees where we are trying to catch it while it is downloading.
    SEL testSelector = self.invocation.selector;
    BOOL fasterMetadataUpdates = NO;
    fasterMetadataUpdates |= (testSelector == @selector(testIncomingUpdateWhileDownloading) && [agentName isEqual:@"B"]);
    fasterMetadataUpdates |= (testSelector == @selector(testIncomingUpdateOfPreviouslyDownloadedFileWhileDownloading) && [agentName isEqual:@"B"]);
    fasterMetadataUpdates |= (testSelector == @selector(testLocalUpdateWhileDownloading) && [agentName isEqual:@"B"]);

    if (fasterMetadataUpdates) {
        clientParameters.metadataUpdateInterval = 0.0001;
    }

    return clientParameters;
}

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

    XCTAssertEqual(1ULL, [metadataItems count]);
    
    OFXFileMetadata *metadata = [metadataItems anyObject];
    XCTAssertEqualObjects([metadata.fileURL lastPathComponent], @"test.package");
    XCTAssertEqual(34ULL, metadata.fileSize);
    XCTAssertEqualWithAccuracy(metadata.creationDate.timeIntervalSinceReferenceDate, metadata.modificationDate.timeIntervalSinceReferenceDate, 0.01); // Copying files into a package modifies the directory
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
        XCTAssertEqual([metadataItems count], 1ULL, @"the old metadata should replace the new one");

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

        XCTAssertEqual([[self.agentB metadataItemsForAccount:account] count], 1ULL);
    }
    
    // Download the item
    {
        OFXServerAccount *account = [self.agentB.accountRegistry.validCloudSyncAccounts lastObject];

        OFXFileMetadata *placeholderMetadata = [[self.agentB metadataItemsForAccount:account] anyObject];
        XCTAssertFalse(placeholderMetadata.downloaded);

        [self.agentB requestDownloadOfItemAtURL:placeholderMetadata.fileURL completionHandler:^(NSError *errorOrNil) {
            XCTAssertNil(errorOrNil);
        }];

        OFXFileMetadata *downloadedMetadata = [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata){
            return metadata.downloaded;
        }];
        XCTAssertTrue(downloadedMetadata.downloaded);
        XCTAssertEqualObjects(placeholderMetadata.creationDate, downloadedMetadata.creationDate);
        XCTAssertEqualWithAccuracy(downloadedMetadata.creationDate.timeIntervalSinceReferenceDate, downloadedMetadata.modificationDate.timeIntervalSinceReferenceDate, 0.01); // Copying files into a package modifies the directory

        // Make sure we got the right contents
        OFDiffFiles(self, [[self fixtureNamed:@"test.package"] path], [downloadedMetadata.fileURL path], nil);
    }
}

- (void)testDownloadUpdatedDocumentWithoutDownloadingFirstVersion;
{
    OFXFileMetadata *firstMetadata = [self uploadFixture:@"test.package"];
 
    // Wait until we see the first version
    OFXFileMetadata *bFirstSeenMetadata = [self waitForFileMetadata:self.agentB where:nil];
    XCTAssertTrue(bFirstSeenMetadata.downloaded == NO);
    XCTAssertEqualWithAccuracy(bFirstSeenMetadata.creationDate.timeIntervalSinceReferenceDate, bFirstSeenMetadata.modificationDate.timeIntervalSinceReferenceDate, 0.01); // Copying files into a package modifies the directory

    [self waitForSeconds:1]; // make sure the modification will differ ... the filesystem only stores second resolution
    
    // Update it. We should not have to explicitly tell the agent to upload -- this should happen eagerly when connected to the network (based on autosave or explicit save).
    OFXFileMetadata *secondMetadata = [self uploadFixture:@"test2.package" as:@"test.package" replacingMetadata:firstMetadata];

    // Wait for the upload to finish (or we could call -sync: in the wait block below
    OFXFileMetadata *uploadedEditMetadata = [self waitForFileMetadata:self.agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded && OFNOTEQUAL(bFirstSeenMetadata.editIdentifier, metadata.editIdentifier);
    }];
    XCTAssertTrue(OFISEQUAL(bFirstSeenMetadata.creationDate, uploadedEditMetadata.creationDate));
    XCTAssertTrue(OFNOTEQUAL(bFirstSeenMetadata.modificationDate, uploadedEditMetadata.modificationDate));
    
    // Wait until we see an updated copy
    OFXFileMetadata *bSecondSeenMetadata = [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return OFISEQUAL(secondMetadata.editIdentifier, metadata.editIdentifier);
    }];
    XCTAssertTrue(bFirstSeenMetadata.downloaded == NO);
    XCTAssertTrue(OFISEQUAL(bFirstSeenMetadata.creationDate, bSecondSeenMetadata.creationDate));
    XCTAssertTrue(OFNOTEQUAL(bFirstSeenMetadata.modificationDate, bSecondSeenMetadata.modificationDate));
    XCTAssertTrue(OFISEQUAL(uploadedEditMetadata.modificationDate, bSecondSeenMetadata.modificationDate));

    // Download the updated copy
    OFXFileMetadata *contentDownloadedMetadata = [self downloadWithMetadata:bFirstSeenMetadata agent:self.agentB];
    
    XCTAssertEqualObjects(contentDownloadedMetadata.editIdentifier, bSecondSeenMetadata.editIdentifier);
    XCTAssertEqualObjects(contentDownloadedMetadata.creationDate, bSecondSeenMetadata.creationDate);
    XCTAssertEqualObjects(contentDownloadedMetadata.modificationDate, bSecondSeenMetadata.modificationDate);

    // Make sure we got the right contents
    OFDiffFiles(self, [[self fixtureNamed:@"test2.package"] path], [contentDownloadedMetadata.fileURL path], nil);
}

- (void)testDownloadUpdatedDocumentAfterDownloadingFirstVersion;
{
    OFXFileMetadata *firstMetadata = [self uploadFixture:@"test.package"];
    
    // Wait until we see the first version
    OFXFileMetadata *bFirstSeenMetadata = [self waitForFileMetadata:self.agentB where:nil];
    XCTAssertTrue(bFirstSeenMetadata.downloaded == NO);
    XCTAssertEqualObjects(firstMetadata.creationDate, bFirstSeenMetadata.creationDate);
    XCTAssertEqualWithAccuracy(bFirstSeenMetadata.creationDate.timeIntervalSinceReferenceDate, bFirstSeenMetadata.modificationDate.timeIntervalSinceReferenceDate, 0.01); // Copying files into a package modifies the directory

    // Download the first version
    OFXFileMetadata *contentDownloadedMetadata = [self downloadWithMetadata:bFirstSeenMetadata agent:self.agentB];
    XCTAssertEqualWithAccuracy(contentDownloadedMetadata.creationDate.timeIntervalSinceReferenceDate, contentDownloadedMetadata.modificationDate.timeIntervalSinceReferenceDate, 0.01); // Copying files into a package modifies the directory

    // Update it. We should not have to explicitly tell the agent to upload -- this should happen eagerly when connected to the network (based on autosave or explicit save).
    [self uploadFixture:@"test2.package" as:@"test.package" replacingMetadata:firstMetadata];
    
    // Wait for the upload to finish (or we could call -sync: in the wait block below
    OFXFileMetadata *uploadedEditMetadata = [self waitForFileMetadata:self.agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded && OFNOTEQUAL(bFirstSeenMetadata.editIdentifier, metadata.editIdentifier);
    }];
    XCTAssertTrue(OFISEQUAL(bFirstSeenMetadata.creationDate, uploadedEditMetadata.creationDate));
    XCTAssertTrue(OFNOTEQUAL(bFirstSeenMetadata.modificationDate, uploadedEditMetadata.modificationDate));
    
    // Wait until we see an updated copy; since we downloaded the first copy, the sync system should automatically download the edit
    OFXFileMetadata *secondContentDownloadedMetadata = [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded && OFNOTEQUAL(bFirstSeenMetadata.editIdentifier, metadata.editIdentifier);
    }];
    XCTAssertTrue(secondContentDownloadedMetadata.downloaded);
    XCTAssertEqualObjects(uploadedEditMetadata.creationDate, secondContentDownloadedMetadata.creationDate);
    XCTAssertEqualObjects(uploadedEditMetadata.modificationDate, secondContentDownloadedMetadata.modificationDate);
    XCTAssertEqualObjects(uploadedEditMetadata.editIdentifier, secondContentDownloadedMetadata.editIdentifier);
    
    // Make sure we got the right contents
    OFDiffFiles(self, [[self fixtureNamed:@"test2.package"] path], [contentDownloadedMetadata.fileURL path], nil);
}

- (void)testDownloadUpdatedDocumentAfterDownloadingFirstVersionAndThenMissingSomeVersions;
{
    OFXFileMetadata *currentMetadataA = [self uploadFixture:@"test.package"];
    
    // Download the first version and then go offline
    OFXFileMetadata *currentMetadataB = [self waitForFileMetadata:self.agentB where:nil];
    [self downloadWithMetadata:currentMetadataB agent:self.agentB];
    self.agentB.syncSchedule = OFXSyncScheduleNone;

    // Update the file a couple times to step the version counter past what agentB knows about.
    for (NSUInteger uploadIndex = 0; uploadIndex < 3; uploadIndex++) {
        OFXFileMetadata *uploadedMetadataA = [self makeRandomPackageNamed:@"test.package" memberCount:2 memberSize:64];
        XCTAssertEqualObjects(uploadedMetadataA.fileIdentifier, currentMetadataA.fileIdentifier);
        XCTAssertFalse([uploadedMetadataA.editIdentifier isEqual:currentMetadataA.editIdentifier]);
        currentMetadataA = uploadedMetadataA;
    }
    
    // Go back online and wait for the download to update to the latest version
    self.agentB.syncSchedule = OFXSyncScheduleAutomatic;
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded && [metadata.editIdentifier isEqual:currentMetadataA.editIdentifier];
    }];
    
    // Make sure we got the same contents
    OFDiffFiles(self, [currentMetadataA.fileURL path], [currentMetadataB.fileURL path], nil/*operations*/);
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
        XCTAssertEqualObjects(uploadedMetadataA.fileIdentifier, currentMetadataA.fileIdentifier);
        XCTAssertFalse([uploadedMetadataA.editIdentifier isEqual:currentMetadataA.editIdentifier]);
        currentMetadataA = uploadedMetadataA;
    }
    
    // Eventually we should settle down to the final state on B.
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded && [metadata.editIdentifier isEqual:currentMetadataA.editIdentifier];
    }];
    
    // Make sure we got the same contents
    OFDiffFiles(self, [currentMetadataA.fileURL path], [currentMetadataB.fileURL path], nil/*operations*/);
}

- (void)testDownloadWithStaleMetadata;
{
    OFXFileMetadata *firstMetadata = [self uploadFixture:@"test.package"];
    
    // Wait until we see the first version
    [self.agentB sync:nil];
    OFXFileMetadata *bFirstSeenMetadata = [self waitForFileMetadata:self.agentB where:nil];
    XCTAssertTrue(bFirstSeenMetadata.downloaded == NO);
    XCTAssertEqualObjects(firstMetadata.creationDate, bFirstSeenMetadata.creationDate);
    XCTAssertEqualObjects(firstMetadata.modificationDate, bFirstSeenMetadata.modificationDate);
    XCTAssertEqualWithAccuracy(bFirstSeenMetadata.creationDate.timeIntervalSinceReferenceDate, bFirstSeenMetadata.modificationDate.timeIntervalSinceReferenceDate, 0.01); // Copying files into a package modifies the directory

    // Update it. We should not have to explicitly tell the agent to upload -- this should happen eagerly when connected to the network (based on autosave or explicit save).
    OFXFileMetadata *uploadedEditMetadata = [self uploadFixture:@"test2.package" as:@"test.package" replacingMetadata:firstMetadata];
    XCTAssertEqualObjects(bFirstSeenMetadata.creationDate, uploadedEditMetadata.creationDate);
    XCTAssertTrue(OFNOTEQUAL(bFirstSeenMetadata.modificationDate, uploadedEditMetadata.modificationDate));
    
    // Attempt downloading with agentB *maybe* having old metadata. There is a race here with the net state notification. Our request might come back immediately (since we've already downloaded the old file contents).
    OFXFileMetadata *contentDownloadedMetadata = [self downloadWithMetadata:bFirstSeenMetadata agent:self.agentB];
    XCTAssertTrue(contentDownloadedMetadata.downloaded);
    
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
    
    XCTAssertEqualObjects(expectedDownloadMetadata.creationDate, contentDownloadedMetadata.creationDate);
    XCTAssertEqualObjects(expectedDownloadMetadata.modificationDate, contentDownloadedMetadata.modificationDate);
    XCTAssertEqualObjects(expectedDownloadMetadata.editIdentifier, contentDownloadedMetadata.editIdentifier);
    
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
            XCTAssertTrue(percentUploaded >= 0, @"Percent should be non-negative");
            XCTAssertTrue(percentUploaded <= 1, @"Percent should not go over 100%%");
            
            float previousPercentUploaded = -1;
            if ([percentages count] > 0)
                previousPercentUploaded = [[percentages lastObject] floatValue];
            
            if (previousPercentUploaded != percentUploaded) {
                XCTAssertTrue(previousPercentUploaded <= percentUploaded, @"Percent should never decrease");
                if (percentUploaded != 0 && percentUploaded != 1)
                    [percentages addObject:@(percentUploaded)]; // Record partial percentages
            }
            
            if (metadata.uploaded) {
                XCTAssertEqual(percentUploaded, 1.0f, @"Fully uploaded files should end at 100%%");
                return YES;
            }
            return NO;
        }];
        
        //NSLog(@"percentages = %@", percentages);
        XCTAssertTrue([percentages count] > 0, @"Should see some partial percentages");
    }
    
    // Then, download the file and make sure we see some partial percentages.
    {
        OFXAgent *agent = self.agentB;

        {
            [agent sync:nil];
            OFXFileMetadata *metadata = [self waitForFileMetadata:self.agentB where:nil];

            XCTAssertFalse(metadata.downloaded);
            XCTAssertFalse(metadata.downloading);

            [self.agentB requestDownloadOfItemAtURL:metadata.fileURL completionHandler:^(NSError *errorOrNil) {
                XCTAssertNil(errorOrNil);
            }];
        }

        NSMutableArray *percentages = [NSMutableArray array];
        [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
            float percentDownloaded = metadata.percentDownloaded;
            XCTAssertTrue(percentDownloaded >= 0, @"Percent should be non-negative");
            XCTAssertTrue(percentDownloaded <= 1, @"Percent should not go over 100%%");
            
            float previousPercentDownloaded = -1;
            if ([percentages count] > 0)
                previousPercentDownloaded = [[percentages lastObject] floatValue];
            
            if (previousPercentDownloaded != percentDownloaded) {
                XCTAssertTrue(previousPercentDownloaded <= percentDownloaded, @"Percent should never decrease");
                if (percentDownloaded != 0 && percentDownloaded != 1)
                    [percentages addObject:@(percentDownloaded)]; // Record partial percentages
            }
            
            if (metadata.downloaded) {
                XCTAssertFalse(metadata.downloading, @"Should stop being downloaded once fully downloaded");
                XCTAssertEqual(percentDownloaded, 1.0f, @"Fully downloaded files should end at 100%%");
                return YES;
            } else if (percentDownloaded > 0) // might not have started yet
                XCTAssertTrue(metadata.downloading, @"Should stay downloading until fully downloaded");
            return NO;
        }];
        //NSLog(@"percentages = %@", percentages);
        XCTAssertTrue([percentages count] > 0, @"Should see some partial percentages");
    }
}

- (void)testIncomingUpdateWhileDownloading;
{
    // Make a large file on agentA
    OFXFileMetadata *originalMetadata = [self makeRandomLargePackage:@"random.package"];

    // Start downloading the large file
    OFXAgent *agentB = self.agentB;
    [self downloadFileWithIdentifier:originalMetadata.fileIdentifier untilPercentage:0.1 agent:agentB];

    [NSError suppressingLogsWithUnderlyingDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_NOT_FOUND action:^{
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
        
        XCTAssertTrue(ITEM_MATCHES_FIXTURE(smallFileB, @"test.package"));
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
    OFXFileMetadata *originalMetadata = [self copyFixtureNamed:@"test.package"];
    
    // Make a large replacement; this should start downloading on B since it downloaded the first version. Wait for it to get to a certain percentage though.
    OFXFileMetadata *randomMetadata = [self makeRandomPackageNamed:@"test.package" memberCount:32 memberSize:4*1024*1024]; // Too low and we can randomly finish the download before B can clobber the file.
    XCTAssertEqualObjects(originalMetadata.fileIdentifier, randomMetadata.fileIdentifier);
    
    [self downloadFileWithIdentifier:randomMetadata.fileIdentifier untilPercentage:0.1 agent:self.agentB];
    
    // Replace the file on B.
    OFXServerAccount *accountB = [self.agentB.accountRegistry.validCloudSyncAccounts lastObject];
    [self copyFixtureNamed:@"test2.package" toPath:@"test.package" ofAccount:accountB];
    
    OFXFileMetadata *(^updatedFile)(NSSet *metadataItems, NSString *fileIdentifier, BOOL shouldMatch) = ^OFXFileMetadata *(NSSet *metadataItems, NSString *fileIdentifier, BOOL shouldMatch){
        OFXFileMetadata *updatedMetadata = [metadataItems any:^BOOL(OFXFileMetadata *metadata) {
            // Both files should be conflicts
            NSString *filename = [[metadata.fileURL lastPathComponent] stringByDeletingPathExtension];
            if (![filename containsString:@"Conflict" options:NSCaseInsensitiveSearch])
                return NO;
            
            return !(shouldMatch ^ [metadata.fileIdentifier isEqual:fileIdentifier]);
        }];
        
        // Both should be downloaded
        if (!updatedMetadata.downloaded)
            return nil;
        return updatedMetadata;
    };
    
    // Should end up with two files due to the conflict
    BOOL (^predicate)(NSSet *metadataItems) = ^(NSSet *metadataItems){
        // We should have two conflict files, one for each edit (the random blob from agentA and test2.package from agentB).
        if ([metadataItems count] != 2)
            return NO;
        
        OFXFileMetadata *updateFromAgentA = updatedFile(metadataItems, originalMetadata.fileIdentifier, YES); // This should be the original -> random edited file
        if (!updateFromAgentA)
            return NO;

        OFXFileMetadata *updateFromAgentB = updatedFile(metadataItems, originalMetadata.fileIdentifier, NO); // This should be the conflict with the random edit.
        if (!updateFromAgentB)
            return NO;
        
        XCTAssertEqualObjects(updateFromAgentA.editIdentifier, randomMetadata.editIdentifier);
        XCTAssertTrue(ITEM_MATCHES_FIXTURE(updateFromAgentB, @"test2.package"));
        
        return YES;
    };
    
    [self waitForFileMetadataItems:self.agentA where:predicate];
    [self waitForFileMetadataItems:self.agentB where:predicate];
}

- (void)testIncomingMoveAndOutgoingUpload;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    agentA.automaticallyDownloadFileContents = YES;
    agentB.automaticallyDownloadFileContents = YES;
    
    // Get the same file on both.
    [self uploadFixture:@"test.package"];
    OFXFileMetadata *originalMetadata = [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded;
    }];
    
    agentA.syncSchedule = OFXSyncScheduleNone;
    agentB.syncSchedule = OFXSyncScheduleNone;
    
    // Move on A
    [self movePath:@"test.package" toPath:@"test-A.package" ofAccount:[self singleAccountInAgent:agentA]];
    
    // Add a new file on B
    [self copyFixtureNamed:@"test2.package" toPath:@"test-B.package" ofAccount:[self singleAccountInAgent:agentB]];
    
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    agentB.syncSchedule = OFXSyncScheduleAutomatic;
    
    // Make sure the changes are acknowledged
    [self waitForChangeToMetadata:originalMetadata inAgent:agentA];
    [self waitForChangeToMetadata:originalMetadata inAgent:agentB];
    
    // Wait for the agents to settle down to a common state.
    [self waitForAgentsEditsToAgree];
    [self requireAgentsToHaveSameFilesByName];
    
    {
        NSSet *metadataItems = [self metadataItemsForAgent:agentA];
        XCTAssertTrue([metadataItems count] == 2);

        OFXFileMetadata *finalMetadataA = [metadataItems any:^BOOL(OFXFileMetadata *metadata) {
            return [[metadata.fileURL lastPathComponent] isEqual:@"test-A.package"];
        }];
        OFXFileMetadata *finalMetadataB = [metadataItems any:^BOOL(OFXFileMetadata *metadata) {
            return [[metadata.fileURL lastPathComponent] isEqual:@"test-B.package"];
        }];
        
        XCTAssertTrue(ITEM_MATCHES_FIXTURE(finalMetadataA, @"test.package"));
        XCTAssertTrue(ITEM_MATCHES_FIXTURE(finalMetadataB, @"test2.package"));
    }
}

// Simulate a network failure while trying to delete version N of a file after uploading version N+1. This started happening fairly often in 10.10, seemingly due to changes in the network stack <bug:///109269> (Unassigned: Please don't interpret network loss as a conflict error [distance, ssl]). We now ignore network failures when doing this cleanup on an upload, but we should eventually notice these stale versions and clean them up.
- (void)testCleanupOfStaleVersions;
{
    OFXAgent *agentA = self.agentA;
    agentA.clientParameters.deletePreviousFileVersionAfterNewVersionUploaded = NO;

    OFXAgent *agentB = self.agentB;
    agentB.syncSchedule = OFXSyncScheduleNone;

    // Upload two versions of a file on A
    OFXFileMetadata *originalMetadata = [self uploadFixture:@"test.package"];
    OFXFileMetadata *updatedMetadata = [self uploadFixture:@"test2.package" as:@"test.package" replacingMetadata:originalMetadata];

    // Turn syncing on for agent B; it should download the newest version of the document and delete the old one.
    agentB.syncSchedule = OFXSyncScheduleAutomatic;
    
    OFXFileMetadata *finalMetadataB = [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        if ([metadata.fileIdentifier isEqual:updatedMetadata.fileIdentifier] && [metadata.editIdentifier isEqual:updatedMetadata.editIdentifier]) {
            if (metadata.downloaded)
                return YES;
            if (!metadata.downloading)
                [agentB requestDownloadOfItemAtURL:metadata.fileURL completionHandler:nil];
        }
        return NO;
    }];
    
    XCTAssertTrue(ITEM_MATCHES_FIXTURE(finalMetadataB, @"test2.package"), "Agent B should have downloaded the current version, not the stale version");
    XCTAssert(OFXTraceHasSignal(@"OFXContainerAgent.delete_stale_version_during_sync"), "The old version should have been noticed and cleaned up.");
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

