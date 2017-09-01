// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFileExchange/OFXErrors.h>

#import "OFXServerAccountRegistry-Internal.h"

RCS_ID("$Id$")

@interface OFXAgentAccountChangeTestCase : OFXTestCase
@end

@implementation OFXAgentAccountChangeTestCase

- (NSSet *)automaticallyStartedAgentNames;
{
    return nil;
}

- (BOOL)automaticallyAddAccount;
{
    return NO;
}

- (void)testAddAccount;
{
    // Start the agent and then after a while add an account
    OFXAgent *agent = self.agentA;
    [agent applicationLaunched];
    
    [self waitSomeTimeUpToSeconds:0.2];

    XCTAssertEqual([agent.accountRegistry.allAccounts count], 0ULL);

    OFXServerAccount *account = [self addAccountToRegistry:(OFXTestServerAccountRegistry *)agent.accountRegistry isFirst:YES];
    [self waitForAsyncOperations];
    
    NSURL *url = account.localDocumentsURL;
    XCTAssertTrue([url checkResourceIsReachableAndReturnError:NULL]);
}

- (void)testStartWithAccount;
{
    OFXAgent *agent = self.agentA;
    OFXServerAccount *account = [self addAccountToRegistry:(OFXTestServerAccountRegistry *)agent.accountRegistry];
    
    [agent applicationLaunched];
    [self waitForAsyncOperations];
    
    XCTAssertTrue([account.localDocumentsURL checkResourceIsReachableAndReturnError:NULL]);
    
    NSURL *localStoreURL = [agent.accountRegistry localStoreURLForAccount:account];
    XCTAssertTrue([localStoreURL checkResourceIsReachableAndReturnError:NULL]);
}

- (void)testRemoveAccount;
{
    // Add the account
    OFXAgent *agent = self.agentA;
    OFXServerAccount *account = [self addAccountToRegistry:(OFXTestServerAccountRegistry *)agent.accountRegistry];

    [agent applicationLaunched];
    [self waitForAsyncOperations];

    NSURL *localAccountStoreURL = [agent.accountRegistry localStoreURLForAccount:account];
    __autoreleasing NSError *error;
    XCTAssertTrue([localAccountStoreURL checkResourceIsReachableAndReturnError:&error], @"Our local management files for the account should exist by this time");

    // Then remove it.
    [account prepareForRemoval];
    
    // Wait for the local management files to disappear
    [self waitUntil:^BOOL{
        __autoreleasing NSError *checkError;
        if ([localAccountStoreURL checkResourceIsReachableAndReturnError:&checkError])
            return NO;
        XCTAssertTrue([checkError causedByMissingFile], @"should only get a missing file error");
        return YES;
    }];
    
    // We don't want to bulk delete files if you unlink an account. Rather, the user should clean those up when they are done with them. If they turn syncing *back* on, though, we might hit conflicts (since we don't know if the server or client version is current unless the files are identical).
    XCTAssertTrue([account.localDocumentsURL checkResourceIsReachableAndReturnError:&error], @"Document directory should still exist");
}

- (void)testRemoveDocumentsDirectoryWhileNotRunning;
{
    // Start up
    OFXAgent *agent = self.agentA;
    OFXServerAccount *account = [self addAccountToRegistry:(OFXTestServerAccountRegistry *)agent.accountRegistry];
    [agent applicationLaunched];
    [self waitForAsyncOperations];

    // Shut down
    __block BOOL terminated = NO;
    [agent applicationWillTerminateWithCompletionHandler:^{
        terminated = YES;
    }];
    [self waitUntil:^{ return terminated; } ];
    
    // Remove the account's documents directory
    __autoreleasing NSError *error;
    OBShouldNotError([[NSFileManager defaultManager] atomicallyRemoveItemAtURL:account.localDocumentsURL error:&error]);
    
    [NSError suppressingLogsWithUnderlyingDomain:OFXErrorDomain code:OFXLocalAccountDocumentsDirectoryMissing action:^{
        // Restarting should fail -- we need the user to either put back the documents directory or to remove and re-add the account.
        [agent applicationLaunched];
        [self waitForAsyncOperations];
        
        XCTAssertTrue([account.lastError hasUnderlyingErrorDomain:OFXErrorDomain code:OFXLocalAccountDocumentsDirectoryMissing]);
    }];
}

- (void)testAddAccountWithExistingEmptyDirectory;
{
    // Start the agent and then after a while add an account
    OFXAgent *agent = self.agentA;
    [agent applicationLaunched];
    
    [self waitSomeTimeUpToSeconds:0.2];
    
    XCTAssertEqual([agent.accountRegistry.allAccounts count], 0ULL);
    
    OFXTestServerAccountRegistry *registry = (OFXTestServerAccountRegistry *)agent.accountRegistry;
    
    __autoreleasing NSError *error;
    NSURL *localDocumentsURL = [self localDocumentsURLForAddingAccountToRegistry:registry];
    OBShouldNotError([[NSFileManager defaultManager] createDirectoryAtURL:localDocumentsURL withIntermediateDirectories:NO attributes:nil error:&error]);

    OFXServerAccount *account;
    OBShouldNotError(account = [self addAccountToRegistry:registry withLocalDocumentsURL:localDocumentsURL isFirst:YES error:&error]);
    
    [self waitUntil:^BOOL{
        return [agent.runningAccounts member:account] != nil;
    }];
}

- (void)testAddAccountWithExistingNonEmptyDirectory;
{
    // Start the agent and then after a while add an account
    OFXAgent *agent = self.agentA;
    [agent applicationLaunched];
    
    [self waitSomeTimeUpToSeconds:0.2];
    
    XCTAssertEqual([agent.accountRegistry.allAccounts count], 0ULL);
    
    OFXTestServerAccountRegistry *registry = (OFXTestServerAccountRegistry *)agent.accountRegistry;
    
    __autoreleasing NSError *error;
    NSURL *localDocumentsURL = [self localDocumentsURLForAddingAccountToRegistry:registry];
    OBShouldNotError([[NSFileManager defaultManager] createDirectoryAtURL:localDocumentsURL withIntermediateDirectories:NO attributes:nil error:&error]);
    OBShouldNotError([[NSFileManager defaultManager] createDirectoryAtURL:[localDocumentsURL URLByAppendingPathComponent:@"foo"] withIntermediateDirectories:NO attributes:nil error:&error]);
    
    error = nil;
    OFXServerAccount *account = [self addAccountToRegistry:registry withLocalDocumentsURL:localDocumentsURL isFirst:YES error:&error];
    XCTAssertNil(account, @"Adding account should have failed due to non-empty documents directory");
    XCTAssertTrue([error hasUnderlyingErrorDomain:OFXErrorDomain code:OFXLocalAccountDirectoryNotUsable]);
}

- (void)testRemovingAccountWhileDownloadingDocuments;
{
    // Add an account on A
    OFXAgent *agentA = self.agentA;
    {
        [self addAccountToRegistry:(OFXTestServerAccountRegistry *)agentA.accountRegistry];
        [agentA applicationLaunched];
    }
    
    // Upload a document on agent A
    OFXFileMetadata *originalMetadata = [self makeRandomFlatFile:@"random.txt"];

    // Add the account for B, wait for the download to start, and then remove the account.
    OFXAgent *agentB = self.agentB;
    {
        [self addAccountToRegistry:(OFXTestServerAccountRegistry *)agentB.accountRegistry isFirst:NO];
        [agentB applicationLaunched];
    }
    
    // Wait for the metadata to appear and then start downloading it.
    [self waitForFileMetadata:agentB where:^BOOL(OFXFileMetadata *metadata) {
        return [metadata.fileIdentifier isEqual:originalMetadata.fileIdentifier];
    }];
    [self downloadFileWithIdentifier:originalMetadata.fileIdentifier untilPercentage:0.1 agent:agentB];

    OFXServerAccount *accountB = [[agentB.accountRegistry validCloudSyncAccounts] lastObject];
    [accountB prepareForRemoval];
    
    // Wait a bit to see if anything breaks.
    [self waitForSeconds:1];
}

- (void)testRemoveLocalDocumentsDirectoryWhileDownloadingDocuments;
{
    OBFinishPortingLater("<bug:///147837> (iOS-OmniOutliner Engineering: OFXAgentAccountChangeTestCase.m:201: Test disabled for now)"); //  It fails with the current framework, and while we have some ideas for a fix, this is rare enough and the fix dangerous enough that we're leaving this as is for 1.0
#if 0
    return;
    
    // Add an account on A and upload a large-ish document
    OFXAgent *agentA = self.agentA;
    OFXFileMetadata *originalMetadata;
    {
        [self addAccountToRegistry:(OFXTestServerAccountRegistry *)agentA.accountRegistry];
        [agentA applicationLaunched];
        
        originalMetadata = [self makeRandomPackageNamed:@"random.package" memberCount:16 memberSize:4*1024*1024];
    }
    
    // Add the account for B, start a download and move the local documents directory to the trash.
    OFXAgent *agentB = self.agentB;
    {
        [self addAccountToRegistry:(OFXTestServerAccountRegistry *)agentB.accountRegistry isFirst:NO];
        [agentB applicationLaunched];
        [self downloadFileWithIdentifier:originalMetadata.fileIdentifier untilPercentage:0.1 agent:agentB];
    }

    OFXServerAccount *accountB = [self singleAccountInAgent:agentB];
    
    NSLog(@"**** Performing removal ****");
    
    NSOperationQueue *coordinationQueue = [[NSOperationQueue alloc] init];
    [coordinationQueue addOperationWithBlock:^{
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        BOOL success;
        __autoreleasing NSError *error;
        
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
        success = [coordinator removeItemAtURL:accountB.localDocumentsURL error:&error byAccessor:
                   ^BOOL(NSURL *newURL, NSError **outError) {
                       return [[NSFileManager defaultManager] removeItemAtURL:newURL error:outError];
                   }];
#else
        success = [coordinator writeItemAtURL:accountB.localDocumentsURL withChanges:YES error:&error byAccessor:^BOOL(NSURL *newURL, NSError *__autoreleasing *outError) {
            // No actual write; just trying to provoke the double-relinquish in <bug:///88939> (Crash when a synced folder is deleted from Finder)
            return YES;
        }];
        if (!success) {
            XCTAssertTrue(success, @"Removal should not fail");
            [error log:@"Error writing local documents directory"];
        }
        
        // We want 'move' in this case so that we can be sure that when the replacement account agent starts up, it gets the destination URL correct (it looks at the URL and rejects it if it is in the trash).
        success = [coordinator moveItemAtURL:accountB.localDocumentsURL error:&error byAccessor:
                   ^NSURL *(NSURL *newURL, NSError **outError) {
                       __autoreleasing NSURL *resultingItemURL;
                       if ([[NSFileManager defaultManager] trashItemAtURL:newURL resultingItemURL:&resultingItemURL error:outError]) {
                           NSLog(@"Moved to %@", resultingItemURL);
                           return resultingItemURL;
                       }
                       return nil;
                   }];
#endif
        XCTAssertTrue(success, @"Removal should not fail");
    
        if (!success)
            [error log:@"Error moving local documents directory"];
    }];
    
    [NSError suppressingLogsWithUnderlyingDomain:OFXErrorDomain code:OFXLocalAccountDocumentsDirectoryMissing action:^{
        [self waitUntil:^BOOL{
            return [accountB.lastError hasUnderlyingErrorDomain:OFXErrorDomain code:OFXLocalAccountDocumentsDirectoryMissing];
        }];
    }];
    
    [coordinationQueue self]; // make sure this stays alive and running our operation.
#endif
}

// TODO: Test failing to add an account pointing at a pre-existing non-empty documents URL
// TODO: Test re-establishing the local documents directory

@end
