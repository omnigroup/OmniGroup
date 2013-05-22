// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

#import "OFXTrace.h"

#import <OmniFoundation/OFNull.h>

RCS_ID("$Id$")

@interface OFXRenameTestCase : OFXTestCase
@end

@implementation OFXRenameTestCase

- (void)testFilename;
{
    // Upload a file and wait for it to propagate
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(accountA);
    
    OFXAgent *agentB = self.agentB;
    OFXServerAccount *accountB = [agentB.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(accountB);

    [self uploadFixture:@"test.package"];
    [self waitForFileMetadata:agentB where:nil];
    
    // Rename the file on A. Wait for the local and remote sides to both show the rename.
    [self movePath:@"test.package" toPath:@"test-rename.package" ofAccount:accountA];

    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded && [[metadata.fileURL lastPathComponent] isEqual:@"test-rename.package"];
    }];
    STAssertTrue([[agentA metadataItemsForAccount:accountA] count] == 1, @"Shouldn't get a new item, but rename the existing one");
    
    OFXFileMetadata *metadataB = [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded && [[metadata.fileURL lastPathComponent] isEqual:@"test-rename.package"];
    }];
    STAssertTrue([[agentB metadataItemsForAccount:accountB] count] == 1, @"Shouldn't get a new item, but rename the existing one");
    
    // Make sure the move happened on the remote side too
    OFDiffFiles(self, [[self fixtureNamed:@"test.package"] path], [metadataB.fileURL path], nil);
}

- (void)testParentDirectory;
{
    OFXAgent *agent = self.agentA;
    OFXServerAccount *account = [agent.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(account);
    
    [self uploadFixture:@"test.package" as:@"folder/test1.package" replacingMetadata:nil];
    [self uploadFixture:@"test.package" as:@"folder/test2.package" replacingMetadata:nil];
    
    [self movePath:@"folder" toPath:@"folder-rename" ofAccount:account];
    
    [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded && [[metadata.fileURL absoluteString] hasSuffix:@"/folder-rename/test1.package/"];
    }];
    [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded && [[metadata.fileURL absoluteString] hasSuffix:@"/folder-rename/test2.package/"];
    }];
    
    STAssertTrue([[agent metadataItemsForAccount:account] count] == 2, @"Both items should be renamed instead of duplicated");
}

- (void)testSwitchPackagePathExtension;
{
    OFXAgent *agent = self.agentA;
    OFXServerAccount *account = [agent.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(account);

    [self uploadFixture:@"test.package"];
    
    // Start up agentB to be sure it sees this change, rather than coming in after the dramatic transformation.
    [self waitForFileMetadata:self.agentB where:nil];
    
    [self movePath:@"test.package" toPath:@"test.snackage" ofAccount:account];
    
    [self waitForFileMetadata:self.agentB where:^(OFXFileMetadata *metadata){
        return [[metadata.fileURL lastPathComponent] isEqualToString:@"test.snackage"];
    }];
    STAssertEquals([[self metadataItemsForAgent:self.agentB] count], 1ULL, @"should replace the old file");
}

- (void)testSwitchToPackagePathExtension;
{
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(accountA);

    OFXAgent *agentB = self.agentB;

    [self uploadFixture:@"flat1.txt" as:@"folder/flat.txt" replacingMetadata:nil];
    [self movePath:@"folder" toPath:@"test.package" ofAccount:accountA];
    
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded && [[metadata.fileURL absoluteString] hasSuffix:@"/test.package/"];
    }];
    OFXFileMetadata *metadataB = [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded && [[metadata.fileURL absoluteString] hasSuffix:@"/test.package/"];
    }];

    OFDiffFiles(self, [[self fixtureNamed:@"flat1.txt"] path], [[metadataB.fileURL URLByAppendingPathComponent:@"flat.txt"] path], nil);
}

- (void)testSwitchFromPackagePathExtension;
{
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(accountA);
    
    OFXAgent *agentB = self.agentB;

    [self copyFixtureNamed:@"test.package"]; // This wait for the download to happen on B before doing the rename. We'll have a test elsewhere to check delete-while-download.
    
    [self movePath:@"test.package" toPath:@"folder" ofAccount:accountA];
    
    [self waitForFileMetadataItems:agentA where:^BOOL(NSSet *metadataItems) {
        for (OFXFileMetadata *metadataItem in metadataItems)
            if (!metadataItem.uploaded)
                return NO;
        return [metadataItems count] == 5; // Hard coded number of files inside our test wrapper
    }];
    NSSet *metadataItemsB = [self waitForFileMetadataItems:agentB where:^BOOL(NSSet *metadataItems) {
        for (OFXFileMetadata *metadataItem in metadataItems)
            if (!metadataItem.downloaded)
                return NO;
        return [metadataItems count] == 5; // Hard coded number of files inside our test wrapper
    }];
    
    OFDiffFiles(self, [[self fixtureNamed:@"test.package"] path], [[[[metadataItemsB anyObject] fileURL] path] stringByDeletingLastPathComponent], nil);
}

- (void)testRenameOfUndownloadedFile;
{
    self.agentB.automaticallyDownloadFileContents = NO;
    
    OFXFileMetadata *originalMetadata = [self copyFixtureNamed:@"test.package" waitForDownload:NO];
    
    OFXServerAccount *accountA = [self.agentA.accountRegistry.validCloudSyncAccounts lastObject];
    OFXServerAccount *accountB = [self.agentB.accountRegistry.validCloudSyncAccounts lastObject];
    
    [self.agentB moveItemAtURL:[accountB.localDocumentsURL URLByAppendingPathComponent:@"test.package" isDirectory:YES]
                         toURL:[accountB.localDocumentsURL URLByAppendingPathComponent:@"test-rename.package" isDirectory:YES]
             completionHandler:nil];

    __block OFXFileMetadata *renamedFileMetadataA;
    [self waitForFileMetadataItems:self.agentA where:^BOOL(NSSet *metadataItems) {
        if ([metadataItems count] != 1)
            return NO;
        OFXFileMetadata *metadata = [metadataItems anyObject];
        if ([[metadata.fileURL lastPathComponent] isEqual:@"test-rename.package"]) {
            renamedFileMetadataA = metadata;
            return YES;
        }
        return NO;
    }];
    STAssertTrue(OFNOTEQUAL(originalMetadata.editIdentifier, renamedFileMetadataA.editIdentifier), @"Should have changed");
    STAssertTrue(renamedFileMetadataA.downloaded, @"Should still be downloaded");
    STAssertFalse(renamedFileMetadataA.downloading, @"Shouldn't need downloading after rename");

    __block OFXFileMetadata *renamedFileMetadataB;
    [self waitForFileMetadataItems:self.agentB where:^BOOL(NSSet *metadataItems) {
        if ([metadataItems count] != 1)
            return NO;
        OFXFileMetadata *metadata = [metadataItems anyObject];
        if ([[metadata.fileURL lastPathComponent] isEqual:@"test-rename.package"]) {
            renamedFileMetadataB = metadata;
            return YES;
        }
        return NO;
    }];
    STAssertFalse(renamedFileMetadataB.downloaded, @"Rename shouldn't have provoked download");
    STAssertFalse(renamedFileMetadataB.downloading, @"Rename shouldn't have provoked download");

    // Then go ahead and download
    [self.agentB requestDownloadOfItemAtURL:[accountB.localDocumentsURL URLByAppendingPathComponent:@"test-rename.package" isDirectory:YES] completionHandler:^(NSError *errorOrNil) {
        STAssertNil(errorOrNil, @"Download should start");
    }];
    
    [self waitForFileMetadata:self.agentA where:^BOOL(OFXFileMetadata *metadata) {
        return OFISEQUAL(metadata.editIdentifier, renamedFileMetadataB.editIdentifier) && metadata.isDownloaded;
    }];
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return OFISEQUAL(metadata.editIdentifier, renamedFileMetadataB.editIdentifier) && metadata.isDownloaded;
    }];
    
    // Make sure the contents are as expected
    OFDiffFiles(self, [[self fixtureNamed:@"test.package"] path], [[accountA.localDocumentsURL URLByAppendingPathComponent:@"test-rename.package" isDirectory:YES] path], nil);
    OFDiffFiles(self, [[self fixtureNamed:@"test.package"] path], [[accountB.localDocumentsURL URLByAppendingPathComponent:@"test-rename.package" isDirectory:YES] path], nil);
}

- (void)testIncomingRenameOfUndownloadedFile;
{
    self.agentB.automaticallyDownloadFileContents = NO;
    [self copyFixtureNamed:@"test.package" waitForDownload:NO];
    
    OFXServerAccount *accountA = [self.agentA.accountRegistry.validCloudSyncAccounts lastObject];
    [self movePath:@"test.package" toPath:@"test-renamed.package" ofAccount:accountA];
    
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        return [[metadata.fileURL lastPathComponent] isEqual:@"test-renamed.package"];
    }];
}

- (void)testCaseOnlyRename;
{
    // NSFileCoordinator doesn't send file presenter messages when the rename is case-only, sadly.
    
    [self copyFixtureNamed:@"test.package"];

    OFXServerAccount *accountA = [self.agentA.accountRegistry.validCloudSyncAccounts lastObject];
    [self movePath:@"test.package" toPath:@"Test.package" ofAccount:accountA];

    [self waitForFileMetadataItems:self.agentB where:^BOOL(NSSet *metadataItems) {
        if ([metadataItems count] != 1)
            return NO;
        OFXFileMetadata *metadata = [metadataItems anyObject];
        return [[metadata.fileURL lastPathComponent] isEqual:@"Test.package"];
    }];

    STAssertFalse(OFXTraceHasSignal(@"OFXFileSnapshotDeleteTransfer.remote_delete_attempted"), @"No delete should have happend (which will if we interpet the move as a creation/deletion pair instead of a move");
}

static BOOL _hasFileWithSuffix(NSSet *metadataItems, NSString *suffix)
{
    return [metadataItems any:^BOOL(OFXFileMetadata *metadata) { return [[metadata.fileURL absoluteString] hasSuffix:suffix]; }] != nil;
}
#define hasFileWithSuffix(suffix) _hasFileWithSuffix(metadataItems, suffix)

- (void)testCaseOnlyRenameOfFolder;
{
    // NSFileCoordinator doesn't send file presenter messages when the rename is case-only, sadly.
    
    OFXServerAccount *accountA = [self.agentA.accountRegistry.validCloudSyncAccounts lastObject];
    [self copyFixtureNamed:@"test.package" toPath:@"dir/test.package" ofAccount:accountA];

    [self movePath:@"dir" toPath:@"Dir" ofAccount:accountA];
    
    [self waitForFileMetadataItems:self.agentB where:^BOOL(NSSet *metadataItems) {
        if ([metadataItems count] != 1)
            return NO;
        return hasFileWithSuffix(@"Dir/test.package/");
    }];
    
    STAssertFalse(OFXTraceHasSignal(@"OFXFileSnapshotDeleteTransfer.remote_delete_attempted"), @"No delete should have happend (which will if we interpet the move as a creation/deletion pair instead of a move");
}

- (void)testUncoordinatedRenameOfDirectoryOfDocuments;
{
    // Our fixes for case-only renames had a side effect of making uncoordinated renames work (since we do inode-matching). Make sure this keeps working.
    OFXServerAccount *accountA = [self.agentA.accountRegistry.validCloudSyncAccounts lastObject];
    [self uploadFixture:@"test.package" as:@"dir1/A.package" replacingMetadata:nil];
    [self uploadFixture:@"test.package" as:@"dir1/B.package" replacingMetadata:nil];
    [self uploadFixture:@"test.package" as:@"dir1/C.package" replacingMetadata:nil];
    
    // Do an uncoordinated move (like 'mv dir1 dir2' in Terminal).
    NSURL *dir1URL = [accountA.localDocumentsURL URLByAppendingPathComponent:@"dir1" isDirectory:YES];
    NSURL *dir2URL = [accountA.localDocumentsURL URLByAppendingPathComponent:@"dir2" isDirectory:YES];
    
    // Can't use NSFileManager since it returns EEXIST in this case. rename(2) works.
    int rc = rename([[NSFileManager defaultManager] fileSystemRepresentationWithPath:[dir1URL path]],
                    [[NSFileManager defaultManager] fileSystemRepresentationWithPath:[dir2URL path]]);
    STAssertEquals(rc, 0, @"rename failed");
    
    // First off, our local agent should notice the move
    [self waitForFileMetadataItems:self.agentA where:^BOOL(NSSet *metadataItems) {
        if ([metadataItems count] != 3)
            return NO;
        
        return hasFileWithSuffix(@"dir2/A.package/") && hasFileWithSuffix(@"dir2/B.package/") && hasFileWithSuffix(@"dir2/C.package/");
    }];
    
    // and the remote side should too
    [self waitForFileMetadataItems:self.agentB where:^BOOL(NSSet *metadataItems) {
        if ([metadataItems count] != 3)
            return NO;
        
        return hasFileWithSuffix(@"dir2/A.package/") && hasFileWithSuffix(@"dir2/B.package/") && hasFileWithSuffix(@"dir2/C.package/");
    }];
    
    STAssertFalse(OFXTraceHasSignal(@"OFXFileSnapshotDeleteTransfer.remote_delete_attempted"), @"No delete should have happend (which will if we interpet the move as a creation/deletion pair instead of a move");
}

#if 0
- (void)testRenameOfFileAndCreationOfNewFileAsSamePath;
{
    // Make sure we don't generate spurious conflicts. We should update metadata for all files that we knew about before downloading stuff about new snapshots (so that we see the rename away from one name before a new file is downloaded to take its place).    
    [self uploadFixture:@"test.package"];
    
    self.agentB.syncingEnabled = NO;
    
    // Rename the file on A and once that completes, add a new file in its place. We don't need to pause here since NSFileCoordinator *does* to sub-item renames.
    OFXServerAccount *accountA = [self.agentA.accountRegistry.validCloudSyncAccounts lastObject];
    [self movePath:@"test.package" toPath:@"test-renamed.package" ofAccount:accountA];
    [self copyFixtureNamed:@"test2.package" toPath:@"test.package" ofAccount:accountA];

    // Wait for all our uploads to finish
    [self waitForFileMetadataItems:self.agentA where:^BOOL(NSSet *metadataItems) {
        if ([metadataItems count] != 2)
            return NO;
        for (OFXFileMetadata *metadata in metadataItems)
            if (!metadata.uploaded)
                return NO;
        return YES;
    }];
    
    // Turn syncing back on on B and wait for it to process stuff.
    self.agentB.syncingEnabled = YES;
    
    __block NSSet *resultMetadataItems;
    [self waitForFileMetadataItems:self.agentB where:^BOOL(NSSet *metadataItems) {
        if ([metadataItems count] != 2)
            return NO;
        for (OFXFileMetadata *metadata in metadataItems)
            if (!metadata.uploaded || !metadata.downloaded)
                return NO;
        resultMetadataItems = metadataItems;
        return YES;
    }];
    
    OFXFileMetadata *metadata1 = [resultMetadataItems any:^BOOL(OFXFileMetadata *metadata) {
        return [[metadata.fileURL lastPathComponent] isEqualToString:@"test-renamed.package"];
    }];
    OFXFileMetadata *metadata2 = [resultMetadataItems any:^BOOL(OFXFileMetadata *metadata) {
        return [[metadata.fileURL lastPathComponent] isEqualToString:@"test.package"];
    }];
    
    STAssertTrue(ITEM_MATCHES_FIXTURE(metadata1, @"test.package"), nil);
    STAssertTrue(ITEM_MATCHES_FIXTURE(metadata2, @"test2.package"), nil);
}
#endif

- (void)testRenameOfNewLocalFileWhileOffline;
{
    OFXAgent *agentA = self.agentA;
    agentA.syncingEnabled = NO; // Make sure the file stays in the 'new' state
    
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    [self copyFixtureNamed:@"test.package" ofAccount:accountA];
    
    // Wait for the new file to be acknowledged
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return YES;
    }];
    
    // Rename the file and wait for the rename to be acknowledged
    [self movePath:@"test.package" toPath:@"test-renamed.package" ofAccount:accountA];
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return [[metadata.fileURL lastPathComponent] isEqual:@"test-renamed.package"];
    }];
}

- (void)testRenameOfNewLocalFileWhileUploading;
{
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];

    // Add a random file and wait for it to be acknowledged
    NSString *randomText = [self copyRandomTextFileOfLength:32*1024*1024 toPath:@"random.txt" ofAccount:accountA];
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return YES;
    }];
    
    // Wait for the upload to start up
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploading && metadata.percentUploaded > 0;
    }];

    // Rename the file locally.
    [self movePath:@"random.txt" toPath:@"random-renamed.txt" ofAccount:accountA];
    
    // Wait for agent B to see everything in the end state
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        [self downloadWithMetadata:metadata agent:self.agentB];
        return YES;
    }];
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        NSURL *fileURL = metadata.fileURL;
        if (!metadata.downloaded || ![[fileURL lastPathComponent] isEqual:@"random-renamed.txt"])
            return NO;
        
        NSString *stringB = [[NSString alloc] initWithContentsOfURL:fileURL encoding:NSUTF8StringEncoding error:NULL];
        STAssertEqualObjects(randomText, stringB, nil);
        return YES;
    }];
}

// like testRenameOfNewLocalFileWhileUploading, but an edit of a previously uploaded file
- (void)testRenameOfEditedLocalFileWhileUploading;
{
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];

    // Add a random file and wait for it to be uploaded
    [self copyFixtureNamed:@"flat1.txt" toPath:@"test.txt" ofAccount:accountA];
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded;
    }];

    // Edit the file and wait for the upload to start
    NSString *randomText = [self copyRandomTextFileOfLength:32*1024*1024 toPath:@"test.txt" ofAccount:accountA];
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploading && metadata.percentUploaded > 0;
    }];
    
    // Rename the file locally.
    [self movePath:@"test.txt" toPath:@"test-renamed.txt" ofAccount:accountA];
    
    // Wait for agent B to see everything in the end state
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        [self downloadWithMetadata:metadata agent:self.agentB];
        return YES;
    }];
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        NSURL *fileURL = metadata.fileURL;
        if (!metadata.downloaded || ![[fileURL lastPathComponent] isEqual:@"test-renamed.txt"])
            return NO;
        
        NSString *stringB = [[NSString alloc] initWithContentsOfURL:fileURL encoding:NSUTF8StringEncoding error:NULL];
        STAssertEqualObjects(randomText, stringB, nil);
        return YES;
    }];
}

// like testRenameOfNewLocalFileWhileUploading, but interrupts the first upload.
- (void)testRenameOfNewLocalFileWhileUploadingAndThenInterruptingUpload;
{
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    
    // Add a random file and wait for it to be acknowledged
    NSString *randomText = [self copyRandomTextFileOfLength:32*1024*1024 toPath:@"random.txt" ofAccount:accountA];
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return YES;
    }];
    
    // Wait for the upload to start up
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploading && metadata.percentUploaded > 0;
    }];
    
    // Rename the file locally.
    [self movePath:@"random.txt" toPath:@"random-renamed.txt" ofAccount:accountA];
    
    // Interrupt the upload and restart
    agentA.syncingEnabled = NO;
    agentA.syncingEnabled = YES;
    
    // Wait for agent B to see everything in the end state
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        [self downloadWithMetadata:metadata agent:self.agentB];
        return YES;
    }];
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        NSURL *fileURL = metadata.fileURL;
        if (!metadata.downloaded || ![[fileURL lastPathComponent] isEqual:@"random-renamed.txt"])
            return NO;
        
        NSString *stringB = [[NSString alloc] initWithContentsOfURL:fileURL encoding:NSUTF8StringEncoding error:NULL];
        STAssertEqualObjects(randomText, stringB, nil);
        return YES;
    }];
}

- (void)_performMultipleQuickRenamesOfFixture:(NSString *)fixtureName isDirectory:(BOOL)isDirectory;
{
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    
    /*OFXFileMetadata *originalMetadata =*/ [self uploadFixture:fixtureName];
        
    NSURL *sourceURL = [accountA.localDocumentsURL URLByAppendingPathComponent:fixtureName isDirectory:isDirectory];
    NSURL *destinationURL;
    for (NSUInteger moveIndex = 0; moveIndex < 100; moveIndex++) {
        [NSThread sleepForTimeInterval:OFRandomNextDouble() * 0.05]; // wiggle a bit to see if we can shake loose some races
        
        NSString *destinationName = [[NSString stringWithFormat:@"%@-%ld", [fixtureName stringByDeletingPathExtension], moveIndex] stringByAppendingPathExtension:[fixtureName pathExtension]];
        destinationURL = [accountA.localDocumentsURL URLByAppendingPathComponent:destinationName isDirectory:isDirectory];
        [self moveURL:sourceURL toURL:destinationURL];
        sourceURL = destinationURL;
    }
    
    // Should settle to the last name, with the same file identifier
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata) {
        // We would like to end up with the same file identifier, but NSFilePresenter notifications are async, so this is hard. The file might have been moved again before we process the first move, and so it will look like it is missing if we happen to do a full scan (which we do since we get generic 'changed' notifications from NSFilePresenter too. So, we should end up with the same contents and file names, but quick moves like this might end up resulting in a deletion and re-add of a file.
        //STAssertEqualObjects(originalMetadata.fileIdentifier, metadata.fileIdentifier, nil);
        return [[metadata.fileURL lastPathComponent] isEqual:[destinationURL lastPathComponent]];
    }];
}

- (void)testMultipleQuickRenamesOfPackage;
{
    [self _performMultipleQuickRenamesOfFixture:@"test.package" isDirectory:YES];
}
- (void)testMultipleQuickRenamesOfFlatFile;
{
    [self _performMultipleQuickRenamesOfFixture:@"flat1.txt" isDirectory:NO];
}

- (void)testMoveDocumentsWhileStillUploadingPreviousMove;
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
    
    // Rename the directory on A, wait for the renames to be acknowledged, uploads to start, and then rename the directory again.
    [self movePath:@"dir" toPath:@"dir2" ofAccount:accountA];
    
    [self waitForFileMetadataItems:agentA where:^BOOL(NSSet *metadataItems) {
        return [metadataItems all:^BOOL(OFXFileMetadata *metadata) {
            return [[[metadata.fileURL URLByDeletingLastPathComponent] lastPathComponent] isEqual:@"dir2"];
        }];
    }];
    
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploading && metadata.percentUploaded > 0;
    }];
    
    // Move it again
    [self movePath:@"dir2" toPath:@"dir3" ofAccount:accountA];
    
    // Both accounts should settle to having the renamed documents
    BOOL (^predicate)(NSSet *metadataItems) = ^BOOL(NSSet *metadataItems){
        if ([metadataItems count] != fileCount)
            return NO;
        
        for (NSUInteger fileIndex = 0; fileIndex < fileCount; fileIndex++) {
            NSString *filename = [NSString stringWithFormat:@"file%lu.txt", fileIndex];
            if (![metadataItems any:^BOOL(OFXFileMetadata *metadata) {
                NSURL *fileURL = metadata.fileURL;
                return [[fileURL lastPathComponent] isEqualToString:filename] && [[[fileURL URLByDeletingLastPathComponent] lastPathComponent] isEqualToString:@"dir3"];
            }])
                return NO;
        }
        return YES;
    };
    
    [self waitForFileMetadataItems:agentA where:predicate];
    [self waitForFileMetadataItems:agentB where:predicate];
}

// Test moving a document inside another document and back out
// Test rename combined with edit (while offline, or fast enough that one happens before first finishes).
// test rename of file while offline and not downloaded
// test rename file while it is downloading
// test rename of file away from original name and then back, while offline. could elide the whole transfer, but shouldn't explode at any rate.

@end
