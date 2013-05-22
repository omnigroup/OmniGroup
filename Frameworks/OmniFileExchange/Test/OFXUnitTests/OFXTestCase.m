// Copyright 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

#import <OmniFileExchange/OFXAccountClientParameters.h>
#import <OmniFileExchange/OFXServerAccountValidator.h>
#import <OmniFileStore/Errors.h>
#import <OmniFileStore/OFSFileManager.h>
#import <OmniFileStore/OFSFileManagerDelegate.h>
#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniFoundation/OFXMLIdentifier.h>

#import "OFXServerAccount-Internal.h"
#import "OFXTrace.h"
#import "OFXTestSaveFilePresenter.h"
#import "OFXContentIdentifier.h"

RCS_ID("$Id$")

@implementation OFXTestServerAccountRegistry
@end

@interface OFXTestCase () <OFSFileManagerDelegate>
@property(nonatomic,readonly) NSString *remoteDirectoryName;
@property(nonatomic,readonly) NSURL *remoteBaseURL;
@end

@implementation OFXTestCase
{
    OFRandomState *_randomState;
    NSMutableArray *_helpers;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OFXTraceEnabled = YES;

    NSArray *fixtureURLs = [OMNI_BUNDLE URLsForResourcesWithExtension:nil subdirectory:@"Fixtures"];
    for (NSURL *fixtureURL in fixtureURLs) {
        OFXRegisterDisplayNameForContentAtURL(fixtureURL, [fixtureURL lastPathComponent]);
    }
}

- (OFXTestServerAccountRegistry *)makeAccountRegistry:(NSString *)suffix;
{
    NSString *name = [NSString stringWithFormat:@"Accounts-%@", self.name];
    
    if (![NSString isEmptyString:suffix])
        name = [name stringByAppendingFormat:@"-%@", suffix];
    
    NSString *accountsDirectoryPath = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    NSURL *accountsDirectoryURL = [NSURL fileURLWithPath:accountsDirectoryPath];
    
    // Clean up cruft from previous runs
    __autoreleasing NSError *error;
    if (![[NSFileManager defaultManager] removeItemAtURL:accountsDirectoryURL error:&error]) {
        STAssertTrue([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT], nil);
    }
    
    OFXTestServerAccountRegistry *registry;
    OBShouldNotError(registry = [[OFXTestServerAccountRegistry alloc] initWithAccountsDirectoryURL:accountsDirectoryURL error:&error]);
    
    registry.suffix = suffix;
    
    STAssertNotNil(registry, nil);
    STAssertEquals([registry.allAccounts count], (NSUInteger)0, nil);
    
    return registry;
}

- (NSURL *)localDocumentsURLForAddingAccountToRegistry:(OFXTestServerAccountRegistry *)registry;
{
    NSURL *localDocumentsURL;
    {
        NSString *name = [NSString stringWithFormat:@"LocalDocuments-%@", self.name];
        NSString *suffix = registry.suffix;
        
        if (![NSString isEmptyString:suffix])
            name = [name stringByAppendingFormat:@"-%@", suffix];
        
        NSString *localDocumentsPath = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
        
        localDocumentsURL = [NSURL fileURLWithPath:localDocumentsPath isDirectory:YES];
        
        // Clean up cruft from previous runs
        __autoreleasing NSError *error;
        if (![[NSFileManager defaultManager] removeItemAtURL:localDocumentsURL error:&error]) {
            STAssertTrue([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT], nil);
        }
    }
    return localDocumentsURL;
}

- (OFXServerAccount *)addAccountToRegistry:(OFXTestServerAccountRegistry *)registry;
{
    return [self addAccountToRegistry:registry isFirst:YES];
}

- (OFXServerAccount *)addAccountToRegistry:(OFXTestServerAccountRegistry *)registry isFirst:(BOOL)isFirst;
{
    NSURL *localDocumentsURL = [self localDocumentsURLForAddingAccountToRegistry:registry];

    __autoreleasing NSError *error;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:localDocumentsURL withIntermediateDirectories:NO attributes:nil error:&error]) {
        [error log:@"Error creating account local documents directory at %@", localDocumentsURL];
        return nil;
    }

    OFXServerAccount *account;
    OBShouldNotError(account = [self addAccountToRegistry:registry withLocalDocumentsURL:localDocumentsURL isFirst:isFirst error:&error]);
    return account;
}

- (OFXServerAccount *)addAccountToRegistry:(OFXTestServerAccountRegistry *)registry withLocalDocumentsURL:(NSURL *)localDocumentsURL isFirst:(BOOL)isFirst error:(NSError **)outError;
{
    OFXServerAccountType *accountType = [OFXServerAccountType accountTypeWithIdentifier:OFXOmniSyncServerAccountTypeIdentifier];
    OBASSERT(accountType);
    
    NSURL *remoteBaseURL = self.accountRemoteBaseURL;
    
    OFXServerAccount *account = [[OFXServerAccount alloc] initWithType:accountType remoteBaseURL:remoteBaseURL localDocumentsURL:localDocumentsURL error:outError];
    if (!account)
        return nil;
    
    // Avoid race conditions in the testing tool. If we use the validator for both accounts, *sometimes* the validation for agentB's account will hit the credential challenge and sometimes it won't. If it does, it would end up removing the credentials for agentA's account, which might be in the middle of doing something.
    __block BOOL success = NO;
    __block NSError *error; // Strong variable to hold the error so that our autorelease pool below doesn't eat it
    
    if (isFirst) {
        OBASSERT([_agentA.accountRegistry.allAccounts count] == 0); // Could be totally nil or just have zero accounts if we are running at test with -automaticallyAddAccount returning NO.

        NSURLCredential *credential = [self accountCredentialWithPersistence:NSURLCredentialPersistenceNone];
        
        __block BOOL finished = NO;
        
        id <OFXServerAccountValidator> accountValidator = [account.type validatorWithAccount:account username:credential.user password:credential.password];
        accountValidator.shouldSkipConformanceTests = YES; // We bridge to the conformance tests in OFSDAVDynamicTestCase. Doing our suite of conformance tests before each OFX test is overkill.
        accountValidator.finished = ^(NSError *errorOrNil){
            if (errorOrNil) {
                NSLog(@"Error registering testing account: %@", [errorOrNil toPropertyList]);
                [NSException raise:NSGenericException format:@"Test can't continue"];
            } else {
                OBASSERT(account.credential);
                
                __autoreleasing NSError *addError;
                success = [registry addAccount:account error:&addError];
                if (!success)
                    error = addError;
            }
            finished = YES;
        };
        [accountValidator startValidation];
        
        while (!finished) {
            @autoreleasepool {
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            }
        }
    } else {
        OBASSERT(_agentA != nil);
            
        OFXServerAccount *accountA = [_agentA.accountRegistry.validCloudSyncAccounts lastObject];
        OBASSERT(accountA.credential);
            
        [account _storeCredential:accountA.credential forServiceIdentifier:accountA.credentialServiceIdentifier];

        OBASSERT(account.credential);
        
        __autoreleasing NSError *addError;
        success = [registry addAccount:account error:&addError];
        if (!success)
            error = addError;
    }
    
    OBASSERT(success == ([registry.validCloudSyncAccounts indexOfObjectIdenticalTo:account] != NSNotFound));

    if (success)
        return account;

    if (outError)
        *outError = error;
    return nil;
}

/*
 Each agent for a given test has a full local sync stack but shares a remote sync location. Agents from different tests are isolated from one another.
 */
static OFXAgent *_makeAgent(OFXTestCase *self, NSUInteger flag, NSString *agentName)
{
    OFXTestServerAccountRegistry *registry = [self makeAccountRegistry:agentName];
    BOOL isFirst = (flag == AgentA);
    
    if (self.automaticallyAddAccount) {
        OFXServerAccount *account = [self addAccountToRegistry:registry isFirst:isFirst];
        OB_UNUSED_VALUE(account);
        OBASSERT(account);
    }
    
    NSArray *extraPackagePathExtensions = [self extraPackagePathExtensionsForAgent:flag];
    
    // Make an agent, but don't start it by default. Use our 'accountRegistry' property so that test cases can specify a transient account registry.
    OFXAgent *agent = [[OFXAgent alloc] initWithAccountRegistry:registry remoteDirectoryName:self.remoteDirectoryName syncPathExtensions:self.syncPathExtensions extraPackagePathExtensions:extraPackagePathExtensions];
    
    agent.debugName = agentName;
    agent.automaticallyDownloadFileContents = self.automaticallyDownloadFileContents;
    agent.clientParameters = [self accountClientParametersForAgent:flag name:agentName];
    
    if (flag & self.automaticallyStartAgents) {
        [agent applicationLaunched];
        
        // Let the startup async operations finish, since they'll signal traces, and then reset the trace
        [self waitForAsyncOperations];
        
        OFXServerAccount *account = [registry.validCloudSyncAccounts lastObject];
        OBASSERT(account);
        [self waitUntil:^BOOL{
            return [agent.runningAccounts member:account] != nil;
        }];

        OFXTraceReset();
        
        OBASSERT(agent.started);
    }
    
    return agent;
}

@synthesize agentA = _agentA;
- (OFXAgent *)agentA;
{
    if (!_agentA)
        _agentA = _makeAgent(self, AgentA, @"A");
    return _agentA;
}

@synthesize agentB = _agentB;
- (OFXAgent *)agentB;
{
    [self agentA]; // Have to make this one first... make sure it is done.
    if (!_agentB)
        _agentB = _makeAgent(self, AgentB, @"B");
    return _agentB;
}

static BOOL _removeBaseDirectory(OFSFileManager *fileManager, NSURL *remoteBaseURL)
{
    __autoreleasing NSError *error;
    if ([fileManager deleteURL:remoteBaseURL error:&error])
        return YES;
    
    // Sometimes our first request will fail with a multistatus with an interior OFS_HTTP_FORBIDDEN. It isn't clear why...
    if ([error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_MULTI_STATUS] &&
        [error hasUnderlyingErrorDomain:OFSDAVHTTPErrorDomain code:OFS_HTTP_FORBIDDEN]) {
        error = nil;
        if ([fileManager deleteURL:remoteBaseURL error:&error])
            return YES;
    }
    
    if ([error hasUnderlyingErrorDomain:OFSErrorDomain code:OFSNoSuchFile])
        return YES;
    
    NSLog(@"Error deleting remote sync directory at %@: %@", remoteBaseURL, [error toPropertyList]);
    [NSException raise:NSGenericException format:@"Test can't continue"];
    return NO;
}

- (void)setUp
{
    [super setUp];
        
    OFXTraceReset();
    
    // TODO: Support for logging the seed and reading it from the environment
    _randomState = OFRandomStateCreate();
    
    OBASSERT(_helpers == nil);
    _helpers = [NSMutableArray new];
                       
    // Make sure subclass -tearDown calls super
    OBASSERT(_agentA == nil);
    OBASSERT(_agentB == nil);
        
    _remoteDirectoryName = [NSString stringWithFormat:@"TestSyncRoot-%@", self.name];

    // Clear our remote sync directory
    NSURL *accountRemoteBaseURL = self.accountRemoteBaseURL;
    

    __autoreleasing NSError *error = nil;
    _remoteBaseURL = [accountRemoteBaseURL URLByAppendingPathComponent:_remoteDirectoryName isDirectory:YES];
    OFSFileManager *fileManager = [[OFSFileManager alloc] initWithBaseURL:accountRemoteBaseURL delegate:self error:&error];
    
    //NSLog(@"Cleaning out base directory for test %@ at %@", [self name], [_remoteBaseURL absoluteString]);
    _removeBaseDirectory(fileManager, _remoteBaseURL);
    //NSLog(@"Creating base directory for test %@ at %@", [self name], [_remoteBaseURL absoluteString]);

    error = nil;
    if (![fileManager createDirectoryAtURL:_remoteBaseURL attributes:nil error:&error]) {
        NSLog(@"Error creating remote sync directory at %@: %@", _remoteBaseURL, [error toPropertyList]);
        [NSException raise:NSGenericException format:@"Test can't continue"];
    }

    // Make sure our "cleanup" didn't accidentally start up the agents.
    OBASSERT(_agentA == nil);
    OBASSERT(_agentB == nil);
}

- (void)tearDown
{
    [self stopAgents];

    for (id <OFXTestHelper> helper in _helpers)
        [helper tearDown];
    _helpers = nil;
    
    _agentA = nil;
    _agentB = nil;
    _remoteDirectoryName = nil;
    _remoteBaseURL = nil;
    
    OFRandomStateDestroy(_randomState);
    
    [super tearDown];
}

// Subclasses dealing with start/stop may want to control this more finely.
- (NSUInteger)automaticallyStartAgents;
{
    return AgentA|AgentB;
}

- (BOOL)automaticallyAddAccount;
{
    return YES;
}

- (BOOL)automaticallyDownloadFileContents;
{
    // If we are acting like the Mac agent, then download all files up front.
    return OFISEQUAL(self.syncPathExtensions, [OFXAgent wildcardSyncPathExtensions]);
}

- (OFXAccountClientParameters *)accountClientParametersForAgent:(NSUInteger)flag name:(NSString *)agentName;
{
    OFXAccountClientParameters *parameters = [OFXAgent defaultClientParameters];
    NSString *preferenceKey = [parameters.defaultClientIdentifierPreferenceKey stringByAppendingString:agentName];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![[defaults volatileDomainForName:NSRegistrationDomain] objectForKey:preferenceKey])
        [defaults registerDefaults:@{preferenceKey:agentName}];
    
    // No point appending our agentName here since OFSyncClient assumes this is constant (and we don't really need it to change in our tests).
    NSString *hostIdentifierDomain = parameters.hostIdentifierDomain;
    
    return [[OFXAccountClientParameters alloc] initWithDefaultClientIdentifierPreferenceKey:preferenceKey
                                                                       hostIdentifierDomain:hostIdentifierDomain
                                                                    currentFrameworkVersion:parameters.currentFrameworkVersion];
}

- (NSArray *)syncPathExtensions;
{
    return [OFXAgent wildcardSyncPathExtensions];
}

- (NSArray *)extraPackagePathExtensionsForAgent:(NSUInteger)flag;
{
    return nil;
}

- (OFXServerAccountRegistry *)accountRegistry;
{
    return [OFXServerAccountRegistry defaultAccountRegistry];
}

- (void)stopAgents;
{
    __block BOOL runningA = _agentA.started;
    __block BOOL runningB = _agentB.started;
    
    if (runningA) {
        [_agentA applicationWillTerminateWithCompletionHandler:^{
            runningA = NO;
        }];
    }
    if (runningB) {
        [_agentB applicationWillTerminateWithCompletionHandler:^{
            runningB = NO;
        }];
    }
    
    while (runningA || runningB) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    }
}

- (OFXServerAccount *)singleAccountInAgent:(OFXAgent *)agent;
{
    NSArray *accounts = agent.accountRegistry.validCloudSyncAccounts;
    OBASSERT([accounts count] == 1);
    return [accounts lastObject];
}

- (NSSet *)metadataItemsForAgent:(OFXAgent *)agent;
{
    OFXServerAccount *account = [agent.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(account);
    return [agent metadataItemsForAccount:account];
}

- (OFXFileMetadata *)metadataWithIdentifier:(NSString *)fileIdentifier inAgent:(OFXAgent *)agent;
{
    return [[self metadataItemsForAgent:agent] any:^BOOL(OFXFileMetadata *metadata){
        return [metadata.fileIdentifier isEqual:fileIdentifier];
    }];
}

- (void)waitSomeTimeUpToSeconds:(NSTimeInterval)interval;
{
    NSTimeInterval factor = OFRandomNextStateDouble(_randomState);
    OBASSERT(factor >= 0);
    OBASSERT(factor < 1);
    
    [self waitForSeconds:interval * factor];
}

- (void)waitForSeconds:(NSTimeInterval)interval;
{
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    
    while (start + interval > [NSDate timeIntervalSinceReferenceDate]) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceReferenceDate:(start + interval)]];
        }
    }
}

- (void)waitForAsyncOperations;
{
    __block BOOL waitingA = _agentA.started;
    __block BOOL waitingB = _agentB.started;

    // This flushes through the per-account agents and our completion block is run back on the calling queue (so anything they put on our queue has been flushed out by the time 'done' is set.

    if (waitingA) {
        [_agentA afterAsynchronousOperationsFinish:^{
            waitingA = NO;
        }];
    }
    if (waitingB) {
        [_agentB afterAsynchronousOperationsFinish:^{
            waitingB = NO;
        }];
    }
    
    while (waitingA || waitingB) {
        [self waitForSeconds:0.05];
    }
}

// Wait for up to 5 seconds before giving up.
- (void)waitUntil:(BOOL (^)(void))finished;
{
    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
    
    unsigned long waitSeconds = 20;
    const char *waitTime = getenv("OFXTestWaitTime");
    if (waitTime) {
        unsigned long seconds = strtoul(waitTime, NULL, 0);
        if (seconds > 0)
            waitSeconds = seconds;
    }
    
    while (YES) {
        if (finished())
            return;
        if ([NSDate timeIntervalSinceReferenceDate] - start > waitSeconds)
            [NSException raise:NSGenericException format:@"Test timed out"];
        [self waitForSeconds:0.05];
    }
}

- (NSSet *)waitForFileMetadataItems:(OFXAgent *)agent where:(BOOL (^)(NSSet *metadataItems))qualifier;
{
    __block NSSet *metadataItems;
    [self waitUntil:^BOOL{
        metadataItems = [self metadataItemsForAgent:agent];
        return !qualifier || qualifier(metadataItems);
    }];
    return metadataItems;
}

- (OFXFileMetadata *)waitForFileMetadata:(OFXAgent *)agent where:(BOOL (^)(OFXFileMetadata *metadata))qualifier;
{
    __block OFXFileMetadata *result;
    
    [self waitUntil:^BOOL{
        NSSet *metadataItems = [self metadataItemsForAgent:agent];
        
        for (OFXFileMetadata *candidate in metadataItems) {
            if (!qualifier || qualifier(candidate)) {
                result = candidate;
                break;
            }
        }
        
        return result != nil;
    }];
    
    return result;
}

- (void)waitForSync:(OFXAgent *)agent;
{
    __block BOOL finished = NO;
    [agent sync:^{
        finished = YES;
    }];
    
    [self waitUntil:^{
        return finished;
    }];
}

- (void)waitForChangeToMetadata:(OFXFileMetadata *)originalMetadata inAgent:(OFXAgent *)agent;
{
    [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
        return [metadata.fileIdentifier isEqual:originalMetadata.fileIdentifier] && ![metadata.editIdentifier isEqual:originalMetadata.editIdentifier];
    }];
}

// Currently assumes we are downloading all files
- (void)waitForAgentsToAgree;
{
    [self waitUntil:^BOOL{
        NSMutableDictionary *fileToEdit = [NSMutableDictionary new];
        
        for (OFXFileMetadata *metadata in [self metadataItemsForAgent:self.agentA]) {
            if (!metadata.uploaded || metadata.uploading || !metadata.downloaded || metadata.downloading)
                return NO;

            STAssertNil(fileToEdit[metadata.fileIdentifier], @"Should be no duplicate file identifiers");
            fileToEdit[metadata.fileIdentifier] = metadata.editIdentifier;
        }
        
        for (OFXFileMetadata *metadata in [self metadataItemsForAgent:self.agentB]) {
            if (!metadata.uploaded || metadata.uploading || !metadata.downloaded || metadata.downloading)
                return NO;

            if (![fileToEdit[metadata.fileIdentifier] isEqual:metadata.editIdentifier])
                return NO;
            [fileToEdit removeObjectForKey:metadata.fileIdentifier];
        }
        
        return [fileToEdit count] == 0;
    }];
    
    [self requireAgentsToHaveSameFiles];
}

- (void)requireAgentsToHaveSameFiles;
{
    OFXAgent *agentA = self.agentA;
    OFXAgent *agentB = self.agentB;
    
    NSURL *localDocumentsA = [self singleAccountInAgent:agentA].localDocumentsURL;
    NSURL *localDocumentsB = [self singleAccountInAgent:agentB].localDocumentsURL;

    OFDiffFiles(self, [localDocumentsA path], [localDocumentsB path], nil/*filter*/);
}

- (NSURL *)fixtureNamed:(NSString *)fixtureName;
{
    OBPRECONDITION(fixtureName);

    NSString *extension = [fixtureName pathExtension];
    if (!extension)
        extension = @"";
    
    NSString *resourceName = [fixtureName stringByDeletingPathExtension];
    
    NSURL *fixtureURL = [OMNI_BUNDLE URLForResource:resourceName withExtension:extension subdirectory:@"Fixtures"];
    OBASSERT(fixtureURL);
    
    return [fixtureURL URLByStandardizingPath];
}

static void _recursivelyClearDates(NSFileWrapper *wrapper)
{
    NSMutableDictionary *attributes = [[wrapper fileAttributes] mutableCopy];
    [attributes removeObjectForKey:NSFileCreationDate];
    [attributes removeObjectForKey:NSFileModificationDate];
    [wrapper setFileAttributes:attributes];
    
    if ([wrapper isDirectory]) {
        [[wrapper fileWrappers] enumerateKeysAndObjectsUsingBlock:^(id key, NSFileWrapper *child, BOOL *stop) {
            _recursivelyClearDates(child);
        }];
    }
}

+ (void)copyFileURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL filePresenter:(id <NSFilePresenter>)filePresenter;
{
    __autoreleasing NSError *error = nil;
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:filePresenter];
    BOOL success = [coordinator readItemAtURL:sourceURL withChanges:YES
                               writeItemAtURL:destinationURL withChanges:YES
                                        error:&error byAccessor:
    ^BOOL(NSURL *newReadingURL, NSURL *newWritingURL, NSError **outError) {
        if (![[NSFileManager defaultManager] createDirectoryAtURL:[newWritingURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:outError])
            return NO;
        
        // We want our edits to look like edits, so make sure the modificatation date changes.
        NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithURL:sourceURL options:0 error:outError];
        if (!wrapper)
            return NO;
         
        _recursivelyClearDates(wrapper);
         
        if (![wrapper writeToURL:destinationURL options:NSFileWrapperWritingAtomic originalContentsURL:destinationURL error:outError])
            return NO;
        OFXNoteContentChanged(self, destinationURL);
        return YES;
    }];
    
    if (!success) {
        [error log:@"Error copying %@ to %@", sourceURL, destinationURL];
        [NSException raise:NSGenericException format:@"Test can't continue"];
    }
}

- (void)copyFileURL:(NSURL *)sourceURL toPath:(NSString *)destinationPath ofAccount:(OFXServerAccount *)account;
{
    OBPRECONDITION(sourceURL);
    OBPRECONDITION(destinationPath);
    OBPRECONDITION(account);
    
    NSURL *destinationURL = [account.localDocumentsURL URLByAppendingPathComponent:destinationPath];
    
    [[self class] copyFileURL:sourceURL toURL:destinationURL filePresenter:nil];
}

- (void)copyFixtureNamed:(NSString *)fixtureName toPath:(NSString *)destinationPath ofAccount:(OFXServerAccount *)account;
{
    OBPRECONDITION(fixtureName);    
    [self copyFileURL:[self fixtureNamed:fixtureName] toPath:destinationPath ofAccount:account];
}

- (void)copyFixtureNamed:(NSString *)fixtureName ofAccount:(OFXServerAccount *)account;
{
    [self copyFixtureNamed:fixtureName toPath:fixtureName ofAccount:account];
}

- (NSString *)copyRandomTextFileOfLength:(NSUInteger)textLength toPath:(NSString *)destinationPath ofAccount:(OFXServerAccount *)account;
{
    __autoreleasing NSError *error;
    NSURL *randomTextURL = [account.localDocumentsURL URLByAppendingPathComponent:destinationPath];
    OBShouldNotError(randomTextURL = [[NSFileManager defaultManager] temporaryURLForWritingToURL:randomTextURL allowOriginalDirectory:NO error:&error]);
    
    NSString *randomText = [OFRandomCreateDataOfLength(textLength) unadornedLowercaseHexString];
    OBShouldNotError([[randomText dataUsingEncoding:NSUTF8StringEncoding] writeToURL:randomTextURL options:0 error:&error]);
    
    [self copyFileURL:randomTextURL toPath:destinationPath ofAccount:account];
    
    OBShouldNotError([[NSFileManager defaultManager] removeItemAtURL:randomTextURL error:&error]);
    
    return randomText;
}

- (NSString *)copyLargeRandomTextFileToPath:(NSString *)destinationPath ofAccount:(OFXServerAccount *)account;
{
    return [self copyRandomTextFileOfLength:16*1024*1024 toPath:destinationPath ofAccount:account];
}

- (OFXFileMetadata *)copyFixtureNamed:(NSString *)fixtureName waitForDownload:(BOOL)waitForDownload;
{
    // Make a document and download to two agents
    OFXAgent *agent = self.agentA;
    OFXServerAccount *account = [agent.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(account);
    
    [self copyFixtureNamed:fixtureName ofAccount:account];
    
    __block OFXFileMetadata *resultMetadata;
    [self waitForFileMetadata:self.agentB where:^BOOL(OFXFileMetadata *metadata){
        if ([[metadata.fileURL lastPathComponent] isEqual:fixtureName] && (!waitForDownload || metadata.isDownloaded)) {
            resultMetadata = metadata;
            return YES;
        }
        return NO;
    }];
    
    return resultMetadata;
}

- (OFXFileMetadata *)copyFixtureNamed:(NSString *)fixtureName;
{
    return [self copyFixtureNamed:fixtureName waitForDownload:YES];
}

- (void)writeRandomFlatFile:(NSString *)name withSize:(NSUInteger)fileSize;
{
    OFXAgent *agentA = self.agentA;
    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    NSURL *fileURL = [accountA.localDocumentsURL URLByAppendingPathComponent:name isDirectory:NO];
    {
        __autoreleasing NSError *error;
        NSURL *temporaryFileURL;
        OBShouldNotError(temporaryFileURL = [[NSFileManager defaultManager] temporaryURLForWritingToURL:fileURL allowOriginalDirectory:NO error:&error]);
        
        OBShouldNotError([OFRandomCreateDataOfLength(fileSize) writeToURL:temporaryFileURL options:0 error:&error]);
        OBShouldNotError([[NSFileManager defaultManager] moveItemAtURL:temporaryFileURL toURL:fileURL error:&error]);
    }
}

- (OFXFileMetadata *)makeRandomFlatFile:(NSString *)name withSize:(NSUInteger)fileSize;
{
    [self writeRandomFlatFile:name withSize:fileSize];
    
    // Wait for this to upload -- this assumes we are doing the upload for the first time.
    NSString *pathSuffix = [[@"/" stringByAppendingString:name] stringByRemovingSuffix:@"/"];
    OFXFileMetadata *uploadedMetadata = [self waitForFileMetadata:self.agentA where:^BOOL(OFXFileMetadata *metadata) {
        NSString *filePath = [[metadata.fileURL path] stringByRemovingSuffix:@"/"];
        return [filePath hasSuffix:pathSuffix] && metadata.uploaded;
    }];
    
    return uploadedMetadata;
}

- (OFXFileMetadata *)makeRandomFlatFile:(NSString *)name;
{
    return [self makeRandomFlatFile:name withSize:64*1024*1024];
}

- (OFXFileMetadata *)makeRandomPackageNamed:(NSString *)name memberCount:(NSUInteger)memberCount memberSize:(NSUInteger)memberSize;
{
    OFXAgent *agentA = self.agentA;
    
    // If there is a previous version of this file, ignore it below.
    __block OFXFileMetadata *previousMetadata;
    [self waitForFileMetadataItems:agentA where:^BOOL(NSSet *metadataItems) {
        for (OFXFileMetadata *metadata in metadataItems) {
            if ([[metadata.fileURL lastPathComponent] isEqualToString:name])
                previousMetadata = metadata;
        }
        return YES;
    }];

    OFXServerAccount *accountA = [agentA.accountRegistry.validCloudSyncAccounts lastObject];
    NSURL *packageURL = [accountA.localDocumentsURL URLByAppendingPathComponent:name isDirectory:YES];
    {
        __autoreleasing NSError *error;
        NSURL *temporaryPackageURL;
        OBShouldNotError(temporaryPackageURL = [[NSFileManager defaultManager] temporaryURLForWritingToURL:packageURL allowOriginalDirectory:NO error:&error]);
        
        OBShouldNotError([[NSFileManager defaultManager] createDirectoryAtURL:temporaryPackageURL withIntermediateDirectories:NO attributes:nil error:&error]);
        for (NSUInteger memberIndex = 0; memberIndex < memberCount; memberIndex++) {
            NSURL *fileURL = [temporaryPackageURL URLByAppendingPathComponent:[NSString stringWithFormat:@"file-%ld", memberIndex]];
            OBShouldNotError([OFRandomCreateDataOfLength(memberSize) writeToURL:fileURL options:0 error:&error]);
        }
        
        [[self class] copyFileURL:temporaryPackageURL toURL:packageURL filePresenter:nil];
        
        OBShouldNotError([[NSFileManager defaultManager] removeItemAtURL:temporaryPackageURL error:&error]);
    }
    
    // Wait for this to upload.
    OFXFileMetadata *uploadedMetadata = [self waitForFileMetadata:agentA where:^BOOL(OFXFileMetadata *metadata) {
        if ([previousMetadata.editIdentifier isEqualToString:metadata.editIdentifier])
             return NO;
        if (![[[metadata fileURL] lastPathComponent] isEqualToString:name])
            return NO;
        return metadata.uploaded;
    }];
    
    return uploadedMetadata;
}

- (OFXFileMetadata *)makeRandomLargePackage:(NSString *)name;
{
    return [self makeRandomPackageNamed:name memberCount:16 memberSize:4*1024*1024];
}

- (OFXFileMetadata *)uploadFixture:(NSString *)fixtureName;
{
    return [self uploadFixture:fixtureName as:fixtureName replacingMetadata:nil];
}

- (OFXFileMetadata *)uploadFixture:(NSString *)fixtureName as:(NSString *)destinationPath replacingMetadata:(OFXFileMetadata *)previousMetadata;
{
    // Publish the file on agent A and wait until it is pushed up
    
    OFXAgent *agent = self.agentA;
    OFXServerAccount *account = [agent.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(account);
    
    [self copyFixtureNamed:fixtureName toPath:destinationPath ofAccount:account];
    return [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
        // Wait for *this* file to be uploaded
        if (![[[metadata.fileURL absoluteString] stringByRemovingSuffix:@"/"] hasSuffix:[destinationPath stringByRemovingSuffix:@"/"]])
            return NO;
        
        // Also wait for this *version* of the file to be uploaded if we are replacing an old version.
        if (OFISEQUAL(metadata.editIdentifier, previousMetadata.editIdentifier))
            return NO;
        
        return metadata.uploaded;
    }];
}

- (OFXFileMetadata *)downloadWithMetadata:(OFXFileMetadata *)metadata agent:(OFXAgent *)agent;
{
    STAssertFalse(metadata.downloaded, nil); // Otherwise our wait below might spuriously succeed
    
    // Request the download and make sure the request has been processed
    __block BOOL downloadRequested = NO;
    [agent requestDownloadOfItemAtURL:metadata.fileURL completionHandler:^(NSError *errorOrNil) {
        STAssertNil(errorOrNil, nil);
        downloadRequested = YES;
    }];
    
    [self waitUntil:^BOOL{
        return downloadRequested;
    }];
    
    // Wait for the request to finish
    OBASSERT([agent.accountRegistry.validCloudSyncAccounts count] == 1);
    OFXServerAccount *account = [agent.accountRegistry.validCloudSyncAccounts lastObject];
    __block BOOL downloadFinished = NO;
    [self waitUntil:^BOOL{
        [agent countPendingTransfersForAccount:account completionHandler:^(NSError *errorOrNil, NSUInteger count) {
            STAssertNil(errorOrNil, nil);
            downloadFinished = (count == 0);
        }];
        return downloadFinished;
    }];
    
    return [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *downloadedMetadata) {
        return downloadedMetadata.downloaded;
    }];
}

- (void)downloadFileWithIdentifier:(NSString *)fileIdentifier untilPercentage:(double)untilPercentage agent:(OFXAgent *)agent;
{
    [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
        if (OFISEQUAL(metadata.fileIdentifier, fileIdentifier)) {
            [agent requestDownloadOfItemAtURL:metadata.fileURL completionHandler:nil];
            return YES;
        }
        return NO;
    }];
    [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata) {
        if (OFNOTEQUAL(fileIdentifier, metadata.fileIdentifier))
            return NO;
        
        return metadata.downloading && metadata.percentDownloaded >= untilPercentage;
    }];
}

- (void)moveURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL;
{
    __autoreleasing NSError *error = nil;
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    OBShouldNotError([coordinator moveItemAtURL:sourceURL toURL:destinationURL createIntermediateDirectories:NO error:&error]);
    OFXNoteContentMoved(self, sourceURL, destinationURL);
}

- (void)movePath:(NSString *)sourcePath toPath:(NSString *)destinationPath ofAccount:(OFXServerAccount *)account;
{
    NSURL *sourceURL = [account.localDocumentsURL URLByAppendingPathComponent:sourcePath];
    NSURL *destinationURL = [account.localDocumentsURL URLByAppendingPathComponent:destinationPath];
    [self moveURL:sourceURL toURL:destinationURL];
}

- (void)deletePath:(NSString *)filePath ofAccount:(OFXServerAccount *)account;
{
    NSURL *fileURL = [account.localDocumentsURL URLByAppendingPathComponent:filePath];
    
    __autoreleasing NSError *error = nil;
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    BOOL success = [coordinator removeItemAtURL:fileURL error:&error byAccessor:
     ^BOOL(NSURL *newURL, NSError **outError) {
         if (![[NSFileManager defaultManager] removeItemAtURL:newURL error:outError]) {
             STFail(@"Removal should not fail");
             return NO;
         }
         OFXNoteContentDeleted(self, newURL);
         return YES;
     }];
    
    if (!success)
        [error log:@"Error removing file %@", filePath];
}

- (void)deletePath:(NSString *)filePath inAgent:(OFXAgent *)agent;
{
    [self deletePath:filePath ofAccount:[self singleAccountInAgent:agent]];
}

- (NSError *)lastErrorInAgent:(OFXAgent *)agent;
{
    OFXServerAccount *account = [self singleAccountInAgent:agent];
    return account.lastError;
}

- (void)addFilePresenterWritingURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL;
{
    OFXTestSaveFilePresenter *presenter = [[OFXTestSaveFilePresenter alloc] initWithSaveToURL:destinationURL fromURL:sourceURL];
    [_helpers addObject:presenter];
}

- (void)addFilePresenterWritingFixture:(NSString *)fixtureName toURL:(NSURL *)fileURL;
{
    [self addFilePresenterWritingURL:[self fixtureNamed:fixtureName] toURL:fileURL];
}

- (void)addFilePresenterWritingFixture:(NSString *)fixtureName toPath:(NSString *)path inAgent:(OFXAgent *)agent;
{
    OFXServerAccount *account = [self singleAccountInAgent:agent];
    
    NSURL *fixtureURL = [self fixtureNamed:fixtureName];
    NSNumber *isDirectory;
    NSError *error;
    OBShouldNotError([fixtureURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error]);
    
    NSURL *fileURL = [account.localDocumentsURL URLByAppendingPathComponent:path isDirectory:[isDirectory boolValue]];

    [self addFilePresenterWritingFixture:fixtureName toURL:fileURL];
}

#pragma mark - OFSFileManagerDelegate

// Just needed for cleaning up old data -- otherwise OFXAgent and friends will handle this.
- (NSURLCredential *)fileManager:(OFSFileManager *)manager findCredentialsForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    if ([challenge previousFailureCount] <= 2) {
        // Use the account credential if we have an account added. We might be clearing out the remote directory before an account has been added to this test's account registry, though
        NSURLCredential *credential;
        if (_agentA) {
            OFXServerAccount *account = [self.agentA.accountRegistry.validCloudSyncAccounts lastObject];
            credential = account.credential;
        } else
            credential = [self accountCredentialWithPersistence:NSURLCredentialPersistenceNone]; // Fallback.
        
        OBASSERT(credential);
        return credential;
    }
    return nil;
}

- (void)fileManager:(OFSFileManager *)manager validateCertificateForChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    // Trust all certificates for these tests.
    OFAddTrustForChallenge(challenge, OFCertificateTrustDurationSession);
}

@end

@implementation NSFileCoordinator (OFXTestCaseExtensions)

- (BOOL)writeData:(NSData *)data toURL:(NSURL *)fileURL options:(NSDataWritingOptions)options error:(NSError **)outError;
{
    OBPRECONDITION(data);
    OBPRECONDITION(fileURL);
    
    __block BOOL success = NO;
    [self coordinateWritingItemAtURL:fileURL options:NSFileCoordinatorWritingForMerging error:outError byAccessor:^(NSURL *newURL) {
        success = [data writeToURL:fileURL options:options error:outError];
    }];
    
    return success;
}

@end
