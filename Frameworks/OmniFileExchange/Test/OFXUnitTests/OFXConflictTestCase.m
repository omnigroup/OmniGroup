// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

#import "OFXTrace.h"

#import <OmniFoundation/OFNull.h>

RCS_ID("$Id$")

@interface OFXConflictTestCase : OFXTestCase
@end


@implementation OFXConflictTestCase

- (void)_waitForConflictResolutionWithContentName:(NSString *)contentName1 andContentName:(NSString *)contentName2;
{
    BOOL (^predicate)(NSSet *) = ^BOOL(NSSet *metadataItems){
        // should end up with two documents
        if ([metadataItems count] != 2) {
            // Sometimes we get three files if both clients try to resolve the conflict. This is rare, but it can happen (ideally it wouldn't, but this is hard to avoid).
            if ([metadataItems count] > 3)
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
        
        // Sometimes both agents try to resolve the conflict and we end up with both having the conflict name. It may be possible to resolve this, but it doesn't seem like a super high priority.
        // <bug:///87499> (Sometimes a conflict can result in two "conflict" documents)
#if 0
        // one should have the original name
        if (![metadataItems any:^BOOL(OFXFileMetadata *metadata) {
            if (![[metadata.fileURL lastPathComponent] isEqual:@"test.package"])
                return NO;
            return YES;
        }])
            return NO;
        
        // one should have a conflict name
        if (![metadataItems any:^BOOL(OFXFileMetadata *metadata) {
            if (![[[metadata.fileURL lastPathComponent] pathExtension] isEqual:@"package"])
                return NO;
            if (![[[metadata.fileURL lastPathComponent] stringByDeletingPathExtension] containsString:@"Conflict" options:NSCaseInsensitiveSearch])
                return NO;
            return YES;
        }])
            return NO;
#else
        // They should have different names and one should have a conflict name (but both might as noticed in the bug referenced above).
        {
            OFXFileMetadata *metadata1 = [metadataItems anyObject];
            NSMutableSet *otherMetadataItems = [metadataItems mutableCopy];
            [otherMetadataItems removeObject:metadata1];
            OFXFileMetadata *metadata2 = [otherMetadataItems anyObject];
            
            if ([[metadata1.fileURL lastPathComponent] isEqual:[metadata2.fileURL lastPathComponent]]) {
                STFail(@"We should never report two metadata items with the same fileURL anyway");
                return NO;
            }
            
            if (![[[metadata1.fileURL lastPathComponent] stringByDeletingPathExtension] containsString:@"Conflict" options:NSCaseInsensitiveSearch] &&
                ![[[metadata2.fileURL lastPathComponent] stringByDeletingPathExtension] containsString:@"Conflict" options:NSCaseInsensitiveSearch])
                return NO;
        }
#endif
        
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
        return metadata.isDownloaded;
    }];
    
    STAssertTrue(OFXTraceHasSignal(@"OFXFileItem.delete_transfer.commit.removed_local_snapshot"), @"should have removed the old snapshot");
    STAssertTrue(OFSameFiles(self, [[self fixtureNamed:@"test2.package"] path], [restoredFile.fileURL path], NULL/*filter*/), @"Updated contents should have been restored");
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

    STAssertTrue(OFXTraceHasSignal(@"OFXFileItem.incoming_delete.removed_local_snapshot"), @"should have removed the old snapshot");
    STAssertTrue(OFXTraceSignalCount(@"OFXFileItem.incoming_delete.removed_local_document") == 0, @"should not have removed the local document");
    STAssertTrue(OFSameFiles(self, [[self fixtureNamed:@"test2.package"] path], [restoredFile.fileURL path], NULL/*filter*/), @"Updated contents should have been restored");
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
    // The case above renames one of the files due to the download commit failing (since it starts before the shadowing is known). Make sure we do conflict renames even if no downloads happen.
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

    STAssertNil([self lastErrorInAgent:agentA], nil);
    STAssertNil([self lastErrorInAgent:agentB], nil);
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
    STFail(@"Implement me");
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
    [self waitForAgentsToAgree];
    
    // Ideally we'll have just one file, with one of the two possible names, but sometimes we get two files.
    NSSet *metadataItems = [self metadataItemsForAgent:agentA];
    STAssertTrue([metadataItems count] == 1 || [metadataItems count] == 2, @"Expect one or two file items, depending on how the conflict is resolved.");
    if ([metadataItems count] == 1) {
        OBASSERT_NOT_REACHED("This type of conflict resolution currently produces two files, but it would be nice if this got fixed");
        STAssertEquals([metadataItems count], 1UL, @"Rename-only conflict should not generate another copy of the file");
        
        OFXFileMetadata *finalMetadata = [metadataItems anyObject];
        NSString *finalName = [finalMetadata.fileURL lastPathComponent];
        STAssertTrue([finalName isEqual:@"test-A.package"] || [finalName isEqual:@"test-B.package"], @"Rename conflict should pick one of the names");
        
        STAssertTrue(ITEM_MATCHES_FIXTURE(finalMetadata, @"test2.package"), @"Rename conflict should have kept edited contents");
    } else {
        NSSet *metadataItems = [self metadataItemsForAgent:agentA];
        STAssertEquals([metadataItems count], 2UL, @"Expecting rename conflict to keep both files");
        
        OFXFileMetadata *finalMetadataA = [metadataItems any:^BOOL(OFXFileMetadata *metadata) {
            return [[metadata.fileURL lastPathComponent] isEqual:@"test-A.package"];
        }];
        OFXFileMetadata *finalMetadataB = [metadataItems any:^BOOL(OFXFileMetadata *metadata) {
            return [[metadata.fileURL lastPathComponent] isEqual:@"test-B.package"];
        }];
        
        STAssertTrue(ITEM_MATCHES_FIXTURE(finalMetadataA, @"test.package"), @"Expecting to currently keep both files");
        STAssertTrue(ITEM_MATCHES_FIXTURE(finalMetadataB, @"test2.package"), @"Expecting to currently keep both files");
    }
}

#if 0
- (void)testIncomingEditAndMoveVsLocalEdit;
{
    STFail(@"Implement me");
}
#endif

// Take that, LHC!
- (void)testRepeatedConflictGeneration;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    NSURL *localDocumentsA = [self singleAccountInAgent:agentA].localDocumentsURL;
    NSURL *localDocumentsB = [self singleAccountInAgent:agentB].localDocumentsURL;

    // Get the same file on both.
    OFXFileMetadata *originalFile = [self uploadFixture:@"flat1.txt"];
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return metadata.downloaded;
    }];
    
    // Bang two datas into the same file repeatedly. In some cases, a conflict resolution renames the original, so make sure to find the file by identifier each time.
    const NSUInteger collisionCount = 5;
    NSMutableSet *allGeneratedDatas = [NSMutableSet set];
    
    void (^validate)(NSUInteger collisions) = ^(NSUInteger collisions){
        [self requireAgentsToHaveSameFiles];

        // On each write operation, we should lose one data. That is, we had file X and tried to overwrite it with Y and Z. One of those should win and one should disappear. We start with 'flat1.txt' being the intial loser, so on the first collision we should end up with 2 files. On the second, 3. Third 4. In some relatively rare cases, we end up duplicating files during conflict resolution, so we can't just check the file count.
        NSUInteger expectedDataCount = (collisions + 1);
        
        NSError *error;
        NSArray *fileURLs;
        OBShouldNotError(fileURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:localDocumentsA includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:&error]);
        
        NSMutableSet *foundDatas = [NSMutableSet set];
        for (NSURL *fileURL in fileURLs) {
            // Not using coordination to read here, but we waited for all the writes to finish (in theory).
            NSData *fileData = [[NSData alloc] initWithContentsOfURL:fileURL];
            STAssertNotNil(fileData, nil);
            
            STAssertNotNil([allGeneratedDatas member:fileData], nil);
            [foundDatas addObject:fileData];
        }
        
        STAssertEquals([foundDatas count], expectedDataCount, @"All datas should have appeared in some resulting file");
    };
    
    for (NSUInteger collisionIndex = 0; collisionIndex < collisionCount; collisionIndex++) {
        OFXFileMetadata *metadataA = [self metadataWithIdentifier:originalFile.fileIdentifier inAgent:agentA];
        OFXFileMetadata *metadataB = [self metadataWithIdentifier:originalFile.fileIdentifier inAgent:agentB];

        NSLog(@"### starting %ld ###", collisionIndex);
        
        NSData *dataA = OFRandomCreateDataOfLength(128);
        NSData *dataB = OFRandomCreateDataOfLength(128);
        
        [allGeneratedDatas addObject:dataA];
        [allGeneratedDatas addObject:dataB];
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __autoreleasing NSError *error;
        BOOL success = [coordinator prepareToWriteItemsAtURLs:@[metadataA.fileURL, metadataB.fileURL] withChanges:YES error:&error byAccessor:^BOOL(NSError **outError){
            return [coordinator writeData:dataA toURL:metadataA.fileURL options:NSDataWritingAtomic error:outError] && [coordinator writeData:dataB toURL:metadataB.fileURL options:NSDataWritingAtomic error:outError];
        }];
        STAssertTrue(success, nil);
        
        // Wait for the edit identifiers to change and uploads to be done
        [self waitUntil:^BOOL{
            OFXFileMetadata *updatedMetadataA = [self metadataWithIdentifier:originalFile.fileIdentifier inAgent:agentA];
            if ([updatedMetadataA.editIdentifier isEqualToString:metadataA.editIdentifier] || updatedMetadataA.uploading)
                return NO;
            
            OFXFileMetadata *updatedMetadataB = [self metadataWithIdentifier:originalFile.fileIdentifier inAgent:agentB];
            if ([updatedMetadataB.editIdentifier isEqualToString:metadataB.editIdentifier] || updatedMetadataB.uploading)
                return NO;
            
            return YES;
        }];
        
        // The wait for the agents to have the same set of files. Could maybe also do this based on having the same set of {file id,edit id} identifier tuples.
        [self waitUntil:^BOOL{
            return OFSameFiles(self, [localDocumentsA path], [localDocumentsB path], nil/*filter*/);
        }];
        
        // For now, validate on each operation
        validate(collisionIndex + 1);
    }
}

// Trying to provoke <bug:///91387> (Continual conflicts being generated when they shouldn't be)
// A is the only editor but B was generating conflicts based on the incoming renames.
- (void)testRenamesWhileUploadingLotsOfFiles;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    OFXServerAccount *accountA = [self singleAccountInAgent:agentA];
    
    // Get two files on both sides
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

    // Rename the two starting files back and forth a few times
    for (NSUInteger renameIndex = 0; renameIndex < 20; renameIndex++) {
        [self movePath:@"a.txt" toPath:@"c.txt" ofAccount:accountA];
        [self waitForSeconds:1];
        
        [self movePath:@"b.txt" toPath:@"a.txt" ofAccount:accountA];
        [self waitForSeconds:1];
        
        [self movePath:@"c.txt" toPath:@"b.txt" ofAccount:accountA];
        [self waitForSeconds:1];
    }
    
    // Wait for both sides to be idle
    [self waitForAgentsToAgree];

    // There should be no conflicts.
    for (OFXFileMetadata *metadata in [self metadataItemsForAgent:agentA]) {
        STAssertFalse([[[metadata.fileURL lastPathComponent] stringByDeletingPathExtension] containsString:@"Conflict" options:NSCaseInsensitiveSearch], @"should be no conflicts, but found %@", metadata.fileURL);
    }
}

// Test edit on one side, rename on the other
// Test making the same edits on two agents -- ETag based conflicts would still call this a conflict, but it might be nice to notice that the contents are the same and just ignore it. This wouldn't work reliably w/o app help though -- for example identifiers for new rows in OmniOutliner would differ, even if they had the exact same cell values.

@end

