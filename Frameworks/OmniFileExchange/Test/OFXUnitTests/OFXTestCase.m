// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXTestCase.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniFileExchange/OFXAccountClientParameters.h>
#import <OmniFileExchange/OFXServerAccountValidator.h>
#import <OmniFoundation/NSFileCoordinator-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/OFCredentials.h>
#import <OmniFoundation/OFRandom.h>
#import <OmniFoundation/OFXMLIdentifier.h>

#import "OFXContentIdentifier.h"
#import "OFXServerAccount-Internal.h"
#import "OFXTestSaveFilePresenter.h"
#import "OFXTrace.h"

#import "OFNetStateMock.h"

RCS_ID("$Id$")

@implementation OFXTestServerAccountRegistry
@end

@interface OFXTestCase ()
@property(nonatomic,readonly) OFXAgent *existingAgentA;
@property(nonatomic,readonly) NSString *remoteDirectoryName;
@property(nonatomic,readonly) NSURL *remoteBaseURL;
@end

@implementation OFXTestCase
{
    OFRandomState *_randomState;
    NSMutableArray *_helpers;
    NSMutableDictionary *_agentByName;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    OBFinishPortingLater("<bug:///147836> (iOS-OmniOutliner Engineering: OFXTestCase.m:49 - Make this configurable so that these tests can be run against the real class too)");
    [OFNetStateNotifierMock install];
    
    OFXTraceEnabled = YES;

    NSArray *fixtureURLs = [OMNI_BUNDLE URLsForResourcesWithExtension:nil subdirectory:@"Fixtures"];
    for (NSURL *fixtureURL in fixtureURLs) {
        OFXRegisterDisplayNameForContentAtURL(fixtureURL, [fixtureURL lastPathComponent]);
    }
}

- (NSString *)baseTemporaryDirectory;
{
    NSString *result = [NSTemporaryDirectory() stringByAppendingPathComponent:@"OFXTests"];
    const char *base = getenv("OFXTestBaseDirectory");
    if (base) {
        NSString *directoryName = [[NSString alloc] initWithBytes:base length:strlen(base) encoding:NSUTF8StringEncoding];
        return [result stringByAppendingPathComponent:directoryName];
    }
    return result;
}

- (OFXTestServerAccountRegistry *)makeAccountRegistry:(NSString *)suffix;
{
    NSString *name = [NSString stringWithFormat:@"Accounts-%@", self.name];
    
    if (![NSString isEmptyString:suffix])
        name = [name stringByAppendingFormat:@"-%@", suffix];
    
    NSString *accountsDirectoryPath = [[self baseTemporaryDirectory] stringByAppendingPathComponent:name];
    NSURL *accountsDirectoryURL = [NSURL fileURLWithPath:accountsDirectoryPath];
    
    // Clean up cruft from previous runs
    __autoreleasing NSError *error;
    if (![[NSFileManager defaultManager] removeItemAtURL:accountsDirectoryURL error:&error]) {
        XCTAssertTrue([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]);
    }
    
    OFXTestServerAccountRegistry *registry;
    OBShouldNotError(registry = [[OFXTestServerAccountRegistry alloc] initWithAccountsDirectoryURL:accountsDirectoryURL error:&error]);
    
    registry.suffix = suffix;
    
    XCTAssertNotNil(registry);
    XCTAssertEqual([registry.allAccounts count], (NSUInteger)0);
    
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
        
        NSString *localDocumentsPath = [[self baseTemporaryDirectory] stringByAppendingPathComponent:name];
        
        localDocumentsURL = [NSURL fileURLWithPath:localDocumentsPath isDirectory:YES];
        
        // Clean up cruft from previous runs
        __autoreleasing NSError *error;
        if (![[NSFileManager defaultManager] removeItemAtURL:localDocumentsURL error:&error]) {
            XCTAssertTrue([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT]);
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
    if (![[NSFileManager defaultManager] createDirectoryAtURL:localDocumentsURL withIntermediateDirectories:YES attributes:nil error:&error]) {
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
    
    OFXServerAccount *account = [[OFXServerAccount alloc] initWithType:accountType usageMode:OFXServerAccountUsageModeCloudSync remoteBaseURL:remoteBaseURL localDocumentsURL:localDocumentsURL error:outError];
    if (!account)
        return nil;
    
    // Avoid race conditions in the testing tool. If we use the validator for both accounts, *sometimes* the validation for agentB's account will hit the credential challenge and sometimes it won't. If it does, it would end up removing the credentials for agentA's account, which might be in the middle of doing something.
    __block BOOL success = NO;
    __block NSError *error; // Strong variable to hold the error so that our autorelease pool below doesn't eat it
    
    if (isFirst) {
        OBASSERT([self.existingAgentA.accountRegistry.allAccounts count] == 0); // Could be totally nil or just have zero accounts if we are running at test with -automaticallyAddAccount returning NO.

        NSURLCredential *credential = [self accountCredentialWithPersistence:NSURLCredentialPersistenceNone];
        
        __block BOOL finished = NO;
        
        id <OFXServerAccountValidator> accountValidator = [account.type validatorWithAccount:account username:credential.user password:credential.password];
        accountValidator.shouldSkipConformanceTests = YES; // We bridge to the conformance tests in ODAVDynamicTestCase. Doing our suite of conformance tests before each OFX test is overkill.
        accountValidator.finished = ^(NSError *errorOrNil){
            if (errorOrNil) {
                NSLog(@"Error registering testing account: %@", [errorOrNil toPropertyList]);
                [NSException raise:NSGenericException format:@"Test can't continue"];
            } else {
                OBASSERT(account.credentialServiceIdentifier);
                
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
        OBASSERT(self.existingAgentA != nil);
            
        OFXServerAccount *accountA = [self.existingAgentA.accountRegistry.validCloudSyncAccounts lastObject];
        
        NSURLCredential *credential = OFReadCredentialsForServiceIdentifier(accountA.credentialServiceIdentifier, NULL);
        XCTAssertNotNil(credential);
        OBASSERT(credential);
            
        [account _storeCredential:credential forServiceIdentifier:accountA.credentialServiceIdentifier];

        OBASSERT(account.credentialServiceIdentifier);
        
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
NSString * const OFXTestFirstAgentName = @"A";

static OFXAgent *_makeAgent(OFXTestCase *self, NSString *agentName)
{
    OFXTestServerAccountRegistry *registry = [self makeAccountRegistry:agentName];
    BOOL isFirst = [agentName isEqual:OFXTestFirstAgentName];
    
    if (self.automaticallyAddAccount) {
        OFXServerAccount *account = [self addAccountToRegistry:registry isFirst:isFirst];
        OB_UNUSED_VALUE(account);
        OBASSERT(account);
    }
    
    NSArray *extraPackagePathExtensions = [self extraPackagePathExtensionsForAgentName:agentName];
    
    // Make an agent, but don't start it by default. Use our 'accountRegistry' property so that test cases can specify a transient account registry.
    OFXAgent *agent = [[OFXAgent alloc] initWithAccountRegistry:registry remoteDirectoryName:self.remoteDirectoryName syncPathExtensions:self.syncPathExtensions extraPackagePathExtensions:extraPackagePathExtensions];
    
    agent.debugName = agentName;
    agent.automaticallyDownloadFileContents = self.automaticallyDownloadFileContents;
    agent.clientParameters = [self accountClientParametersForAgentName:agentName];
    
    if ([self.automaticallyStartedAgentNames member:agentName]) {
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

- (OFXAgent *)existingAgentA;
{
    return _agentByName[OFXTestFirstAgentName];
}

- (OFXAgent *)agentWithName:(NSString *)name;
{
    if (![name isEqual:OFXTestFirstAgentName]) {
        (void)[self agentA]; // Have to make this one first... make sure it is done.
    }
    
    OFXAgent *agent = _agentByName[name];
    if (!agent) {
        agent = _makeAgent(self, name);
        _agentByName[name] = agent;
    }
    return agent;
}

- (OFXAgent *)agentA;
{
    return [self agentWithName:OFXTestFirstAgentName];
}

- (OFXAgent *)agentB;
{
    return [self agentWithName:@"B"];
}

- (OFXAgent *)agentC;
{
    return [self agentWithName:@"C"];
}

static BOOL _removeBaseDirectory(OFXTestCase *self, ODAVConnection *connection, NSURL *remoteBaseURL, BOOL allowRetry)
{
    NSError *error;
    
    if ([connection synchronousDeleteURL:remoteBaseURL withETag:nil error:&error])
        return YES;
    
    if (allowRetry) {
        // Sometimes our first request will fail with a multistatus with an interior ODAV_HTTP_FORBIDDEN. It isn't clear why...
        if ([error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_MULTI_STATUS] &&
            [error hasUnderlyingErrorDomain:ODAVHTTPErrorDomain code:ODAV_HTTP_FORBIDDEN])
            return _removeBaseDirectory(self, connection, remoteBaseURL, NO/*allowRetry*/);
    }

    if ([error hasUnderlyingErrorDomain:ODAVErrorDomain code:ODAVNoSuchFile])
        return YES;
    
    NSLog(@"Error deleting remote sync directory at %@: %@", remoteBaseURL, [error toPropertyList]);
    [NSException raise:NSGenericException format:@"Test can't continue"];
    return NO;
}

- (void) recordFailureWithDescription:(NSString *) description inFile:(NSString *) filename atLine:(NSUInteger) lineNumber expected:(BOOL) expected;
{
    [super recordFailureWithDescription:description inFile:filename atLine:lineNumber expected:expected];
    [NSException raise:NSGenericException reason:@"Halting test due to error"];
}

- (void)setUp
{
    [super setUp];
        
    OFXTraceReset();
    
    OBASSERT([_agentByName count] == 0, "Make sure subclass -tearDown calls super");
    _agentByName = [[NSMutableDictionary alloc] init];
    
    // TODO: Support for logging the seed and reading it from the environment
    _randomState = OFRandomStateCreate();
    
    OBASSERT(_helpers == nil);
    _helpers = [NSMutableArray new];
    
    _remoteDirectoryName = [NSString stringWithFormat:@"TestSyncRoot-%@", self.name];

    // Clear our remote sync directory
    NSURL *accountRemoteBaseURL = self.accountRemoteBaseURL;
    

    _remoteBaseURL = [accountRemoteBaseURL URLByAppendingPathComponent:_remoteDirectoryName isDirectory:YES];
    
    ODAVConnection *connection = [[ODAVConnection alloc] initWithSessionConfiguration:[ODAVConnectionConfiguration new] baseURL:_remoteBaseURL];
    connection.validateCertificateForChallenge = ^NSURLCredential *(NSURLAuthenticationChallenge *challenge){
        // Trust all certificates for these tests.
        OFAddTrustForChallenge(challenge, OFCertificateTrustDurationSession);
        return nil;
    };
    connection.findCredentialsForChallenge = ^NSOperation <OFCredentialChallengeDisposition> *(NSURLAuthenticationChallenge *challenge){
        if ([challenge previousFailureCount] <= 2) {
            // Use the account credential if we have an account added. We might be clearing out the remote directory before an account has been added to this test's account registry, though
            NSURLCredential *credential;
            if (self.existingAgentA) {
                OFXServerAccount *account = [self.existingAgentA.accountRegistry.validCloudSyncAccounts lastObject];
                
                credential = OFReadCredentialsForServiceIdentifier(account.credentialServiceIdentifier, NULL);
            } else
                credential = [self accountCredentialWithPersistence:NSURLCredentialPersistenceNone]; // Fallback.
            
            OBASSERT(credential);
            return OFImmediateCredentialResponse(NSURLSessionAuthChallengeUseCredential, credential);
        }
        return nil;
    };
    
    //NSLog(@"Cleaning out base directory for test %@ at %@", [self name], [_remoteBaseURL absoluteString]);
    _removeBaseDirectory(self, connection, _remoteBaseURL, YES/*allowRetry*/);
    //NSLog(@"Creating base directory for test %@ at %@", [self name], [_remoteBaseURL absoluteString]);

    NSError *error;
    NSURL *createdURL = [connection synchronousMakeCollectionAtURL:_remoteBaseURL error:&error].URL;
    if (!createdURL) {
        [error log:@"Error creating remote sync directory at %@", _remoteBaseURL];
        [NSException raise:NSGenericException format:@"Test can't continue"];
    }
    _remoteBaseURL = createdURL;
    
    // Make sure our "cleanup" didn't accidentally start up the agents.
    OBASSERT([_agentByName count] == 0);
}

- (void)tearDown
{
    [self stopAgents];

    for (id <OFXTestHelper> helper in _helpers)
        [helper tearDown];
    _helpers = nil;
    
    _agentByName = nil;

    _remoteDirectoryName = nil;
    _remoteBaseURL = nil;
    
    OFRandomStateDestroy(_randomState);
    
    [super tearDown];
}

// Subclasses dealing with start/stop may want to control this more finely.
- (NSSet *)automaticallyStartedAgentNames;
{
    return [NSSet setWithObjects:OFXTestFirstAgentName, @"B", nil];
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

- (OFXAccountClientParameters *)accountClientParametersForAgentName:(NSString *)agentName;
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

- (NSArray *)extraPackagePathExtensionsForAgentName:(NSString *)agentName;
{
    return nil;
}

- (OFXServerAccountRegistry *)accountRegistry;
{
    return [OFXServerAccountRegistry defaultAccountRegistry];
}

- (void)stopAgents;
{
    OBASSERT([NSThread isMainThread], "Make sure we don't need locking for this counter");
    __block NSUInteger startedAgentCount = 0;

    [_agentByName enumerateKeysAndObjectsUsingBlock:^(NSString *name, OFXAgent *agent, BOOL *stop) {
        if (agent.started) {
            startedAgentCount++;
            [agent applicationWillTerminateWithCompletionHandler:^{
                OBASSERT([NSThread isMainThread], "Make sure we don't need locking for this counter");
                startedAgentCount--;
            }];
        }
    }];
    
    [self waitUntil:^BOOL{
        return (startedAgentCount == 0);
    }];
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
    OBASSERT([NSThread isMainThread], "Make sure we don't need locking for this counter");
    __block NSUInteger startedAgents = 0;
    
    [_agentByName enumerateKeysAndObjectsUsingBlock:^(NSString *name, OFXAgent *agent, BOOL *stop) {
        if (agent.started) {
            startedAgents++;
        
            // This flushes through the per-account agents and our completion block is run back on the calling queue (so anything they put on our queue has been flushed out by the time 'done' is set.
            [agent afterAsynchronousOperationsFinish:^{
                OBASSERT([NSThread isMainThread], "Make sure we don't need locking for this counter");
                startedAgents--;
            }];
        }
    }];
    
    while (startedAgents > 0) {
        [self waitForSeconds:0.05];
    }
}

// Wait for up to 5 seconds before giving up.
- (void)waitUntil:(BOOL (^)(void))finished;
{
    unsigned long waitSeconds = 20;
    const char *waitTime = getenv("OFXTestWaitTime");
    if (waitTime) {
        unsigned long seconds = strtoul(waitTime, NULL, 0);
        if (seconds > 0)
            waitSeconds = seconds;
    }
    
    if (!OFRunLoopRunUntil(waitSeconds, OFRunLoopRunTypePolling, finished)) {
        [self timedOut];
    }
}

static void _logAgentState(OFXAgent *agent)
{
    if (!agent)
        return;
    
    for (OFXServerAccount *account in agent.accountRegistry.validCloudSyncAccounts) {
    
        NSMutableArray *metadata = [NSMutableArray array];
        [metadata addObjectsFromSet:[agent metadataItemsForAccount:account]];
        [metadata sortUsingComparator:^NSComparisonResult(OFXFileMetadata *item1, OFXFileMetadata *item2) {
            NSComparisonResult rc = [[item1.intendedFileURL path] compare:[item2.intendedFileURL path]];
            if (rc == NSOrderedSame) {
                rc = [item1.creationDate compare:item2.creationDate];
            }
            return rc;
        }];
        
        NSString *metadataString = [[metadata arrayByPerformingBlock:^(OFXFileMetadata *metadataItem){
            return [[metadataItem debugDictionary] description];
        }] componentsJoinedByString:@"\n"];
        NSLog(@"Agent state for %@ / %@:\n%@", [agent shortDescription], [account shortDescription], metadataString);
    }
}

- (void)timedOut;
{
    NSLog(@"Test %@ timed out", self);
    
    [_agentByName enumerateKeysAndObjectsUsingBlock:^(NSString *name, OFXAgent *agent, BOOL *stop) {
        _logAgentState(agent);
    }];
    
    [NSException raise:NSGenericException format:@"Test timed out"];
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

- (BOOL)agentEditsAgree:(NSArray *)agents withFileCount:(NSUInteger)fileCount;
{
    return [self agentEditsAgree:agents waitingForTransfers:YES withFileCount:fileCount];
}

- (BOOL)agentEditsAgree:(NSArray *)agents waitingForTransfers:(BOOL)waitingForTransfers withFileCount:(NSUInteger)fileCount;
{
    if ([agents count] < 2) {
        OBASSERT_NOT_REACHED("Not terribly useful");
        return YES;
    }
    
    OFXAgent *firstAgent = agents[0];
    NSArray *otherAgents = [agents subarrayWithRange:NSMakeRange(1, [agents count] - 1)];
    
    NSDictionary *firstAgentFileIdentifierToEditIdentifier = [NSMutableDictionary new];
    {
        NSMutableDictionary *fileToEdit = [NSMutableDictionary dictionary];
        
        NSSet *metadataItems = [self metadataItemsForAgent:firstAgent];
        if (fileCount != NSNotFound && fileCount != [metadataItems count])
            return NO;
        
        for (OFXFileMetadata *metadata in metadataItems) {
            if (!metadata.uploaded || metadata.uploading || !metadata.downloaded || metadata.downloading)
                return NO;
            
            XCTAssertNil(fileToEdit[metadata.fileIdentifier], @"Should be no duplicate file identifiers");
            fileToEdit[metadata.fileIdentifier] = metadata.editIdentifier;
        }
        
        firstAgentFileIdentifierToEditIdentifier = [fileToEdit copy];
    }
    
    for (OFXAgent *agent in otherAgents) {
        NSMutableDictionary *fileToEdit = [firstAgentFileIdentifierToEditIdentifier mutableCopy];
        
        NSSet *metadataItems = [self metadataItemsForAgent:agent];
        if ([metadataItems count] != [firstAgentFileIdentifierToEditIdentifier count])
            return NO;
        
        for (OFXFileMetadata *metadata in metadataItems) {
            if (!metadata.uploaded || metadata.uploading || !metadata.downloaded || metadata.downloading)
                return NO;
            
            if (![fileToEdit[metadata.fileIdentifier] isEqual:metadata.editIdentifier])
                return NO;
            [fileToEdit removeObjectForKey:metadata.fileIdentifier];
        }
        
        return [fileToEdit count] == 0;
    }
    
    return YES;
}

- (void)waitForAgentsEditsToAgree;
{
    [self waitForAgentsEditsToAgree:@[self.agentA, self.agentB]];
}

- (void)waitForAgentsEditsToAgree:(NSArray *)agents;
{
    [self waitForAgentsEditsToAgree:agents withFileCount:NSNotFound];
}
- (void)waitForAgentsEditsToAgree:(NSArray *)agents withFileCount:(NSUInteger)fileCount;
{
    [self waitUntil:^{
        return [self agentEditsAgree:agents withFileCount:fileCount];
    }];
}

- (void)requireAgentsToHaveSameFilesByName;
{
    [self requireAgentsToHaveSameFilesByName:@[self.agentA, self.agentB]];
}

// This requires exact name as well as contents
- (void)requireAgentsToHaveSameFilesByName:(NSArray *)agents;
{
    if ([agents count] < 2) {
        OBASSERT_NOT_REACHED("Not terribly useful");
        return;
    }
    
    OFXAgent *firstAgent = agents[0];
    NSArray *otherAgents = [agents subarrayWithRange:NSMakeRange(1, [agents count] - 1)];

    NSURL *localDocumentsForFirstAgent = [self singleAccountInAgent:firstAgent].localDocumentsURL;

    for (OFXAgent *agent in otherAgents) {
        NSURL *localDocumentsForOtherAgent = [self singleAccountInAgent:agent].localDocumentsURL;
        OFDiffFiles(self, [localDocumentsForFirstAgent path], [localDocumentsForOtherAgent path], nil/*operations*/);
    }
}

// Useful for conflict checking cases where the conflict renaming might have assigned different names on different agents, but the identifier->contents should be the same across all.
- (void)requireAgentsToHaveSameFilesByIdentifier:(NSArray *)agents;
{
    if ([agents count] < 2) {
        OBASSERT_NOT_REACHED("Not terribly useful");
        return;
    }
    
    OFXAgent *firstAgent = agents[0];
    NSDictionary *firstAgentFileIdentifierToMetadata = [[self metadataItemsForAgent:firstAgent] indexByBlock:^id(OFXFileMetadata *metadata) {
        return metadata.fileIdentifier;
    }];
    
    NSArray *otherAgents = [agents subarrayWithRange:NSMakeRange(1, [agents count] - 1)];
    for (OFXAgent *otherAgent in otherAgents) {
        NSSet *metadataItems = [self metadataItemsForAgent:otherAgent];
        XCTAssertEqual([firstAgentFileIdentifierToMetadata count], [metadataItems count], @"should have the same number of files");
        
        for (OFXFileMetadata *metadata in metadataItems) {
            OFXFileMetadata *firstMetadata = firstAgentFileIdentifierToMetadata[metadata.fileIdentifier];
            XCTAssertEqualObjects(metadata.editIdentifier, firstMetadata.editIdentifier, @"should be on the same version");
            OFDiffFiles(self, [metadata.fileURL path], [firstMetadata.fileURL path], nil/*operations*/);
        }
    }
}

- (BOOL)agent:(OFXAgent *)agent hasTextContentsByPath:(NSDictionary *)textContentsByPath;
{
    NSURL *localDocuments = [self singleAccountInAgent:agent].localDocumentsURL;
    
    __block BOOL ok = YES;
    [textContentsByPath enumerateKeysAndObjectsUsingBlock:^(NSString *filename, NSString *expectedTextContents, BOOL *stop) {
        NSString *actualTextContent = [[NSString alloc] initWithContentsOfURL:[localDocuments URLByAppendingPathComponent:filename] encoding:NSUTF8StringEncoding error:NULL];
        if (![actualTextContent isEqual:expectedTextContents]) {
            ok = NO;
            *stop = YES;
        }
    }];
    
    return ok;
}

- (void)requireAgent:(OFXAgent *)agent toHaveTextContentsByPath:(NSDictionary *)textContentsByPath;
{
    NSURL *localDocuments = [self singleAccountInAgent:agent].localDocumentsURL;
    
    [textContentsByPath enumerateKeysAndObjectsUsingBlock:^(NSString *filename, NSString *expectedTextContents, BOOL *stop) {
        NSString *actualTextContent = [[NSString alloc] initWithContentsOfURL:[localDocuments URLByAppendingPathComponent:filename] encoding:NSUTF8StringEncoding error:NULL];
        XCTAssertEqualObjects(actualTextContent, expectedTextContents);
    }];
}

- (void)requireAgent:(OFXAgent *)agent toHaveDataContentsByPath:(NSDictionary *)dataContentsByPath;
{
    NSURL *localDocuments = [self singleAccountInAgent:agent].localDocumentsURL;
    
    [dataContentsByPath enumerateKeysAndObjectsUsingBlock:^(NSString *filename, NSData *expectedDataContents, BOOL *stop) {
        NSData *actualDataContent = [[NSData alloc] initWithContentsOfURL:[localDocuments URLByAppendingPathComponent:filename]];
        XCTAssertEqualObjects(actualDataContent, expectedDataContents);
    }];
}

- (NSDictionary *)_relativeIntendedPathToContentIdentifiersForAgent:(OFXAgent *)agent;
{
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
    
    OFXServerAccount *account = [self singleAccountInAgent:agent];
    NSURL *localDocumentsURL = account.localDocumentsURL;
    
    NSMutableDictionary *indentedPathToContentIdentifiers = [NSMutableDictionary dictionary];
    
    __autoreleasing NSError *error = nil;
    BOOL success = [coordinator readItemAtURL:localDocumentsURL withChanges:YES error:&error byAccessor:^BOOL(NSURL *newURL, NSError **outError) {
        OBASSERT(OFURLEqualsURL(localDocumentsURL, newURL));
        NSSet *metadatItems = [agent metadataItemsForAccount:account];
        for (OFXFileMetadata *metadata in metadatItems) {
            __autoreleasing NSError *contentError = nil;
            NSString *identifier = OFXContentIdentifierForURL(metadata.fileURL, &contentError);
            if (!identifier) {
                if ([contentError hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT])
                    // Moved?
                    continue;
                else {
                    [contentError log:@"Cannot determine content for %@", metadata.fileURL];
                    if (outError)
                        *outError = contentError;
                    return NO;
                }
            }
            
            NSURL *intendedURL = metadata.intendedFileURL;
            
            NSString *relativePath = OFFileURLRelativePath(localDocumentsURL, intendedURL);
            NSMutableSet *identifiers = indentedPathToContentIdentifiers[relativePath];
            if (!identifiers) {
                identifiers = [NSMutableSet set];
                indentedPathToContentIdentifiers[relativePath] = identifiers;
            }

            [identifiers addObject:identifier];
        }
        return YES;
    }];
    
    XCTAssertTrue(success);
    
    return indentedPathToContentIdentifiers;
}

- (BOOL)agentsToHaveSameIntendedFiles;
{
    NSDictionary *identifiersA = [self _relativeIntendedPathToContentIdentifiersForAgent:self.agentA];
    NSDictionary *identifiersB = [self _relativeIntendedPathToContentIdentifiersForAgent:self.agentB];
    
    return [identifiersA isEqualTo:identifiersB];
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
    
    NSString *randomText = [[OFRandomCreateDataOfLength(textLength) unadornedLowercaseHexString] stringByAppendingString:@"\n"];
    OBShouldNotError([[randomText dataUsingEncoding:NSUTF8StringEncoding] writeToURL:randomTextURL options:0 error:&error]);
    
    [self copyFileURL:randomTextURL toPath:destinationPath ofAccount:account];
    
    OBShouldNotError([[NSFileManager defaultManager] removeItemAtURL:randomTextURL error:&error]);
    
    return randomText;
}

- (NSString *)copyLargeRandomTextFileToPath:(NSString *)destinationPath ofAccount:(OFXServerAccount *)account;
{
    return [self copyRandomTextFileOfLength:16*1024*1024 toPath:destinationPath ofAccount:account];
}

- (OFXFileMetadata *)copyFixtureNamed:(NSString *)fixtureName toPath:(NSString *)toPath waitingForAgentsToDownload:(NSArray *)otherAgents;
{
    // Make a document and download to two agents
    OFXAgent *agent = self.agentA;
    OBASSERT_IF(otherAgents, [otherAgents indexOfObject:agent] == NSNotFound, "The other agents should not include agent A");
    
    OFXServerAccount *account = [agent.accountRegistry.validCloudSyncAccounts lastObject];
    OBASSERT(account);
    
    [self copyFixtureNamed:fixtureName toPath:toPath ofAccount:account];
    
    // Wait for the file to get uploaded
    __block OFXFileMetadata *resultMetadata;
    [self waitForFileMetadata:agent where:^BOOL(OFXFileMetadata *metadata){
        if ([[metadata.fileURL lastPathComponent] isEqual:toPath] && metadata.uploaded) {
            resultMetadata = metadata;
            return YES;
        }
        return NO;
    }];
    
    // Wait for all the other agents to download it.
    for (OFXAgent *otherAgent in otherAgents) {
        [self waitForFileMetadata:otherAgent where:^BOOL(OFXFileMetadata *metadata){
            if (![metadata.fileIdentifier isEqual:resultMetadata.fileIdentifier])
                return NO;
            if (metadata.downloaded)
                return YES;
            [otherAgent requestDownloadOfItemAtURL:metadata.fileURL completionHandler:nil];
            return NO;
        }];
    }
    
    return resultMetadata;
}

- (OFXFileMetadata *)copyFixtureNamed:(NSString *)fixtureName;
{
    return [self copyFixtureNamed:fixtureName toPath:fixtureName waitingForAgentsToDownload:@[self.agentB]];
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
        if (previousMetadata && OFISEQUAL(metadata.editIdentifier, previousMetadata.editIdentifier))
            return NO;
        
        return metadata.uploaded;
    }];
}

- (OFXFileMetadata *)downloadWithMetadata:(OFXFileMetadata *)metadata agent:(OFXAgent *)agent;
{
    XCTAssertFalse(metadata.downloaded); // Otherwise our wait below might spuriously succeed
    
    // Request the download and make sure the request has been processed
    __block BOOL downloadRequested = NO;
    [agent requestDownloadOfItemAtURL:metadata.fileURL completionHandler:^(NSError *errorOrNil) {
        XCTAssertNil(errorOrNil);
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
            XCTAssertNil(errorOrNil);
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
             XCTFail(@"Removal should not fail");
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

@end

@implementation NSFileCoordinator (OFXTestCaseExtensions)

- (NSData *)readDataFromURL:(NSURL *)fileURL options:(NSDataReadingOptions)options error:(NSError **)outError;
{
    OBPRECONDITION(fileURL);
    
    __block NSData *result = nil;
    __block NSError *strongError = nil;
    [self coordinateWritingItemAtURL:fileURL options:NSFileCoordinatorWritingForMerging error:outError byAccessor:^(NSURL *newURL) {
        __autoreleasing NSError *error;
        result = [NSData dataWithContentsOfURL:fileURL options:options error:&error];
        if (!result) {
            strongError = error;
        }
    }];
    if (!result && outError) {
        *outError = strongError;
    }
    return result;
}

- (BOOL)writeData:(NSData *)data toURL:(NSURL *)fileURL options:(NSDataWritingOptions)options error:(NSError **)outError;
{
    OBPRECONDITION(data);
    OBPRECONDITION(fileURL);
    
    __block BOOL success = NO;
    __block NSError *strongError = nil;
    [self coordinateWritingItemAtURL:fileURL options:NSFileCoordinatorWritingForMerging error:outError byAccessor:^(NSURL *newURL) {
        __autoreleasing NSError *error;
        success = [data writeToURL:fileURL options:options error:&error];
        if (!success) {
            strongError = error;
        }
    }];
    if (!success && outError) {
        *outError = strongError;
    }
    return success;
}

@end
