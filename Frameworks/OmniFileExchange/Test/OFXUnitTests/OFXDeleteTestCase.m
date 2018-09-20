// Copyright 2013-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

#import <OmniFoundation/OFNull.h>
#import <OmniFileExchange/OFXAccountClientParameters.h>

#import "OFXTrace.h"

RCS_ID("$Id$")

@interface OFXDeleteTestCase : OFXTestCase
@end

@implementation OFXDeleteTestCase

// Run a single test over and over.
#if 0
+ (XCTestSuite *)defaultTestSuite;
{
    SenTestSuite *suite = OB_AUTORELEASE([[SenTestSuite alloc] initWithName:@"-infinite-"]);
    
    SEL testSelector = @selector(testParentDirectory);
    
    NSMethodSignature *methodSignature = [self instanceMethodSignatureForSelector:testSelector];
    if (!methodSignature ||
        [methodSignature numberOfArguments] != 2 || /* 2 args: self, _cmd */
        strcmp([methodSignature methodReturnType], "v") != 0) {
        [NSException raise:NSGenericException format:@"Method -[%@ %@] has incorrect signature", [self description], NSStringFromSelector(testSelector)];
    }

    for (NSUInteger idx = 0; idx < 100; idx++) {        
        NSInvocation *testInvocation = [NSInvocation invocationWithMethodSignature:methodSignature];
        [testInvocation retainArguments]; // Do this before setting the argument so it gets captured in ARC mode
        [testInvocation setSelector:testSelector];
        
        OFTestCase *testCase = [self testCaseWithInvocation:testInvocation];
        [suite addTest:testCase];
    }
    
    return suite;
}
#endif

- (OFXAccountClientParameters *)accountClientParametersForAgentName:(NSString *)agentName;
{
    OFXAccountClientParameters *clientParameters = [super accountClientParametersForAgentName:agentName];
    
    // Speed up metadata updates in a copule casees where we are trying to catch it while it is downloading.
    SEL testSelector = self.invocation.selector;
    BOOL fasterMetadataUpdates = NO;

    if ([agentName isEqual:@"A"]) {
        fasterMetadataUpdates |= (testSelector == @selector(testDeleteWhileStillUploadingForFirstTime));
    }

    if ([agentName isEqual:@"B"]) {
        fasterMetadataUpdates |= (testSelector == @selector(testRaceBetweenDownloadUpdateAndLocalDeletion));
        fasterMetadataUpdates |= (testSelector == @selector(testIncomingDeleteOfFlatFileWhileStillDownloading));
        fasterMetadataUpdates |= (testSelector == @selector(testIncomingDeleteOfPackageWhileStillDownloading));
        fasterMetadataUpdates |= (testSelector == @selector(testLocalDeleteOfFlatFileWhileStillDownloading));
        fasterMetadataUpdates |= (testSelector == @selector(testLocalDeleteOfPackageWhileStillDownloading));
    }

    if (fasterMetadataUpdates) {
        clientParameters.metadataUpdateInterval = 0.0001;
    }
    
    return clientParameters;
}

- (void)testFile;
{
    // Upload a file and wait for it to propagate
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(accountA);
    
    OFXAgent *agentB = self.agentB;
    OFXServerAccount *accountB = [agentB.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(accountB); OB_UNUSED_VALUE(accountB);
    
    [self uploadFixture:@"test.package"];
    OFXFileMetadata *metadataB = [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.isDownloaded;
    }];
    
    // Make sure the file is present on the remote side.
    OFDiffFiles(self, [[self fixtureNamed:@"test.package"] path], [metadataB.fileURL path], nil);

    //NSLog(@"##### deleting #####");
    
    // Remove the file on A. Wait for the local and remote sides to both show the rename.
    [self deletePath:@"test.package" ofAccount:accountA];
    
    
    [self waitForFileMetadataItems:agentA where:^BOOL(NSSet *metadataItems){
        return [metadataItems count] == 0;
    }];
    [self waitForFileMetadataItems:agentB where:^BOOL(NSSet *metadataItems){
        return [metadataItems count] == 0;
    }];
    
    // Make sure the published file has been removed.
    __autoreleasing NSError *error;
    XCTAssertNil([[NSFileManager defaultManager] attributesOfItemAtPath:[metadataB.fileURL path] error:&error]);
    XCTAssertTrue([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]);
    
    // Stop the agents and restart them to make sure nothing reappears (might if we left a snapshot in their internal directories).
    [self stopAgents];
    [agentA applicationLaunched];
    [agentB applicationLaunched];
    [self waitForAsyncOperations];

    XCTAssertTrue([[self metadataItemsForAgent:agentA] count] == 0, @"Deleted items should not resurrect");
    XCTAssertTrue([[self metadataItemsForAgent:agentB] count] == 0, @"Deleted items should not resurrect");
}

- (void)testParentDirectory;
{
    // Upload multiple files and wait for them to propagate
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(accountA);
    
    OFXAgent *agentB = self.agentB;
    OFXServerAccount *accountB = [agentB.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(accountB); OB_UNUSED_VALUE(accountB);
    
    [self uploadFixture:@"test.package" as:@"folder/test1.package" replacingMetadata:nil];
    [self uploadFixture:@"test.package" as:@"folder/test2.package" replacingMetadata:nil];
    [self uploadFixture:@"test.package" as:@"folder/test3.package" replacingMetadata:nil];
    
    NSSet *metadataItemsB = [self waitForFileMetadataItems:agentB where:^BOOL(NSSet *metadataItems){
        if ([metadataItems count] != 3)
            return NO;
        for (OFXFileMetadata *metadata in metadataItems)
            if (!metadata.isDownloaded)
                return NO;
        return YES;
    }];
    
    // Make sure the file is present on the remote side.
    for (OFXFileMetadata *metadataB in metadataItemsB) {
        OFDiffFiles(self, [[self fixtureNamed:@"test.package"] path], [metadataB.fileURL path], nil);
    }
    
    //NSLog(@"##### deleting #####");
    
    // Remove the folder on A. Wait for the local and remote sides to both show the rename.
    [self deletePath:@"folder" ofAccount:accountA];
    
    
    [self waitForFileMetadataItems:agentA where:^BOOL(NSSet *metadataItems){
        return [metadataItems count] == 0;
    }];
    [self waitForFileMetadataItems:agentB where:^BOOL(NSSet *metadataItems){
        return [metadataItems count] == 0;
    }];
    
    // Make sure the published files have been removed.
    for (OFXFileMetadata *metadataB in metadataItemsB) {
        __autoreleasing NSError *error;
        XCTAssertNil([[NSFileManager defaultManager] attributesOfItemAtPath:[metadataB.fileURL path] error:&error]);
        XCTAssertTrue([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]);
    }
    
    // Stop the agents and restart them to make sure nothing reappears (might if we left a snapshot in their internal directories).
    [self stopAgents];
    [agentA applicationLaunched];
    [agentB applicationLaunched];
    [self waitForAsyncOperations];
    
    XCTAssertTrue([[self metadataItemsForAgent:agentA] count] == 0, @"Deleted items should not resurrect");
    XCTAssertTrue([[self metadataItemsForAgent:agentB] count] == 0, @"Deleted items should not resurrect");
}

- (void)testDeleteWhileStillUploadingForFirstTime;
{
    OFXAgent *agent = self.agentA;
    OFXServerAccount *account = [agent.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(account);

    // Make a large random file, and start uploading it. Our local deletion is racing against this, so if it is too small we can get random failures below where we check that we didn't commit the upload.
    [self copyRandomTextFileOfLength:64*1024*1024 toPath:@"random.txt" ofAccount:account];

    // Wait for the file to make some progress, so we know the transfer was really going.
    [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
        float percentUploaded = metadata.percentUploaded;
        if (percentUploaded >= 1) {
            XCTFail(@"Waited too long!");
        }
        return (percentUploaded > 0.1);
    }];
    
    // Delete the file
    [self deletePath:@"random.txt" ofAccount:account];
    
    // Wait for the metadata to disappear
    [self waitForFileMetadataItems:agent where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];

    // Wait for our upload/delete transfers to idle out.
    OFXTraceWait(@"OFXFileSnapshotUploadTransfer.finished");
    
    // And make sure we do a "delete" to clean up the local snapshot.
    OFXTraceWait(@"OFXFileSnapshotDeleteTransfer.finished");
    OFXTraceWait(@"OFXFileItem.delete_transfer.commit.removed_local_snapshot");
    
    XCTAssertTrue(OFXTraceHasSignal(@"OFXContainerAgent.upload_did_not_commit"), @"Upload completion should have failed validation");
    XCTAssertFalse(OFXTraceHasSignal(@"OFXFileSnapshotDeleteTransfer.remote_delete_attempted"), @"We should not have tried to delete the remote URL");
}

- (void)testDeleteWhileUploadingEditOfExitingDocument;
{
    OFXAgent *agent = self.agentA;
    OFXServerAccount *account = [agent.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(account);

    // Make an original document and wait for it to fully upload.
    [self copyFixtureNamed:@"flat1.txt" toPath:@"random.txt" ofAccount:account];
    [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded;
    }];
    
    // Replace original with large edited file.
    [self copyLargeRandomTextFileToPath:@"random.txt" ofAccount:account];
    
    // Wait for upload to start
    [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploading;
    }];
    
    // Wait for the file to make some progress, so we know the transfer was really going.
    [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
        float percentUploaded = metadata.percentUploaded;
        if (percentUploaded >= 1) {
            XCTFail(@"Waited too long!");
        }
        return (percentUploaded > 0.1);
    }];
    
    // Delete the file
    [self deletePath:@"random.txt" ofAccount:account];
    
    // Wait for the metadata to disappear
    [self waitForFileMetadataItems:agent where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];

    [NSError suppressingLogsWithUnderlyingDomain:NSPOSIXErrorDomain code:ENOENT action:^{
        // And make sure we do a "delete" to clean up the local snapshot.
        OFXTraceWait(@"OFXFileSnapshotDeleteTransfer.finished");
        OFXTraceWait(@"OFXFileItem.delete_transfer.commit.removed_local_snapshot");
    }];

    XCTAssertTrue(OFXTraceHasSignal(@"OFXFileSnapshotDeleteTransfer.remote_delete_attempted"), @"We should have deleted the remote URL");
}

- (void)testDeleteOfUndownloadedFile;
{
    self.agentB.automaticallyDownloadFileContents = NO;

    [self copyFixtureNamed:@"test.package" toPath:@"test.package" waitingForAgentsToDownload:nil]; /* Just waiting for the metadata -- it's not going to get downloaded */
    
    // -waitForAgentsEditsToAgree: waits for the file to be downloaded.
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return [[metadata.fileURL lastPathComponent] isEqual:@"test.package"];
    }];
    
    OFXServerAccount *accountB = [[self.agentB.accountRegistry validCloudSyncAccounts] lastObject];
    [self.agentB deleteItemAtURL:[accountB.localDocumentsURL URLByAppendingPathComponent:@"test.package" isDirectory:YES] completionHandler:^(NSError *errorOrNil) {
        XCTAssertNil(errorOrNil, @"Should be no error");
    }];
    
    // Wait for A to hear about it
    [self waitForFileMetadataItems:self.agentA where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
    
    XCTAssertTrue(OFXTraceHasSignal(@"OFXContainerAgent.delete_item.metadata"), @"Should have just been done via metadata since there was no file");
}

- (void)testIncomingDeleteOfUndownloadedFile;
{
    self.agentB.automaticallyDownloadFileContents = NO;
    
    [self copyFixtureNamed:@"test.package" toPath:@"test.package" waitingForAgentsToDownload:nil]; /* Just waiting for the metadata -- it's not going to get downloaded */

    OFXServerAccount *accountA = [[self.agentA.accountRegistry validCloudSyncAccounts] lastObject];
    [self deletePath:@"test.package" ofAccount:accountA];
    
    // Wait for B to hear about it
    [self waitForFileMetadataItems:self.agentB where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
    
    // The metadata updates are async as are the trace counters, and they aren't serialized vs. each other, so we need to wait to avoid races
    [self waitUntil:^BOOL{
        return OFXTraceHasSignal(@"OFXFileItem.incoming_delete.removed_local_snapshot");
    }];
}

- (void)_doDeleteOnAgent:(OFXAgent *)deletingAgent whileStillDownloading:(OFXFileMetadata *)originalMetadata;
{
    // Start downloading the large file on B
    OFXAgent *agentB = self.agentB;
    [self downloadFileWithIdentifier:originalMetadata.fileIdentifier untilPercentage:0.1 agent:agentB];
    
    // ... and then delete on either the incoming or local side.
    [deletingAgent deleteItemAtURL:originalMetadata.fileURL completionHandler:^(NSError *errorOrNil){
        XCTAssertNil(errorOrNil, @"Should not fail");
    }];
    
    // Both A and B should settle down to having no files
    [self waitForFileMetadataItems:self.agentA where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
    [self waitForFileMetadataItems:self.agentB where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
}

// Maybe the web server will kill our transfer while it is in progress?
// Try both a delete of a large flat file (does Apache kill our transfer) and a wrapper with several times (so we get a 404 on something).
- (void)testIncomingDeleteOfFlatFileWhileStillDownloading;
{
    // Make a large file on agentA
    OFXFileMetadata *originalMetadata = [self makeRandomFlatFile:@"random.txt"];
    
    // B will download, push a delete from A (so it is incoming to B).
    [self _doDeleteOnAgent:self.agentA whileStillDownloading:originalMetadata];
}

- (void)testIncomingDeleteOfPackageWhileStillDownloading;
{
    // Make a large file on agentA
    OFXFileMetadata *originalMetadata = [self makeRandomLargePackage:@"random.package"];
    
    // B will download, push a delete from A (so it is incoming to B).
    [self _doDeleteOnAgent:self.agentA whileStillDownloading:originalMetadata];
}

// Local variants of the delete-while-downloading
- (void)testLocalDeleteOfFlatFileWhileStillDownloading;
{
    // Make a large file on agentA
    OFXFileMetadata *originalMetadata = [self makeRandomFlatFile:@"random.txt"];
    
    // Transform the metadata from A into one from B
    __block OFXFileMetadata *originalMetadataB = [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return [metadata.fileIdentifier isEqual:originalMetadata.fileIdentifier];
    }];
    
    // B will download, so the delete on B is local
    [self _doDeleteOnAgent:self.agentB whileStillDownloading:originalMetadataB];
}

- (void)testLocalDeleteOfPackageWhileStillDownloading;
{
    // Make a large file on agentA
    OFXFileMetadata *originalMetadata = [self makeRandomLargePackage:@"random.package"];
    
    // Transform the metadata from A into one from B
    __block OFXFileMetadata *originalMetadataB = [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return [metadata.fileIdentifier isEqual:originalMetadata.fileIdentifier];
    }];
    
    // B will download, so the delete on B is local
    [self _doDeleteOnAgent:self.agentB whileStillDownloading:originalMetadataB];
}

- (void)testDeleteAndReplaceFileWhileOtherClientOffline;
{
    OFXFileMetadata *originalMetadata = [self copyFixtureNamed:@"test.package"];
    
    // Take agentB offline so it doesn't see the intermediate state
    self.agentB.syncSchedule = OFXSyncScheduleNone;

    // Delete the file and replace it with a different one.
    OFXServerAccount *accountA = [self.agentA.accountRegistry.validCloudSyncAccounts lastObject];
    [self deletePath:@"test.package" ofAccount:accountA];
    
    // Since NSFileCoordinator doesn't properly send sub-item deletions (12684711) we don't see the remove/write as a new identity unless we specifically wait for the delete to happen on the next scan before we write the new file.
    [self waitForFileMetadataItems:self.agentA where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
    
    // Wait for the second upload to happen too. Otherwise, when agentB comes back on line, it may quickly see the delete instead of seeing both changes at the same time.
    [self copyFixtureNamed:@"test2.package" toPath:@"test.package" ofAccount:accountA];
    [self waitForFileMetadata:self.agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.isUploaded;
    }];
    
    // Turn syncing back on on B
    self.agentB.syncSchedule = OFXSyncScheduleAutomatic;
    
    // Wait for B to see the updated file
    OFXFileMetadata *updatedMetadata = [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        // We expect that the delete above should actually make a new file identity, not just update the existing one. Without this, the test may spuriously succeed.
        if (OFISEQUAL(metadata.fileIdentifier, originalMetadata.fileIdentifier))
            return NO;
            
        return metadata.downloaded;
    }];
    
    // B should have gotten the new contents
    XCTAssertTrue(ITEM_MATCHES_FIXTURE(updatedMetadata, @"test2.package"));
}

// Similar to -testLocalDeleteOfFlatFileWhileStillDownloading, but here we are trying to test the race between committing a download and the local deletion.
// TODO: Test both uncoordinated and coordinated deletes; the uncoordinated case only matters if we are downloading updates (since the first download is what will create the local file for use with file coordination).
- (void)testRaceBetweenDownloadAndLocalDeletion;
{
    self.agentB.automaticallyDownloadFileContents = NO;
    
    const NSUInteger fileCount = 50;
    for (NSUInteger fileIndex = 0; fileIndex < fileCount; fileIndex++) {
        [self makeRandomFlatFile:[NSString stringWithFormat:@"file%lu.txt", fileIndex] withSize:fileIndex*fileIndex*fileIndex];
    }
    
    // Wait for agentB to know about all the files
    NSSet *metadataItemsOnB = [self waitForFileMetadataItems:self.agentB where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == fileCount;
    }];
    
    NSArray *sizeSortedMetadataItemsOnB = [metadataItemsOnB.allObjects sortedArrayUsingComparator:^NSComparisonResult(OFXFileMetadata *metadata1, OFXFileMetadata *metadata2) {
        if (metadata1.fileSize < metadata2.fileSize)
            return NSOrderedAscending;
        if (metadata1.fileSize > metadata2.fileSize)
            return NSOrderedDescending;
        return NSOrderedSame;
    }];
    
    // Start downloads and then deletions of all the files, in increasing order of size.
    for (OFXFileMetadata *metadataItem in sizeSortedMetadataItemsOnB) {
        [self.agentB requestDownloadOfItemAtURL:metadataItem.fileURL completionHandler:^(NSError *errorOrNil) {
            XCTAssertNil(errorOrNil, @"Download request should work");
        }];
    }
    for (OFXFileMetadata *metadataItem in sizeSortedMetadataItemsOnB) {
        // Give a little time for the downloads to catch up.
        [NSThread sleepForTimeInterval:0.1*OFRandomNextDouble()];
        [self.agentB deleteItemAtURL:metadataItem.fileURL completionHandler:^(NSError *errorOrNil) {
            XCTAssertNil(errorOrNil, @"Delete request should work");
        }];
    }
    
    // Both agents should settle at zero files.
    [self waitForFileMetadataItems:self.agentA where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
    [self waitForFileMetadataItems:self.agentB where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
}

// Similar to -testRaceBetweenDownloadAndLocalDeletion, but we are downloading updates instead of just the first version.
- (void)testRaceBetweenDownloadUpdateAndLocalDeletion;
{
    // Not using -makeRandomFlatFile:withSize: since that waits. Bulk create a bunch of files.
    const NSUInteger fileCount = 50;
    for (NSUInteger fileIndex = 0; fileIndex < fileCount; fileIndex++) {
        [self writeRandomFlatFile:[NSString stringWithFormat:@"file%lu.txt", fileIndex] withSize:10*fileIndex*fileIndex*fileIndex];
    }
    
    // Wait for them all to appear on B.
    [self waitForFileMetadataItems:self.agentB where:^BOOL(NSSet *metadataItems) {
        if ([metadataItems count] != fileCount)
            return NO;
        return [metadataItems all:^BOOL(OFXFileMetadata *metadata) {
            return metadata.downloaded;
        }];
    }];
    
    // For each file, write an update and then as soon as B starts downloading it, delete it locally. We are hoping to catch issues with the commit of a downoaded update racing with noticing the local deletion.
    __block NSUInteger deletesAttemptedWhileDownloading = 0;
    NSMutableDictionary *filenameToContents = [NSMutableDictionary new];;
    for (OFXFileMetadata *metadataItem in [self metadataItemsForAgent:self.agentA]) {
        NSData *updatedContents = OFRandomCreateDataOfLength(metadataItem.fileSize);
        filenameToContents[[metadataItem.fileURL lastPathComponent]] = updatedContents;

        NSError *error;
        OBShouldNotError([updatedContents writeToURL:metadataItem.fileURL options:NSDataWritingAtomic error:&error]);
        
        [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *updatedMetadata) {
            if (OFNOTEQUAL(metadataItem.fileIdentifier, updatedMetadata.fileIdentifier))
                return NO;
            
            if (updatedMetadata.downloading) {
                deletesAttemptedWhileDownloading++;
                [self deletePath:[updatedMetadata.fileURL lastPathComponent] inAgent:self.agentB];
                return YES;
            }
            
            if ([metadataItem.editIdentifier isEqual:updatedMetadata.editIdentifier])
                return NO; // Haven't noticed the change yet.
            
            return YES;
        }];
    }
    
    XCTAssertGreaterThan(deletesAttemptedWhileDownloading, 0ULL, "Should have managed at least one attempt at a delete while we were still downloading");
    
    // Some of the deletes might happen, some might get dropped. Any files that are left should have the updated contents.
    [self waitForAgentsEditsToAgree];
    [self requireAgentsToHaveSameFilesByName];
    
    // We expect that we'll get all the updated contents (no deletes should win). Once we start a download, deletes are delayed until the download ends, and once the download ends, there will be a file in place (so the next scan won't issue a delete).
    [self requireAgent:self.agentB toHaveDataContentsByPath:filenameToContents];
}

// <bug:///88190> (Clients out of sync after deleting subfolder while uploading contents)
- (void)_deleteRenamedDirectoryAndWaitForAcknowledgement:(BOOL)waitForMoveAcknowledgement;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];

    // Make a bunch of documents on both clients
    agentB.automaticallyDownloadFileContents = YES;

    NSError *error;
    OBShouldNotError([[NSFileManager defaultManager] createDirectoryAtURL:[accountA.localDocumentsURL URLByAppendingPathComponent:@"dir" isDirectory:YES]
                                              withIntermediateDirectories:NO attributes:nil error:&error]);
    
    const NSUInteger fileCount = 10;
    for (NSUInteger fileIndex = 0; fileIndex < fileCount; fileIndex++) {
        [self makeRandomFlatFile:[NSString stringWithFormat:@"dir/file%lu.txt", fileIndex] withSize:4*1024*1024];
    }
    
    [self waitForFileMetadataItems:agentB where:^BOOL(NSSet *metadataItems) {
        if ([metadataItems count] != fileCount)
            return NO;
        return [metadataItems all:^BOOL(OFXFileMetadata *metadata) {
            return metadata.downloaded;
        }];
    }];
    
    // Rename the directory on A, wait for the renames to be acknowledged, uploads to start, and then delete the whole directory.
    [self movePath:@"dir" toPath:@"dir2" ofAccount:accountA];
    
    if (waitForMoveAcknowledgement) {
        [self waitForFileMetadataItems:agentA where:^BOOL(NSSet *metadataItems) {
            return [metadataItems all:^BOOL(OFXFileMetadata *metadata) {
                return [[[metadata.fileURL URLByDeletingLastPathComponent] lastPathComponent] isEqual:@"dir2"];
            }];
        }];
    
        // Can't wait for this independently -- waiting for this implies waiting for the move to be acknowledged.
        [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
            return metadata.uploading && metadata.percentUploaded > 0;
        }];
    }
    
    [self deletePath:@"dir2" ofAccount:accountA];
    
    // Both accounts should settle to zero documents
    [self waitForFileMetadataItems:agentA where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
    [self waitForFileMetadataItems:agentB where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
}

- (void)testDeleteRenamedDirectory;
{
    [self _deleteRenamedDirectoryAndWaitForAcknowledgement:YES];
}

// Same as -testDeleteRenamedDirectory, but we don't wait for the move to be acknowledged. This hit a different set of assertions since we'd try to process the queued NSFilePresenter move message on items had been deleted.
- (void)testQuicklyDeleteRenamedDirectory;
{
    [self _deleteRenamedDirectoryAndWaitForAcknowledgement:NO];
}

// Noticed as part of <bug:///88190> (Clients out of sync after deleting subfolder while uploading contents)
- (void)testDeleteAllDocumentsWhileStopped;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    
    [self uploadFixture:@"test.package"];
    
    __block BOOL stopped = NO;
    [self.agentA applicationWillTerminateWithCompletionHandler:^{
        stopped = YES;
    }];
    [self waitUntil:^BOOL{
        return stopped;
    }];
    
    [self deletePath:@"test.package" ofAccount:accountA];
    
    [self.agentA applicationLaunched];
    
    // Fragile, but wait for a bit to let the agent start so our metadata is reasonable.
    [self waitForSeconds:0.5];
    
    // Both accounts should settle to zero documents
    [self waitForFileMetadataItems:agentA where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
    [self waitForFileMetadataItems:agentB where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
}

- (void)testDocumentWithMultipleVersionsOnServer;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    OFXTraceReset();
    
    // Make sure neither agent cleans up file versions so that there are multiple to delete
    agentA.clientParameters.deletePreviousFileVersionAfterNewVersionUploaded = NO;
    agentB.clientParameters.deletePreviousFileVersionAfterNewVersionUploaded = NO;
    agentA.clientParameters.deleteStaleFileVersionsWhenSyncing = NO;
    agentB.clientParameters.deleteStaleFileVersionsWhenSyncing = NO;
    
    // Upload two versions of a file on A
    OFXFileMetadata *originalMetadata = [self uploadFixture:@"test.package"];
    [self uploadFixture:@"test2.package" as:@"test.package" replacingMetadata:originalMetadata];

    // Make sure B sees the file so that we can use this as a check that the delete has happened (since in-progress deletes vend no metadata, so we can't check agentA's metadata items.
    [self waitForFileMetadataItems:agentB where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 1;
    }];
    
    // Deleting this should remove both versions
    [self deletePath:@"test.package" ofAccount:[self singleAccountInAgent:agentA]];
    
    [self waitForFileMetadataItems:agentB where:^BOOL(NSSet *metadataItems) {
        return [metadataItems count] == 0;
    }];
    
    NSArray *deletedURLs = OFXTraceCopy(@"OFXFileSnapshotDeleteTransfer.deleted_urls");
    XCTAssertEqual([deletedURLs count], 2UL, "Delete should have removed both versions");

    // A little inside-baseball here to know how versions are represented.
    XCTAssert([[deletedURLs[0] lastPathComponent] hasSuffix:@"~0"], "Should delete the oldest version first");
    XCTAssert([[deletedURLs[1] lastPathComponent] hasSuffix:@"~1"], "Should delete the newest version second");
}

@end
