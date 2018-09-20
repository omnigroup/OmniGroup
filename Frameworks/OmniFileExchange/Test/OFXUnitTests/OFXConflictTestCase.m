// Copyright 2013-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

#import "OFXTrace.h"

#import <OmniFoundation/OFNull.h>
@import OmniDAV;

RCS_ID("$Id$")

@interface OFXConflictTestCase : OFXTestCase
@end


@implementation OFXConflictTestCase

BOOL OFXIsConflict(OFXFileMetadata *metadata)
{
    return [[[metadata.fileURL lastPathComponent] stringByDeletingPathExtension] containsString:@"Conflict" options:NSCaseInsensitiveSearch];
}

static NSString *_fileContents(OFXConflictTestCase *self, OFXFileMetadata *metadata)
{
    NSString *contents = [[NSString alloc] initWithContentsOfFile:metadata.fileURL.path encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertNotNil(contents);
    return contents;
}

static NSSet *_contentsOfFiles(OFXConflictTestCase *self, NSSet *metadataItems)
{
    return [metadataItems setByPerformingBlock:^id(OFXFileMetadata *metadata) {
        return _fileContents(self, metadata);
    }];
}

static OFXFileMetadata *_fileWithContents(OFXConflictTestCase *self, NSSet *metadataItems, NSString *contents)
{
    for (OFXFileMetadata *metadata in metadataItems) {
        __autoreleasing NSError *error = nil;
        
        NSString *string = [[NSString alloc] initWithContentsOfFile:metadata.fileURL.path encoding:NSUTF8StringEncoding error:&error];
        if ([error causedByMissingFile])
            continue; // This file has been moved already -- keep looking

        if ([string isEqual:contents])
            return metadata;
    }
    
    XCTFail(@"No file found with the specified contents");
    return nil;
}

static OFXFileMetadata *_fileWithIdentifier(OFXConflictTestCase *self, NSSet *metadataItems, NSString *fileIdentifier)
{
    for (OFXFileMetadata *metadata in metadataItems) {
        if (OFISEQUAL(metadata.fileIdentifier, fileIdentifier))
            return metadata;
    }
    XCTFail(@"No file found with the specified identifier");
    return nil;
}

- (void)_waitForConflictResolutionWithContentName:(NSString *)contentName1 andContentName:(NSString *)contentName2;
{
    BOOL (^predicate)(NSSet *) = ^BOOL(NSSet *metadataItems){
        // should end up with two documents; no spurious conflicts should be created
        if ([metadataItems count] < 2)
            return NO; // Wait for items to appear
        if ([metadataItems count] > 2) {
            [NSException raise:NSGenericException reason:@"Too many metadata items"];
            return NO;
        }

        OBASSERT((contentName1 == nil) == (contentName2 == nil));
        BOOL compareContents = (contentName1 != nil);
        
        // both should be uploaded (and downloaded if we are going to compare contents).
        if (![metadataItems all:^BOOL(OFXFileMetadata *metadata) {
            return metadata.uploaded && (!compareContents || metadata.downloaded);
        }])
            return NO;
        
        // Currently we (transiently) rename both files to have conflict names.
        {
            OFXFileMetadata *metadata1 = [metadataItems anyObject];
            NSMutableSet *otherMetadataItems = [metadataItems mutableCopy];
            [otherMetadataItems removeObject:metadata1];
            OFXFileMetadata *metadata2 = [otherMetadataItems anyObject];
            
            if ([[metadata1.fileURL lastPathComponent] isEqual:[metadata2.fileURL lastPathComponent]]) {
                XCTFail(@"We should never report two metadata items with the same fileURL anyway");
                return NO;
            }
            
            if (!OFXIsConflict(metadata1) || !OFXIsConflict(metadata2))
                return NO;
            
            // Both should have the same desired URL
            XCTAssertTrue(OFURLEqualsURL(metadata1.intendedFileURL, metadata2.intendedFileURL), @"Both files should remember the same user intended URL");
        }
        
        if (compareContents) {
            // Both sets of new data should appear, but we don't know which file will get which
            NSArray *metadataItemArray = [metadataItems allObjects];
            OFXFileMetadata *item1 = metadataItemArray[0];
            OFXFileMetadata *item2 = metadataItemArray[1];
            
            if (!(ITEM_MATCHES_FIXTURE(item1, contentName1) && ITEM_MATCHES_FIXTURE(item2, contentName2)) &&
                !(ITEM_MATCHES_FIXTURE(item1, contentName2) && ITEM_MATCHES_FIXTURE(item2, contentName1)))
                // They are downloaded and uploaded... no point in waiting
                return NO;
            //[NSException raise:NSGenericException reason:@"Original document and conflict document don't have the two sets of expected contents"];
        }
        
        return YES;
    };
    
    [self waitForFileMetadataItems:self.agentA where:predicate];
    [self waitForFileMetadataItems:self.agentB where:predicate];
}

- (void)testEditDocument;
{
    [self copyFixtureNamed:@"test.package"];
    
    // Make edits w/o waiting for a sync in the middle. We don't pause the agent syncing, so theoretically there is some chance the first edit could sync before the second but practically that will never happen.
    
    NSString *contentName1 = @"test2.package";
    NSString *contentName2 = @"test3.package";
    
    [self copyFixtureNamed:contentName1 toPath:@"test.package" ofAccount:[self.agentA.accountRegistry.validCloudSyncAccounts lastObject]];
    [self copyFixtureNamed:contentName2 toPath:@"test.package" ofAccount:[self.agentB.accountRegistry.validCloudSyncAccounts lastObject]];

    [self _waitForConflictResolutionWithContentName:contentName1 andContentName:contentName2];
}

- (void)testDeleteVsEditConflict;
{
    OFXFileMetadata *originalMetadata = [self copyFixtureNamed:@"test.package"];
    
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;

    // Stop syncing on B and delete the item there.
    agentB.syncSchedule = OFXSyncScheduleNone;
    [self deletePath:@"test.package" ofAccount:[agentB.accountRegistry.validCloudSyncAccounts lastObject]];
    
    // Edit the document on A and wait for it to sync up.
    [self copyFixtureNamed:@"test2.package" toPath:@"test.package" ofAccount:[self.agentA.accountRegistry.validCloudSyncAccounts lastObject]];
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.isUploaded && OFNOTEQUAL(metadata.editIdentifier, originalMetadata.editIdentifier);
    }];
    
    // Reenable syncing on B -- it should delete its old snapshot and then resurrect the file by syncing again.
    agentB.syncSchedule = OFXSyncScheduleAutomatic;
    OFXFileMetadata *restoredFile = [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return [metadata.fileIdentifier isEqual:originalMetadata.fileIdentifier] && ![metadata.editIdentifier isEqual:originalMetadata.editIdentifier] && metadata.isDownloaded;
    }];
    
    XCTAssertTrue(OFXTraceHasSignal(@"OFXFileItem.delete_transfer.commit.removed_local_snapshot"), @"should have removed the old snapshot");
    XCTAssertTrue(OFSameFiles(self, [[self fixtureNamed:@"test2.package"] path], [restoredFile.fileURL path], nil/*operations*/), @"Updated contents should have been restored");
}

- (void)testDeleteVsUnsavedEditConflict;
{
    OFXFileMetadata *originalMetadata = [self copyFixtureNamed:@"test.package"];
    
    // Set up an 'unsaved edit' on B
    OFXAgent *agentB = self.agentB;
    OFXServerAccount *accountB = [agentB.accountRegistry.validCloudSyncAccounts lastObject];
    [self addFilePresenterWritingFixture:@"test2.package" toURL:[accountB.localDocumentsURL URLByAppendingPathComponent:@"test.package" isDirectory:YES]];

    // Delete the file on A.
    OFXAgent *agentA = self.agentA;
    [self deletePath:@"test.package" ofAccount:[agentA.accountRegistry.validCloudSyncAccounts lastObject]];
    
    // The file should reappear with the autosaved contents.
    OFXFileMetadata *restoredFile = [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return OFNOTEQUAL(metadata.fileIdentifier, originalMetadata.fileIdentifier) && metadata.isDownloaded;
    }];

    XCTAssertTrue(OFXTraceHasSignal(@"OFXFileItem.incoming_delete.removed_local_snapshot"), @"should have removed the old snapshot");
    XCTAssertTrue(OFXTraceSignalCount(@"OFXFileItem.incoming_delete.removed_local_document") == 0, @"should not have removed the local document");
    XCTAssertTrue(OFSameFiles(self, [[self fixtureNamed:@"test2.package"] path], [restoredFile.fileURL path], nil/*operations*/), @"Updated contents should have been restored");
}

- (void)testTwoDifferentFilesCreatedWithSameName;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;

    // Go offline and create different files with the same name on two clients
    agentA.syncSchedule = OFXSyncScheduleNone;
    agentB.syncSchedule = OFXSyncScheduleNone;
    
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    OFXServerAccount *accountB = [agentB.accountRegistry.validCloudSyncAccounts lastObject];
    
    NSString *contentName1 = @"test.package";
    NSString *contentName2 = @"test2.package";
    
    [self copyFixtureNamed:contentName1 toPath:@"test.package" ofAccount:accountA];
    [self copyFixtureNamed:contentName2 toPath:@"test.package" ofAccount:accountB];
    
    // Go online and let the conflict resolve.
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    agentB.syncSchedule = OFXSyncScheduleAutomatic;
    
    [self _waitForConflictResolutionWithContentName:contentName1 andContentName:contentName2];
}

- (void)testTwoDifferentFilesCreatedWithSameNameWithDownloadingOff;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    agentA.automaticallyDownloadFileContents = NO;
    agentB.automaticallyDownloadFileContents = NO;
    
    // Go offline and create different files with the same name on two clients
    agentA.syncSchedule = OFXSyncScheduleNone;
    agentB.syncSchedule = OFXSyncScheduleNone;
    
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    OFXServerAccount *accountB = [agentB.accountRegistry.validCloudSyncAccounts lastObject];
    
    NSString *contentName1 = @"test.package";
    NSString *contentName2 = @"test2.package";
    
    [self copyFixtureNamed:contentName1 toPath:@"test.package" ofAccount:accountA];
    [self copyFixtureNamed:contentName2 toPath:@"test.package" ofAccount:accountB];
    
    // Go online and let the conflict resolve.
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    agentB.syncSchedule = OFXSyncScheduleAutomatic;
    
    [self _waitForConflictResolutionWithContentName:nil andContentName:nil];
}

- (void)_runLocallyCreatedFileVsRemotelyCreatedFile:(BOOL)waitForBToAck;
{
    OFXAgent *agentA = self.agentA;
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    
    OFXAgent *agentB = self.agentB;
    agentB.syncSchedule = OFXSyncScheduleNone;
    
    // Upload a file on A which B can't see since it is offline.
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    [self copyFixtureNamed:@"test.package" ofAccount:accountA];
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded;
    }];
    
    // Make a new file on B with the same name
    OFXServerAccount *accountB = [agentB.accountRegistry.validCloudSyncAccounts lastObject];
    [self copyFixtureNamed:@"test2.package" toPath:@"test.package" ofAccount:accountB];
    
    // Test the path of discovering the name conflict while we are still uploading.
    if (waitForBToAck) {
        [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
            return YES;
        }];
    }
    
    // Take B back on line and wait for the fallout
    agentB.syncSchedule = OFXSyncScheduleAutomatic;
    [self _waitForConflictResolutionWithContentName:@"test.package" andContentName:@"test2.package"];
}

- (void)testLocallyCreatedFileVsRemotelyCreatedFile;
{
    [self _runLocallyCreatedFileVsRemotelyCreatedFile:YES];
}
- (void)testLocallyCreatedFileVsRemotelyCreatedFileWhileUploading;
{
    [self _runLocallyCreatedFileVsRemotelyCreatedFile:NO];
}

- (void)testLocalEditVsIncomingCreate;
{
    OFXAgent *agentA = self.agentA;
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    
    OFXAgent *agentB = self.agentB;
    agentB.syncSchedule = OFXSyncScheduleNone;
    
    // Upload a file on A which B can't see since it is offline.
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    [self copyFixtureNamed:@"test.package" ofAccount:accountA];
    [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.uploaded;
    }];
    
    // Turn off sync on A and then make an edit
    agentA.syncSchedule = OFXSyncScheduleNone;
    [self copyFixtureNamed:@"test2.package" toPath:@"test.package" ofAccount:accountA];
    
    // Make a conflicting document on B.
    OFXServerAccount *accountB = [agentB.accountRegistry.validCloudSyncAccounts lastObject];
    [self copyFixtureNamed:@"test3.package" toPath:@"test.package" ofAccount:accountB];

    // Take both back on line and wait for the fallout
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    agentB.syncSchedule = OFXSyncScheduleAutomatic;
    [self _waitForConflictResolutionWithContentName:@"test2.package" andContentName:@"test3.package"];
}

- (void)testDeleteVsDelete;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;

    [self uploadFixture:@"test.package"];
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded;
    }];
    
    agentA.syncSchedule = OFXSyncScheduleNone;
    agentB.syncSchedule = OFXSyncScheduleNone;

    BOOL (^predicate)(NSSet *metadataItems) = ^BOOL(NSSet *metadataItems){
        return [metadataItems count] == 0;
    };

    // Apache reports a 500 when attempting to MOVE a snapshot into tmp in preparation for deletion, but it isn't there (when racing with another client).
    [NSError suppressingLogsWithUnderlyingDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_INTERNAL_SERVER_ERROR action:^{
        // Delete the file on both sides.
        [self deletePath:@"test.package" inAgent:agentA];
        [self deletePath:@"test.package" inAgent:agentB];

        // Wait for both to locally acknowledge the delete
        [self waitForFileMetadataItems:agentA where:predicate];
        [self waitForFileMetadataItems:agentB where:predicate];

        // Take both accounts online and wait a while. They should both state at zero files and no error should be registered.
        agentA.syncSchedule = OFXSyncScheduleAutomatic;
        agentB.syncSchedule = OFXSyncScheduleAutomatic;

        [self waitForSeconds:1];
    
        [self waitForFileMetadataItems:agentA where:predicate];
        [self waitForFileMetadataItems:agentB where:predicate];
    }];

    XCTAssertNil([self lastErrorInAgent:agentA]);
    XCTAssertNil([self lastErrorInAgent:agentB]);
}

- (void)testIncomingCreationVsLocalAutosaveCreation;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    // Get B primed to write a file to a destination
    [self addFilePresenterWritingFixture:@"test.package" toPath:@"test.package" inAgent:agentB];

    // And then add a file on A which will get put in that same destination
    [self copyFixtureNamed:@"test2.package" toPath:@"test.package" ofAccount:[self singleAccountInAgent:agentA]];
    
    [self _waitForConflictResolutionWithContentName:@"test.package" andContentName:@"test2.package"];
}

- (void)testIncomingMoveVsLocalAutosaveCreation;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    // Get the same file on both.
    [self uploadFixture:@"test.package"];
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded;
    }];
    
    // Get B primed to write a new document to the new location.
    [self addFilePresenterWritingFixture:@"test2.package" toPath:@"test-renamed.package" inAgent:agentB];
    
    // Move the file to this new location on A
    [self movePath:@"test.package" toPath:@"test-renamed.package" ofAccount:[self singleAccountInAgent:agentA]];
    
    [self _waitForConflictResolutionWithContentName:@"test.package" andContentName:@"test2.package"];
}

#if 0
- (void)testIncomingEditAndMoveVsLocalAutosaveCreation;
{
    XCTFail(@"Implement me");
}
#endif

- (void)testIncomingEditAndMoveVsLocalMove;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    // Get the same file on both.
    [self uploadFixture:@"test.package"];
    OFXFileMetadata *originalMetadata = [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded;
    }];

    agentA.syncSchedule = OFXSyncScheduleNone;
    agentB.syncSchedule = OFXSyncScheduleNone;
    
    // Move locally
    [self movePath:@"test.package" toPath:@"test-A.package" ofAccount:[self singleAccountInAgent:agentA]];
    
    // Edit and move remotely
    [self copyFixtureNamed:@"test2.package" toPath:@"test-B.package" ofAccount:[self singleAccountInAgent:agentB]];
    
    // Sync and we should end up with one file, with the new contents and one of the names.
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    agentB.syncSchedule = OFXSyncScheduleAutomatic;
    
    // Make sure the changes are acknowledged
    [self waitForChangeToMetadata:originalMetadata inAgent:agentA];
    [self waitForChangeToMetadata:originalMetadata inAgent:agentB];
    
    // Wait for the agents to settle down to a common state.
    [self waitForAgentsEditsToAgree];
    [self requireAgentsToHaveSameFilesByName];
    
    // Ideally we'll have just one file, with one of the two possible names, but sometimes we get two files.
    NSSet *metadataItems = [self metadataItemsForAgent:agentA];
    XCTAssertTrue([metadataItems count] == 1 || [metadataItems count] == 2, @"Expect one or two file items, depending on how the conflict is resolved.");
    if ([metadataItems count] == 1) {
        OBASSERT_NOT_REACHED("This type of conflict resolution currently produces two files, but it would be nice if this got fixed");
        XCTAssertEqual([metadataItems count], 1UL, @"Rename-only conflict should not generate another copy of the file");
        
        OFXFileMetadata *finalMetadata = [metadataItems anyObject];
        NSString *finalName = [finalMetadata.fileURL lastPathComponent];
        XCTAssertTrue([finalName isEqual:@"test-A.package"] || [finalName isEqual:@"test-B.package"], @"Rename conflict should pick one of the names");
        
        XCTAssertTrue(ITEM_MATCHES_FIXTURE(finalMetadata, @"test2.package"), @"Rename conflict should have kept edited contents");
    } else {
        XCTAssertEqual([metadataItems count], 2UL, @"Expecting rename conflict to keep both files");
        
        OFXFileMetadata *finalMetadataA = [metadataItems any:^BOOL(OFXFileMetadata *metadata) {
            return [[metadata.fileURL lastPathComponent] isEqual:@"test-A.package"];
        }];
        OFXFileMetadata *finalMetadataB = [metadataItems any:^BOOL(OFXFileMetadata *metadata) {
            return [[metadata.fileURL lastPathComponent] isEqual:@"test-B.package"];
        }];
        
        XCTAssertTrue(ITEM_MATCHES_FIXTURE(finalMetadataA, @"test.package"), @"Expecting to currently keep both files");
        XCTAssertTrue(ITEM_MATCHES_FIXTURE(finalMetadataB, @"test2.package"), @"Expecting to currently keep both files");
    }
}

#if 0
- (void)testIncomingEditAndMoveVsLocalEdit;
{
    XCTFail(@"Implement me");
}
#endif

// Take that, LHC!
- (void)testRepeatedConflictGeneration;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    NSURL *localDocumentsA = [self singleAccountInAgent:agentA].localDocumentsURL;

    // Get the same file on both.
    OFXFileMetadata *originalFile = [self uploadFixture:@"flat1.txt"];
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded;
    }];
    
    // Bang two datas into the same file repeatedly. In some cases, a conflict resolution renames the original, so make sure to find the file by identifier each time.
    const NSUInteger collisionCount = 5;
    NSMutableSet *allGeneratedDatas = [NSMutableSet set];
    
    void (^checkExistingDatasVsAllGeneratedDatas)(NSUInteger collisions) = ^(NSUInteger expectedDataCount){
        NSError *error;
        NSArray *fileURLs;
        OBShouldNotError(fileURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:localDocumentsA includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:&error]);
        
        NSMutableSet *foundDatas = [NSMutableSet set];
        for (NSURL *fileURL in fileURLs) {
            // Not using coordination to read here, but we waited for all the writes to finish (in theory).
            NSData *fileData = [[NSData alloc] initWithContentsOfURL:fileURL];
            XCTAssertNotNil(fileData);
            
            XCTAssertNotNil([allGeneratedDatas member:fileData]);
            [foundDatas addObject:fileData];
        }
        
        XCTAssertEqual([foundDatas count], expectedDataCount, @"All datas should have appeared in some resulting file");
    };
    
    // collisionIndex is marked __block so that the blocks below don't capture a single value, but read it each time they are executed
    for (__block NSUInteger collisionIndex = 0; collisionIndex < collisionCount; collisionIndex++) {
        
        // On each write operation, we should lose one data. That is, we had file X and tried to overwrite it with Y and Z. One of those should win and one should disappear. We start with 'flat1.txt' being the intial loser, so on the first collision we should end up with 2 files. On the second, 3, and so on.
        NSUInteger expectedDataCount = (collisionIndex + 2);

        OFXFileMetadata *metadataA = [self metadataWithIdentifier:originalFile.fileIdentifier inAgent:agentA];
        OFXFileMetadata *metadataB = [self metadataWithIdentifier:originalFile.fileIdentifier inAgent:agentB];

        NSData *dataA = OFRandomCreateDataOfLength(128);
        NSData *dataB = OFRandomCreateDataOfLength(128);
        
        [allGeneratedDatas addObject:dataA];
        [allGeneratedDatas addObject:dataB];
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __autoreleasing NSError *error;
        BOOL success = [coordinator prepareToWriteItemsAtURLs:@[metadataA.fileURL, metadataB.fileURL] withChanges:YES error:&error byAccessor:^BOOL(NSError **outError){
            return [coordinator writeData:dataA toURL:metadataA.fileURL options:NSDataWritingAtomic error:outError] && [coordinator writeData:dataB toURL:metadataB.fileURL options:NSDataWritingAtomic error:outError];
        }];
        XCTAssertTrue(success);
        
        // As noted above, on each iteration, we should gain one more conflict file. Wait until we have this many on each agent and they are all downloaded.
        BOOL (^waitForDownload)(NSSet *) = ^BOOL(NSSet *metadataItems){
            if ([metadataItems count] != expectedDataCount)
                return NO;
            return [metadataItems all:^BOOL(OFXFileMetadata *metadata) {
                return metadata.downloaded;
            }];
        };
        [self waitForFileMetadataItems:agentA where:waitForDownload];
        [self waitForFileMetadataItems:agentB where:waitForDownload];
        
        // Then wait for the agents to have the same set of files. Could maybe also do this based on having the same set of {file id,edit id} identifier tuples.
        [self waitUntil:^BOOL{
            return [self agentsToHaveSameIntendedFiles];
        }];
        
        // For now, validate on each operation
        checkExistingDatasVsAllGeneratedDatas(expectedDataCount);
    }
}

- (void)testRenameLoopWhileOffline;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;

    OFXServerAccount *accountA = [self singleAccountInAgent:agentA];

    // Get a few files on both sides.
    [self copyRandomTextFileOfLength:10 toPath:@"a.txt" ofAccount:accountA];
    [self copyRandomTextFileOfLength:10 toPath:@"b.txt" ofAccount:accountA];
    [self copyRandomTextFileOfLength:10 toPath:@"c.txt" ofAccount:accountA];
    [self copyRandomTextFileOfLength:10 toPath:@"d.txt" ofAccount:accountA];

    [self waitForFileMetadataItems:agentB where:^BOOL(NSSet <OFXFileMetadata *> *metadataItems) {
        if ([metadataItems count] != 4) {
            return NO;
        }
        for (OFXFileMetadata *metadata in metadataItems) {
            if (!metadata.isDownloaded) {
                return NO;
            }
        }
        return YES;
    }];

    agentA.syncSchedule = OFXSyncScheduleManual;
    agentB.syncSchedule = OFXSyncScheduleManual;
    [self waitForSeconds:0.5];

    for (NSInteger try = 0; try < 10; try++) {
        // move 'd' aside, move the rest one spot and move 'e' back to close the loop.
        // The quick move of d->e->a can cause a transient error while scanning.
        [NSError suppressingLogsWithUnderlyingDomain:NSPOSIXErrorDomain code:ENOENT action:^{
            [self movePath:@"d.txt" toPath:@"e.txt" ofAccount:accountA];
            [self movePath:@"c.txt" toPath:@"d.txt" ofAccount:accountA];
            [self movePath:@"b.txt" toPath:@"c.txt" ofAccount:accountA];
            [self movePath:@"a.txt" toPath:@"b.txt" ofAccount:accountA];
            [self movePath:@"e.txt" toPath:@"a.txt" ofAccount:accountA];

            [self waitForSeconds:0.5];
            [self waitForSync:agentA];
        }];

        // Wake up B
        [self waitForSync:agentB];
        [self waitForSeconds:0.5];
        
        [self waitForAgentsEditsToAgree];
        [self requireAgentsToHaveSameFilesByName];
    }
}

// Trying to provoke <bug:///91387> (Continual conflicts being generated when they shouldn't be)
// A is the only editor but B was generating conflicts based on the incoming renames.
- (void)testRenamesWhileUploadingLotsOfFiles;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    OFXServerAccount *accountA = [self singleAccountInAgent:agentA];
    
    // Get some files on both sides
    [self uploadFixture:@"flat1.txt" as:@"a.txt" replacingMetadata:nil];
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded;
    }];
    [self uploadFixture:@"flat1.txt" as:@"b.txt" replacingMetadata:nil];
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded;
    }];
    
    // Start uploading a ton of small files.
    for (NSUInteger fileIndex = 0; fileIndex < 300; fileIndex++)
        [self copyFixtureNamed:@"flat1.txt" toPath:[NSString stringWithFormat:@"x/%ld.txt", fileIndex] ofAccount:accountA];

    [NSError suppressingLogsWithUnderlyingDomain:NSPOSIXErrorDomain code:ENOENT action:^{
    // Rename the two starting files back and forth a few times
        for (NSUInteger renameIndex = 0; renameIndex < 40; renameIndex++) {
            [self movePath:@"a.txt" toPath:@"c.txt" ofAccount:accountA];
            [self waitForSeconds:1];

            [self movePath:@"b.txt" toPath:@"a.txt" ofAccount:accountA];
            [self waitForSeconds:1];

            [self movePath:@"c.txt" toPath:@"b.txt" ofAccount:accountA];
            [self waitForSeconds:1];
        }
    }];

    // Wait for all the uploads to finish. We don't know how long this will take, so just make sure we keep making progress.
    __block NSUInteger remaining = NSUIntegerMax;
    while (remaining > 0) {
        [self waitUntil:^BOOL{
            NSUInteger notUploaded = 0;
            for (OFXFileMetadata *metadata in [agentA metadataItemsForAccount:accountA]) {
                if (!metadata.uploaded)
                    notUploaded++;
            }
            if (notUploaded < remaining) {
                remaining = notUploaded;
                return YES;
            }
            return NO;
        }];
    }
    
    // Wait for both sides to be idle
    [self waitForAgentsEditsToAgree];
    [self requireAgentsToHaveSameFilesByName];

    // There should be no conflicts.
    for (OFXFileMetadata *metadata in [self metadataItemsForAgent:agentA]) {
        XCTAssertFalse(OFXIsConflict(metadata), @"should be no conflicts, but found %@", metadata.fileURL);
    }
}

static void _waitForAndResolveLateConflictByRenaming(OFXConflictTestCase *self,
                                                     OFXAgent *agentA, OFXAgent *agentB, OFXAgent *agentC,
                                                     NSString *random1, NSString *random2, NSString *random3)
{
    OBPRECONDITION(agentA.syncSchedule == OFXSyncScheduleNone);
    OBPRECONDITION(agentB.syncSchedule == OFXSyncScheduleNone);
    OBPRECONDITION(agentC.syncSchedule == OFXSyncScheduleNone);

    // Turn on syncing on two agents, wait for everything to idle.
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    agentB.syncSchedule = OFXSyncScheduleAutomatic;
    
    // Wait for the uploads to be done and conflict to occur
    [self waitForFileMetadataItems:agentA where:^BOOL(NSSet *metadataItems) {
        if ([metadataItems count] != 2)
            return NO;
        return [metadataItems all:^BOOL(OFXFileMetadata *metadata) {
            return metadata.uploaded && metadata.downloaded && OFXIsConflict(metadata);
        }];
    }];

    // Wait for B to catch up and make sure we got the same contents (by identifier -- the names conflict chosen may differ).
    [self waitForAgentsEditsToAgree:@[agentA, agentB]];
    [self requireAgentsToHaveSameFilesByIdentifier:@[agentA, agentB]];
    
    // Turn the third agent on and wait for it to download everything
    agentC.syncSchedule = OFXSyncScheduleAutomatic;
    
    [self waitForAgentsEditsToAgree:@[agentA, agentB, agentC] withFileCount:3];
    [self requireAgentsToHaveSameFilesByIdentifier:@[agentA, agentB, agentC]];
    
    // Check that we ended up with the right set of contents and three files in conflict
    [self waitForFileMetadataItems:agentA where:^BOOL(NSSet *metadataItems) {
        if ([metadataItems count] != 3)
            return NO;
        if (![metadataItems all:^BOOL(OFXFileMetadata *metadata) {
            return metadata.downloaded && OFXIsConflict(metadata);
        }])
            return NO;
        
        NSMutableSet *fileContents = [NSMutableSet set];
        for (OFXFileMetadata *metadata in metadataItems) {
            NSString *string = [[NSString alloc] initWithContentsOfFile:metadata.fileURL.path encoding:NSUTF8StringEncoding error:NULL];
            OBASSERT(string);
            [fileContents addObject:string];
        }
        
        XCTAssertNotNil([fileContents member:random1]);
        XCTAssertNotNil([fileContents member:random2]);
        XCTAssertNotNil([fileContents member:random3]);
        return YES;
    }];
    
    // Resolve the conflict by moving aside two of the files. The third should automatically resolve to the original name
    {
        NSSet *metadataItems = [self metadataItemsForAgent:agentA];
        [self movePath:[_fileWithContents(self, metadataItems, random1).fileURL lastPathComponent] toPath:@"test1.txt" ofAccount:[self singleAccountInAgent:agentA]];
        [self movePath:[_fileWithContents(self, metadataItems, random2).fileURL lastPathComponent] toPath:@"test2.txt" ofAccount:[self singleAccountInAgent:agentA]];
    }
    
    // Wait for A to upload its changes so that the 'wait to agree' is on the new state, not old.
    [self waitForFileMetadataItems:agentA where:^BOOL(NSSet *metadataItems) {
        return [metadataItems all:^BOOL(OFXFileMetadata *metadata) {
            return metadata.uploaded && !OFXIsConflict(metadata);
        }];
    }];
    
    NSArray *agents = @[agentA, agentB, agentC];
    [self waitForAgentsEditsToAgree:agents];
    
    // -waitForAgentsEditsToAgree: only makes sure the file identifier to edit identifier mapping is the same, but our new conflict resolution can just do local renames, so we need to wait for all the agents to have no conflict files too.
    for (OFXAgent *agent in agents) {
        [self waitForFileMetadataItems:agent where:^BOOL(NSSet *metadataItems) {
            return [metadataItems all:^BOOL(OFXFileMetadata *metadata) {
                return !OFXIsConflict(metadata);
            }];
        }];
    }
    
    [self requireAgentsToHaveSameFilesByName:@[agentA, agentB, agentC]];
    
    NSSet *fileNames = [[self metadataItemsForAgent:agentA] setByPerformingBlock:^(OFXFileMetadata *metadata){
        return metadata.fileURL.lastPathComponent;
    }];
    
    XCTAssertTrue([fileNames containsObject:@"test.txt"], @"Original name should have been taken over by the remaining conflict");
    XCTAssertTrue([fileNames containsObject:@"test1.txt"], @"Conflict file should have been renamed");
    XCTAssertTrue([fileNames containsObject:@"test2.txt"], @"Conflict file should have been renamed");
}

- (void)testLateAppearanceOfAnotherConflictByCreation;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    OFXAgent *agentC = self.agentC;
    
    [agentC applicationLaunched]; // Won't have been automatically started by our superclass

    // Make sure syncing is off
    agentA.syncSchedule = OFXSyncScheduleNone;
    agentB.syncSchedule = OFXSyncScheduleNone;
    agentC.syncSchedule = OFXSyncScheduleNone;

    // Make three random files at the same location
    NSString *random1 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentA]];
    NSString *random2 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentB]];
    NSString *random3 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentC]];

    // A scan can fail due to conflict resolution renaming things during the scan.
    [NSError suppressingLogsWithUnderlyingDomain:NSPOSIXErrorDomain code:ENOENT action:^{
        _waitForAndResolveLateConflictByRenaming(self, agentA, agentB, agentC, random1, random2, random3);
    }];
}

- (void)testLateAppearanceOfAnotherConflictByEditing;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    OFXAgent *agentC = self.agentC;
    
    [agentC applicationLaunched]; // Won't have been automatically started by our superclass
    
    // Copy a file into place
    [self copyFixtureNamed:@"flat1.txt" toPath:@"test.txt" waitingForAgentsToDownload:@[agentB, agentC]];

    // Make sure syncing is off
    agentA.syncSchedule = OFXSyncScheduleNone;
    agentB.syncSchedule = OFXSyncScheduleNone;
    agentC.syncSchedule = OFXSyncScheduleNone;
    
    // Replace the original file by three random edits
    NSString *random1 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentA]];
    NSString *random2 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentB]];
    NSString *random3 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentC]];

    // Conflict files may be moved around while scanning.
    [NSError suppressingLogsWithUnderlyingDomain:NSPOSIXErrorDomain code:ENOENT action:^{
        _waitForAndResolveLateConflictByRenaming(self, agentA, agentB, agentC, random1, random2, random3);
    }];
}

// -testLateAppearanceOfAnotherConflictByCreation and -testLateAppearanceOfAnotherConflictByEditing handle the renaming case
//- (void)testUserResolvedConflictByRenaming;
//{
//    XCTFail(@"Test that once a conflict has happened, the user can rename a file to a totally different name and the remaining file will revert to its desired name");
//}

- (void)testUserResolvedConflictByDeleting;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;

    // Make two files at the same location
    
    agentA.syncSchedule = OFXSyncScheduleNone;
    agentB.syncSchedule = OFXSyncScheduleNone;

    NSString *random1 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentA]];
    NSString *random2 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentB]];
    
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    agentB.syncSchedule = OFXSyncScheduleAutomatic;

    // Get everything in sync
    [self waitForAgentsEditsToAgree:@[agentA, agentB] withFileCount:2];
    [self requireAgentsToHaveSameFilesByIdentifier:@[agentA, agentB]];
    
    // Remove the conflicting file generated by A
    OFXFileMetadata *file1 = _fileWithContents(self, [agentA metadataItemsForAccount:[self singleAccountInAgent:agentA]], random1);
    XCTAssertTrue(OFXIsConflict(file1));
    
    [self deletePath:[file1.fileURL lastPathComponent] inAgent:agentA];
    
    // Wait for A to sync the delete and for B to see this
    [self waitForAgentsEditsToAgree:@[agentA, agentB] withFileCount:1];
    [self requireAgentsToHaveSameFilesByIdentifier:@[agentA, agentB]];
    
    // There should be a single file left with the original name and the contents generated on B.
    NSSet *metadataItems = [agentA metadataItemsForAccount:[self singleAccountInAgent:agentA]];
    XCTAssertEqual([metadataItems count], 1UL);
    
    OFXFileMetadata *metadata = [metadataItems anyObject];
    XCTAssertFalse(OFXIsConflict(metadata));
    XCTAssertNotNil(_fileWithContents(self, metadataItems, random2));
}

- (void)testUserResolvedConflictByRenamingWinnerToOriginalName;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    // Make two files at the same location
    
    agentA.syncSchedule = OFXSyncScheduleNone;
    agentB.syncSchedule = OFXSyncScheduleNone;
    
    NSString *random1 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentA]];
    NSString *random2 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentB]];
    
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    agentB.syncSchedule = OFXSyncScheduleAutomatic;
    
    // Get everything in sync
    [self waitForAgentsEditsToAgree:@[agentA, agentB] withFileCount:2];
    [self requireAgentsToHaveSameFilesByIdentifier:@[agentA, agentB]];
    
    // Rename the conflicting file generated by A
    OFXFileMetadata *file1 = _fileWithContents(self, [agentA metadataItemsForAccount:[self singleAccountInAgent:agentA]], random1);
    XCTAssertTrue(OFXIsConflict(file1));
    
    // The expected behavior is the the agent that sees a move of a file into the original name should interpret this as its queue to finalize the other conflict names by making them non-automatic moves and publishing them to the server (which may cause moves on the other clients if they chose different names). The move of the original file should not be published (since it was an automove) and so the other agents should eventually move that file back to its desired name as the other files vacate that location.
    // This finalization of conflict names means that if the user lets a conflict sit around for a while and then decides that they don't want the original file (maybe forgetting about the conflict file), and deletes it, the other file would move into the old unconflicted name.
    // NOTE: A quick move of the 'winner' with an edit as well, should be published to the server as an edit, falling under -testEditOfConflictVersion. Might be some extra sharp edges in there still (in flight upload of an edit followed by a quick rename of the file to be the winner before the upload commits?)
    OFXTraceReset();
    
    [self movePath:[file1.fileURL lastPathComponent] toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentA]];
    
    // This should settle down to both agents agreeing that file1 is test.txt and file2 is its conflict name and that it is a final name.
    for (OFXAgent *agent in @[agentA, agentB]) {
        [self waitForFileMetadataItems:agent where:^BOOL(NSSet *metadataItems) {
            if ([metadataItems count] != 2)
                return NO;
            
            // Nothing should be untransfered or at a location it doesn't want
            if ([metadataItems any:^BOOL(OFXFileMetadata *metadata) {
                if (!metadata.uploaded || metadata.uploading || !metadata.downloaded || metadata.downloading)
                    return YES;
                if (OFNOTEQUAL(metadata.intendedFileURL, metadata.fileURL))
                    return YES;
                return NO;
            }])
                return NO;
            
            // One item should be at a conflict name...
            if (![metadataItems any:^BOOL(OFXFileMetadata *metadata) {
                return OFXIsConflict(metadata);
            }])
                return NO;
            
            // ... and the other should be at the original name
            if (![metadataItems any:^BOOL(OFXFileMetadata *metadata) {
                return [[metadata.fileURL lastPathComponent] isEqual:@"test.txt"];
            }])
                return NO;
            
            // Check that the files have the expected contents on both sides
            XCTAssertEqualObjects([_fileWithContents(self, metadataItems, random1).fileURL lastPathComponent], @"test.txt");
            XCTAssertTrue(OFXIsConflict(_fileWithContents(self, metadataItems, random2)));

            return YES;
        }];
    }
    
    // During all this, no automoves should have been done, but one should have been undone (on B -- the user initiated undo of the automove doesn't get counted by this trace).
    XCTAssertEqual(OFXTraceSignalCount(@"OFXContainerAgent.conflict_automove_undone"), 1UL);
    XCTAssertEqual(OFXTraceSignalCount(@"OFXContainerAgent.conflict_automove_done"), 0UL);
}

- (void)testEditOfConflictVersion;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    // Make two files at the same location
    
    agentA.syncSchedule = OFXSyncScheduleNone;
    agentB.syncSchedule = OFXSyncScheduleNone;
    
    NSString *random1 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentA]];
    NSString *random2 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentB]];
    
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    agentB.syncSchedule = OFXSyncScheduleAutomatic;
    
    // Get everything in sync
    [self waitForAgentsEditsToAgree:@[agentA, agentB] withFileCount:2];
    [self requireAgentsToHaveSameFilesByIdentifier:@[agentA, agentB]];
    
    // Remember the conflict names on A and B
    OFXFileMetadata *file1a = _fileWithContents(self, [agentA metadataItemsForAccount:[self singleAccountInAgent:agentA]], random1);
    OFXFileMetadata *file2a = _fileWithContents(self, [agentA metadataItemsForAccount:[self singleAccountInAgent:agentA]], random2);
    OFXFileMetadata *file1b = _fileWithContents(self, [agentB metadataItemsForAccount:[self singleAccountInAgent:agentB]], random1);
    OFXFileMetadata *file2b = _fileWithContents(self, [agentB metadataItemsForAccount:[self singleAccountInAgent:agentB]], random2);

    XCTAssertTrue(OFXIsConflict(file1a));
    XCTAssertTrue(OFXIsConflict(file2a));
    XCTAssertTrue(OFXIsConflict(file1b));
    XCTAssertTrue(OFXIsConflict(file2b));

    // Make an edit to the file generated on A.
    NSString *random3 = [self copyRandomTextFileOfLength:16 toPath:[file1a.fileURL lastPathComponent] ofAccount:[self singleAccountInAgent:agentA]];
    
    // Wait for A to upload this edit and for B to download it.
    [self waitForChangeToMetadata:file1a inAgent:agentA];
    [self waitForAgentsEditsToAgree:@[agentA, agentB]];
    
    // Now, all the files should still be in conflict, should not have changed conflict names, but the contents of file1[ab] should have changed.
    NSSet *updatedMetadataItemsA = [agentA metadataItemsForAccount:[self singleAccountInAgent:agentA]];
    NSSet *updatedMetadataItemsB = [agentB metadataItemsForAccount:[self singleAccountInAgent:agentB]];
    
    OFXFileMetadata *updatedFile1a = _fileWithIdentifier(self, updatedMetadataItemsA, file1a.fileIdentifier);
    OFXFileMetadata *updatedFile2a = _fileWithIdentifier(self, updatedMetadataItemsA, file2a.fileIdentifier);
    OFXFileMetadata *updatedFile1b = _fileWithIdentifier(self, updatedMetadataItemsB, file1b.fileIdentifier);
    OFXFileMetadata *updatedFile2b = _fileWithIdentifier(self, updatedMetadataItemsB, file2b.fileIdentifier);

    // Files should not have moved
    XCTAssertEqualObjects(file1a.fileURL, updatedFile1a.fileURL);
    XCTAssertEqualObjects(file2a.fileURL, updatedFile2a.fileURL);
    XCTAssertEqualObjects(file1b.fileURL, updatedFile1b.fileURL);
    XCTAssertEqualObjects(file2b.fileURL, updatedFile2b.fileURL);
    
    // Contents should be as expected
    XCTAssertEqualObjects(random3, _fileContents(self, updatedFile1a));
    XCTAssertEqualObjects(random3, _fileContents(self, updatedFile1b));

    XCTAssertEqualObjects(random2, _fileContents(self, updatedFile2a));
    XCTAssertEqualObjects(random2, _fileContents(self, updatedFile2b));
}

// Make a conflict between agents A and B. Add a third file on C that tries to conflict with one of the automove chosen names on A,B. This is pretty contrived, but...
- (void)testRenameFileConflictWithConflictVersion;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    OFXAgent *agentC = self.agentC;
    
    // Get agentC alive, but ignoring the others
    [agentC applicationLaunched];
    agentC.syncSchedule = OFXSyncScheduleNone;

    // Make two files at the same location on two agents
    agentA.syncSchedule = OFXSyncScheduleNone;
    agentB.syncSchedule = OFXSyncScheduleNone;
    
    NSString *random1 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentA]];
    NSString *random2 = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentB]];
    
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    agentB.syncSchedule = OFXSyncScheduleAutomatic;
    
    // Get everything in sync between just those two
    [self waitForAgentsEditsToAgree:@[agentA, agentB] withFileCount:2];
    [self requireAgentsToHaveSameFilesByIdentifier:@[agentA, agentB]];
    
    // Add a file on C that uses the name of one of the files that exist on A/B
    OFXFileMetadata *file1a = _fileWithContents(self, [self metadataItemsForAgent:agentA], random1);
    NSURL *fileC = file1a.fileURL;
    NSString *random3 = [self copyRandomTextFileOfLength:16 toPath:[fileC lastPathComponent] ofAccount:[self singleAccountInAgent:agentB]];
    
    // Turn on sync on C and wait for the dust to settle.
    agentC.syncSchedule = OFXSyncScheduleAutomatic;
    [self waitForAgentsEditsToAgree:@[agentA, agentB, agentC] withFileCount:3];
    
    // All the file contents should be around
    NSSet *metadataItems = [self metadataItemsForAgent:agentA];
    NSSet *contents = _contentsOfFiles(self, metadataItems);
    XCTAssertNotNil([contents member:random1]);
    XCTAssertNotNil([contents member:random2]);
    XCTAssertNotNil([contents member:random3]);
    
    // The file at fileC should not be a conflict version.
    OFXFileMetadata *metadataC = _fileWithContents(self, metadataItems, random3);
    XCTAssertEqualObjects(metadataC.fileURL.lastPathComponent, fileC.lastPathComponent);
    XCTAssertEqualObjects(metadataC.fileURL, metadataC.intendedFileURL);
    
    // The other files should be conflict versions
    for (OFXFileMetadata *metadata in metadataItems) {
        if (metadata == metadataC)
            continue;
        XCTAssertFalse([metadata.fileURL isEqual:metadata.intendedFileURL]);
        XCTAssertTrue(OFXIsConflict(metadata));
    }
}

- (void)testMoveTwoFilesToSameLocation;
{
    // Make a couple files, minding their own business...
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;

    NSString *random1 = [self copyRandomTextFileOfLength:16 toPath:@"test1.txt" ofAccount:[self singleAccountInAgent:agentA]];
    NSString *random2 = [self copyRandomTextFileOfLength:16 toPath:@"test2.txt" ofAccount:[self singleAccountInAgent:agentB]];

    [self waitForAgentsEditsToAgree:@[agentA, agentB] withFileCount:2];
    
    agentA.syncSchedule = OFXSyncScheduleNone;
    agentB.syncSchedule = OFXSyncScheduleNone;
    
    // Then try to move them to the same spot while offline
    [self movePath:@"test1.txt" toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentA]];
    [self movePath:@"test2.txt" toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentB]];
    
    // Wait for each agent to realize its move happened locally
    for (OFXAgent *agent in @[agentA, agentB]) {
        [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
            return [metadata.fileURL.lastPathComponent isEqualToString:@"test.txt"];
        }];
    }
    
    // Turn syncing on and wait for stuff to settle out
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    agentB.syncSchedule = OFXSyncScheduleAutomatic;
    
    for (OFXAgent *agent in @[agentA, agentB]) {
        [self waitForFileMetadataItems:agent where:^BOOL(NSSet *metadataItems) {
            if ([metadataItems count] != 2)
                return NO;
            return [metadataItems all:^BOOL(OFXFileMetadata *metadata) {
                if (!OFXIsConflict(metadata))
                    return NO;
                if (![[metadata.intendedFileURL lastPathComponent] isEqual:@"test.txt"])
                    return NO;
                return YES;
            }];
        }];
    }
    
    // Make sure we still have both contents
    NSSet *contents = _contentsOfFiles(self, [self metadataItemsForAgent:agentA]);
    XCTAssertNotNil([contents member:random1]);
    XCTAssertNotNil([contents member:random2]);
}

- (void)testEditToMovedFile;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentA]];
    [self waitForAgentsEditsToAgree:@[agentA, agentB] withFileCount:1];
    
    agentA.syncSchedule = OFXSyncScheduleNone;
    agentB.syncSchedule = OFXSyncScheduleNone;
    
    // On A, move aside the original file and replace it.
    [self movePath:@"test.txt" toPath:@"moved.txt" ofAccount:[self singleAccountInAgent:agentA]];
    NSString *textA = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentA]];
    
    // On B, update the original file's contents
    NSString *textB = [self copyRandomTextFileOfLength:16 toPath:@"test.txt" ofAccount:[self singleAccountInAgent:agentB]];
    
    // Turn syncing on and wait for stuff to settle out
    agentA.syncSchedule = OFXSyncScheduleAutomatic;
    agentB.syncSchedule = OFXSyncScheduleAutomatic;

    [self waitUntil:^BOOL{
        // Both should be on the same versions
        if (![self agentEditsAgree:@[agentA, agentB] withFileCount:2])
            return NO;
        
        // There should be no conflicts
        for (OFXAgent *agent in @[agentA, agentB]) {
            if ([[self metadataItemsForAgent:agent] any:^BOOL(OFXFileMetadata *metadata) { return OFXIsConflict(metadata); }])
                return NO;
        }
        
        // We should have the expected contents
        return [self agent:agentA hasTextContentsByPath:@{@"test.txt": textA, @"moved.txt":textB}];
    }];
    
    // Make sure the other side ended up with the same.
    [self requireAgentsToHaveSameFilesByName];
}

// Test edit on one side, rename on the other
// Test making the same edits on two agents -- ETag based conflicts would still call this a conflict, but it might be nice to notice that the contents are the same and just ignore it. This wouldn't work reliably w/o app help though -- for example identifiers for new rows in OmniOutliner would differ, even if they had the exact same cell values.

@end

