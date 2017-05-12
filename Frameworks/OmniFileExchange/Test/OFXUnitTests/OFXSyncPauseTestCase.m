// Copyright 2013-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

RCS_ID("$Id$")

@interface OFXInterruptSyncTestCase : OFXTestCase
@end

@implementation OFXInterruptSyncTestCase

+ (XCTestSuite *)defaultTestSuite;
{
    if (self == [OFXInterruptSyncTestCase class])
        return [[XCTestSuite alloc] initWithName:@"OFXInterruptSyncTestCase"]; // Don't run tests for this abstract superclass
    return [super defaultTestSuite];
}

- (void)testPauseUploadAndThenResume;
{
    OFXAgent *agentA = self.agentA;

    // Make a large random file, and start uploading it.
    NSString *randomText;
    {
        OFXServerAccount *account = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
        OBASSERT(account);
        randomText = [self copyLargeRandomTextFileToPath:@"random.txt" ofAccount:account];
    }
    
    // Wait for the file to make some progress, so we know the transfer was really going.
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        float percentUploaded = metadata.percentUploaded;
        if (percentUploaded >= 1) {
            XCTFail(@"Waited too long!");
        }
        if (percentUploaded > 0.1) {
            // Turn off syncing. This should cancel the pending transfer.
            [self disableAgent:agentA];
            return YES;
        }
        return NO;
    }];
    
    if (agentA.started) { // Only applies to 'pause' version
        // Wait for the transfer to be cancelled.
        [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
            return (metadata.uploading == NO && metadata.percentUploaded == 0);
        }];
    }
    
    // Sync on another agent and there should be nothing present
    OFXAgent *agentB = self.agentB;
    [self waitForSync:agentB];
    XCTAssertEqual([[self metadataItemsForAgent:agentB] count], 0ULL, @"should be no metadata items");
        
    // Turn syncing back on and wait for the file to get uploaded
    [self enableAgent:agentA];
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return (metadata.uploaded == YES && metadata.percentUploaded >= 1);
    }];
    
    // The item should then appear on the other agent.
    OFXFileMetadata *metadataB = [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return YES;
    }];
    
    // Download it
    [self.agentB requestDownloadOfItemAtURL:metadataB.fileURL completionHandler:^(NSError *errorOrNil) {
        XCTAssertNil(errorOrNil, @"Download should start");
    }];
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return (metadata.downloaded == YES && metadata.percentDownloaded >= 1);
    }];

    // Check that the contents are the same.
    {
        OFXServerAccount *account = [agentB.accountRegistry.validCloudSyncAccounts lastObject];
        OBASSERT(account);
        
        NSURL *randomTextURL = [account.localDocumentsURL URLByAppendingPathComponent:@"random.txt"];
        NSString *downloadedRandomText = [[NSString alloc] initWithContentsOfURL:randomTextURL encoding:NSUTF8StringEncoding error:NULL];
        XCTAssertTrue([randomText isEqual:downloadedRandomText], @"Downloaded text should be the same as uploaded");
    }
}

- (void)testPauseDownloadAndThenResume;
{
    // Make a large random file, and upload it.
    NSString *randomText;
    {
        OFXAgent *agentA = self.agentA;
        OFXServerAccount *account = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
        OBASSERT(account);
        
        randomText = [self copyLargeRandomTextFileToPath:@"random.txt" ofAccount:account];
        
        [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
            return metadata.uploaded && !metadata.uploading;
        }];
    }
    
    // Start a download on the second agent.
    OFXAgent *agentB = self.agentB;
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        [self.agentB requestDownloadOfItemAtURL:metadata.fileURL completionHandler:^(NSError *errorOrNil) {
            XCTAssertNil(errorOrNil, @"Download should start");
        }];
        return YES;
    }];

    // Wait for the download to make some progress and then cancel it.
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        float percentDownloaded = metadata.percentDownloaded;
        if (percentDownloaded >= 1) {
            XCTFail(@"Waited too long!");
        }
        if (percentDownloaded > 0.1) {
            [self disableAgent:agentB];
            return YES;
        }
        return NO;
    }];

    if (agentB.started) { // Only applies to 'pause' version
        // Wait for the transfer to be cancelled.
        [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
            return (metadata.downloading == NO && metadata.percentDownloaded == 0);
        }];
    }
    
    // Turn syncing back on. Since we'd previously requested that the file download, it will restart (bug? should we clear this in OFXFileItem when sync is turned off?)
    [self enableAgent:agentB];
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return (metadata.downloading == NO && metadata.percentDownloaded >= 1);
    }];
    
    // Check that the contents are the same.
    {
        OFXServerAccount *account = [agentB.accountRegistry.validCloudSyncAccounts lastObject];
        OBASSERT(account);
        
        NSURL *randomTextURL = [account.localDocumentsURL URLByAppendingPathComponent:@"random.txt"];
        NSString *downloadedRandomText = [[NSString alloc] initWithContentsOfURL:randomTextURL encoding:NSUTF8StringEncoding error:NULL];
        XCTAssertTrue([randomText isEqual:downloadedRandomText], @"Downloaded text should be the same as uploaded");
    }
}

- (void)testCreateFileWhileSyncingDisabled;
{
    // Pause our agent.
    OFXAgent *agent = self.agentA;
    OFXServerAccount *account = [agent.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(account);
    [self disableAgent:agent];
    
    // Wait a bit to make sure it is done with startup sync.
    [self waitForAsyncOperations];
    
    // Create a file.
    [self copyFixtureNamed:@"test.package" ofAccount:account];
    
    if (agent.started) { // Only applies to 'pause' version
        // Our agent should notice this new file, wait for the item to appear.
        [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
            return metadata.uploaded == NO;
        }];
        
        // Wait a bit more to see if the agent decides to upload it... it shouldn't.
        [self waitForSeconds:0.25];
        [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
            return metadata.uploaded == NO && metadata.uploading == NO;
        }];
    }

    // Turn syncing back on; the file should get uploaded.
    [self enableAgent:agent];
    [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded == YES && metadata.uploading == NO;
    }];
}

- (void)testRenameFileWhileSyncingDisabled;
{
    // Make a document and download to two agents
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(accountA);
    
    [self copyFixtureNamed:@"test.package" ofAccount:accountA];
    
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata){
        return [[metadata.fileURL lastPathComponent] isEqual:@"test.package"] && metadata.isDownloaded;
    }];

    // Turn off syncing and rename the file
    [self disableAgent:agentA];
    [self movePath:@"test.package" toPath:@"test-rename.package" ofAccount:accountA];

    if (agentA.started) { // Only applies to 'pause' version
        // We should notice that it needs upload.
        [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
            return metadata.uploaded == NO;
        }];
    }
    
    // Wait a bit more to see if the agent decides to upload it... it shouldn't.
    [self waitForSeconds:0.25];
    
    if (agentA.started) { // Only applies to 'pause' version
        [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
            return metadata.uploaded == NO && metadata.uploading == NO;
        }];
    }
    
    // Turn syncing back on; the rename should get uploaded.
    [self enableAgent:agentA];
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return [[metadata.fileURL lastPathComponent] isEqual:@"test-rename.package"] && metadata.isDownloaded;
    }];
}

- (void)testDeleteFileWhileSyncingDisabled;
{
    // Make a document and download to two agents
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(accountA);
    
    [self copyFixtureNamed:@"test.package" ofAccount:accountA];
    
    OFXAgent *agentB = self.agentB;
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata){
        return [[metadata.fileURL lastPathComponent] isEqual:@"test.package"] && metadata.isDownloaded;
    }];

    // Turn off syncing and delete the file
    [self disableAgent:agentA];
    [self deletePath:@"test.package" ofAccount:accountA];

    if (agentA.started) { // Only applies to 'pause' version
        // We should stop advertising the file locally.
        [self waitForFileMetadataItems:agentA where:^BOOL(NSSet *metadataItems) {
            return [metadataItems count] == 0;
        }];
    }

    // Wait for a bit; the other agent should still have the file.
    [self waitForSeconds:1];
    [self waitForSync:agentB];
    [self waitForSeconds:1];

    XCTAssertEqual([[self metadataItemsForAgent:agentB] count], 1ULL, @"Delete should not have been pushed");

    // Turn syncing back on and then the file should disappear on the second agent.
    [self enableAgent:agentA];
    [self waitForFileMetadataItems:agentB where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
}

// We have different code paths for an actual coordinated delete vs. move (into .Trash). Make sure this works too.
- (void)testDeleteFileByMovingOutOfAccountWhileSyncingDisabled;
{
    // Make a document and download to two agents
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(accountA);
    
    [self copyFixtureNamed:@"test.package" ofAccount:accountA];
    
    OFXAgent *agentB = self.agentB;
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata){
        return [[metadata.fileURL lastPathComponent] isEqual:@"test.package"] && metadata.isDownloaded;
    }];
    
    // Turn off syncing and move the file out of the account
    [self disableAgent:agentA];
    {
        NSURL *fileURL = [accountA.localDocumentsURL URLByAppendingPathComponent:@"test.package"];
        
        __autoreleasing NSError *error;
        NSURL *temporaryURL;
        OBShouldNotError(temporaryURL = [[NSFileManager defaultManager] temporaryURLForWritingToURL:fileURL allowOriginalDirectory:NO error:&error]);
        [self moveURL:fileURL toURL:temporaryURL];
    }
    
    if (agentA.started) { // Only applies to 'pause' version
        // We should stop advertising the file locally.
        [self waitForFileMetadataItems:agentA where:^BOOL(NSSet *metadataItems) {
            return [metadataItems count] == 0;
        }];
    }
    
    // Wait for a bit; the other agent should still have the file.
    [self waitForSeconds:1];
    [self waitForSync:agentB];
    [self waitForSeconds:1];
    XCTAssertEqual([[self metadataItemsForAgent:agentB] count], 1ULL, @"Delete should not have been pushed");
    
    // Turn syncing back on and then the file should disappear on the second agent.
    [self enableAgent:agentA];
    [self waitForFileMetadataItems:agentB where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
}

#pragma mark - Subclass requirements

- (void)enableAgent:(OFXAgent *)agent;
{
    OBRequestConcreteImplementation(self, _cmd);
}
- (void)disableAgent:(OFXAgent *)agent;
{
    OBRequestConcreteImplementation(self, _cmd);
}

@end

@interface OFXSyncPauseTestCase : OFXInterruptSyncTestCase
@end

@implementation OFXSyncPauseTestCase

- (void)enableAgent:(OFXAgent *)agent;
{
    agent.syncSchedule = OFXSyncScheduleAutomatic;
}
- (void)disableAgent:(OFXAgent *)agent;
{
    agent.syncSchedule = OFXSyncScheduleNone;
}

@end

@interface OFXSyncStopTestCase : OFXInterruptSyncTestCase
@end

@implementation OFXSyncStopTestCase

- (void)enableAgent:(OFXAgent *)agent;
{
    if (!agent.started)
        [agent applicationLaunched];
}
- (void)disableAgent:(OFXAgent *)agent;
{
    if (agent.started) {
        __block BOOL stopped = NO;
        [agent applicationWillTerminateWithCompletionHandler:^{
            stopped = YES;
        }];
        [self waitUntil:^BOOL{
            return stopped;
        }];
    }
}

@end
