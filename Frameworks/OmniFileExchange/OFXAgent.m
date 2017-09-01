// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFXAgent-Internal.h"

#import <OmniDAV/ODAVConnection.h>
#import <OmniDAV/ODAVErrors.h>
#import <OmniFileExchange/OFXAccountClientParameters.h>
#import <OmniFileExchange/OFXFileMetadata.h>
#import <OmniFileExchange/OFXRegistrationTable.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniFoundation/OFBackgroundActivity.h>
#import <OmniFoundation/OFNetReachability.h>
#import <OmniFoundation/OFNetStateNotifier.h>
#import <OmniFoundation/OFNetStateRegistration.h>
#import <OmniFoundation/OFPreference.h>

#import "OFXAccountAgent-Internal.h"
#import "OFXServerAccountRegistry-Internal.h"

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIApplication.h>
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <OmniFoundation/OFController.h>
#import <CoreServices/CoreServices.h>
#endif

RCS_ID("$Id$")

static OFDeclareTimeInterval(OFXAgentSyncInterval, 5*60, 5, 5*60);

OFDeclareDebugLogLevel(OFXSyncDebug);

// Make sure to log if we hit a log call before this is loaded from preferences/environment
OFDeclareDebugLogLevel(OFXFileCoordinatonDebug);
OFDeclareDebugLogLevel(OFXScanDebug);
OFDeclareDebugLogLevel(OFXLocalRelativePathDebug);
OFDeclareDebugLogLevel(OFXTransferDebug);
OFDeclareDebugLogLevel(OFXConflictDebug);
OFDeclareDebugLogLevel(OFXMetadataDebug);
OFDeclareDebugLogLevel(OFXContentDebug);
OFDeclareDebugLogLevel(OFXActivityDebug);

@interface OFXAgent () <OFNetStateNotifierDelegate, OFNetReachabilityDelegate>
@end

@implementation OFXAgent
{
    NSString *_memberIdentifier;
    
    NSSet <NSString *> *_localPackagePathExtensions;
    NSSet <NSString *> *_syncPathExtensions;
    
    NSDictionary <NSString *, OFXAccountAgent *> *_uuidToAccountAgent;
    
    OFXRegistrationTable <OFXRegistrationTable<OFXFileMetadata *> *> *_registrationTable;

    OFNetStateNotifier *_stateNotifier;
    
    OFNetReachability *_netReachability;
    NSTimer *_periodicSyncTimer;
}

static NSString *UserAgent = nil;

+ (void)initialize;
{
    OBINITIALIZE;
        
    OFVersionNumber *version = [[self defaultClientParameters] currentFrameworkVersion];
    NSString *versionString = [NSString stringWithFormat:@"OmniFileExchange/%@", [version cleanVersionString]];
    UserAgent = [ODAVConnectionConfiguration userAgentStringByAddingComponents:@[versionString]];
    
    OBASSERT([[[NSBundle mainBundle] infoDictionary] objectForKey:@"OFSSyncContainerIdentifiers"] == nil); // Old key.
}

static NSString * const OFXWildcardPathExtension = @".*"; // dot included to make this not a valid path extension so that "foo.*" will sync...

BOOL OFXShouldSyncAllPathExtensions(NSSet *pathExtensions)
{
    if ([pathExtensions member:OFXWildcardPathExtension]) {
        OBASSERT([pathExtensions count] == 1); // No reason to list other stuff
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#ifdef OMNI_ASSERTIONS_ON
        if (OFNOTEQUAL([[NSBundle mainBundle] bundleIdentifier], @"com.omnigroup.OmniPresence.iOS")) {
            OBASSERT_NOT_REACHED("At least for now, iOS apps shouldn't be syncing everything, but only their specific file types.");
        }
#endif
#endif
        return YES;
    }
    return NO;
}

+ (NSArray *)wildcardSyncPathExtensions;
{
    static dispatch_once_t onceToken;
    static NSArray *wildcardSyncPathExtensions;
    dispatch_once(&onceToken, ^{
        wildcardSyncPathExtensions = @[OFXWildcardPathExtension];
    });
    return wildcardSyncPathExtensions;
}

+ (NSArray *)defaultSyncPathExtensions;
{
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"OFXSyncPathExtensions"];
}

+ (BOOL)hasDefaultSyncPathExtensions;
{
    return [[self defaultSyncPathExtensions] count] > 0;
}

+ (OFXAccountClientParameters *)defaultClientParameters;
{
    static OFXAccountClientParameters *parameters;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        parameters = [[OFXAccountClientParameters alloc] initWithDefaultClientIdentifierPreferenceKey:@"OFXSyncClientIdentifier"
                                                                                 hostIdentifierDomain:@"com.omnigroup.OmniFileExchange.SyncClient"
                                                                              currentFrameworkVersion:[[OFVersionNumber alloc] initWithVersionString:@"2"]];
    });
    return parameters;
}

+ (ODAVConnectionConfiguration *)makeConnectionConfiguration;
{
#if ODAV_NSURLSESSION
    OBFinishPortingLater("<bug:///147923> (iOS-OmniOutliner Bug: Look at the callers -- once we move to using NSURLSession, we'll be not reusing https connections across uploads/downloads - in -[OFXAgent makeConnectionConfiguration])");

    NSURLSessionConfiguration *configuration = [[NSURLSessionConfiguration defaultSessionConfiguration] copy];
    
    configuration.HTTPShouldUsePipelining = YES;
#else
    ODAVConnectionConfiguration *configuration = [ODAVConnectionConfiguration new];
    
    configuration.userAgent = UserAgent;
#endif
    
    return configuration;
}

// Hidden default to change our default behavior of trying to use cellular data. The user can override this in the Settings app, so we don't have any UI for controlling it.
+ (BOOL)isCellularSyncEnabled;
{
    return [[OFPreference preferenceForKey:@"OFXHiddenShouldUseCellularDataForSync"] boolValue];
}

- init;
{
    NSArray *syncPathExtensions = [[self class] defaultSyncPathExtensions];
    
    return [self initWithAccountRegistry:[OFXServerAccountRegistry defaultAccountRegistry] remoteDirectoryName:nil syncPathExtensions:syncPathExtensions];
}

- initWithAccountRegistry:(OFXServerAccountRegistry *)accountRegistry remoteDirectoryName:(NSString *)remoteDirectoryName syncPathExtensions:(id <NSFastEnumeration>)syncPathExtensions;
{
    return [self initWithAccountRegistry:accountRegistry remoteDirectoryName:remoteDirectoryName syncPathExtensions:syncPathExtensions extraPackagePathExtensions:nil];
}

// extraPackagePathExtensions allows testing code to "know" an extension is a package even when there is not UTI defined locally. This is used in the unit tests for checking that if one client knows about a package path extension, that this will make the other clients treat it as one.
- initWithAccountRegistry:(OFXServerAccountRegistry *)accountRegistry remoteDirectoryName:(NSString *)remoteDirectoryName syncPathExtensions:(id <NSFastEnumeration>)syncPathExtensions extraPackagePathExtensions:(id <NSFastEnumeration>)extraPackagePathExtensions;
{
    OBPRECONDITION(accountRegistry);
    OBPRECONDITION([[accountRegistry.accountsDirectoryURL absoluteString] hasSuffix:@"/"]);
    OBPRECONDITION([remoteDirectoryName containsString:@"/"] == NO);

    if (!(self = [super init]))
        return nil;
    
    // <bug:///84962> (Create a lock file in the account registry directory to prevent multiple agents from running)
    
    // Unique identifier for OFNetState{Registration,Notifier} that identifiers our sync system (so we can have two in one process for unit tests and not falsely ignore notifications from one to the other).
    _memberIdentifier = OFXMLCreateID();
    
    // Gather the types that we locally know as packages.
    {
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
        NSBundle *bundle = [NSBundle mainBundle];
#else
        NSBundle *bundle = [OFController controllingBundle]; // Not +[NSBundle mainBundle] so that this works with tests.
#endif
        NSMutableSet *localPackagePathExtensions = [NSMutableSet new];
        NSDictionary *infoDictionary = [bundle infoDictionary];
        
        for (NSString *pathExtension in extraPackagePathExtensions) {
            OBASSERT(![NSString isEmptyString:pathExtension], @"Should pass valid path extensions");
            OBASSERT([pathExtension isEqual:[pathExtension stringByDeletingPathExtension]], @"Should pass bare path extensions");
            [localPackagePathExtensions addObject:pathExtension];
        }
        
        // We don't assume that LaunchServices will see our file types (in particular, we might be a testing tool). But it *should* know about the types that our types conform to.
        void (^_addPackagePathExtensions)(NSArray *fileTypes) = ^(NSArray *fileTypes){
            for (NSDictionary *fileType in fileTypes) {
                NSArray *conformsToTypes = fileType[(__bridge NSString *)kUTTypeConformsToKey];
                OBASSERT(conformsToTypes, "No %@ entry in file type %@", kUTTypeConformsToKey, fileType);
                
                BOOL isFile = NO;
                BOOL isFolder = NO;
                BOOL isPackage = NO;
                
                for (NSString *conformsToType in conformsToTypes) {
                    if (OFTypeConformsTo(conformsToType, kUTTypeData))
                        isFile = YES;
                    if (OFTypeConformsTo(conformsToType, kUTTypeFolder)) // kUTTypeFolder is a user-navigable sub-type of kUTTypeDirectory
                        isFolder = YES;
                    if (OFTypeConformsTo(conformsToType, kUTTypePackage))
                        isPackage = YES;
                }
                
                OBASSERT((isFile?1:0) + (isFolder?1:0) + (isPackage?1:0) == 1, "Should be a file, folder, or package"); // TODO: This can fail when a file has a UTI that isn't registered on the current system (i.e., UTTypeIsDeclared() returns NO). How should we handle that?
                OB_UNUSED_VALUE(isFile);
                OB_UNUSED_VALUE(isFolder);
                
                // We do NOT sync folder-based types as if they were packages. For example, OmniOutliner has a HTML export that writes a directory of files (index.html, attachments, JavaScript). This conforms to kUTTypeFolder and the user can navigate into it in Finder (to open the index.html). We want to sync these individual items as files since that is how the user sees them in Finder.
                if (isPackage) {
                    NSArray *pathExtensions = fileType[@"UTTypeTagSpecification"][@"public.filename-extension"];

                    // Might be an abstract type w/o any path extensions.
                    if (pathExtensions) {
                        if (![pathExtensions isKindOfClass:[NSArray class]]) {
                            OBASSERT([pathExtensions isKindOfClass:[NSString class]]);
                            pathExtensions = @[pathExtensions];
                        }
                        OBASSERT([pathExtensions count] > 0);
                        for (NSString *pathExtension in pathExtensions) {
                            OBASSERT([pathExtension isEqual:[pathExtension lowercaseString]]);
                            [localPackagePathExtensions addObject:[pathExtension lowercaseString]];
                        }
                    }
                }
            }
        };
        _addPackagePathExtensions(infoDictionary[@"UTExportedTypeDeclarations"]);
        _addPackagePathExtensions(infoDictionary[@"UTExportedTypeDeclarations"]);
        _localPackagePathExtensions = [localPackagePathExtensions copy];
    }
    
    if (syncPathExtensions) {
        NSMutableSet *syncPathExtensionSet = [NSMutableSet new];
        for (NSString *pathExtension in syncPathExtensions)
            [syncPathExtensionSet addObject:pathExtension];
        _syncPathExtensions = [syncPathExtensionSet copy];
    }
    
    // TODO: Sign up for network status changes and stop trying to sync when there is no network.
    // TODO: Scan the local containers directory and purge containers that don't show up in our sync accounts any more (not sure how this would happen, though).
    
    // All the containers will live under here.
    DEBUG_SYNC(1, @"Creating sync agent %p", self);
    DEBUG_SYNC(1, @"  accountsDirectoryURL %@", accountRegistry.accountsDirectoryURL);
    DEBUG_SYNC(1, @"  remoteDirectoryName %@", remoteDirectoryName);
    DEBUG_SYNC(1, @"  localPackagePathExtensions %@", [[[_localPackagePathExtensions allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByComma]);
    DEBUG_SYNC(1, @"  syncPathExtensions %@", [[[_syncPathExtensions allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByComma]);
    DEBUG_SYNC(1, @"  accountRegistry %@", accountRegistry);
    
    // Nil for regular apps, but can be non-nil for tests to put all the goop for one test in its own directory on the remote side.
    _remoteDirectoryName = [remoteDirectoryName copy];

    _clientParameters = [[self class] defaultClientParameters];
    
    _accountRegistry = accountRegistry;
    
    _started = NO;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // If we get launched into the background by iOS for a backgroun fetch, make sure we have the right state here.
    _foregrounded = ([[UIApplication sharedApplication] applicationState] != UIApplicationStateBackground);
#else
    _foregrounded = YES;
#endif
    _syncSchedule = OFXSyncScheduleAutomatic;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_accountAgentDidStopForReplacement:) name:OFXAccountAgentDidStopForReplacementNotification object:nil];
    
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(_started == NO); // should have stopped the agent before owner let go of it
    
    DEBUG_SYNC(1, @"Deallocating sync agent %p", self);
    
    // Should be cleared when we are stopped and we should be stopped before being released
    OBASSERT(_registrationTable == nil);
    OBASSERT(_uuidToAccountAgent == nil);
}

#define REQUIRE(var, value, message) do { \
    OBASSERT([NSThread isMainThread], "State changes should only happen on the main thread"); \
    if (var != value) \
        [NSException raise:NSInternalInconsistencyException format:@"%@ Expected %s %d, but had %d.", message, #var, value, var]; \
} while (0)

static unsigned AccountRegistryContext;
static unsigned AccountAgentNetStateRegistrationGroupIdentifierContext;

- (void)applicationLaunched;
{
    REQUIRE(_started, NO, @"Called -applicationLaunched.");

    DEBUG_SYNC(1, @"Application launched");

    // Start syncing!
    _started = YES;
    
    OBASSERT(_registrationTable == nil);
    _registrationTable = [[OFXRegistrationTable alloc] initWithName:[NSString stringWithFormat:@"Sync Agent %p registrations", self]];
    
    OBASSERT(_stateNotifier == nil);
    _stateNotifier = [[OFNetStateNotifier alloc] initWithMemberIdentifier:_memberIdentifier];
    _stateNotifier.delegate = self;
    _stateNotifier.name = _debugName;
    DEBUG_SYNC(1, @"State notifier is %@", _stateNotifier);
    
    _netReachability = [[OFNetReachability alloc] initWithDefaultRoute:YES/*ignore ad-hoc wi-fi*/];
    _netReachability.delegate = self;
    
    OBASSERT([NSThread isMainThread]);
    OBASSERT(_accountRegistry);
    
    [_accountRegistry addObserver:self forKeyPath:OFValidateKeyPath(_accountRegistry, validCloudSyncAccounts) options:0 context:&AccountRegistryContext];
    [self _validatedAccountsChanged];
    
    if (_foregrounded)
        [self _syncAndStartTimer];
}

- (void)applicationWillEnterForeground;
{
    REQUIRE(_started, YES, @"Called -applicationWillEnterForeground.");
    REQUIRE(_foregrounded, NO, @"Called -applicationWillEnterForeground.");
    
    _foregrounded = YES;
    
    // Resume syncing
    [self _syncAndStartTimer];
}

- (void)applicationDidEnterBackground;
{
    REQUIRE(_foregrounded, YES, @"Called -applicationDidEnterBackground.");

    // Try to finish any pending uploads.
    OFBackgroundActivity *activity = [OFBackgroundActivity backgroundActivityWithIdentifier:@"com.omnigroup.OmniFileExchange.OFXAgent.applicationDidEnterBackground"];
    
    // We'll sync on foregrounding, and then we'll want to reset our timer relative to that.
    [_periodicSyncTimer invalidate];
    _periodicSyncTimer = nil;
    
    [self afterAsynchronousOperationsFinish:^{
        [activity finished];
    }];
    
    _foregrounded = NO;
}

static void _startObservingAccountAgent(OFXAgent *self, OFXAccountAgent *accountAgent)
{
    [accountAgent addObserver:self forKeyPath:OFValidateKeyPath(accountAgent, netStateRegistrationGroupIdentifier) options:0 context:&AccountAgentNetStateRegistrationGroupIdentifierContext];
}
static void _stopObservingAccountAgent(OFXAgent *self, OFXAccountAgent *accountAgent)
{
    [accountAgent removeObserver:self forKeyPath:OFValidateKeyPath(accountAgent, netStateRegistrationGroupIdentifier) context:&AccountAgentNetStateRegistrationGroupIdentifierContext];
}

- (void)applicationWillTerminateWithCompletionHandler:(void (^)(void))completionHandler; // Waits for syncing to finish and shuts down the agent
{
    OBPRECONDITION([NSThread isMainThread]);
    DEBUG_SYNC(1, @"Application will terminate");
            
    // We currently have to be running so that we can grab a snapshot of the account agents
    REQUIRE(_started, YES, @"Called -applicationWillTerminateWithCompletionHandler:.");
    
    DEBUG_SYNC(1, @"Stopping agent");
    
    // TODO: Pause whatever sync timer we add at some point.
    
    // Mark ourselves as stopped as far as the main thread is concerned. Might be operations enqueued, though.
    _started = NO;
    
    [_periodicSyncTimer invalidate];
    _periodicSyncTimer = nil;
    
    _netReachability.delegate = nil;
    _netReachability = nil;
    
    [_stateNotifier invalidate];
    _stateNotifier.delegate = nil;
    _stateNotifier = nil;

    // If we have a completion block, add an operation that will only run once all the accounts have stopped.
    NSOperation *completionOperation;
    if (completionHandler)
        completionOperation = [NSBlockOperation blockOperationWithBlock:completionHandler];
    
    [_uuidToAccountAgent enumerateKeysAndObjectsUsingBlock:^(NSString *uuid, OFXAccountAgent *accountAgent, BOOL *stop) {
        DEBUG_SYNC(1, @"Stopping account agent %@", accountAgent);
        if (accountAgent.started) {
            _stopObservingAccountAgent(self, accountAgent);
            
            NSOperation *accountStopped;
            if (completionOperation) {
                accountStopped = [NSBlockOperation blockOperationWithBlock:^{}];
                [completionOperation addDependency:accountStopped];
            }
            [accountAgent stop:^{
                if (accountStopped)
                    [[NSOperationQueue mainQueue] addOperation:accountStopped];
            }];
        }
    }];
    
    if (completionOperation)
        [[NSOperationQueue mainQueue] addOperation:completionOperation];

    // Clear this out so that when the account preference changes our observer doesn't also try to -stop the account agents.
    _uuidToAccountAgent = nil;
    [self willChangeValueForKey:OFValidateKeyPath(self, runningAccounts)];
    _runningAccounts = nil;
    [self didChangeValueForKey:OFValidateKeyPath(self, runningAccounts)];
    
    // We call this directly w/o dispatching so we can ensure that another operation doesn't happen that creates new account agents (which might want to look at the same directories these were).
    
    [_accountRegistry removeObserver:self forKeyPath:OFValidateKeyPath(_accountRegistry, validCloudSyncAccounts) context:&AccountRegistryContext];
    _registrationTable = nil;
}

- (OFXRegistrationTable <OFXFileMetadata *> *)metadataItemRegistrationTableForAccount:(OFXServerAccount *)account;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_registrationTable); // Undefined while the agent is stopped
    OBPRECONDITION([_runningAccounts member:account]); // Callers shouldn't ask us about accounts we haven't declared as running.
    
    return _registrationTable[OFXCopyRegistrationKeyForAccountMetadataItems(account.uuid)];
}

- (NSSet <OFXFileMetadata *> *)metadataItemsForAccount:(OFXServerAccount *)account;
{
    NSMutableSet <OFXFileMetadata *> *result = [NSMutableSet set];
    
    // Strip out locally deleted metadata
    for (OFXFileMetadata *metadata in [self metadataItemRegistrationTableForAccount:account].values) {
        if (metadata.fileURL != nil)
            [result addObject:metadata];
    }
    return result;
}

// Allow callers to do something after all the currently queued operations on the main agent and the container agents have finished.
- (NSOperation *)afterAsynchronousOperationsFinish:(void (^)(void))block;
{
    OBPRECONDITION([NSThread isMainThread]);

    REQUIRE(_started, YES, @"Called -afterAsynchronousOperationsFinish:.");

    NSBlockOperation *blockOperation = [NSBlockOperation blockOperationWithBlock:block];
    
    // Then wait for all the account agents that are registered (which might change from when we got called initially).
    [_uuidToAccountAgent enumerateKeysAndObjectsUsingBlock:^(NSString *uuid, OFXAccountAgent *accountAgent, BOOL *stop) {
        if (!accountAgent.started)
            return;
        [blockOperation addDependency:[accountAgent afterAsynchronousOperationsFinish:^{}]];
    }];
    
    // Let the block execute once the accounts have seen everything to date.
    [[NSOperationQueue mainQueue] addOperation:blockOperation];

    return blockOperation;
}

// We don't clear out the timer, state notifier, etc when this is NO. Rather we just ignore notifications from them while the flag is off. This is much easier and probably sufficient.
- (void)setSyncSchedule:(OFXSyncSchedule)schedule;
{
    if (_syncSchedule == schedule)
        return;
    
    _syncSchedule = schedule;
    
    [_uuidToAccountAgent enumerateKeysAndObjectsUsingBlock:^(NSString *uuid, OFXAccountAgent *accountAgent, BOOL *stop) {
        // If we are disabling syncing, the account will shut down in-progress transfers
        accountAgent.syncingEnabled = [self _syncingAllowed];
    }];
    
    // If we now allow automatic sync (by schedule and foregrounded-ness), go ahead and do a sync
    if (_foregrounded && _syncSchedule >= OFXSyncScheduleAutomatic)
        [self sync:nil];
}

// Called as part of retrying sync on an account that automatically paused itself due to errors.
- (void)restoreSyncEnabledForAccount:(OFXServerAccount *)account;
{
    OFXAccountAgent *accountAgent = _uuidToAccountAgent[account.uuid];
    accountAgent.syncingEnabled = [self _syncingAllowed];
}

- (void)setAutomaticallyDownloadFileContents:(BOOL)automaticallyDownloadFileContents;
{
    if (_automaticallyDownloadFileContents == automaticallyDownloadFileContents)
        return;
    
    _automaticallyDownloadFileContents = automaticallyDownloadFileContents;
    [_uuidToAccountAgent enumerateKeysAndObjectsUsingBlock:^(NSString *uuid, OFXAccountAgent *accountAgent, BOOL *stop) {
        // Any in progress downloads will continue.
        accountAgent.automaticallyDownloadFileContents = _automaticallyDownloadFileContents;
    }];
}

- (BOOL)shouldAutomaticallyDownloadItemWithMetadata:(OFXFileMetadata *)metadataItem;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_netReachability);

    // Automatic downloads shouldn't happen while on the user's cellular connection. Due to fallback support in iOS 7, we might return YES here, but then fail the connection later since we configure the transfer operation to not use the cellular network.
    if (!_netReachability.reachable || _netReachability.usingCell)
        return NO;
    
    // Only automatically download "small" items.
    unsigned long long fileSize = metadataItem.fileSize;
    
    NSUInteger maximumAutomaticDownloadSize = [[OFPreference preferenceForKey:@"OFXMaximumAutomaticDownloadSize"] unsignedIntegerValue];
    
    return (fileSize <= (unsigned long long)maximumAutomaticDownloadSize);
}

// Explicit request to sync. This should typically just be done as part of application lifecycle and on a timer.
- (void)sync:(void (^)(void))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    REQUIRE(_started, YES, @"Called -sync:.");
    
    // Try to stay alive while the sync is happening.
    OFBackgroundActivity *activity = [OFBackgroundActivity backgroundActivityWithIdentifier:@"com.omnigroup.OmniFileExchange.Sync"];
    
    // TODO: Discard sync requests that are made while there is an unstarted sync request already queued?
    
    NSBlockOperation *completionOperation = [NSBlockOperation blockOperationWithBlock:^{
        if (completionHandler)
            completionHandler();
        [activity finished];
    }];
    
    [_uuidToAccountAgent enumerateKeysAndObjectsUsingBlock:^(NSString *uuid, OFXAccountAgent *accountAgent, BOOL *stop) {
        // TODO: Added a check for -syncingEnabled here, but this might make the 'manual' sync schedule not work.
        if (!accountAgent.started || !accountAgent.syncingEnabled)
            return;

        // TODO: Consider using OFNetReachability to skip account agents which are unreachable (offline).

        // Maybe should use a GCD semaphore or the like...?
        NSBlockOperation *completionIndicator = [NSBlockOperation blockOperationWithBlock:^{}];
        [completionOperation addDependency:completionIndicator];
        [accountAgent sync:^{
            [[NSOperationQueue mainQueue] addOperation:completionIndicator];
        }];
    }];
    
    [[NSOperationQueue mainQueue] addOperation:completionOperation];
}

// Either the error handler is called (for preflight problems), or the action, but not both.
- (void)_operateOnFileAtURL:(NSURL *)fileURL errorHandler:(void (^)(NSError *error))errorHandler withAction:(void (^)(OFXAccountAgent *))accountAction;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_started == NO) {
        if (errorHandler) {
            __autoreleasing NSError *error;
            OFXError(&error, OFXAgentNotStarted, @"Attempted to operate on a document while the sync agent was not started.", nil);
            errorHandler(error);
        }
        return;
    }
    
    errorHandler = [errorHandler copy];
    
    OFXAccountAgent *accountAgent = [self _accountAgentContainingFileURL:fileURL];
    if (!accountAgent) {
        if (errorHandler) {
            __autoreleasing NSError *error;
            OFXError(&error, OFXFileNotContainedInAnyAccount, @"Attempted operate on a document that is not part of any account.", nil);
            errorHandler(error);
        }
    }
    
    accountAction(accountAgent);
}

- (void)requestDownloadOfItemAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    [self _operateOnFileAtURL:fileURL errorHandler:completionHandler withAction:^(OFXAccountAgent *accountAgent){
        [accountAgent requestDownloadOfItemAtURL:fileURL completionHandler:completionHandler];
    }];
}

- (void)deleteItemAtURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *errorOrNil))completionHandler;
{
    [self _operateOnFileAtURL:fileURL errorHandler:completionHandler withAction:^(OFXAccountAgent *accountAgent){
        [accountAgent deleteItemAtURL:fileURL completionHandler:completionHandler];
    }];
}

- (void)moveItemAtURL:(NSURL *)originalFileURL toURL:(NSURL *)updatedFileURL completionHandler:(void (^)(OFFileMotionResult *result, NSError *errorOrNil))completionHandler;
{
    [self _operateOnFileAtURL:originalFileURL errorHandler:^(NSError *error){
        OBASSERT([NSThread isMainThread]);
        if (completionHandler)
            completionHandler(nil, error);
    } withAction:^(OFXAccountAgent *accountAgent){
        [accountAgent moveItemAtURL:originalFileURL toURL:updatedFileURL completionHandler:completionHandler];
    }];
}

- (void)countPendingTransfersForAccount:(OFXServerAccount *)serverAccount completionHandler:(void (^)(NSError *errorOrNil, NSUInteger count))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_started == NO) {
        if (completionHandler) {
            __autoreleasing NSError *error;
            OFXError(&error, OFXAgentNotStarted, @"Attempted to operate on a document while the sync agent was not started.", nil);
            completionHandler(error, NSNotFound);
        }
        return;
    }
    
    completionHandler = [completionHandler copy];
    
    OFXAccountAgent *accountAgent = _uuidToAccountAgent[serverAccount.uuid];
    if (!accountAgent) {
        if (completionHandler) {
            __autoreleasing NSError *error;
            OFXError(&error, OFXFileNotContainedInAnyAccount, @"Attempted operation on an account that is not registered with this agent.", nil);
            completionHandler(error, NSNotFound);
        }
    }
    
    [accountAgent countPendingTransfers:completionHandler];
}

- (void)countFileItemsWithLocalChangesForAccount:(OFXServerAccount *)serverAccount completionHandler:(void (^)(NSError *errorOrNil, NSUInteger count))completionHandler;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_started == NO) {
        if (completionHandler) {
            __autoreleasing NSError *error;
            OFXError(&error, OFXAgentNotStarted, @"Attempted to operate on a document while the sync agent was not started.", nil);
            completionHandler(error, NSNotFound);
        }
        return;
    }
    
    completionHandler = [completionHandler copy];
    
    OFXAccountAgent *accountAgent = _uuidToAccountAgent[serverAccount.uuid];
    if (!accountAgent) {
        if (completionHandler) {
            __autoreleasing NSError *error;
            OFXError(&error, OFXFileNotContainedInAnyAccount, @"Attempted operation on an account that is not registered with this agent.", nil);
            completionHandler(error, NSNotFound);
        }
    }
    
    [accountAgent countFileItemsWithLocalChanges:completionHandler];
}

#pragma mark - OFNetStateNotifierDelegate

- (void)netStateNotifierStateChanged:(OFNetStateNotifier *)notifier;
{
    OBPRECONDITION([NSThread mainThread]);
    OBPRECONDITION(_stateNotifier == nil || _stateNotifier == notifier);
    
    if (_stateNotifier == nil) {
        OBASSERT(_started == NO);
        return; // We were in the process of shutting down
    }
    DEBUG_SYNC(1, @"State notifier changed: %@", notifier);

    if (!_foregrounded || _syncSchedule < OFXSyncScheduleAutomatic)
        return;
    
    [self sync:nil];
}

#pragma mark - OFNetReachabilityDelegate protocol

- (void)reachabilityDidUpdate:(OFNetReachability *)reachability reachable:(BOOL)reachable usingCell:(BOOL)usingCell;
{
    if (!_foregrounded || _syncSchedule < OFXSyncScheduleAutomatic)
        return;

    DEBUG_SYNC(1, @"Reachability changed: reachable=%u, usingCell=%u", reachable, usingCell);

    [self sync:nil]; // We call -sync even when the network isn't reachable so that we'll report an offline state in a timely manner
}

#pragma mark - NSKeyValueObserving

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    OBPRECONDITION([NSThread isMainThread]);

    if (context == &AccountRegistryContext) {
        OBASSERT(object == _accountRegistry);
        OBASSERT([keyPath isEqual:OFValidateKeyPath(_accountRegistry, validCloudSyncAccounts)]);
        
        [self _validatedAccountsChanged];
    }
    if (context == &AccountAgentNetStateRegistrationGroupIdentifierContext) {
        OBASSERT([_uuidToAccountAgent keyForObjectEqualTo:object] != nil);
        OBASSERT([keyPath isEqual:OFValidateKeyPath(((OFXAccountAgent *)object), netStateRegistrationGroupIdentifier)]);
        
        [self _validatedAccountsChanged];
    }
}

#pragma mark - Debugging

- (NSString *)shortDescription;
{
    if (_debugName)
        return [NSString stringWithFormat:@"<Agent %@ %p>", _debugName, self];
    return [super shortDescription];
}

#pragma mark - Internal

- (NSOperationQueue *)_operationQueueForAccount:(OFXServerAccount *)serverAccount;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_started);
    
    OFXAccountAgent *accountAgent = _uuidToAccountAgent[serverAccount.uuid];
    OBASSERT(accountAgent, @"Passed in unknown/not-validated account?");
    
    NSOperationQueue *queue = accountAgent.operationQueue;
    OBASSERT(queue, @"Agent stopped?");
    
    return queue;
}

#pragma mark - Private

- (void)_validatedAccountsChanged;
{
    OBPRECONDITION([NSThread isMainThread]);
    OBPRECONDITION(_started); // We only sign up for this notification if we start OK.
        
    // Grab a snapshot of the server accounts that have credentials. We don't want to have a user add/remove accounts out from underneath us while syncing is going on. The most crucial properties on the server account are read-only (credentials are editable).
    NSArray *serverAccounts = [NSArray arrayWithArray:_accountRegistry.validCloudSyncAccounts];
    NSMutableSet <OFXServerAccount *> *failedAccounts = [[NSMutableSet alloc] init];
    
    DEBUG_SYNC(2, @"Performing account change (%ld accounts)", [serverAccounts count]);
    
    NSMutableDictionary <NSString *, OFXAccountAgent *> *uuidToAccountAgent = [NSMutableDictionary new];
    NSMutableArray <OFXAccountAgent *> *addedAccountAgents = [NSMutableArray new];
    
    // Collect resolve paths for all the accounts on the Mac. We do this up front so that we can detect if one account's local documents directory has been moved inside another.
#if OFX_MAC_STYLE_ACCOUNT
    NSMutableDictionary *uuidToLocalDocumentsURL = [[NSMutableDictionary alloc] init];
#endif
    
    // Make sure we have account agents for all the accounts.
    for (OFXServerAccount *serverAccount in serverAccounts) {
        NSString *accountIdentifier = serverAccount.uuid;
        
#if OFX_MAC_STYLE_ACCOUNT
        {
            // Might not be able to resolve the local documents bookmark URL on the Mac.
            __autoreleasing NSError *resolveError;
            if (![serverAccount resolveLocalDocumentsURL:&resolveError]) {
                OFXError(&resolveError, OFXLocalAccountDocumentsDirectoryMissing,
                         NSLocalizedStringFromTableInBundle(@"Cannot start account agent.", @"OmniFileExchange", OMNI_BUNDLE, @"Error description"),
                         NSLocalizedStringFromTableInBundle(@"Unable to find synchronized folder for account.", @"OmniFileExchange", OMNI_BUNDLE, @"Error reason"));
                [serverAccount reportError:resolveError format:@"Error starting account agent. Local account documents folder count not be resolved."];
                [failedAccounts addObject:serverAccount];
                continue;
            }
            
            uuidToLocalDocumentsURL[accountIdentifier] = serverAccount.localDocumentsURL;
        }
#endif
        
        OFXAccountAgent *accountAgent = [_uuidToAccountAgent objectForKey:accountIdentifier];
        if (!accountAgent) {
            accountAgent = [self _makeAccountAgentForAccount:serverAccount];
            [addedAccountAgents addObject:accountAgent];
        }
        
        [uuidToAccountAgent setObject:accountAgent forKey:accountIdentifier];
    }
    
#if OFX_MAC_STYLE_ACCOUNT
    // Check if any account folders are inside other account folders. This can produce bad behaviors (though it works surprisingly well... unless the two folders are syncing to the same account)
    // If we put A inside B, we'll disable syncing on B.
    if ([serverAccounts count] > 1) {
        NSMutableSet *parentPaths = [[NSMutableSet alloc] init];
        for (OFXServerAccount *serverAccount in serverAccounts) {
            NSString *path = [[uuidToLocalDocumentsURL[serverAccount.uuid] path] stringByDeletingLastPathComponent];
            if (!path)
                continue; // Path for this account couldn't be resolved -- possibly deleted.
            
            while (YES) {
                [parentPaths addObject:path];
                NSString *parentPath = [path stringByDeletingLastPathComponent];
                if ([NSString isEmptyString:parentPath] || [parentPath isEqual:@"/"])
                    break;
                path = parentPath;
            }
        }
        
        for (OFXServerAccount *serverAccount in serverAccounts) {
            NSString *path = [uuidToLocalDocumentsURL[serverAccount.uuid] path];
            if (!path)
                continue; // Path for this account couldn't be resolved -- possibly deleted.

            if ([parentPaths containsObject:path]) {
                __autoreleasing NSError *error;
                OFXError(&error, OFXLocalAccountDocumentsInsideAnotherAccount,
                         NSLocalizedStringFromTableInBundle(@"Cannot start syncing.", @"OmniFileExchange", OMNI_BUNDLE, @"Error description"),
                         NSLocalizedStringFromTableInBundle(@"This OmniPresence folder contains another OmniPresence synced folder.", @"OmniFileExchange", OMNI_BUNDLE, @"Error reason"));

                [serverAccount reportError:error];
                
                // This will make sure we stop the account (or don't start it)
                OFXAccountAgent *agent = uuidToAccountAgent[serverAccount.uuid];
                [uuidToAccountAgent removeObjectForKey:serverAccount.uuid];
                [addedAccountAgents removeObject:agent];

                [failedAccounts addObject:serverAccount];
            }
        }
    }
#endif
    
    // Inform any agents that we no longer have that they should cleanup and stop
    [_uuidToAccountAgent enumerateKeysAndObjectsUsingBlock:^(NSString *uuid, OFXAccountAgent *accountAgent, BOOL *stop){
        if ([uuidToAccountAgent objectForKey:uuid] == nil) {
            // Delay the cleanup until the agent knows that it is stopped (so that snapshots don't disappear out from underneath file items, etc).
            void (^cleanup)(void) = ^{
                [_accountRegistry _cleanupAccountAfterRemoval:accountAgent.account];
            };
            
            if (accountAgent.started) {
                DEBUG_SYNC(1, @"Stopping account agent %@", accountAgent);
                _stopObservingAccountAgent(self, accountAgent);
                [accountAgent stop:^{
                    // -stop: calls us on the agent's queue.
                    [[NSOperationQueue mainQueue] addOperationWithBlock:cleanup];
                }];
            } else
                cleanup();
        }
    }];
    
    // Update our idea of what agents we have
    _uuidToAccountAgent = [uuidToAccountAgent copy];
    
    // Start up any new agents
    for (OFXAccountAgent *accountAgent in addedAccountAgents) {
        DEBUG_SYNC(1, @"Starting account agent %@", accountAgent);
        
        __autoreleasing NSError *startError;
        if (![accountAgent start:&startError]) {
            [startError log:@"Error starting account agent %@", accountAgent];
            [accountAgent.account reportError:startError];
            [failedAccounts addObject:accountAgent.account];
            continue;
        }
        _startObservingAccountAgent(self, accountAgent);
    }
    
    NSMutableSet <OFXServerAccount *> *runningAccounts = [NSMutableSet new];
    NSMutableSet <NSString *> *accountNetStateGroupIdentifiers = [NSMutableSet new];
    [_uuidToAccountAgent enumerateKeysAndObjectsUsingBlock:^(NSString *uuid, OFXAccountAgent *accountAgent, BOOL *stop) {
        if (accountAgent.started) {
            [runningAccounts addObject:accountAgent.account];
            
            NSString *groupIdentifier = accountAgent.netStateRegistrationGroupIdentifier;
            if (groupIdentifier) // Might still be loading the Info.plist
                [accountNetStateGroupIdentifiers addObject:groupIdentifier];
        } else {
            // Will already be in failedAccounts if it was newly appearing this time around and failed in -start:, but if it was in a previous round, it won't be.
            [failedAccounts addObject:accountAgent.account];
        }
    }];
    
    if (OFNOTEQUAL(_runningAccounts, runningAccounts)) {
        [self willChangeValueForKey:OFValidateKeyPath(self, runningAccounts)];
        _runningAccounts = [runningAccounts copy];
        [self didChangeValueForKey:OFValidateKeyPath(self, runningAccounts)];
    }
    if (OFNOTEQUAL(_failedAccounts, failedAccounts)) {
        [self willChangeValueForKey:OFValidateKeyPath(self, failedAccounts)];
        _failedAccounts = [failedAccounts copy];
        [self didChangeValueForKey:OFValidateKeyPath(self, failedAccounts)];
    }
    OBASSERT([_runningAccounts count] + [_failedAccounts count] == [serverAccounts count], "Every account should be running or failed");
    OBASSERT([_runningAccounts intersectsSet:_failedAccounts] == NO, "Cannot be running and failed");
    
    // Update our net state monitor for all the accounts we are using.
    BOOL changedGroupIdentifiers = NO;
    OBASSERT(_stateNotifier);
    if (OFNOTEQUAL(_stateNotifier.monitoredGroupIdentifiers, accountNetStateGroupIdentifiers)) {
        DEBUG_SYNC(1, @"Monitoring groups %@", accountNetStateGroupIdentifiers);
        _stateNotifier.monitoredGroupIdentifiers = accountNetStateGroupIdentifiers;
        changedGroupIdentifiers = YES;
    }
    
    // Pretty terrible check, but no need to do an extra sync while we are just starting (since we'll do one as part of our startup).
    // We do need to sync if we aren't in the middle of startup and we've added a new account or we've found out about a new group identifier.
    BOOL isStarting = (_periodicSyncTimer == nil);
    BOOL shouldSync = (!isStarting && ([addedAccountAgents count] > 0 || changedGroupIdentifiers));
    
    if (shouldSync)
        [self sync:nil];
    
    DEBUG_SYNC(1, @"Finished updating accounts");
}

- (OFXAccountAgent *)_accountAgentContainingFileURL:(NSURL *)fileURL;
{
    OBPRECONDITION([NSThread isMainThread]);

    __block OFXAccountAgent *containingAccountAgent;
    [_uuidToAccountAgent enumerateKeysAndObjectsUsingBlock:^(NSString *uuid, OFXAccountAgent *accountAgent, BOOL *stop) {
        if ([accountAgent containsLocalDocumentFileURL:fileURL]) {
            containingAccountAgent = accountAgent;
            *stop = YES;
        }
    }];
    return containingAccountAgent;
}

- (BOOL)_syncingAllowed;
{
    return _started && _syncSchedule > OFXSyncScheduleNone;
}

- (void)_syncAndStartTimer;
{
    OBPRECONDITION([NSThread isMainThread]);

    REQUIRE(_started, YES, @"Called -_syncAndStartTimer.");
    OBPRECONDITION(_periodicSyncTimer == nil);
    
    [self sync:nil];

    // ... and sign up to do syncing every once in a while. This will only matter if you have a document open, don't edit it, and no one else on your LAN edits it, don't background and re-foreground the app.
    _periodicSyncTimer = [NSTimer scheduledTimerWithTimeInterval:OFXAgentSyncInterval target:self selector:@selector(_periodicSyncTimerFired:) userInfo:nil repeats:YES];
}

- (void)_periodicSyncTimerFired:(NSTimer *)timer;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    DEBUG_SYNC(1, @"Sync timer fired");

    if (!_foregrounded || _syncSchedule < OFXSyncScheduleAutomatic)
        return;
    
    [self sync:nil];
}

- (OFXAccountAgent *)_makeAccountAgentForAccount:(OFXServerAccount *)account;
{
    NSURL *localAccountDirectory = [_accountRegistry localStoreURLForAccount:account];
    
    DEBUG_SYNC(1, @"Adding container agent for %@", account);
    OFXAccountAgent *accountAgent = [[OFXAccountAgent alloc] initWithAccount:account agentMemberIdentifier:_memberIdentifier registrationTable:_registrationTable remoteDirectoryName:_remoteDirectoryName localAccountDirectory:localAccountDirectory localPackagePathExtensions:_localPackagePathExtensions syncPathExtensions:_syncPathExtensions];
    accountAgent.debugName = _debugName;
    accountAgent.syncingEnabled = [self _syncingAllowed];
    accountAgent.automaticallyDownloadFileContents = _automaticallyDownloadFileContents;
    accountAgent.clientParameters = _clientParameters;
    
    return accountAgent;
}

// Called by agents when they notice something they can't handle and stay running. After they've stopped themselves and done what they can, we need to replace them.
- (void)_accountAgentDidStopForReplacement:(NSNotification *)note;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    if (_started == NO) {
        // Oh well, we were stopping anyway!
        return;
    }
    
    OFXAccountAgent *accountAgent = note.object;
    OFXServerAccount *account = accountAgent.account;
    
    if (_uuidToAccountAgent[account.uuid] != accountAgent) {
        OBASSERT_NOT_REACHED("Some sort of race condition?");
        return;
    }

    // Publish this agent as being stopped.
    {
        OBASSERT(accountAgent.started == NO, @"The posting account told us it had already stopped, so we shouldn't have to");

        _stopObservingAccountAgent(self, accountAgent);
        NSMutableDictionary *uuidToAccountAgent = [_uuidToAccountAgent mutableCopy];
        [uuidToAccountAgent removeObjectForKey:account.uuid];
        _uuidToAccountAgent = [uuidToAccountAgent copy];
    
        OBASSERT([_runningAccounts member:account], @"Can't have stopped unless we were running");
        NSMutableSet *runningAccounts = [_runningAccounts mutableCopy];
        [runningAccounts removeObject:account];
        [self willChangeValueForKey:OFValidateKeyPath(self, runningAccounts)];
        _runningAccounts = [runningAccounts copy];
        [self didChangeValueForKey:OFValidateKeyPath(self, runningAccounts)];
    }

    // Then rescan and start agents as normal
    [self _validatedAccountsChanged];
}

@end
