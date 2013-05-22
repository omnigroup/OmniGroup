// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFSTestCase.h"

enum {
    AgentA = (1<<0),
    AgentB = (1<<1),
};

#import <OmniFileExchange/OFXServerAccountRegistry.h>

@interface OFXTestServerAccountRegistry : OFXServerAccountRegistry
@property(nonatomic,copy) NSString *suffix;
@end


@class OFXAgent, OFXServerAccount, OFXFileMetadata;

@interface OFXTestCase : OFSTestCase

- (OFXTestServerAccountRegistry *)makeAccountRegistry:(NSString *)suffix;

- (NSURL *)localDocumentsURLForAddingAccountToRegistry:(OFXTestServerAccountRegistry *)registry;

- (OFXServerAccount *)addAccountToRegistry:(OFXTestServerAccountRegistry *)registry;
- (OFXServerAccount *)addAccountToRegistry:(OFXTestServerAccountRegistry *)registry isFirst:(BOOL)isFirst;
- (OFXServerAccount *)addAccountToRegistry:(OFXTestServerAccountRegistry *)registry withLocalDocumentsURL:(NSURL *)localDocumentsURL isFirst:(BOOL)isFirst error:(NSError **)outError;

// Info used to set up the agent.
@property(nonatomic,readonly) NSArray *syncPathExtensions;
- (NSArray *)extraPackagePathExtensionsForAgent:(NSUInteger)flag;

@property(nonatomic,readonly) NSUInteger automaticallyStartAgents; // setup/teardown will start/stop the agents (specified by AgentA, AgentB mask)
@property(nonatomic,readonly) BOOL automaticallyAddAccount; // Returns YES by default; if YES, agents returned by this class will already have an account.
@property(nonatomic,readonly) BOOL automaticallyDownloadFileContents; // By default, returns YES if syncPathExtensions is "everything"
- (OFXAccountClientParameters *)accountClientParametersForAgent:(NSUInteger)flag name:(NSString *)agentName;

@property(nonatomic,readonly) OFXAgent *agentA;
@property(nonatomic,readonly) OFXAgent *agentB;

- (void)stopAgents; // Helper that sends -applicationWillTerminateWithCompletionHandler: and waits for it to finish.

- (OFXServerAccount *)singleAccountInAgent:(OFXAgent *)agent;

- (NSSet *)metadataItemsForAgent:(OFXAgent *)agent;
- (OFXFileMetadata *)metadataWithIdentifier:(NSString *)fileIdentifier inAgent:(OFXAgent *)agent;

- (void)waitSomeTimeUpToSeconds:(NSTimeInterval)interval;
- (void)waitForSeconds:(NSTimeInterval)interval;
- (void)waitForAsyncOperations;
- (void)waitUntil:(BOOL (^)(void))finished;
- (NSSet *)waitForFileMetadataItems:(OFXAgent *)agent where:(BOOL (^)(NSSet *metadataItems))qualifier;
- (OFXFileMetadata *)waitForFileMetadata:(OFXAgent *)agent where:(BOOL (^)(OFXFileMetadata *metadata))qualifier;
- (void)waitForSync:(OFXAgent *)agent;
- (void)waitForChangeToMetadata:(OFXFileMetadata *)originalMetadata inAgent:(OFXAgent *)agent;
- (void)waitForAgentsToAgree;

- (void)requireAgentsToHaveSameFiles;

- (NSURL *)fixtureNamed:(NSString *)fixtureName;

+ (void)copyFileURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL filePresenter:(id <NSFilePresenter>)filePresenter;
- (void)copyFileURL:(NSURL *)fileURL toPath:(NSString *)destinationPath ofAccount:(OFXServerAccount *)account;
- (void)copyFixtureNamed:(NSString *)fixtureName toPath:(NSString *)destinationPath ofAccount:(OFXServerAccount *)account;
- (void)copyFixtureNamed:(NSString *)fixtureName ofAccount:(OFXServerAccount *)account;
- (NSString *)copyRandomTextFileOfLength:(NSUInteger)textLength toPath:(NSString *)destinationPath ofAccount:(OFXServerAccount *)account;
- (NSString *)copyLargeRandomTextFileToPath:(NSString *)destinationPath ofAccount:(OFXServerAccount *)account;

// Returns metadata item for agentA
- (OFXFileMetadata *)copyFixtureNamed:(NSString *)fixtureName waitForDownload:(BOOL)waitForDownload;
- (OFXFileMetadata *)copyFixtureNamed:(NSString *)fixtureName; // Copies to A and waits for B to download. Returns the edit identifier

- (void)writeRandomFlatFile:(NSString *)name withSize:(NSUInteger)fileSize;

- (OFXFileMetadata *)makeRandomFlatFile:(NSString *)name withSize:(NSUInteger)fileSize;
- (OFXFileMetadata *)makeRandomFlatFile:(NSString *)name; // Makes a large random text file on agent A and uploads it. Shouldn't be downloaded on B since it is large. Returns the original metadata from agent A
- (OFXFileMetadata *)makeRandomPackageNamed:(NSString *)name memberCount:(NSUInteger)memberCount memberSize:(NSUInteger)memberSize;
- (OFXFileMetadata *)makeRandomLargePackage:(NSString *)name; // Makes a large package on agent A and uploads it. Shouldn't be downloaded on B since it is large. Returns the original metadata from agent A

- (OFXFileMetadata *)uploadFixture:(NSString *)fixtureName;
- (OFXFileMetadata *)uploadFixture:(NSString *)fixtureName as:(NSString *)destinationPath replacingMetadata:(OFXFileMetadata *)previousMetadata;

- (OFXFileMetadata *)downloadWithMetadata:(OFXFileMetadata *)metadata agent:(OFXAgent *)agent;
- (void)downloadFileWithIdentifier:(NSString *)fileIdentifier untilPercentage:(double)untilPercentage agent:(OFXAgent *)agent;

- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL;
- (void)movePath:(NSString *)sourcePath toPath:(NSString *)destinationPath ofAccount:(OFXServerAccount *)account;
- (void)deletePath:(NSString *)filePath ofAccount:(OFXServerAccount *)account;
- (void)deletePath:(NSString *)filePath inAgent:(OFXAgent *)agent;

- (NSError *)lastErrorInAgent:(OFXAgent *)agent;

// Simulate unsaved changes
- (void)addFilePresenterWritingURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL;
- (void)addFilePresenterWritingFixture:(NSString *)fixtureName toURL:(NSURL *)fileURL;
- (void)addFilePresenterWritingFixture:(NSString *)fixtureName toPath:(NSString *)path inAgent:(OFXAgent *)agent;

@end

#define ITEM_MATCHES_FIXTURE(i,f) OFSameFiles(self, [(i).fileURL path], [[self fixtureNamed:(f)] path], NULL)

// These might move to NSFileCoordinator(OFExtensions) if they turn out to be useful/clear enough.
@interface NSFileCoordinator (OFXTestCaseExtensions)
- (BOOL)writeData:(NSData *)data toURL:(NSURL *)fileURL options:(NSDataWritingOptions)options error:(NSError **)outError;
@end
